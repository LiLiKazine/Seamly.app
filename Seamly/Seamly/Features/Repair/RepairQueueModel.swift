import CoreGraphics
import Foundation
import Observation
import StitchKit

/// The queue's state: which finding is on screen, what the user has answered but not yet saved,
/// and the one write at the end.
///
/// Off the view because the commit is the delicate part. An edit that did not survive to disk
/// must never be reported as saved — `DECISIONS.md [B4]` is that class of bug on the import
/// path, and `CaptureModel.update(_:)` throws precisely so this can surface it.
@MainActor
@Observable
final class RepairQueueModel {
    let captureID: UUID
    private let model: CaptureModel

    private(set) var findings: [Finding] = []
    var position: Int = 0
    private(set) var answered: Set<Int> = []

    private(set) var frames: (upper: CGImage, lower: CGImage)?
    private(set) var alignment: JoinAlignment?
    private(set) var loadError: String?
    /// Separate from `loadError`: a save failure must not blank out the canvas the user was
    /// just looking at and might retry against.
    private(set) var saveError: String?
    private(set) var busy = false

    /// Answers held until the queue finishes. Committed once, because a chrome change moves
    /// every position below it and a per-answer commit would re-composite — seconds on a long
    /// capture — between two questions.
    private var editedDy: [Int: Int] = [:]
    private var editedChrome: [UUID: ChromeInsets] = [:]
    /// The edges the user has actually answered. `editedChrome` cannot serve: it holds a whole
    /// `ChromeInsets` per keyframe, so it cannot tell an edge the user set from the sibling it
    /// carried along untouched.
    private var editedEdges: [UUID: Set<ChromeEdge>] = [:]

    /// Bumped at the top of every `load()`; a load only commits its result if this still
    /// matches when its `await` returns. `CaptureModel.joinFrames` reads through an independent
    /// `Task.detached`, which does not observe a `.task(id:)` cancellation, so a slow load can
    /// resolve after a faster later one. Tokens rather than finding numbers: paging away and
    /// back is a legitimate way to reach the same finding twice, and the first visit's stale
    /// load must not overwrite what the second visit (and a drag on top of it) produced.
    private var loadToken = 0

    init(captureID: UUID, model: CaptureModel, startAt: Int) {
        self.captureID = captureID
        self.model = model
        let findings = model.captures.first { $0.id == captureID }?.findings ?? []
        self.findings = findings
        self.position = findings.firstIndex { $0.n == startAt } ?? 0
    }

    var current: Finding? { findings.indices.contains(position) ? findings[position] : nil }
    var answeredCount: Int { answered.count }
    var hasPendingEdits: Bool { !editedDy.isEmpty || !editedChrome.isEmpty }

    private var session: StitchSession? {
        model.captures.first { $0.id == captureID }?.session
    }

    // MARK: - Loading

    /// The single load path. Every exit sets either `loadError` or the pair of `frames` and
    /// `alignment` — it never leaves the screen on a spinner with nothing in flight to end it.
    func load() async {
        loadToken += 1
        let token = loadToken
        loadError = nil
        frames = nil
        alignment = nil

        guard let session else {
            loadError = CaptureCondition.message(for: CaptureModel.CaptureError.notFound)
            return
        }
        guard let finding = current else {
            loadError = CaptureCondition.nothingToLineUpMessage
            return
        }
        // Only a seam has frames to load. Bars and gaps answer against the proxy.
        guard case .join(let joinIndex) = finding.target else { return }

        var next = JoinAlignment(session: session, joinIndex: joinIndex)
        // Carry an unsaved edit across a move between findings, so paging away and back does
        // not silently discard the user's work.
        if let dy = editedDy[joinIndex] { next?.setDy(dy) }
        guard let resolved = next else {
            loadError = CaptureCondition.joinNotDescribedMessage
            return
        }
        do {
            let loaded = try await model.joinFrames(captureID, joinIndex: joinIndex)
            guard token == loadToken else { return }
            frames = loaded
            alignment = resolved
        } catch {
            guard token == loadToken else { return }
            // The model logged the raw error; this is the sentence a person can read.
            loadError = CaptureCondition.message(for: error)
        }
    }

    // MARK: - Answering a seam

