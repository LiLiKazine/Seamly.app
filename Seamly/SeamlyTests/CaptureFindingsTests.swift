import Testing
import Foundation
import StitchKit
@testable import Seamly

/// A capture enumerates its own problems, and the number a margin marker shows is the number
/// the queue uses. Both come from here, so the ordering and the numbering are asserted rather
/// than assumed.
struct CaptureFindingsTests {

    private func session(
        count: Int,
        height: Int = 300,
        dy: Int = 180,
        flagged: Set<Int> = [],
        breaksAfter: [Int] = [],
        chromeReviewed: Set<Int> = []
    ) -> StitchSession {
        let keyframes = (0..<count).map {
            Keyframe(filename: "kf-\($0).bgra", pixelWidth: 120, pixelHeight: height, index: $0)
        }
        var s = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: keyframes,
            seams: (0..<max(0, count - 1)).map {
                Seam(fromIndex: $0, provisionalDy: dy, confidence: flagged.contains($0) ? 0.2 : 0.9,
                     isLowConfidence: flagged.contains($0))
            },
            segmentBreaks: breaksAfter.map { SegmentBreak(afterKeyframeIndex: $0, reason: .lostLock) }
        )
        // `chromeReviewed` names the frames whose bars are UNCERTAIN — they get a record with
        // no automatic measurement, which is what `chromeEdgesNeedingReview` keys off. Every
        // other frame gets a confident zero-inset measurement.
        s.keyframeChrome = keyframes.map { kf in
            chromeReviewed.contains(kf.index)
                ? KeyframeChrome(keyframeID: kf.id)
                : KeyframeChrome(keyframeID: kf.id,
                                 automatic: ChromeMeasurement(insets: .zero, confidence: 0.9))
        }
        return s
    }

    private func findings(_ s: StitchSession) -> [Finding] {
        CaptureFindings.all(in: s, placement: Compositor(refinementDelta: 0).placement(s))
    }

    // MARK: - What becomes a finding

    @Test func aCleanCaptureHasNoFindings() {
        #expect(findings(session(count: 4)).isEmpty)
    }

    @Test func aFlaggedSeamBecomesASeamFinding() throws {
        let all = findings(session(count: 4, flagged: [1]))
        #expect(all.count == 1)
        let f = try #require(all.first)
        #expect(f.kind == .seam)
        #expect(f.target == .join(1))
        #expect(f.question == "Does this line up?")
        #expect(f.dy == 180)
        #expect(f.confidence == 0.2)
    }

    @Test func aSegmentBreakBecomesAGapFinding() throws {
        let all = findings(session(count: 4, breaksAfter: [1]))
        #expect(all.count == 1)
        let f = try #require(all.first)
        #expect(f.kind == .gap)
        #expect(f.target == .gap(afterKeyframeIndex: 1))
        #expect(f.dy == nil, "nothing overlaps across a break, so there is no offset to state")
    }

    @Test func anUnmeasurableFrameBecomesABarsFinding() throws {
        let s = session(count: 3, chromeReviewed: [1])
        let all = findings(s)
        #expect(all.count == 1)
        let f = try #require(all.first)
        #expect(f.kind == .bars)
        #expect(f.question == "Where do the bars end?")
        guard case .chrome(let keyframeID, let edges) = f.target else {
            Issue.record("expected a chrome target, got \(f.target)")
            return
        }
        #expect(keyframeID == s.keyframes[1].id)
        #expect(edges == [.top, .bottom])
    }

    /// Nothing overlaps across a break, so `Compositor.plan` ignores that seam when laying the
    /// strip out — dragging it would move nothing. `RepairableJoins.walkable` excludes it for
    /// the same reason, and so must this.
    @Test func aFlaggedSeamAcrossABreakIsNotASeamFinding() {
        let all = findings(session(count: 4, flagged: [1], breaksAfter: [1]))
        #expect(all.filter { $0.kind == .seam }.isEmpty)
        #expect(all.filter { $0.kind == .gap }.count == 1)
    }

    // MARK: - Order and numbering

    @Test func findingsAreRankedByKindThenPosition() {
        let all = findings(session(count: 6, flagged: [0, 4], breaksAfter: [2], chromeReviewed: [3]))
        #expect(all.map(\.kind) == [.gap, .bars, .seam, .seam])
        #expect(all.map(\.n) == [1, 2, 3, 4])
        // Missing content outranks uncertain bars outranks an uncertain join — the same
        // ranking Imperfection.Kind already uses. Within a kind, top to bottom.
        let seams = all.filter { $0.kind == .seam }
        #expect(seams[0].atPct < seams[1].atPct)
    }

    @Test func numbersAreOneBasedAndContiguous() {
        let all = findings(session(count: 8, flagged: [1, 3, 5], breaksAfter: [6]))
        #expect(all.map(\.n) == Array(1...all.count))
    }

    @Test func everyFindingSitsInsideTheCapture() {
        for f in findings(session(count: 6, flagged: [0, 4], breaksAfter: [2], chromeReviewed: [3])) {
            #expect(f.atPct >= 0 && f.atPct <= 1, "\(f.title) at \(f.atPct)")
        }
    }

    @Test func idsAreStableAcrossRebuilds() {
        let s = session(count: 6, flagged: [0, 4], breaksAfter: [2], chromeReviewed: [3])
        #expect(findings(s).map(\.id) == findings(s).map(\.id))
    }

    // MARK: - Language

    /// The engine cannot know how much a break swallowed — that is what a break IS. Stating a
    /// pixel count would be inventing a number.
    @Test func aGapIsLabelledLostLockNotAPixelCount() throws {
        let s = session(count: 4, breaksAfter: [1])
        let marks = CaptureMarks.all(
            in: s,
            placement: Compositor(refinementDelta: 0).placement(s),
            findings: findings(s)
        )
        let gap = try #require(marks.first { $0.kind == .gap })
        #expect(gap.lostLabel == "lost lock")
    }

    @Test func frameNumbersReadOneBased() throws {
        let all = findings(session(count: 4, breaksAfter: [1]))
        #expect(try #require(all.first).title == "Gap after frame 2")
    }

    // MARK: - Marks

    @Test func everyJoinIsMarkedAndOnlyDoubtIsNumbered() {
        let s = session(count: 5, flagged: [2])
        let marks = CaptureMarks.all(
            in: s, placement: Compositor(refinementDelta: 0).placement(s), findings: findings(s)
        )
        #expect(marks.count == 4, "four joins in a five-frame capture")
        #expect(marks.filter { $0.kind == .confident }.count == 3)
        #expect(marks.filter { $0.n != nil }.count == 1, "a good capture must look like one image")
    }

    @Test func aMarksNumberIsItsFindingsNumber() throws {
        let s = session(count: 6, flagged: [4], breaksAfter: [2])
        let all = findings(s)
        let marks = CaptureMarks.all(in: s, placement: Compositor(refinementDelta: 0).placement(s), findings: all)
        for f in all {
            let mark = try #require(marks.first { $0.n == f.n })
            #expect(abs(mark.atPct - f.atPct) < 1e-9, "marker \(f.n) is not where finding \(f.n) is")
        }
    }
}
