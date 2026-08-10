import SwiftUI
import StitchKit

/// The finished capture. In a one-shot app this is the destination, not a waypoint: saving
/// is the primary action, and once saved the user is offered a way to clear it out.
struct ResultView: View {
    let captureID: UUID
    let model: CaptureModel
    var onRecordAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var status: String?
    @State private var busy = false
    @State private var savedToPhotos = false

    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    private var condition: CaptureCondition {
        guard let capture else { return .failed("That capture is no longer available.") }
        switch capture.phase {
        case .processing: return .stitching
        case .failed(let message): return .failed(message)
        case .ready: return CaptureCondition(ready: CaptureFacts(capture.session))
        }
    }

    var body: some View {
        Group {
            switch condition {
            case .stitching:
                ProcessingView(progress: model.importProgress)
            case .failed(let message):
                CaptureFailureView(message: message, onRecordAgain: onRecordAgain)
            case .clean, .imperfect, .nothingToStitch:
                if let proxy = capture?.proxy {
                    VStack(spacing: 0) {
                        ConditionNotice(condition: condition)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        CaptureCanvas(proxy: proxy)
                    }
                } else {
                    ContentUnavailableView(
                        "Capture removed",
                        systemImage: "photo.badge.exclamationmark"
                    )
                }
            }
        }
        .navigationTitle("Your screenshot")
        .navigationBarTitleDisplayMode(.inline)
        // Export actions are meaningless while stitching or after a failure — there is
        // nothing to export — so the bar only appears once there is an image.
        .safeAreaInset(edge: .bottom) {
            if capture?.proxy != nil { actions }
        }
        .alert(
            "Export",
            isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(status ?? "")
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if busy { ProgressView() }

            Button {
                save()
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || capture?.proxy == nil)

            HStack(spacing: 16) {
                if let pngURL {
                    ShareLink(item: pngURL) { Label("Share", systemImage: "square.and.arrow.up") }
                } else {
                    Button { prepareImage() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label("PDF", systemImage: "doc.richtext") }
                } else {
                    Button { preparePDF() } label: { Label("PDF", systemImage: "doc.richtext") }
                }
            }
            .font(.subheadline)
            .disabled(busy)

            // Re-recording is offered only when it is actually the fix. A merely misaligned
            // join is not improved by recording again — that is what guided repair is for.
            if condition.recommendsRecordingAgain {
                Button("Record again", action: onRecordAgain).font(.subheadline)
            }

            if savedToPhotos {
                Button("Done — remove from Seamly", role: .destructive) {
                    model.delete(captureID)
                    dismiss()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.bar)
    }

    private func save() {
        run {
            let image = try await model.fullComposite(captureID)
            try await Exporter.saveToPhotos(image)
            savedToPhotos = true
            status = "Saved to Photos."
        }
    }

    private func prepareImage() {
        run {
            let image = try await model.fullComposite(captureID)
            pngURL = try Exporter.pngURL(image, name: "Seamly-\(captureID.uuidString)")
        }
    }

    private func preparePDF() {
        run { pdfURL = try await model.exportPDF(captureID) }
    }

    private func copy() {
        run {
            let image = try await model.fullComposite(captureID)
            Exporter.copyToPasteboard(image)
            status = "Copied."
        }
    }

    /// Shared tail: every export path surfaces what actually went wrong, in plain language —
    /// never a generic "something failed", and never a bridged Swift enum description
    /// (`CaptureCondition.message(for:)`). The model logs the raw error to `Diagnostics`.
    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await body() }
            catch { status = CaptureCondition.message(for: error) }
        }
    }
}
