import SwiftUI
import StitchKit

/// RETURN HOME. The app is backgrounded while the user scrolls another app, so the most common
/// launch context is *"I just stopped a broadcast — what did I get?"* This screen answers that
/// before anything else: the newest capture, resolved, with its marks already visible and one
/// way into fixing them.
///
/// Tapping a margin marker here opens the repair queue at that finding, which deliberately
/// differs from Review, where the same tap only jumps. Home is a glance and the marker is the
/// way in; Review is where you are already looking, and a screen change there would throw away
/// the place you had.
struct HomeScreen: View {
    let model: CaptureModel
    var onLibrary: () -> Void
    var onReview: (UUID) -> Void
    var onRepair: (UUID, Int) -> Void
    var onHelp: () -> Void
    var onVideo: () -> Void
    var onPhotos: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @State private var jumpToken = 0

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }
    private var capture: Capture? { model.captures.first }

    var body: some View {
        VStack(spacing: 0) {
            if let capture {
                header(capture)
                stage(capture)
                statusRow(capture)
            } else {
                NavBar(title: "Seamly", subtitle: "Capture beyond the screen", large: true) {
                    IconButton(symbol: "questionmark.circle", label: "How it works", action: onHelp)
                }
                Spacer(minLength: 0)
                EmptyState(
                    symbol: "plus.viewfinder",
                    title: "Nothing captured yet",
                    message: "Record your screen while you scroll another app, and Seamly stitches everything you reveal into one image."
                )
                Spacer(minLength: 0)
            }
            CaptureDock(onVideo: onVideo, onPhotos: onPhotos)
                .padding(.horizontal, layout.gutter)
                .padding(.top, SeamlySpace.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ capture: Capture) -> some View {
        NavBar(title: "Seamly") {
            IconButton(symbol: "list.bullet", label: "Library", action: onLibrary)
            IconButton(symbol: "questionmark.circle", label: "How it works", action: onHelp)
        }
        HStack(alignment: .firstTextBaseline, spacing: SeamlySpace.s4) {
            Text(capture.title)
                .font(SeamlyFont.largeTitle)
                .foregroundStyle(SeamlyColor.ink)
                .seamlyDisplayTracking()
            Spacer(minLength: SeamlySpace.s4)
            if capture.phase == .ready {
                Text(SeamlyNumber.dimensions(
                    width: Int(capture.pixelSize.width),
                    height: Int(capture.pixelSize.height)
                ))
                .font(SeamlyFont.mono)
                .foregroundStyle(SeamlyColor.inkFaint)
            }
        }
        .padding(.horizontal, layout.gutter)
    }

    // MARK: - The capture, or what happened instead of one

    @ViewBuilder
    private func stage(_ capture: Capture) -> some View {
        Group {
            switch capture.phase {
            case .ready:
                if let proxy = capture.proxy {
                    CaptureView(
                        content: .proxy(proxy),
                        captureSize: capture.pixelSize,
                        marks: capture.displayMarks,
                        findings: capture.findings,
                        onSelect: { n in onRepair(capture.id, n) }
                    )
                } else {
                    // Stored, resolved, but the proxy is gone — deleted out from under us.
                    EmptyState(
                        symbol: "photo.badge.exclamationmark",
                        title: "Capture removed",
                        message: "This capture is no longer on the device."
                    )
                }
            case .processing:
                ProgressNote(label: "Stitching…", value: model.importProgress)
                    .frame(maxWidth: SeamlySpace.columnMax)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                // The design is silent here. Never a raw error: `message` already came through
                // `CaptureCondition.message(for:)`, and the raw one is in Diagnostics. There is
                // no separate "Record again" button because the dock is already on screen
                // directly below with Record as its hero — a second one would be the same
                // action twice.
                VStack(spacing: SeamlySpace.s5) {
                    StatusNote(kind: .failed)
                    Text(message)
                        .font(SeamlyFont.footnote)
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: SeamlySpace.columnMax)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, SeamlySpace.s5)
        .frame(maxWidth: layout.isRegular ? 720 : .infinity)
        .frame(maxWidth: .infinity)
    }

    // MARK: - What this capture wants to say

    @ViewBuilder
    private func statusRow(_ capture: Capture) -> some View {
        let findings = capture.phase == .ready ? capture.findings : []
        let flagged = findings.filter { $0.kind == .seam || $0.kind == .bars }.count
        let gaps = findings.filter { $0.kind == .gap }.count

        HStack(spacing: SeamlySpace.s4) {
            HStack(spacing: SeamlySpace.s3) {
                if capture.session.status == .recording { StatusNote(kind: .incomplete) }
                if capture.session.orderAssumed { StatusNote(kind: .orderAssumed) }
                if flagged > 0 { StatusNote(kind: .flagged, count: flagged) }
                if gaps > 0 { StatusNote(kind: .gap, count: gaps) }
                if capture.phase == .ready, findings.isEmpty {
                    StatusNote(kind: .ready, label: "Every seam matched confidently")
                }
            }
            Spacer(minLength: SeamlySpace.s4)
            if capture.phase == .ready, capture.proxy != nil {
                SeamlyButton(
                    findings.isEmpty ? "Open" : "Review them",
                    variant: .plain,
                    symbol: findings.isEmpty ? nil : "arrow.right"
                ) {
                    onReview(capture.id)
                }
                .accessibilityIdentifier("review-capture")
            }
        }
        .padding(.horizontal, layout.gutter)
        .frame(minHeight: SeamlySpace.hitMin)
    }
}
