import SwiftUI
import CoreGraphics
import UIKit

/// Where a finished capture goes. Grouped image vs document, because that is the decision the
/// user is actually making.
///
/// Nothing is prepared until it is asked for, and the sheet is built fresh on every
/// presentation — so a file rendered from the geometry as it was cannot outlive a repair. The
/// old result screen cached PNG and PDF URLs for the screen's lifetime and had to discard them
/// explicitly on every return from repair, because two of its four export paths would
/// otherwise have handed out pre-repair bytes.
struct ExportSheet: View {
    let captureID: UUID
    let model: CaptureModel
    let onClose: () -> Void

    @State private var busy = false
    @State private var status: String?
    @State private var shareItem: ShareItem?

    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    var body: some View {
        SheetChrome(title: "Export") {
            EmptyView()
        } trailing: {
            SeamlyButton("Done", variant: .plain, size: .small, action: onClose)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if let capture {
                    HStack(spacing: SeamlySpace.s3) {
                        Text(SeamlyNumber.dimensions(
                            width: Int(capture.pixelSize.width),
                            height: Int(capture.pixelSize.height)
                        ))
                        .monospacedDigit()
                        if !capture.findings.isEmpty {
                            Text("· \(capture.findings.count) unanswered").monospacedDigit()
                        }
                    }
                    .font(SeamlyFont.mono)
                    .foregroundStyle(SeamlyColor.inkFaint)
                    .padding(.bottom, SeamlySpace.s5)
                }

                caps("Image")
                ImportRow(symbol: "photo", title: "Save to Photos",
                          detail: "Full resolution PNG", action: saveToPhotos)
                ImportRow(symbol: "square.and.arrow.up", title: "Share PNG",
                          detail: "Composited on demand", action: sharePNG)
                ImportRow(symbol: "doc.on.doc", title: "Copy to Clipboard", action: copy)

                caps("Document").padding(.top, SeamlySpace.s7)
                ImportRow(symbol: "doc.richtext", title: "Export PDF",
                          detail: "Paginated for very long captures", action: sharePDF)

                if busy {
                    ProgressView()
                        .padding(.top, SeamlySpace.s6)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s8)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .alert(
            "Export",
            isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(status ?? "")
        }
        .disabled(busy)
    }

    private func caps(_ text: String) -> some View {
        Text(text.uppercased())
            .font(SeamlyFont.caps)
            .seamlyCapsTracking()
            .foregroundStyle(SeamlyColor.inkFaint)
            .padding(.bottom, SeamlySpace.s3)
    }

    // MARK: - Actions

    private func saveToPhotos() {
        run {
            let image = try await model.fullComposite(captureID)
            try await Exporter.saveToPhotos(image)
            status = "Saved to Photos."
        }
    }

    private func sharePNG() {
        run {
            let image = try await model.fullComposite(captureID)
            shareItem = ShareItem(url: try Exporter.pngURL(image, name: "Seamly-\(captureID.uuidString)"))
        }
    }

    private func sharePDF() {
        run { shareItem = ShareItem(url: try await model.exportPDF(captureID)) }
    }

    private func copy() {
        run {
            let image = try await model.fullComposite(captureID)
            Exporter.copyToPasteboard(image)
            status = "Copied."
        }
    }

    /// Shared tail: every export path surfaces what actually went wrong, in plain language —
    /// never a generic "something failed", and never a bridged Swift enum description. The
    /// model logs the raw error to `Diagnostics`.
    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await body() }
            catch { status = CaptureCondition.message(for: error) }
        }
    }
}

/// `UIActivityViewController` has no SwiftUI equivalent that can be presented *from* a sheet
/// with a prepared file — `ShareLink` needs its item at construction time, and these files are
/// composited on demand. This is the same class of exception as `BroadcastPickerButton`.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
