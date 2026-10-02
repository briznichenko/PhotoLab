import CoreGraphics
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ImportedPhoto: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PhotoLab Imports", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = UUID().uuidString + "." + received.file.pathExtension
            let destination = folder.appendingPathComponent(name)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedPhoto(url: destination)
        }
    }
}

struct Photo: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: UIImage
    let preview: UIImage
}

enum BackgroundEffect: String, CaseIterable, Identifiable, Sendable {
    case original = "Original"
    case blur = "Blur"
    case white = "White"
    case black = "Black"

    var id: String { rawValue }
}

struct EditSettings: Sendable {
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var rotationRadians = 0.0
    var background: BackgroundEffect = .original
    var blurRadius = 18.0
}

struct TextRegion: Identifiable, Sendable {
    let id: Int
    let text: String
    let rect: CGRect
}

struct Analysis: Sendable {
    let smartCrop: CGRect?
    let horizonRadians: Double?
    let text: [TextRegion]
}

struct Comparison: Sendable {
    let identicalFiles: Bool
    let featureDistance: Float?
    let alignedImageData: Data?
}

enum EditorIssue: LocalizedError {
    case unsupportedImage
    case failedToRender

    var errorDescription: String? {
        switch self {
        case .unsupportedImage: "The selected image could not be decoded."
        case .failedToRender: "The image could not be rendered."
        }
    }
}
