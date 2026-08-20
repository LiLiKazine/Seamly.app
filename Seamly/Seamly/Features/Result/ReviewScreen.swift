import SwiftUI
import StitchKit

/// The capture at length, and the one screen where regular width is a different design rather
/// than a bigger one.
struct ReviewScreen: View {
    let captureID: UUID
    let model: CaptureModel
    var onBack: () -> Void
    var onRepair: (Int) -> Void
    var onExport: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    @State private var selected: Int?
    /// `ZoomState`, not a bare `CGFloat`. `MagnifyGesture.magnification` is cumulative from the
    /// START of the current gesture, so multiplying it into an already-updated scale on every
    /// tick compounds superlinearly and slams into the clamp instead of tracking the finger.
    /// `ZoomState` exists in this codebase precisely to bank the committed scale separately —
    /// see its doc comment, which records the bug it was written for.
    @State private var zoom = ZoomState()
    @State private var jump: CaptureJump?
    @State private var jumpToken = 0

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }
    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    var body: some View {
        Group {
            if let capture, let proxy = capture.proxy, capture.phase == .ready {
                if layout.isRegular {
                    regular(capture, proxy)
                } else {
                    compact(capture, proxy)
                }
            } else {
                // Deleted out from under this screen, or still stitching. Either way there is
                // nothing to review; Home is where the state of a capture is reported.
                VStack(spacing: 0) {
                    NavBar(title: "Review", backLabel: "Home", onBack: onBack)
                    EmptyState(
                        symbol: "photo.badge.exclamationmark",
                        title: "Nothing to show yet",
                        message: "This capture isn't ready. Go back and Seamly will tell you where it got to."
                    )
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    // MARK: - Shared pieces

    private func head(_ capture: Capture) -> some View {
        NavBar(
            title: capture.title,
            subtitle: SeamlyNumber.dimensions(
                width: Int(capture.pixelSize.width),
                height: Int(capture.pixelSize.height)
            ) + " · " + SeamlyNumber.counted(capture.session.keyframes.count, "frame", "frames"),
            backLabel: layout.isRegular ? "Library" : "",
            onBack: onBack
        ) {
            if let first = capture.findings.first {
                IconButton(symbol: "slider.horizontal.3", label: "Repair") { onRepair(first.n) }
            }
            IconButton(symbol: "square.and.arrow.up", label: "Export", action: onExport)
        }
    }

    private func stage(_ capture: Capture, _ proxy: CGImage) -> some View {
        CaptureView(
            content: .proxy(proxy),
            captureSize: capture.pixelSize,
            marks: capture.displayMarks,
            findings: capture.findings,
            zoom: zoom.scale,
            selected: selected,
            jump: jump,
            onSelect: { jumpTo($0, in: capture) }
        )
        .padding(.horizontal, layout.gutter)
        .padding(.top, SeamlySpace.s4)
        .padding(.bottom, SeamlySpace.s5)
        .gesture(
            MagnifyGesture()
                .onChanged { zoom.update(magnification: $0.magnification) }
                .onEnded { _ in withAnimation(SeamlyMotion.base) { zoom.end() } }
        )
    }

    /// Select, zoom in, and pan the mark to 40 % down. Never a screen transition — the user is
    /// already looking at this capture, and pushing would throw away the place they had.
    private func jumpTo(_ n: Int, in capture: Capture) {
        guard let finding = capture.findings.first(where: { $0.n == n }) else { return }
        selected = n
        zoom.set(3)
        jumpToken += 1
        jump = CaptureJump(atPct: finding.atPct, token: jumpToken)
    }

    // MARK: - Compact

    private func compact(_ capture: Capture, _ proxy: CGImage) -> some View {
        VStack(spacing: 0) {
            head(capture)
            stage(capture, proxy)
            HStack(spacing: SeamlySpace.s4) {
                summary(capture)
                Spacer(minLength: SeamlySpace.s4)
                if let first = capture.findings.first {
                    SeamlyButton("Review them", symbol: "arrow.right") { onRepair(first.n) }
                        .accessibilityIdentifier("open-repair")
                }
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .frame(minHeight: 52)
        }
    }

    // MARK: - Regular

    private func regular(_ capture: Capture, _ proxy: CGImage) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                head(capture)
                stage(capture, proxy)
            }
            rail(capture)
                .frame(width: SeamlySpace.sidebarWidth)
                .background(SeamlyColor.paperRaised)
                .overlay(alignment: .leading) {
                    Rectangle().fill(SeamlyColor.rule).frame(width: 1)
                }
        }
    }

    private func rail(_ capture: Capture) -> some View {
        let findings = capture.findings
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(findings.isEmpty ? "Nothing to fix" : "\(findings.count) to look at")
                    .font(SeamlyFont.title3)
                    .foregroundStyle(SeamlyColor.ink)
                    .seamlyDisplayTracking()
                Text(findings.isEmpty
                     ? "Every seam matched confidently."
                     : "Select one to jump there.")
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SeamlySpace.s5)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(findings) { finding in
                        FindingLine(finding: finding, selected: selected == finding.n) {
                            jumpTo(finding.n, in: capture)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: SeamlySpace.s4) {
                SeamlyButton("Repair", variant: .outline) {
                    findings.first.map { onRepair($0.n) }
                }
                .disabled(findings.isEmpty)
                .frame(maxWidth: .infinity)
                SeamlyButton("Export", symbol: "square.and.arrow.up", action: onExport)
                    .frame(maxWidth: .infinity)
            }
            .padding(SeamlySpace.s5)
            .overlay(alignment: .top) {
                Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summary(_ capture: Capture) -> some View {
        let findings = capture.findings
        let flagged = capture.flaggedCount
        let gaps = capture.gapCount
        HStack(spacing: SeamlySpace.s3) {
            if flagged > 0 { StatusNote(kind: .flagged, count: flagged) }
            if gaps > 0 { StatusNote(kind: .gap, count: gaps) }
            if findings.isEmpty { StatusNote(kind: .ready, label: "Every seam matched confidently") }
        }
    }
}

/// One row in the regular-width rail. Its number is the number on the margin marker, which is
/// the number the repair queue counts by.
private struct FindingLine: View {
    let finding: Finding
    let selected: Bool
    let action: () -> Void

    private var color: Color {
        switch finding.kind {
        case .gap: SeamlyColor.markGap
        case .bars, .seam: SeamlyColor.markFlag
        }
    }

    /// Numbers carry their unit and don't reflow. `dy` is the offset under the finger;
    /// a gap has none, because nothing overlaps across a break.
    private var measurement: String {
        var parts: [String] = []
        if let dy = finding.dy {
            // Through `SeamlyNumber`, not hand-formatted: a real scroll step runs to four
            // figures, and an ungrouped "dy +1420 px" beside a grouped "884 × 15 402 px" is
            // exactly the inconsistency the thin-space rule exists to prevent.
            parts.append("dy \(dy > 0 ? "+" : "")" + SeamlyNumber.px(dy))
        } else if finding.kind == .gap {
            parts.append("never revealed")
        }
        if let confidence = finding.confidence {
            parts.append("conf \(String(format: "%.2f", confidence))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: SeamlySpace.s4) {
                Text("\(finding.n)")
                    .font(SeamlyFont.caps)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(color, lineWidth: 1.5) }
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(finding.title)
                        .font(SeamlyFont.subheadline)
                        .foregroundStyle(SeamlyColor.ink)
                        .multilineTextAlignment(.leading)
                    if !measurement.isEmpty {
                        Text(measurement)
                            .font(SeamlyFont.mono)
                            .monospacedDigit()
                            .foregroundStyle(SeamlyColor.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(SeamlySpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? SeamlyColor.accentWash : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
        .accessibilityIdentifier("finding-\(finding.n)")
    }
}
