import SwiftUI

struct CropCanvas: View {
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

struct ZoomImage: View {
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

struct RevealComparison: View {
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
