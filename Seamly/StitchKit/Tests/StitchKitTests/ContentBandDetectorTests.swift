import Testing
@testable import StitchKit

/// Build a frame profile with `top` static chrome rows, a content body, and `bottom` static
/// chrome rows. `body` supplies the (scrolling, per-frame-different) content means; chrome
/// rows are high-variance (like real title text / tab icons) but identical across frames.
private func framed(top: Int, bottom: Int, total: Int, body: (Int) -> Float) -> FrameProfile {
    var means = [Float](repeating: 0, count: total)
    var vars = [Float](repeating: 0, count: total)
    for i in 0..<total {
        if i < top || i >= total - bottom {
            means[i] = Float((i * 37) % 100) / 100   // fixed chrome pattern
            vars[i] = 0.3
        } else {
            means[i] = body(i)
            vars[i] = 0.1
        }
    }
    return FrameProfile(means: means, variances: vars, sourceWidth: 100, sourceHeight: total * 10)
}

/// A sequence of frames scrolling a synthetic document by `step` rows each, with `top`/`bottom`
/// static chrome. Row means are a smooth ramp so consecutive frames differ everywhere in the
/// content band.
private func scrollingFrames(count: Int, top: Int, bottom: Int, total: Int, step: Int) -> [FrameProfile] {
    (0..<count).map { f in
        framed(top: top, bottom: bottom, total: total) { i in
            let docRow = (f * step) + (i - top)
            return Float((docRow * 13) % 100) / 100
        }
    }
}

@Suite struct ContentBandDetectorTests {

    // MARK: - Bootstrap static mask

    @Test func staticMaskExcludesChromeAndKeepsContent() {
        let frames = scrollingFrames(count: 2, top: 10, bottom: 8, total: 100, step: 20)
        var detector = ContentBandDetector()
        let mask = detector.staticMask(frames[0], frames[1])
        let m = try! #require(mask)
        #expect(m.count == 100)
        // Chrome rows static -> masked out (false); content rows moved -> kept (true).
        #expect(m[0..<10].allSatisfy { $0 == false })
        #expect(m[92..<100].allSatisfy { $0 == false })
        #expect(m[10..<92].allSatisfy { $0 == true })
    }

    @Test func staticMaskIsNilForPreScrollStillFrames() {
        // Two identical frames: everything static, no content moved -> caller matches unmasked.
        let f = framed(top: 10, bottom: 8, total: 100) { Float($0) / 100 }
        var detector = ContentBandDetector()
        #expect(detector.staticMask(f, f) == nil)
    }

    // MARK: - Consensus lock

    @Test func doesNotLockBeforeEnoughMovingFrames() {
        let frames = scrollingFrames(count: 2, top: 10, bottom: 8, total: 100, step: 20)
        var detector = ContentBandDetector(minMovingFrames: 3)
        detector.observe(frames[0], frames[1], dy: 20)
        #expect(detector.lockedBand == nil)
    }

    @Test func locksStableBandAfterConsensus() {
        let frames = scrollingFrames(count: 6, top: 10, bottom: 8, total: 100, step: 20)
        var detector = ContentBandDetector(minMovingFrames: 3)
        for i in 1..<frames.count {
            detector.observe(frames[i - 1], frames[i], dy: 20)
        }
        let band = try! #require(detector.lockedBand)
        #expect(band.top == 10)
        #expect(band.bottom == 8)
    }

    @Test func consensusIsRobustToOneNoisyPair() {
        // Inject a single pair whose "content" happens to sit still (a paused frame): the
        // per-row vote accumulation must not let that one pair inflate the chrome band.
        var frames = scrollingFrames(count: 6, top: 10, bottom: 8, total: 100, step: 20)
        frames[3] = frames[2]   // a duplicate/paused frame in the middle
        var detector = ContentBandDetector(minMovingFrames: 3)
        for i in 1..<frames.count {
            let dy = (i == 3) ? 0 : 20   // the paused pair reports no motion
            detector.observe(frames[i - 1], frames[i], dy: dy)
        }
        let band = try! #require(detector.lockedBand)
        #expect(band.top == 10)
        #expect(band.bottom == 8)
    }

    // MARK: - Sharp change (segment break signal)

    @Test func bandChangedSharplyFlagsCollapsedHeader() {
        let frames = scrollingFrames(count: 6, top: 10, bottom: 8, total: 100, step: 20)
        var detector = ContentBandDetector(minMovingFrames: 3)
        for i in 1..<frames.count { detector.observe(frames[i - 1], frames[i], dy: 20) }
        #expect(detector.lockedBand != nil)

        // Header collapsed from 10 -> 2 static top rows: a sharp change.
        let collapsed = scrollingFrames(count: 2, top: 2, bottom: 8, total: 100, step: 20)
        #expect(detector.bandChangedSharply(collapsed[0], collapsed[1]) == true)
    }

    @Test func bandUnchangedForSteadyState() {
        let frames = scrollingFrames(count: 8, top: 10, bottom: 8, total: 100, step: 20)
        var detector = ContentBandDetector(minMovingFrames: 3)
        for i in 1..<6 { detector.observe(frames[i - 1], frames[i], dy: 20) }
        #expect(detector.lockedBand != nil)
        // A later steady-state pair with the same chrome must not be flagged.
        #expect(detector.bandChangedSharply(frames[6], frames[7]) == false)
    }
}
