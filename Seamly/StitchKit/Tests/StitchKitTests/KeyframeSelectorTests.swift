import Testing
import Foundation
@testable import StitchKit

/// `KeyframeSelector` is the dumb, robust replacement for the extension's real-time
/// `PositionTracker` + `FrameSelector`: it commits a keyframe whenever the view has scrolled a
/// set fraction of a frame since the last committed keyframe, and reports overlap for the safety
/// cue. It does NOT build order/seams/bands — the app re-derives those with `BatchStitcher`.
@Suite struct KeyframeSelectorTests {

    /// A profile = the window `[offset, offset+height)` of a monotonic ramp signal, so the
    /// matcher recovers an unambiguous downward offset equal to the window delta.
    private func frame(offset: Int, height: Int = 100) -> FrameProfile {
        let means = (0..<height).map { Float(offset + $0) * 0.003 }
        let variances = [Float](repeating: 0.25, count: height)
        return FrameProfile(means: means, variances: variances, sourceWidth: 64, sourceHeight: height)
    }

    @Test func firstFrameAlwaysCommits() {
        var sel = KeyframeSelector()
        #expect(sel.evaluate(frame(offset: 0)).commit)
    }

    @Test func skipsUntilScrolledPastThreshold() {
        var sel = KeyframeSelector(commitFraction: 0.5)   // height 100 → commit at dy ≥ 50
        #expect(sel.evaluate(frame(offset: 0)).commit)    // first → commit, baseline = 0
        #expect(!sel.evaluate(frame(offset: 20)).commit)  // dy 20 < 50 → skip
        #expect(!sel.evaluate(frame(offset: 40)).commit)  // dy 40 < 50 → skip
        #expect(sel.evaluate(frame(offset: 60)).commit)   // dy 60 ≥ 50 → commit, baseline = 60
        #expect(!sel.evaluate(frame(offset: 80)).commit)  // dy 20 from 60 → skip
        #expect(sel.evaluate(frame(offset: 110)).commit)  // dy 50 from 60 → commit
    }

    @Test func reportsOverlapForSafetyCue() {
        var sel = KeyframeSelector(commitFraction: 0.5)
        _ = sel.evaluate(frame(offset: 0))
        let r = sel.evaluate(frame(offset: 30))           // dy 30 → overlap (100-30)/100 = 0.70
        #expect(abs(r.overlapFraction - 0.70) < 0.05)
    }

    @Test func aStillFrameDoesNotCommit() {
        var sel = KeyframeSelector(commitFraction: 0.5)
        _ = sel.evaluate(frame(offset: 0))
        let r = sel.evaluate(frame(offset: 0))            // no scroll → dy 0
        #expect(!r.commit)
        #expect(abs(r.overlapFraction - 1.0) < 0.01)
    }
}
