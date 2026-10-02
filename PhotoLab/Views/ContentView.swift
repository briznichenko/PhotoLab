import PhotosUI
import SwiftUI

struct ContentView: View {
    @State private var store = EditorStore()
    @State private var firstSelection: PhotosPickerItem?
    @State private var secondSelection: PhotosPickerItem?
    @State private var showingInspector = false
    @State private var showingCamera = false
    @State private var comparisonState = ComparisonViewState()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    introduction
                    PhotoSelectionView(
                        firstSelection: $firstSelection,
                        secondSelection: $secondSelection,
                        firstPhoto: store.photo(at: 0),
                        secondPhoto: store.photo(at: 1),
                        onCamera: { showingCamera = true }
                    )
                    if let photo = store.photo(at: 0) {
                        PhotoEditingView(photo: photo, store: store, onInspect: { showingInspector = true })
                    }
                    if let first = store.photo(at: 0), let second = store.photo(at: 1) {
                        PhotoComparisonView(
                            first: first,
                            second: second,
                            comparison: store.comparison,
                            state: $comparisonState
                        )
                    }
                }
            }
            .padding(.horizontal, 8)
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
            if let image = store.editedPreview ?? store.photo(at: 0)?.preview {
                NavigationStack {
                    ZoomImage(image: image, scale: $comparisonState.primaryScale, pan: $comparisonState.primaryPan)
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
}