    func drag(translation: CGFloat, sourcePixelsPerPoint: CGFloat, from start: Int, zoom: CGFloat) {
        guard var alignment, case .join(let joinIndex)? = current?.target else { return }
        let next = alignment.dy(
            draggedBy: translation, from: start,
            sourcePixelsPerPoint: sourcePixelsPerPoint, zoom: zoom
        )
        alignment.setDy(next)
        self.alignment = alignment
        editedDy[joinIndex] = next
    }

    func setDy(_ value: Int) {
        guard var alignment, case .join(let joinIndex)? = current?.target else { return }
        alignment.setDy(value)
        self.alignment = alignment
        editedDy[joinIndex] = alignment.dy
    }

    /// Two source pixels per press: one is imperceptible at 1×, and the queue's chevrons are a
    /// coarse correction — the stepper behind *Adjust manually* is where single pixels live.
    func nudge(_ direction: Int) {
        guard let alignment else { return }
        setDy(alignment.dy + direction * 2)
    }

    // MARK: - Advancing and committing

    /// Mark the current finding answered and move on. Returns `true` when the queue is done and
    /// the caller should close.
    ///
    /// Answering a seam records its offset **even if the user never dragged**. That is the
    /// point of the queue: most flagged seams turn out fine, so the common case is one tap on
    /// the affirmative — and that tap has to mean "I looked at this and it is right". Without
    /// this, an untouched seam writes nothing, `isLowConfidence` stays set, and the finding
    /// comes straight back the next time the capture is opened, having wasted the user's answer.
    func answer() async -> Bool {
        if case .join(let joinIndex)? = current?.target, let alignment {
            editedDy[joinIndex] = alignment.dy
        }
        if let n = current?.n { answered.insert(n) }
        if position + 1 < findings.count {
            position += 1
            return false
        }
        return await commit()
    }

    /// Write every held answer, once. Returns `true` when the caller may close — either the
    /// write succeeded or there was nothing to write.
    func commit() async -> Bool {
        guard hasPendingEdits else { return true }
        guard var session else {
            // The capture disappeared out from under this screen while edits were pending.
            // This drop is not silent: it reads like any other failed save.
            saveError = CaptureCondition.message(for: CaptureModel.CaptureError.notFound)
            return false
        }
        busy = true
        defer { busy = false }

        for (joinIndex, dy) in editedDy {
            guard let i = session.seams.firstIndex(where: { $0.fromIndex == joinIndex }) else {
                // Unreachable: `editedDy` is only set where a `JoinAlignment` exists, and its
                // init requires the seam. Skipping this one edit is the least-bad response to
                // manifest data we did not expect — better than discarding the whole batch.
                continue
            }
            session.seams[i].provisionalDy = dy
            // The user has now looked at this join with their own eyes. Leaving it flagged
            // would re-raise a finding over a join they just answered.
            session.seams[i].isLowConfidence = false
        }
        for (keyframeID, insets) in editedChrome {
            session.setChromeOverride(insets.top, for: .top, keyframeID: keyframeID)
            session.setChromeOverride(insets.bottom, for: .bottom, keyframeID: keyframeID)
        }

        do {
            try await model.update(session)
            editedDy.removeAll()
            editedChrome.removeAll()
            return true
        } catch {
            // The model logged the raw error; this is the sentence a person can read. The
            // edits stay held so the user can try again — they must never be led to believe a
            // repair saved when it did not.
            saveError = CaptureCondition.message(for: error)
            return false
        }
    }

    func clearSaveError() { saveError = nil }

    // MARK: - Answering bars

    /// The crop currently in force for one edge, including any answer held but not yet written.
    func chromeValue(_ edge: ChromeEdge, for finding: Finding) -> Int {
        guard case .chrome(let keyframeID, _) = finding.target else { return 0 }
        if let held = editedChrome[keyframeID] {
            return edge == .top ? held.top : held.bottom
        }
        return session?.chromeValueForEditing(edge, keyframeID: keyframeID) ?? 0
    }

