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
        // Only a seam has frames to load. Bars and gaps answer against the proxy (Task 14).
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
    func answer() async -> Bool {
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

    /// Record a chrome answer. Used by Task 14.
    func setChrome(_ insets: ChromeInsets, keyframeID: UUID) {
        editedChrome[keyframeID] = insets
    }

    func chrome(for keyframeID: UUID) -> ChromeInsets? { editedChrome[keyframeID] }
}
