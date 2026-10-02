import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class EditorStore {
    private let engine = ImageEngine()
    private var loadTokens = [UUID(), UUID()]
    private var comparisonToken = UUID()

    var photos: [Photo?] = [nil, nil]
    var activeSlot = 0
    var settings = EditSettings()
    var analysis: Analysis?
    var comparison: Comparison?
    var editedPreview: UIImage?
    var renderRevision = UUID()
    var exportURL: URL?
    var isBusy = false
    var issue: String?

    var activePhoto: Photo? { photo(at: activeSlot) }

    func photo(at slot: Int) -> Photo? { photos[safe: slot] ?? nil }

    func importSelection(_ selection: PhotosPickerItem?, into slot: Int) async {
        guard let selection else { return }
        let token = UUID()
        guard loadTokens.replaceIfPresent(token, at: slot) else { return }
        isBusy = true
        issue = nil

        do {
            guard let imported = try await selection.loadTransferable(type: ImportedPhoto.self) else {
                throw EditorIssue.unsupportedImage
            }
            try Task.checkCancellation()
            try await acceptPhoto(at: imported.url, slot: slot, token: token)
        } catch is CancellationError {
        } catch {
            if loadTokens[safe: slot] == token { issue = error.localizedDescription }
        }
        if loadTokens[safe: slot] == token { isBusy = false }
    }

    func importCameraImage(_ image: UIImage) async {
        let token = UUID()
        guard loadTokens.replaceIfPresent(token, at: 0) else { return }
        isBusy = true
        issue = nil
        do {
            guard let data = image.jpegData(compressionQuality: 0.95) else {
                throw EditorIssue.unsupportedImage
            }
            let folder = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
                .appendingPathComponent("PhotoLab Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: url, options: .atomic)
            try await acceptPhoto(at: url, slot: 0, token: token)
        } catch {
            if loadTokens[safe: 0] == token { issue = error.localizedDescription }
        }
        if loadTokens[safe: 0] == token { isBusy = false }
    }

    private func acceptPhoto(at url: URL, slot: Int, token: UUID) async throws {
        let previews = try await engine.makePreviews(at: url)
        guard loadTokens[safe: slot] == token, !Task.isCancelled,
              let thumbnail = UIImage(data: previews.thumbnail),
              let preview = UIImage(data: previews.preview) else { return }

        guard photos.replaceIfPresent(Photo(url: url, thumbnail: thumbnail, preview: preview), at: slot) else { return }
        activeSlot = slot
        comparison = nil
        exportURL = nil
        if slot == 0 {
            settings = EditSettings()
            editedPreview = preview
            analysis = nil
            await analyzeFirst()
            await refreshPreview()
        }
        if photo(at: 0) != nil, photo(at: 1) != nil {
            await comparePhotos()
        }
    }

    func analyzeFirst() async {
        guard let photo = photo(at: 0) else { return }
        let id = photo.id
        do {
            let result = try await engine.analyze(at: photo.url)
            if self.photo(at: 0)?.id == id { analysis = result }
        } catch {
            if self.photo(at: 0)?.id == id { issue = error.localizedDescription }
        }
    }

    func comparePhotos() async {
        guard let first = photo(at: 0), let second = photo(at: 1) else { return }
        let token = UUID()
        comparisonToken = token
        let firstID = first.id
        let secondID = second.id
        do {
            let result = try await engine.compare(first: first.url, second: second.url)
            if comparisonToken == token, photo(at: 0)?.id == firstID, photo(at: 1)?.id == secondID {
                comparison = result
            }
        } catch {
            if comparisonToken == token { issue = error.localizedDescription }
        }
    }

    func refreshPreview() async {
        guard let photo = photo(at: 0) else { return }
        let id = photo.id
        let revision = renderRevision
        do {
            try await Task.sleep(for: .milliseconds(180))
            let data = try await engine.render(at: photo.url, settings: settings, maxPixel: 1600)
            guard self.photo(at: 0)?.id == id, renderRevision == revision, !Task.isCancelled else { return }
            editedPreview = UIImage(data: data)
        } catch is CancellationError {
        } catch {
            if self.photo(at: 0)?.id == id, renderRevision == revision { issue = error.localizedDescription }
        }
    }

    func editsChanged() {
        exportURL = nil
        renderRevision = UUID()
    }

    func useSmartCrop() {
        guard let crop = analysis?.smartCrop else { return }
        settings.crop = crop
        editsChanged()
    }

    func useTextCrop() {
        guard let regions = analysis?.text, !regions.isEmpty else { return }
        let union = regions.reduce(CGRect.null) { $0.union($1.rect) }
        settings.crop = union.insetBy(dx: -0.08, dy: -0.08)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        editsChanged()
    }

    func useHorizon() {
        guard let angle = analysis?.horizonRadians else { return }
        settings.rotationRadians = angle
        editsChanged()
    }

    func resetEdits() {
        settings = EditSettings()
        editsChanged()
    }

    func export() async {
        guard let photo = photo(at: 0) else { return }
        isBusy = true
        issue = nil
        do {
            exportURL = try await engine.export(at: photo.url, settings: settings)
        } catch {
            issue = error.localizedDescription
        }
        isBusy = false
    }
}
