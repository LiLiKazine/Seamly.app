import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A picked movie, copied out of the Photos sandbox into a temp URL for AVAssetReader.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            // Copy: the received file is a temporary the system reclaims after this closure.
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// "From Video" entry: pick one screen recording; hand its URL to the model, which decodes it
/// into keyframes and stitches in capture order.
struct VideoImportButton: View {
    let model: LibraryModel
    var onStarted: () -> Void = {}
    @State private var selection: PhotosPickerItem?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selection, matching: .videos) {
                Label("From Video", systemImage: "film")
            }
            if let loadError { Text(loadError).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        loadError = nil
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                loadError = "Couldn't read that video."; return
            }
            selection = nil
            onStarted()
            await model.importVideo(movie.url)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
