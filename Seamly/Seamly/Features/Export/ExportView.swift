import SwiftUI
import UniformTypeIdentifiers

/// Export options for a finished capture. The full-resolution image is composited on demand
/// here; Photos access is requested only when the user actually saves.
struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let captureID: UUID
    let model: CaptureModel

    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section("Image") {
                    Button { save() } label: { Label("Save to Photos", systemImage: "photo.on.rectangle") }
                    if let pngURL {
                        ShareLink(item: pngURL) { Label("Share PNG", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { prepareImage() } label: { Label("Prepare PNG to share", systemImage: "square.and.arrow.up") }
                    }
                    Button { copy() } label: { Label("Copy to Clipboard", systemImage: "doc.on.doc") }
                }
                Section("Document") {
                    if let pdfURL {
                        ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "doc.richtext") }
                    } else {
                        Button { preparePDF() } label: { Label("Prepare PDF", systemImage: "doc.richtext") }
                    }
                }
                if busy { HStack { ProgressView(); Text("Working…") } }
                if let status { Text(status).foregroundStyle(.secondary) }
            }
            .navigationTitle("Export")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let image = try await model.fullComposite(captureID)
                try await Exporter.saveToPhotos(image)
                status = "Saved to Photos."
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func prepareImage() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let image = try await model.fullComposite(captureID)
                pngURL = try Exporter.pngURL(image, name: "Seamly-\(captureID.uuidString)")
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func preparePDF() {
        busy = true
        Task {
            defer { busy = false }
            do { pdfURL = try await model.exportPDF(captureID) }
            catch { status = error.localizedDescription }
        }
    }

    private func copy() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let image = try await model.fullComposite(captureID)
                Exporter.copyToPasteboard(image)
                status = "Copied."
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
