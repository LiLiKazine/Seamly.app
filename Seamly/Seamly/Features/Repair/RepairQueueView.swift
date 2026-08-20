import SwiftUI
import StitchKit

/// Repair as a QUEUE. The user never hunts a 15 000 px image: each problem is presented zoomed,
/// with one question and a wide affirmative answer, because most flagged seams turn out fine
/// and the common case must be one tap.
///
/// The ground is **paper**, not the black canvas the previous repair screen used. That was a
/// considered choice for judging alignment and this reverses it deliberately: the design puts a
/// white sheet on a paper ground, and the sheet is white in both themes, so the content itself
/// is never dimmed.
struct RepairQueueView: View {
    let captureID: UUID
    let model: CaptureModel
    let onClose: () -> Void

    @State private var queue: RepairQueueModel
    @State private var zoom = ZoomState()
    @State private var showManual = false
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    /// The queue was the one screen family that read no size class at all, so on iPad it ran
    /// full-bleed at the phone gutter while Home, Review and Library all adapt. The kit's own
    /// `RepairQueue.jsx` uses the size-class gutter and caps the stage at 620.
    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }

    /// The queue opens hard at 6x; pinch multiplies from there. A named constant because it
    /// must reach BOTH the rendering zoom and the drag's zoom divisor — passing the bare pinch
    /// factor to the drag while rendering at 6x makes the finger move `dy` six times further
    /// than the pixels actually moved, which silently defeats "zoom is the precision mechanism".
    private static let openingZoom: CGFloat = 6

    /// A bars or gap finding is judged against the whole-capture proxy, jumped into position —
    /// there is nothing to drag, so it opens at the same base scale `ReviewScreen` uses for the
    /// same proxy, rather than the seam stage's 6x close-up.
    private static let reviewZoom: CGFloat = 1

    init(captureID: UUID, model: CaptureModel, startAt: Int, onClose: @escaping () -> Void) {
        self.captureID = captureID
        self.model = model
        self.onClose = onClose
        _queue = State(initialValue: RepairQueueModel(captureID: captureID, model: model, startAt: startAt))
    }

    private var capture: Capture? { model.captures.first { $0.id == captureID } }
    private var captureSize: CGSize { capture?.pixelSize ?? .zero }
    private var marks: [CaptureMark] { capture?.displayMarks ?? [] }
    private var findings: [Finding] { queue.findings }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "Repair",
                subtitle: "\(queue.answeredCount) of \(queue.findings.count) answered"
            ) {
                IconButton(symbol: "xmark", label: "Close") {
                    Task { if await queue.commit() { onClose() } }
                }
            }

            if let finding = queue.current {
                stage(finding)
                prompt(finding)
            } else {
                EmptyState(
                    symbol: "checkmark.seal",
                    title: "Nothing to fix",
                    message: "Every seam matched confidently."
                )
                .frame(maxHeight: .infinity)
                SeamlyButton("Close", action: onClose)
                    .padding(SeamlySpace.gutterCompact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
        .overlay { saving }
        .task(id: queue.position) {
            showManual = false
            zoom.reset()
            await queue.load()
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(
                get: { queue.saveError != nil },
                set: { if !$0 { queue.clearSaveError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(queue.saveError ?? "")
        }
    }

    // MARK: - The problem, zoomed

    /// A seam is judged against the live frame pair, because the proxy would not move under
    /// the finger. Bars and gaps are judged against the capture itself, jumped to the frame or
    /// the break in question — there is nothing to drag, and what the user needs to see is the
    /// picture as it stands.
    @ViewBuilder
    private func stage(_ finding: Finding) -> some View {
        Group {
            if let message = queue.loadError {
                EmptyState(symbol: "exclamationmark.triangle", title: "Can't show this", message: message)
            } else if finding.kind == .seam {
                if let frames = queue.frames, let alignment = queue.alignment {
                    CaptureView(
                        content: .join(upper: frames.upper, lower: frames.lower, alignment: alignment),
                        captureSize: captureSize,
                        // NO margin marks on the seam stage. The intention was that the margin
                        // keep describing the whole capture, but it cannot: `.join` has no
                        // ScrollView, so `scrollY` is pinned at 0 while `captureSize` is the whole
                        // capture at 6×. Every mark resolves to `atPct · sheetWidth · 6 · aspect`,
                        // which puts all of them thousands of points below the viewport on a long
                        // capture — and, worse, lands one at a meaningless position on a short
                        // one. A rail that is either empty or lying is worse than no rail.
                        marks: [],
                        findings: findings,
                        zoom: Self.openingZoom * zoom.scale,
                        selected: finding.n,
                        showScale: false,
                        onDrag: { translation, ratio, start in
                            queue.drag(translation: translation, sourcePixelsPerPoint: ratio,
                                       from: start, zoom: Self.openingZoom * zoom.scale)
                        },
                        currentDy: alignment.dy
                    )
                    .simultaneousGesture(magnify)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let proxy = capture?.proxy {
                CaptureView(
                    content: .proxy(proxy),
                    captureSize: captureSize,
                    marks: marks,
                    findings: findings,
                    zoom: Self.reviewZoom * zoom.scale,
                    selected: finding.n,
                    showScale: false,
                    jump: CaptureJump(atPct: finding.atPct, fraction: 0.25, token: queue.position)
                )
                .simultaneousGesture(magnify)
            } else {
                EmptyState(
                    symbol: "photo.badge.exclamationmark",
                    title: "Can't show this",
                    message: "This capture is no longer on the device."
                )
            }
        }
        .frame(maxWidth: SeamlySpace.queueStageMax)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, layout.gutter)
        .padding(.top, SeamlySpace.s3)
        .padding(.bottom, SeamlySpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { zoom.update(magnification: $0.magnification) }
            .onEnded { _ in withAnimation(SeamlyMotion.base) { zoom.end() } }
    }

    // MARK: - The question

    @ViewBuilder
    private func prompt(_ finding: Finding) -> some View {
        QueuePrompt(
            index: queue.position + 1,
            total: queue.findings.count,
            kind: finding.kind,
            question: finding.question,
            detail: finding.detail,
            // Only a seam has an offset to state. A gap has nothing overlapping; a bars answer
            // is a crop, and the steppers show it.
            value: finding.kind == .seam ? queue.alignment?.dy : nil,
            affirmative: affirmative(finding),
            // A gap has no lever — the content was never captured, so a nudge would move
            // nothing. Offering a control that does nothing is worse than offering none.
            onNudge: finding.kind == .seam ? { queue.nudge($0) } : nil,
            onAccept: { accept(finding) },
            onSkipAll: { Task { if await queue.commit() { onClose() } } }
        ) {
            manualPath(finding)
        }
    }

    private func affirmative(_ finding: Finding) -> String {
        switch finding.kind {
        case .seam: "Looks right"
        // Once the user has said what the bars ARE, "No bars here" is the wrong sentence on the
        // button that accepts it — and the wrong instruction to the model behind it.
        case .bars: queue.hasEditedChrome(for: finding) ? "Looks right" : "No bars here"
        case .gap: "Got it"
        }
    }

    private func accept(_ finding: Finding) {
        // "No bars here" is itself the answer, and must be recorded as one: an edge nobody has
        // answered and an edge answered "none" crop identically but are not the same state.
        if finding.kind == .bars { queue.acceptNoBars(for: finding) }
        Task { if await queue.answer() { onClose() } }
    }

    @ViewBuilder
    private func manualPath(_ finding: Finding) -> some View {
        // A gap cannot be adjusted at all — there is no number behind it.
        if finding.kind == .gap {
            EmptyView()
        } else if !showManual {
            Button("Adjust manually") { showManual = true }
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.accent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                switch finding.kind {
                case .seam:
                    if let alignment = queue.alignment {
                        StepperRow(
                            label: "Offset",
                            value: alignment.dy,
                            step: 1,
                            range: alignment.dyRange,
                            hint: "Source pixels between the two halves"
                        ) { queue.setDy($0) }
                    }
                case .bars:
                    StepperRow(
                        label: "Top bar",
                        value: queue.chromeValue(.top, for: finding),
                        step: 5,
                        range: queue.chromeRange(.top, for: finding),
                        hint: "Repeated chrome cropped from this frame"
                    ) { queue.setChrome($0, edge: .top, for: finding) }
                    StepperRow(
                        label: "Bottom bar",
                        value: queue.chromeValue(.bottom, for: finding),
                        step: 5,
                        range: queue.chromeRange(.bottom, for: finding)
                    ) { queue.setChrome($0, edge: .bottom, for: finding) }
                case .gap:
                    EmptyView()
                }
            }
            .padding(.horizontal, SeamlySpace.s4)
            .background(SeamlyColor.paper)
            .overlay {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .strokeBorder(SeamlyColor.rule, lineWidth: 1)
            }
            .seamlyCorners(SeamlyRadius.sm)
        }
    }

    // MARK: - Committing

    /// Committing awaits `CaptureModel.update(_:)`, which persists the manifest *and*
    /// re-composites at full resolution plus a proxy — seconds on a long capture. Without this
    /// the screen is simply frozen: every control is disabled and the stage still has frames,
    /// so the loading branch cannot stand in.
    @ViewBuilder
    private var saving: some View {
        if queue.busy {
            ZStack {
                // Dims rather than replaces: the user keeps sight of the join they just lined
                // up, and the dimming is itself the signal that it is no longer live.
                SeamlyColor.ink.opacity(0.4)
                ProgressView().controlSize(.large)
            }
            .ignoresSafeArea()
            .accessibilityIdentifier("repair-saving")
            .accessibilityLabel("Saving")
        }
    }
}
