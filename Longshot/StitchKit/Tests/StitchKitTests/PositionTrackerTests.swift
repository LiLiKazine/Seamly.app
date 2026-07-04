import Testing
@testable import StitchKit

/// A long deterministic content signal to slice frames from.
private func content(_ count: Int) -> [Float] {
    var out = [Float]()
    var x: UInt64 = 99
    for _ in 0..<count {
        x = x &* 6364136223846793005 &+ 1442695040888963407
        out.append(Float((x >> 33) & 0xFFFF) / Float(0xFFFF))
    }
    return out
}

/// A frame of fixed `height` taken from `signal` starting at content row `pos`.
private func frame(_ signal: [Float], pos: Int, height: Int = 100, width: Int = 100) -> FrameProfile {
    let slice = Array(signal[pos..<pos + height])
    return FrameProfile(means: slice, variances: [Float](repeating: 0.1, count: height), sourceWidth: width, sourceHeight: height * 10)
}

@Suite struct PositionTrackerTests {
    @Test func steadyScrollDownAppendsRevealedRows() {
        let c = content(1000)
        var t = PositionTracker()
        _ = t.process(frame(c, pos: 0))
        let r1 = t.process(frame(c, pos: 20))
        let r2 = t.process(frame(c, pos: 40))
        #expect(r1.decision == .appended(rows: 20))
        #expect(r2.decision == .appended(rows: 20))
        #expect(r2.maxY == 140)
        #expect(r2.position == 40)
    }

    @Test func backScrollThenResumeCapturesUnionOnly() {
        let c = content(1000)
        var t = PositionTracker()
        _ = t.process(frame(c, pos: 0))
        _ = t.process(frame(c, pos: 20))
        _ = t.process(frame(c, pos: 40))          // maxY 140
        let back1 = t.process(frame(c, pos: 20))  // scroll up — within union
        let back2 = t.process(frame(c, pos: 0))   // more up — within union
        #expect(back1.decision == .skipped)
        #expect(back2.decision == .skipped)
        #expect(back2.maxY == 140)
        let resume = t.process(frame(c, pos: 60)) // past maxY again
        #expect(resume.decision == .appended(rows: 20))
        #expect(resume.maxY == 160)
    }

    @Test func pauseOnSameFrameSkips() {
        let c = content(1000)
        var t = PositionTracker()
        _ = t.process(frame(c, pos: 0))
        _ = t.process(frame(c, pos: 20))
        let pause = t.process(frame(c, pos: 20))
        #expect(pause.decision == .skipped)
        #expect(pause.maxY == 120)
    }

    @Test func firesSafetyCueWhenOverlapDropsBelowMargin() {
        let c = content(1000)
        var t = PositionTracker()
        _ = t.process(frame(c, pos: 0))
        let fast = t.process(frame(c, pos: 70))   // overlap 30% < 40% margin
        #expect(fast.needsSafetyCue)
        #expect(fast.decision == .appended(rows: 70))
    }

    @Test func noSafetyCueDuringComfortableOverlap() {
        let c = content(1000)
        var t = PositionTracker()
        _ = t.process(frame(c, pos: 0))
        let ok = t.process(frame(c, pos: 30))     // 70% overlap
        #expect(!ok.needsSafetyCue)
    }

    @Test func relocalizesAfterFlingBackOverSeenContent() {
        let c = content(2000)
        var t = PositionTracker()
        for p in stride(from: 0, through: 300, by: 50) { _ = t.process(frame(c, pos: p)) } // maxY 400, pos 300
        let jump = t.process(frame(c, pos: 50))   // no frame-to-frame overlap, but seen
        #expect(jump.decision == .relocalized(rows: 0))
        #expect(jump.position == 50)
        #expect(jump.maxY == 400)
    }

    @Test func flingIntoUnseenContentBreaksSegment() {
        let c = content(2000)
        var t = PositionTracker()
        for p in stride(from: 0, through: 100, by: 50) { _ = t.process(frame(c, pos: p)) } // maxY 200, pos 100
        let gap = t.process(frame(c, pos: 900))   // never seen, no overlap
        #expect(gap.decision == .segmentBreak(reason: .lostLock))
        #expect(gap.segmentIndex == 1)
        // The breaking frame seeds the new segment.
        let cont = t.process(frame(c, pos: 920))
        #expect(cont.decision == .appended(rows: 20))
        #expect(cont.segmentIndex == 1)
    }

    @Test func rotationBreaksSegment() {
        let c = content(1000)
        var t = PositionTracker()
        _ = t.process(frame(c, pos: 0, width: 100))
        _ = t.process(frame(c, pos: 20, width: 100))
        let rot = t.process(frame(c, pos: 40, width: 200))  // dimension change
        #expect(rot.decision == .segmentBreak(reason: .rotation))
        #expect(rot.segmentIndex == 1)
    }

    @Test func unionSurvivesOvershootSequence() {
        let c = content(2000)
        var t = PositionTracker()
        // down, overshoot back up, re-read, resume — union must equal furthest reached.
        let positions = [0, 40, 80, 120, 80, 40, 80, 120, 160, 200]
        var last = TrackingResult(decision: .skipped, needsSafetyCue: false, position: 0, maxY: 0, confidence: 1, segmentIndex: 0)
        for p in positions { last = t.process(frame(c, pos: p)) }
        #expect(last.maxY == 300)  // furthest top 200 + height 100
        #expect(last.segmentIndex == 0)
    }
}