    /// The compositor refuses a **combined** crop past half the frame, and
    /// `setChromeOverride` clamps each edge to what the other leaves free — so the control must
    /// stop there too, rather than letting a stepper run on while the picture stops moving.
    ///
    /// That means the range is per-edge and depends on the sibling's current value: a ceiling
    /// of half the frame handed to *both* steppers would let the user dial each to the maximum
    /// and then silently see the second one clamped to zero on commit, which is exactly the
    /// "the number you set is not the number that got written" failure this is here to avoid.
    func chromeRange(_ edge: ChromeEdge, for finding: Finding) -> ClosedRange<Int> {
        guard case .chrome(let keyframeID, _) = finding.target,
              let keyframe = session?.keyframes.first(where: { $0.id == keyframeID })
        else { return 0...0 }
        let limit = Int(Double(keyframe.pixelHeight) * ChromeInsets.maxCombinedCropFraction)
        let held = heldOrResolvedChrome(for: keyframeID)
        let sibling = edge == .top ? held.bottom : held.top
        return 0...max(0, limit - sibling)
    }

    func setChrome(_ value: Int, edge: ChromeEdge, for finding: Finding) {
        guard case .chrome(let keyframeID, _) = finding.target else { return }
        var insets = heldOrResolvedChrome(for: keyframeID)
        switch edge {
        case .top: insets.top = value
        case .bottom: insets.bottom = value
        }
        editedChrome[keyframeID] = insets
        // Which EDGE was answered, not merely that this keyframe has an entry. Keyed by keyframe
        // alone, touching one stepper silently protected the other from being answered at all —
        // see `acceptNoBars`.
        editedEdges[keyframeID, default: []].insert(edge)
    }

    /// "No bars here" — the affirmative answer for a bars finding.
    ///
    /// Writes an explicit **zero** override rather than leaving the edge alone. Resolution is
    /// already lossless at zero, so nothing about the picture changes; what changes is that the
    /// edge now has a *user* value, which is what stops `chromeEdgesNeedingReview` returning it
    /// and stops the queue asking again. An unanswered edge and an edge answered "none" resolve
    /// to the same crop and must not read as the same state.
    ///
    /// Only the edges **actually in doubt** are zeroed. A finding's `edges` set can name one
    /// edge alone — the other may carry a confidently measured crop — and blanketing both would
    /// overwrite that measurement with a user "none", un-cropping a bar the pipeline had got
    /// right. That is the precise regression this whole feature exists to prevent.
    /// An edge the user has already dialled in is **not** zeroed either. Held answers were being
    /// read back and then overwritten with 0, so a crop typed into *Adjust manually* was destroyed
    /// by the very tap that submitted it — and the affirmative was the only way to advance a bars
    /// finding, which made the manual path unreachable in practice. Only "Skip all" preserved it,
    /// so the two exits did exactly opposite things.
    func acceptNoBars(for finding: Finding) {
        guard case .chrome(let keyframeID, let edges) = finding.target else { return }
        let answered = editedEdges[keyframeID] ?? []
        var insets = heldOrResolvedChrome(for: keyframeID)
        // Per EDGE. A keyframe-wide test let a nudge on the confident bottom stepper protect the
        // uncertain top edge from ever being zeroed — and `commit` then wrote that untouched,
        // low-confidence guess as a real override, so the edge actually in doubt stopped being
        // flagged without the user ever having answered it. Quieter than the bug it replaced,
        // and worse: nothing on screen said anything had been decided.
        if edges.contains(.top), !answered.contains(.top) { insets.top = 0 }
        if edges.contains(.bottom), !answered.contains(.bottom) { insets.bottom = 0 }
        editedChrome[keyframeID] = insets
    }

    /// Whether the user has typed a crop for this finding's keyframe, which changes what the
    /// affirmative answer means: "no bars here" for an untouched finding, "this is right" once
    /// they have said what the bars actually are.
    func hasEditedChrome(for finding: Finding) -> Bool {
        guard case .chrome(let keyframeID, _) = finding.target else { return false }
        return !(editedEdges[keyframeID] ?? []).isEmpty
    }

    /// The crop currently in force for a keyframe — a held answer if there is one, otherwise
    /// what the session resolves today. Shared by `setChrome` and `acceptNoBars` so neither can
    /// clobber the edge it is not editing.
    private func heldOrResolvedChrome(for keyframeID: UUID) -> ChromeInsets {
        editedChrome[keyframeID] ?? ChromeInsets(
            top: session?.chromeValueForEditing(.top, keyframeID: keyframeID) ?? 0,
            bottom: session?.chromeValueForEditing(.bottom, keyframeID: keyframeID) ?? 0
        )
    }
}
