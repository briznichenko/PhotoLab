import SwiftUI

struct PhotoEditingView: View {
    let photo: Photo
    @Bindable var store: EditorStore
    let onInspect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Photo A").font(.title3.bold())
            if let image = store.editedPreview {
                Button(action: onInspect) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 270)
                        .background(.black, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                Text("Tap to inspect with pinch and pan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Crop").font(.headline)
                CropCanvas(
                    image: photo.preview,
                    crop: $store.settings.crop,
                    textRegions: store.analysis?.text ?? [],
                    onCommit: store.editsChanged
                )
                cropDimension("Width", isWidth: true)
                cropDimension("Height", isWidth: false)
                HStack {
                    Button("Smart crop") { store.useSmartCrop() }
                        .disabled(store.analysis?.smartCrop == nil)
                    Button("Keep text") { store.useTextCrop() }
                        .disabled(store.analysis?.text.isEmpty != false)
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Straighten").font(.headline)
                    Spacer()
                    Button("Use horizon") { store.useHorizon() }
                        .disabled(store.analysis?.horizonRadians == nil)
                }
                Slider(value: $store.settings.rotationRadians, in: -(.pi / 4)...(.pi / 4))
                    .onChange(of: store.settings.rotationRadians) { _, _ in store.editsChanged() }
                Text("\(Int(store.settings.rotationRadians * 180 / .pi))°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Subject and background").font(.headline)
                Picker("Background", selection: $store.settings.background) {
                    ForEach(BackgroundEffect.allCases) { effect in
                        Text(effect.rawValue).tag(effect)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.settings.background) { _, _ in store.editsChanged() }
                if store.settings.background == .blur {
                    Slider(value: $store.settings.blurRadius, in: 2...35)
                        .onChange(of: store.settings.blurRadius) { _, _ in store.editsChanged() }
                }
                Text("The background effect appears when Vision finds a foreground subject.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let text = store.analysis?.text, !text.isEmpty {
                DisclosureGroup("Recognized text (\(text.count))") {
                    ForEach(text) { region in
                        Text(region.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                    }
                }
            }

            HStack {
                Button("Reset edits") { store.resetEdits() }
                Spacer()
                Button("Export JPEG") { Task { await store.export() } }
                    .buttonStyle(.borderedProminent)
            }
            if let url = store.exportURL {
                ShareLink(item: url) {
                    Label("Share exported image", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func cropDimension(_ title: String, isWidth: Bool) -> some View {
        HStack {
            Text(title).frame(width: 55, alignment: .leading)
            Slider(value: Binding(
                get: { Double(isWidth ? store.settings.crop.width : store.settings.crop.height) },
                set: { newValue in
                    var crop = store.settings.crop
                    if isWidth {
                        crop.size.width = CGFloat(newValue)
                    } else {
                        crop.size.height = CGFloat(newValue)
                    }
                    crop.origin.x = min(crop.origin.x, 1 - crop.width)
                    crop.origin.y = min(crop.origin.y, 1 - crop.height)
                    store.settings.crop = crop
                    store.editsChanged()
                }
            ), in: 0.2...1)
        }
    }
}
