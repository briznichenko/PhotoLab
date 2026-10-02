import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var store = EditorStore()
    @State private var firstSelection: PhotosPickerItem?
    @State private var secondSelection: PhotosPickerItem?
    @State private var showingInspector = false
    @State private var showingCamera = false
    @State private var comparisonStyle = 0
    @State private var useAlignment = false
    @State private var linkedZoom = true
    @State private var reveal = 0.5
    @State private var primaryScale = 1.0
    @State private var secondaryScale = 1.0
    @State private var primaryPan = CGSize.zero
    @State private var secondaryPan = CGSize.zero

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    pickers
                    if let photo = store.photos[0] {
                        editing(for: photo)
                    }
                    if let first = store.photos[0], let second = store.photos[1] {
                        comparison(first: first, second: second)
                    }
                }
                .padding()
            }
            .navigationTitle("PhotoLab")
            .toolbar {
                if store.isBusy {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
        }
        .task(id: firstSelection) { await store.importSelection(firstSelection, into: 0) }
        .task(id: secondSelection) { await store.importSelection(secondSelection, into: 1) }
        .task(id: store.renderRevision) { await store.refreshPreview() }
        .alert("Image issue", isPresented: Binding(
            get: { store.issue != nil },
            set: { if !$0 { store.issue = nil } }
        )) {
            Button("OK", role: .cancel) { store.issue = nil }
        } message: {
            Text(store.issue ?? "")
        }
        .sheet(isPresented: $showingInspector) {
            if let image = store.editedPreview ?? store.photos[0]?.preview {
                NavigationStack {
                    ZoomImage(image: image, scale: $primaryScale, pan: $primaryPan)
                        .background(.black)
                        .navigationTitle("Inspect")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showingInspector = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(
                onImage: { image in
                    showingCamera = false
                    Task { await store.importCameraImage(image) }
                },
                onCancel: { showingCamera = false }
            )
            .ignoresSafeArea()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Edit one photo. Compare two.")
                .font(.title2.bold())
            Text("Vision suggests a crop, finds text and subjects, checks similarity, and aligns close matches. You control the final edit.")
                .foregroundStyle(.secondary)
        }
    }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                photoPicker("Photo A", selection: $firstSelection, photo: store.photos[0])
                photoPicker("Photo B", selection: $secondSelection, photo: store.photos[1])
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo A with Camera", systemImage: "camera") {
                    showingCamera = true
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func photoPicker(_ title: String, selection: Binding<PhotosPickerItem?>, photo: Photo?) -> some View {
        PhotosPicker(selection: selection, matching: .images, preferredItemEncoding: .current) {
            VStack(spacing: 8) {
                if let photo {
                    Image(uiImage: photo.thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 110)
                        .clipped()
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.largeTitle)
                        .frame(height: 110)
                }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose \(title)")
    }

    private func editing(for photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Edit Photo A")
            if let image = store.editedPreview {
                Button { showingInspector = true } label: {
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

    private func comparison(first: Photo, second: Photo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Compare")
            if let result = store.comparison {
                if result.identicalFiles {
                    Label("These files have identical bytes", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if let distance = result.featureDistance {
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

            Picker("View", selection: $comparisonStyle) {
                Text("Side by side").tag(0)
                Text("Reveal").tag(1)
            }
            .pickerStyle(.segmented)
            Toggle("Link zoom and pan", isOn: $linkedZoom)
            Toggle("Use Vision alignment", isOn: $useAlignment)
                .disabled(store.comparison?.alignedImageData == nil)

            let secondImage = (useAlignment ? store.comparison?.alignedImageData : nil)
                .flatMap(UIImage.init(data:)) ?? second.preview
            if comparisonStyle == 0 {
                HStack(spacing: 4) {
                    ZoomImage(image: first.preview, scale: $primaryScale, pan: $primaryPan)
                    ZoomImage(
                        image: secondImage,
                        scale: linkedZoom ? $primaryScale : $secondaryScale,
                        pan: linkedZoom ? $primaryPan : $secondaryPan
                    )
                }
                .frame(height: 260)
            } else {
                RevealComparison(
                    first: first.preview,
                    second: secondImage,
                    reveal: $reveal,
                    scale: $primaryScale,
                    pan: $primaryPan
                )
                .frame(height: 320)
                Slider(value: $reveal, in: 0...1)
            }
            Text("Alignment works best for near copies of the same scene. Inspect the edges before trusting a difference.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.title3.bold())
    }
}

private struct CropCanvas: View {
    let image: UIImage
    @Binding var crop: CGRect
    let textRegions: [TextRegion]
    let onCommit: () -> Void
    @State private var dragStart: CGRect?

    var body: some View {
        GeometryReader { geometry in
            let fitted = fit(image.size, inside: geometry.size)
            let cropFrame = CGRect(
                x: fitted.minX + crop.minX * fitted.width,
                y: fitted.minY + crop.minY * fitted.height,
                width: crop.width * fitted.width,
                height: crop.height * fitted.height
            )
            ZStack(alignment: .topLeading) {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                ForEach(textRegions) { region in
                    Rectangle()
                        .stroke(.orange, lineWidth: 1)
                        .frame(width: region.rect.width * fitted.width, height: region.rect.height * fitted.height)
                        .position(
                            x: fitted.minX + region.rect.midX * fitted.width,
                            y: fitted.minY + region.rect.midY * fitted.height
                        )
                }
                Rectangle()
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(.yellow.opacity(0.08))
                    .frame(width: cropFrame.width, height: cropFrame.height)
                    .position(x: cropFrame.midX, y: cropFrame.midY)
                    .contentShape(Rectangle())
                    .gesture(DragGesture()
                        .onChanged { value in
                            let start = dragStart ?? crop
                            if dragStart == nil { dragStart = crop }
                            crop.origin.x = min(max(0, start.origin.x + value.translation.width / fitted.width), 1 - crop.width)
                            crop.origin.y = min(max(0, start.origin.y + value.translation.height / fitted.height), 1 - crop.height)
                        }
                        .onEnded { _ in
                            dragStart = nil
                            onCommit()
                        })
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(height: 280)
    }
}

private struct ZoomImage: View {
    let image: UIImage
    @Binding var scale: Double
    @Binding var pan: CGSize
    @State private var panStart: CGSize?
    @GestureState private var pinch = 1.0

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(scale * pinch)
                .offset(x: pan.width * geometry.size.width, y: pan.height * geometry.size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture()
                    .onChanged { value in
                        let start = panStart ?? pan
                        if panStart == nil { panStart = pan }
                        pan = clampedPan(CGSize(
                            width: start.width + value.translation.width / geometry.size.width,
                            height: start.height + value.translation.height / geometry.size.height
                        ), in: geometry.size, at: scale)
                    }
                    .onEnded { _ in panStart = nil })
                .simultaneousGesture(MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(1, scale * value.magnification), 6)
                        pan = clampedPan(pan, in: geometry.size, at: scale)
                    })
        }
        .background(.black)
        .clipped()
    }

    private func clampedPan(_ candidate: CGSize, in container: CGSize, at zoom: Double) -> CGSize {
        let content = fit(image.size, inside: container)
        let horizontal = max(0, (content.width * zoom - container.width) / 2) / container.width
        let vertical = max(0, (content.height * zoom - container.height) / 2) / container.height
        return CGSize(
            width: min(max(candidate.width, -horizontal), horizontal),
            height: min(max(candidate.height, -vertical), vertical)
        )
    }
}

private struct RevealComparison: View {
    let first: UIImage
    let second: UIImage
    @Binding var reveal: Double
    @Binding var scale: Double
    @Binding var pan: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ZoomImage(image: first, scale: $scale, pan: $pan)
                ZoomImage(image: second, scale: $scale, pan: $pan)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geometry.size.width * reveal)
                    }
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * (reveal - 0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private func fit(_ image: CGSize, inside container: CGSize) -> CGRect {
    guard image.width > 0, image.height > 0 else { return .zero }
    let ratio = min(container.width / image.width, container.height / image.height)
    let size = CGSize(width: image.width * ratio, height: image.height * ratio)
    return CGRect(
        x: (container.width - size.width) / 2,
        y: (container.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}
