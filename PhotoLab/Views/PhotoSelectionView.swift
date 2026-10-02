import PhotosUI
import SwiftUI

struct PhotoSelectionView: View {
    @Binding var firstSelection: PhotosPickerItem?
    @Binding var secondSelection: PhotosPickerItem?
    let firstPhoto: Photo?
    let secondPhoto: Photo?
    let onCamera: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                photoPicker("Photo A", selection: $firstSelection, photo: firstPhoto)
                photoPicker("Photo B", selection: $secondSelection, photo: secondPhoto)
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo A with Camera", systemImage: "camera", action: onCamera)
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
                        .scaledToFit()
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
}
