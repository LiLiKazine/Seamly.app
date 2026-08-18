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

    /// A join to open the repair on. A wrapper rather than a bare `Int` so `fullScreenCover(item:)`
    /// can identify it.
    private struct RepairTarget: Identifiable {
        let id: Int
    }

    @State private var repairTarget: RepairTarget?

    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    /// The join the repair should open on, or `nil` when this capture has nothing to line up.
    ///
    /// Two independent questions, deliberately kept apart: whether the *verdict* offers repair
    /// (`CaptureCondition.offersLiningUp`) and whether the *session* actually has a draggable join
    /// (`RepairableJoins`). A two-frame capture split by a segment break passes the first and fails
    /// the second, and opening a screen with nothing to drag would be worse than no entry at all.
    private var repairOpening: Int? {
        guard condition.offersLiningUp, let session = capture?.session else { return nil }
        let flaggedOnly = if case .imperfect = condition { true } else { false }
        return RepairableJoins.opening(in: session, flaggedOnly: flaggedOnly)
    }

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
            // `condition` above can't produce this today — a pickup with nothing in it is
            // discarded at import and surfaced on home, so it never becomes a capture with a
            // phase. Handled by name anyway: the case exists, and a `default:` here would let a
            // future path that *does* reach it fall into the image branch and render an empty
            // canvas instead of the coaching this state has.
            case .nothingToStitch:
                NothingToStitchView(onRecordAgain: onRecordAgain)
            // Everything left is a capture that stitched.
            case .clean, .imperfect:
                if let proxy = capture?.proxy {
                    VStack(spacing: 0) {
                        ConditionNotice(
                            condition: condition,
                            onLineUp: repairOpening.map { join in { repairTarget = RepairTarget(id: join) } }
                        )
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
        // The quiet entry. A clean capture gets the same words, in the toolbar rather than in a
        // notice — this app has shipped a confidently wrong "clean" verdict before, so a stitch we
        // judged fine still needs a way in. It stays out of the bottom bar, which already stacks
        // Save, the export row, and up to two more rows.
        .toolbar {
            if case .clean = condition, let join = repairOpening {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CaptureCondition.liningUpActionTitle) {
                        repairTarget = RepairTarget(id: join)
                    }
                    .font(.subheadline)
                }
            }
        }
        // Full screen rather than a push: a single-purpose surface with its own Cancel and Done,
        // and pushing it would sit a second back-chevron next to this screen's.
        .fullScreenCover(item: $repairTarget, onDismiss: discardPreparedExports) { target in
            RepairView(captureID: captureID, model: model, openingJoin: target.id)
        }
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

    /// Forget everything that was true of the *previous* manifest, on every return from the repair
    /// screen.
    ///
    /// `pngURL` and `pdfURL` are files already rendered from the geometry as it was; once a join
    /// moves they are stale bytes, and the buttons over them are `ShareLink`s that hand those bytes
    /// straight out. `Save to Photos` and `Copy` re-composite on every tap and so were never
    /// affected — which is exactly what made this easy to miss: two of four export paths silently
    /// broke the promise that the pixels under the finger are the pixels you get. Before guided
    /// repair nothing on this screen could change geometry, so caching them for the screen's
    /// lifetime was safe.
    ///
    /// `savedToPhotos` is the serious one. It is what shows *"Done — remove from Seamly"*, so
    /// leaving it set after a repair invites the user to delete the capture believing the repaired
    /// image is in Photos, when what is there is the copy saved *before* the repair — and the
    /// repaired one is then gone for good. That is data loss, not a stale cache.
    ///
    /// Cleared on *any* dismissal, Cancel included, rather than only on a committed change: this
    /// screen cannot see whether the user actually moved anything, and the trade is one-sided —
    /// re-preparing a file costs a tap, while handing over a stale export or a false "already
    /// saved" costs the user their work.
    private func discardPreparedExports() {
        pngURL = nil
        pdfURL = nil
        savedToPhotos = false
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
