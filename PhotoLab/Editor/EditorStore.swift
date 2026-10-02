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

    var activePhoto: Photo? { photos[activeSlot] }

    func importSelection(_ selection: PhotosPickerItem?, into slot: Int) async {
        guard let selection else { return }
        let token = UUID()
        loadTokens[slot] = token
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
            if loadTokens[slot] == token { issue = error.localizedDescription }
        }
        if loadTokens[slot] == token { isBusy = false }
    }

    func importCameraImage(_ image: UIImage) async {
        let token = UUID()
        loadTokens[0] = token
        isBusy = true
        issue = nil
        do {
            guard let data = image.jpegData(compressionQuality: 0.95) else {
                throw EditorIssue.unsupportedImage
            }
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PhotoLab Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(UUID().uuidString + ".jpg")
            try data.write(to: url, options: .atomic)
            try await acceptPhoto(at: url, slot: 0, token: token)
        } catch {
            if loadTokens[0] == token { issue = error.localizedDescription }
        }
        if loadTokens[0] == token { isBusy = false }
    }

    private func acceptPhoto(at url: URL, slot: Int, token: UUID) async throws {
        let previews = try await engine.makePreviews(at: url)
        guard loadTokens[slot] == token, !Task.isCancelled,
              let thumbnail = UIImage(data: previews.thumbnail),
              let preview = UIImage(data: previews.preview) else { return }

        photos[slot] = Photo(url: url, thumbnail: thumbnail, preview: preview)
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
        if photos[0] != nil, photos[1] != nil {
            await comparePhotos()
        }
    }

    func analyzeFirst() async {
        guard let photo = photos[0] else { return }
        let id = photo.id
        do {
            let result = try await engine.analyze(at: photo.url)
            if photos[0]?.id == id { analysis = result }
        } catch {
            if photos[0]?.id == id { issue = error.localizedDescription }
        }
    }

    func comparePhotos() async {
        guard let first = photos[0], let second = photos[1] else { return }
        let token = UUID()
        comparisonToken = token
        let firstID = first.id
        let secondID = second.id
        do {
            let result = try await engine.compare(first: first.url, second: second.url)
            if comparisonToken == token, photos[0]?.id == firstID, photos[1]?.id == secondID {
                comparison = result
            }
        } catch {
            if comparisonToken == token { issue = error.localizedDescription }
        }
    }

    func refreshPreview() async {
        guard let photo = photos[0] else { return }
        let id = photo.id
        let revision = renderRevision
        do {
            try await Task.sleep(for: .milliseconds(180))
            let data = try await engine.render(at: photo.url, settings: settings, maxPixel: 1600)
            guard photos[0]?.id == id, renderRevision == revision, !Task.isCancelled else { return }
            editedPreview = UIImage(data: data)
        } catch is CancellationError {
        } catch {
            if photos[0]?.id == id, renderRevision == revision { issue = error.localizedDescription }
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
        guard let photo = photos[0] else { return }
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
