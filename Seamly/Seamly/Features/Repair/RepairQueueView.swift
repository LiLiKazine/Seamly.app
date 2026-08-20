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

    /// The queue opens hard at 6x; pinch multiplies from there. A named constant because it
    /// must reach BOTH the rendering zoom and the drag's zoom divisor — passing the bare pinch
    /// factor to the drag while rendering at 6x makes the finger move `dy` six times further
    /// than the pixels actually moved, which silently defeats "zoom is the precision mechanism".
    private static let openingZoom: CGFloat = 6

    init(captureID: UUID, model: CaptureModel, startAt: Int, onClose: @escaping () -> Void) {
        self.captureID = captureID
        self.model = model
        self.onClose = onClose
        _queue = State(initialValue: RepairQueueModel(captureID: captureID, model: model, startAt: startAt))
    }

    private var capture: Capture? { model.captures.first { $0.id == captureID } }
    /// The stage shows one join, but the margin still describes the WHOLE capture — so the
    /// marker the user tapped stays visible beside the pixels it points at.
    private var captureSize: CGSize { capture?.pixelSize ?? .zero }
    private var marks: [CaptureMark] { capture?.displayMarks ?? [] }

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

    @ViewBuilder
    private func stage(_ finding: Finding) -> some View {
        Group {
            if let message = queue.loadError {
                EmptyState(symbol: "exclamationmark.triangle", title: "Can't show this", message: message)
            } else if let frames = queue.frames, let alignment = queue.alignment {
                CaptureView(
                    content: .join(upper: frames.upper, lower: frames.lower, alignment: alignment),
                    captureSize: captureSize,
                    marks: marks,
                    zoom: Self.openingZoom * zoom.scale,
                    selected: finding.n,
                    showScale: false,
                    onDrag: { translation, ratio, start in
                        queue.drag(
                            translation: translation,
                            sourcePixelsPerPoint: ratio,
                            from: start,
                            zoom: Self.openingZoom * zoom.scale
                        )
                    },
                    currentDy: alignment.dy
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { zoom.update(magnification: $0.magnification) }
                        .onEnded { _ in withAnimation(SeamlyMotion.base) { zoom.end() } }
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.top, SeamlySpace.s3)
        .padding(.bottom, SeamlySpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            value: queue.alignment?.dy,
            onNudge: { queue.nudge($0) },
            onAccept: { Task { if await queue.answer() { onClose() } } },
            onSkipAll: { Task { if await queue.commit() { onClose() } } }
        ) {
            manualPath(finding)
        }
    }

    @ViewBuilder
    private func manualPath(_ finding: Finding) -> some View {
        if !showManual {
            Button("Adjust manually") { showManual = true }
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.accent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let alignment = queue.alignment {
            VStack(spacing: 0) {
                StepperRow(
                    label: "Offset",
                    value: alignment.dy,
                    step: 1,
                    range: alignment.dyRange,
                    hint: "Source pixels between the two halves"
                ) { queue.setDy($0) }
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
