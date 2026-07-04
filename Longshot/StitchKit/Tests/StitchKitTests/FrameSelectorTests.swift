import Testing
@testable import StitchKit

/// Construct a tracking result directly so keyframe-selection logic is tested in isolation.
private func res(_ decision: TrackingDecision, maxY: Int, position: Int = 0, confidence: Double = 0.9, segment: Int = 0, cue: Bool = false) -> TrackingResult {
    TrackingResult(decision: decision, needsSafetyCue: cue, position: position, maxY: maxY, confidence: confidence, segmentIndex: segment)
}

@Suite struct FrameSelectorTests {
    @Test func firstFrameCommitsKeyframe() {
        var s = FrameSelector()
        #expect(s.evaluate(res(.appended(rows: 100), maxY: 100), bandHeight: 100) == .commitKeyframe)
    }

    @Test func smallAdvancesAreIgnoredUntilThreshold() {
        var s = FrameSelector()
        _ = s.evaluate(res(.appended(rows: 100), maxY: 100), bandHeight: 100)
        #expect(s.evaluate(res(.appended(rows: 20), maxY: 120), bandHeight: 100) == .ignore)
        #expect(s.evaluate(res(.appended(rows: 20), maxY: 140), bandHeight: 100) == .ignore)
        // 65% of 100 = 65 rows advance -> commit at maxY 165.
        #expect(s.evaluate(res(.appended(rows: 25), maxY: 165), bandHeight: 100) == .commitKeyframe)
    }

    @Test func committedKeyframesRetainAtLeast30PercentOverlap() {
        var s = FrameSelector()
        var t = PositionTracker()
        var commitPositions: [Int] = []
        var pos = 0
        while pos <= 400 {
            let r = t.process(FrameProfile(
                means: sig(pos), variances: [Float](repeating: 0.1, count: 100), sourceWidth: 100, sourceHeight: 1000))
            if s.evaluate(r, bandHeight: 100) == .commitKeyframe { commitPositions.append(r.position) }
            pos += 5
        }
        #expect(commitPositions.count >= 4)
        for i in 1..<commitPositions.count {
            let spacing = commitPositions[i] - commitPositions[i - 1]
            #expect(spacing <= 70)   // overlap = 100 - spacing >= 30%
        }
    }

    @Test func lowConfidenceFrameDefersCommit() {
        var s = FrameSelector()
        _ = s.evaluate(res(.appended(rows: 100), maxY: 100), bandHeight: 100)
        // Threshold crossed but the frame is low quality -> defer.
        #expect(s.evaluate(res(.appended(rows: 70), maxY: 170, confidence: 0.1), bandHeight: 100) == .ignore)
        // A clean frame just past it commits.
        #expect(s.evaluate(res(.appended(rows: 10), maxY: 180, confidence: 0.9), bandHeight: 100) == .commitKeyframe)
    }

    @Test func backScrollAndPauseNeverCommit() {
        var s = FrameSelector()
        _ = s.evaluate(res(.appended(rows: 100), maxY: 100), bandHeight: 100)
        #expect(s.evaluate(res(.skipped, maxY: 100), bandHeight: 100) == .ignore)
        #expect(s.evaluate(res(.skipped, maxY: 100), bandHeight: 100) == .ignore)
    }

    @Test func segmentBreakSeedsNewKeyframe() {
        var s = FrameSelector()
        _ = s.evaluate(res(.appended(rows: 100), maxY: 100), bandHeight: 100)
        _ = s.evaluate(res(.appended(rows: 65), maxY: 165), bandHeight: 100)
        // New segment starts (maxY resets to the new frame height).
        #expect(s.evaluate(res(.segmentBreak(reason: .lostLock), maxY: 100, segment: 1), bandHeight: 100) == .commitKeyframe)
    }

    @Test func finishCommitsTrailingFrame() {
        var s = FrameSelector()
        _ = s.evaluate(res(.appended(rows: 100), maxY: 100), bandHeight: 100)
        _ = s.evaluate(res(.appended(rows: 30), maxY: 130), bandHeight: 100)  // uncommitted tail
        #expect(s.finish() == .commitKeyframe)
        #expect(s.finish() == .ignore)   // nothing left uncommitted
    }
}

/// Deterministic per-position content slice for the overlap integration test.
private func sig(_ pos: Int) -> [Float] {
    var out = [Float]()
    var x = UInt64(pos) &+ 7
    for i in 0..<100 {
        let n = UInt64(pos + i)
        x = (n &* 2654435761) ^ (n >> 3)
        out.append(Float(x & 0xFFFF) / Float(0xFFFF))
    }
    return out
}
