import SwiftUI

struct ComparisonViewState {
    var style = 0
    var useAlignment = false
    var linkedZoom = true
    var reveal = 0.5
    var primaryScale = 1.0
    var secondaryScale = 1.0
    var primaryPan = CGSize.zero
    var secondaryPan = CGSize.zero
}

struct PhotoComparisonView: View {
    let first: Photo
    let second: Photo
    let comparison: Comparison?
    @Binding var state: ComparisonViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare").font(.title3.bold())
            if let comparison {
                if comparison.identicalFiles {
                    Label("These files have identical bytes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let distance = comparison.featureDistance {
                    Text("Vision feature distance: \(distance, format: .number.precision(.fractionLength(3))) · lower means more similar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Vision similarity is unavailable on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Analyzing similarity")
            }

            Picker("View", selection: $state.style) {
                Text("Side by side").tag(0)
                Text("Reveal").tag(1)
            }
            .pickerStyle(.segmented)
            Toggle("Link zoom and pan", isOn: $state.linkedZoom)
            Toggle("Use Vision alignment", isOn: $state.useAlignment)
                .disabled(comparison?.alignedImageData == nil)

            let secondImage = (state.useAlignment ? comparison?.alignedImageData : nil)
                .flatMap(UIImage.init(data:)) ?? second.preview
            if state.style == 0 {
                HStack(spacing: 4) {
                    ZoomImage(image: first.preview, scale: $state.primaryScale, pan: $state.primaryPan)
                    ZoomImage(
                        image: secondImage,
                        scale: state.linkedZoom ? $state.primaryScale : $state.secondaryScale,
                        pan: state.linkedZoom ? $state.primaryPan : $state.secondaryPan
                    )
                }
                .frame(height: 260)
            } else {
                RevealComparison(
                    first: first.preview,
                    second: secondImage,
                    reveal: $state.reveal,
                    scale: $state.primaryScale,
                    pan: $state.primaryPan
                )
                .frame(height: 320)
                Slider(value: $state.reveal, in: 0...1)
            }
            Text("Alignment works best for near copies of the same scene. Inspect the edges before trusting a difference.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
