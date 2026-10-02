import Foundation
import ImageIO
import Testing
@testable import PhotoLab

private final class FixtureLocator {}

struct ImageEngineTests {
    @Test
    func previewCropAndExport() async throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let first = try #require(bundle.url(forResource: "sample-1", withExtension: "jpg"))
        let second = try #require(bundle.url(forResource: "sample-2", withExtension: "jpg"))
        let engine = ImageEngine()

        let previews = try await engine.makePreviews(at: first)
        #expect(!previews.thumbnail.isEmpty)
        #expect(!previews.preview.isEmpty)

        var settings = EditSettings()
        settings.crop = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let rendered = try await engine.render(at: first, settings: settings, maxPixel: 1200)
        let source = try #require(CGImageSourceCreateWithData(rendered as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 960)
        #expect(image.height == 640)

        let exported = try await engine.export(at: first, settings: settings)
        defer { try? FileManager.default.removeItem(at: exported) }
        #expect(FileManager.default.fileExists(atPath: exported.path))

        let comparison = try await engine.compare(first: first, second: second)
        #expect(!comparison.identicalFiles)
    }

    #if !targetEnvironment(simulator)
    @Test
    func visionComparisonAndSubjectEffect() async throws {
        let bundle = Bundle(for: FixtureLocator.self)
        let first = try #require(bundle.url(forResource: "sample-1", withExtension: "jpg"))
        let second = try #require(bundle.url(forResource: "sample-2", withExtension: "jpg"))
        let engine = ImageEngine()

        _ = try await engine.analyze(at: first)
        let comparison = try await engine.compare(first: first, second: second)
        #expect(!comparison.identicalFiles)
        #expect(comparison.featureDistance != nil)

        var settings = EditSettings()
        settings.background = .white
        let rendered = try await engine.render(at: first, settings: settings, maxPixel: 1200)
        #expect(rendered.count > 1_000)
    }
    #endif
}
