import SwiftUI
import PhotosUI
import CoreGraphics
import ImageIO

/// "From Photos" entry: pick several overlapping screenshots; decode each to a CGImage and hand
/// them to the model in pick order. Requires at least two (a single image isn't a stitch).
struct PhotoImportButton: View {
    let model: CaptureModel
    var onStarted: () -> Void = {}
    @State private var selection: [PhotosPickerItem] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .images) {
                Label("From Photos", systemImage: "photo.on.rectangle.angled")
            }
            if let loadError { Text(loadError).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        loadError = nil
        // Clear up front, not on the success branch: `PhotosPickerItem` is `Equatable` and
        // `.onChange` only fires on a *change*, so a selection still standing when we return —
        // after an error, or while an import is in flight — makes re-picking the same photos a
        // no-op and the button looks dead. `items` is already captured, so this is safe here.
        selection = []
        var images: [CGImage] = []
        for (i, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    loadError = "Couldn't read photo \(i + 1)."; return
                }
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    loadError = "Photo \(i + 1) isn't a decodable image."; return
                }
                images.append(img)
            } catch {
                loadError = error.localizedDescription; return
            }
        }
        guard images.count >= 2 else { loadError = "Pick at least two overlapping screenshots."; return }
        onStarted()
        await model.importPhotos(images)
    }
}
