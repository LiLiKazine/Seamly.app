import Testing
@testable import StitchKit

/// Build a frame with `top` static chrome rows, a content body, and `bottom` static
/// chrome rows. `body` supplies the (scrolling, per-frame-different) content means.
private func framed(top: Int, bottom: Int, total: Int, chromeMean: Float, body: (Int) -> Float) -> FrameProfile {
    var means = [Float](repeating: 0, count: total)
    var vars = [Float](repeating: 0, count: total)
    for i in 0..<total {
        if i < top || i >= total - bottom {
            means[i] = chromeMean
            vars[i] = 0.0
        } else {
            means[i] = body(i)
            vars[i] = 0.1
        }
    }
    return FrameProfile(means: means, variances: vars, sourceWidth: 100, sourceHeight: total * 10)
}

@Suite struct ChromeDetectorTests {
    let detector = ChromeDetector()

    @Test func detectsTopAndBottomChromeWhenScrolling() {
        let a = framed(top: 10, bottom: 8, total: 100, chromeMean: 0.15) { Float($0) / 100 }
        let b = framed(top: 10, bottom: 8, total: 100, chromeMean: 0.15) { Float(($0 + 30) % 80) / 100 }
        let bands = detector.detect(a, b, dy: 30)
        #expect(bands.topRows == 10)
        #expect(bands.bottomRows == 8)
        #expect(!bands.isAmbiguous)
    }

    @Test func motionGatingSuppressesChromeWhenNoScroll() {
        // Two identical pre-scroll frames: everything is "static", but with no motion we
        // must not declare the whole frame chrome.
        let a = framed(top: 10, bottom: 8, total: 100, chromeMean: 0.15) { Float($0) / 100 }
        let bands = detector.detect(a, a, dy: 0)
        #expect(bands == .none)
    }

    @Test func toleranceSurvivesSmallChromeDrift() {
        // A clock tick nudges a couple of chrome rows slightly — still within epsilon.
        var b = framed(top: 10, bottom: 8, total: 100, chromeMean: 0.15) { Float(($0 + 30) % 80) / 100 }
        var means = b.means
        means[2] += 0.01
        means[3] -= 0.01
        b = FrameProfile(means: means, variances: b.variances, sourceWidth: b.sourceWidth, sourceHeight: b.sourceHeight)
        let a = framed(top: 10, bottom: 8, total: 100, chromeMean: 0.15) { Float($0) / 100 }
        let bands = detector.detect(a, b, dy: 30)
        #expect(bands.topRows == 10)
    }

    @Test func noChromeWhenContentDiffersEverywhere() {
        let a = framed(top: 0, bottom: 0, total: 100, chromeMean: 0.15) { Float($0) / 100 }
        let b = framed(top: 0, bottom: 0, total: 100, chromeMean: 0.15) { Float(($0 + 30) % 100) / 100 }
        let bands = detector.detect(a, b, dy: 30)
        #expect(bands.topRows == 0)
        #expect(bands.bottomRows == 0)
    }

    @Test func flagsAmbiguousWhenBandJumpsVsPreviousSeam() {
        // Header collapsed: previous seam had 20 top chrome rows, this seam only 5.
        let a = framed(top: 5, bottom: 8, total: 100, chromeMean: 0.15) { Float($0) / 100 }
        let b = framed(top: 5, bottom: 8, total: 100, chromeMean: 0.15) { Float(($0 + 30) % 80) / 100 }
        let bands = detector.detect(a, b, dy: 30, previous: ChromeBands(topRows: 20, bottomRows: 8))
        #expect(bands.topRows == 5)
        #expect(bands.isAmbiguous)
    }
}
