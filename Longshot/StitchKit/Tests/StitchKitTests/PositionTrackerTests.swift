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

    // MARK: - Content-band bootstrap + lock (Gap 1)

    private static let chromeTop = 10, chromeBottom = 10, window = 80
    private static var chromeHeight: Int { chromeTop + window + chromeBottom } // 100

    private func chromePattern(_ i: Int) -> Float { Float((i * 37) % 100) / 100 }

    /// A frame modeling a real screen: high-variance static chrome top+bottom wrapping a
    /// *low-variance* content window (means distinct per row, but low horizontal variance —
    /// the case that biases the unmasked matcher to dy=0).
    private func chromeFrame(_ doc: [Float], scroll: Int) -> FrameProfile {
        let top = Self.chromeTop, bottom = Self.chromeBottom, w = Self.window
        let total = Self.chromeHeight
        var means = [Float](repeating: 0, count: total)
        var vars = [Float](repeating: 0, count: total)
        for i in 0..<top { means[i] = chromePattern(i); vars[i] = 0.3 }
        for r in 0..<w { means[top + r] = doc[scroll + r]; vars[top + r] = 0.02 }
        for i in 0..<bottom { means[total - bottom + i] = chromePattern(1000 + i); vars[total - bottom + i] = 0.3 }
        return FrameProfile(means: means, variances: vars, sourceWidth: 100, sourceHeight: total * 10)
    }

    @Test func lowVarianceContentAdvancesViaBootstrap() {
        // The catastrophic startup stall (Gap 1): with static chrome and faint content, the
        // unmasked matcher pins dy=0 and the whole capture is lost. The bootstrap mask must
        // let the tracker advance from the first scroll.
        let doc = content(2000)
        var t = PositionTracker()
        var last = t.process(chromeFrame(doc, scroll: 0))
        for s in stride(from: 20, through: 100, by: 20) { last = t.process(chromeFrame(doc, scroll: s)) }
        // 6 frames scrolling 20 rows each -> union advanced 5*20 beyond the first frame.
        #expect(last.position == 100)
        #expect(last.maxY == Self.chromeHeight + 100)
    }

    @Test func locksAndExposesContentBandInPixels() {
        let doc = content(2000)
        var t = PositionTracker()
        _ = t.process(chromeFrame(doc, scroll: 0))
        var last = t.process(chromeFrame(doc, scroll: 20))
        for s in stride(from: 40, through: 100, by: 20) { last = t.process(chromeFrame(doc, scroll: s)) }
        // rowScale = sourceHeight/rowCount = (100*10)/100 = 10; chrome 10 rows -> 100 px.
        #expect(last.contentBand.topChrome == 100)
        #expect(last.contentBand.bottomChrome == 100)
        #expect(last.contentBand.isLowConfidence == false)
    }

    @Test func collapsingHeaderBreaksSegment() {
        let doc = content(2000)
        var t = PositionTracker()
        _ = t.process(chromeFrame(doc, scroll: 0))
        var last = TrackingResult(decision: .skipped, needsSafetyCue: false, position: 0, maxY: 0, confidence: 1, segmentIndex: 0)
        for s in stride(from: 20, through: 100, by: 20) { last = t.process(chromeFrame(doc, scroll: s)) }
        #expect(last.segmentIndex == 0)   // still one segment through the stable stretch

        // Header collapses 10 -> 2 rows: rows [2,10) that were chrome become content. The
        // pair still overlaps (content [10,90) unchanged), so this is a band change, not a
        // lost lock.
        var collapsed = chromeFrame(doc, scroll: 100)
        var means = collapsed.means, vars = collapsed.variances
        for i in 2..<Self.chromeTop { means[i] = doc[500 + i]; vars[i] = 0.02 }
        collapsed = FrameProfile(means: means, variances: vars, sourceWidth: 100, sourceHeight: collapsed.sourceHeight)

        let broke = t.process(collapsed)
        #expect(broke.decision == .segmentBreak(reason: .contentChanged))
        #expect(broke.segmentIndex == 1)
    }
}
