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

@Suite struct ChromeStaticRowDetectorTests {

    // MARK: - Bootstrap static mask

    @Test func staticMaskExcludesChromeAndKeepsContent() {
        let frames = scrollingFrames(count: 2, top: 10, bottom: 8, total: 100, step: 20)
        let detector = ChromeStaticRowDetector()
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
        let detector = ChromeStaticRowDetector()
        #expect(detector.staticMask(f, f) == nil)
    }
}
