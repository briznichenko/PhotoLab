import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import Vision

actor ImageEngine {
    private let context = CIContext()
    private var masks: [String: CIImage] = [:]

    func makePreviews(at url: URL) throws -> (thumbnail: Data, preview: Data) {
        let small = try loadImage(at: url, maxPixel: 240)
        let large = try loadImage(at: url, maxPixel: 1600)
        return (try encode(small), try encode(large))
    }

    func analyze(at url: URL) throws -> Analysis {
        let image = try loadImage(at: url, maxPixel: 1600)
        let handler = VNImageRequestHandler(cgImage: image)

        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        try? handler.perform([saliency])
        let boxes = saliency.results?.first?.salientObjects?.map(\.boundingBox) ?? []
        let union = boxes.reduce(CGRect.null) { $0.union($1) }
        let crop: CGRect?
        if union.isNull {
            crop = nil
        } else {
            let padded = union.insetBy(dx: -0.12, dy: -0.12)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            crop = CGRect(x: padded.minX, y: 1 - padded.maxY, width: padded.width, height: padded.height)
        }

        let horizon = VNDetectHorizonRequest()
        try? handler.perform([horizon])

        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        try? handler.perform([recognition])
        let text = (recognition.results ?? []).enumerated().compactMap { index, observation -> TextRegion? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let box = observation.boundingBox
            return TextRegion(
                id: index,
                text: candidate.string,
                rect: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            )
        }

        return Analysis(smartCrop: crop, horizonRadians: horizon.results?.first.map { Double($0.angle) }, text: text)
    }

    func compare(first: URL, second: URL) throws -> Comparison {
        let identical = try digest(first) == digest(second)
        let reference = try loadImage(at: first, maxPixel: 1000)
        let candidate = try loadImage(at: second, maxPixel: 1000)

        var distance: Float?
        if let firstPrint = try? featurePrint(for: reference),
           let secondPrint = try? featurePrint(for: candidate) {
            var measured: Float = 0
            if (try? firstPrint.computeDistance(&measured, to: secondPrint)) != nil {
                distance = measured
            }
        }

        let size = CGSize(width: reference.width, height: reference.height)
        let candidateImage = CIImage(cgImage: candidate)
        let scaledCandidate = candidateImage.transformed(by: CGAffineTransform(
            scaleX: size.width / candidateImage.extent.width,
            y: size.height / candidateImage.extent.height
        ))
        let scaledCG = context.createCGImage(scaledCandidate, from: CGRect(origin: .zero, size: size))
        var alignedData: Data?
        if let scaledCG {
            let registration = VNTranslationalImageRegistrationRequest(targetedCGImage: scaledCG)
            let handler = VNImageRequestHandler(cgImage: reference)
            try? handler.perform([registration])
            if let transform = registration.results?.first?.alignmentTransform {
                let aligned = scaledCandidate.transformed(by: transform)
                    .cropped(to: CGRect(origin: .zero, size: size))
                if let image = context.createCGImage(aligned, from: aligned.extent) {
                    alignedData = try? encode(image)
                }
            }
        }

        return Comparison(identicalFiles: identical, featureDistance: distance, alignedImageData: alignedData)
    }

    func render(at url: URL, settings: EditSettings, maxPixel: Int) throws -> Data {
        let source = try loadImage(at: url, maxPixel: maxPixel)
        var image = CIImage(cgImage: source)
        let originalExtent = image.extent

        if settings.background != .original, let mask = try subjectMask(for: source, url: url, maxPixel: maxPixel) {
            let background: CIImage
            switch settings.background {
            case .original:
                background = image
            case .blur:
                background = image.clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: settings.blurRadius])
                    .cropped(to: originalExtent)
            case .white:
                background = CIImage(color: .white).cropped(to: originalExtent)
            case .black:
                background = CIImage(color: .black).cropped(to: originalExtent)
            }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = image
            blend.backgroundImage = background
            blend.maskImage = mask
            image = blend.outputImage ?? image
        }

        let extent = image.extent
        let crop = settings.crop
        let cropRect = CGRect(
            x: extent.minX + extent.width * crop.minX,
            y: extent.minY + extent.height * (1 - crop.maxY),
            width: extent.width * crop.width,
            height: extent.height * crop.height
        ).intersection(extent)
        guard cropRect.width > 0, cropRect.height > 0 else { throw EditorIssue.failedToRender }
        image = image.cropped(to: cropRect)
        if settings.rotationRadians != 0 {
            image = image.transformed(by: CGAffineTransform(rotationAngle: settings.rotationRadians))
        }
        let outputExtent = image.extent
        image = image.composited(over: CIImage(color: .white).cropped(to: outputExtent))
        guard let output = context.createCGImage(image, from: outputExtent) else { throw EditorIssue.failedToRender }
        return try encode(output)
    }

    func export(at url: URL, settings: EditSettings) throws -> URL {
        let data = try render(at: url, settings: settings, maxPixel: 0)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoLab-" + UUID().uuidString + ".jpg")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    private func subjectMask(for source: CGImage, url: URL, maxPixel: Int) throws -> CIImage? {
        let key = url.path + ":" + String(maxPixel)
        if let cached = masks[key] { return cached }
        let handler = VNImageRequestHandler(cgImage: source)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
        let buffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let mask = CIImage(cvPixelBuffer: buffer)
        masks[key] = mask
        return mask
    }

    private func featurePrint(for image: CGImage) throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let result = request.results?.first else { throw EditorIssue.unsupportedImage }
        return result
    }

    private func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize()
    }

    private func loadImage(at url: URL, maxPixel: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw EditorIssue.unsupportedImage
        }
        let limit = maxPixel == 0 ? max(width, height) : maxPixel
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw EditorIssue.unsupportedImage
        }
        return image
    }

    private func encode(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw EditorIssue.failedToRender
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw EditorIssue.failedToRender }
        return data as Data
    }
}
