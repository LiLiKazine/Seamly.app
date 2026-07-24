import CoreGraphics
import Foundation
@testable import StitchKit

/// Deterministic stand-in for ReplayKit's frame delivery. Slides a viewport window down a tall
/// oracle image, composites a fixed top-chrome bar onto every emitted frame, adds seeded jitter
/// and one optional fling, and feeds each frame to the *real* `ScrollCaptureDriver`. Pure and
/// reproducible: a seeded LCG drives jitter and the fling index is fixed — no `Date`, no `random`.
///
/// This models the exact condition the empty-capture bug lived in: a static top bar that must NOT
/// pin the measured scroll to zero, plus normal finger jitter and one fast flick.
struct CaptureSimulator {
    let oracle: CGImage
    /// On-screen viewport height in source px (top chrome + content).
    let viewportHeight: Int
    /// Fixed top-chrome bar height in source px, composited identically onto every frame.
    let topChromeHeight: Int
    /// Nominal per-frame scroll of the content region (px).
    let scrollStep: Int
    /// Max ± jitter added to each step (px), from the seeded LCG.
    let jitter: Int
    /// Frame index at which a single fling occurs (a large extra jump), or nil for none.
    let flingAtFrame: Int?
    /// Extra px added on the fling frame.
    let flingExtra: Int
    var seed: UInt64 = 0x9E3779B97F4A7C15

    /// The fixed top-chrome strip taken once from the oracle's very top (real Chrome bar pixels).
    private func chromeBar() -> CGImage {
        oracle.cropping(to: CGRect(x: 0, y: 0, width: oracle.width, height: topChromeHeight))!
    }

    /// Compose one on-screen frame at content-scroll `s`: fixed top bar, then a window of the
    /// oracle content beneath it. Assembled in an UNFLIPPED context so buffer row 0 is the top
    /// row (matching real top-down frames and `VerticalProfile`, which does not flip).
    private func frame(chrome: CGImage, contentScroll s: Int) -> CGImage {
        let W = oracle.width
        let contentH = viewportHeight - topChromeHeight
        let content = oracle.cropping(to: CGRect(x: 0, y: topChromeHeight + s, width: W, height: contentH))!
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: viewportHeight, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        // Unflipped: an image drawn at y = viewportHeight - h lands upright with its top at
        // buffer row 0's offset; top chrome sits at the top, content beneath it.
        ctx.draw(content, in: CGRect(x: 0, y: 0, width: W, height: contentH))
        ctx.draw(chrome, in: CGRect(x: 0, y: contentH, width: W, height: topChromeHeight))
        return ctx.makeImage()!
    }

    /// Seeded scroll script: nominal step + jitter each frame, plus one fling. Deterministic.
    private func scrollScript() -> [Int] {
        let contentH = viewportHeight - topChromeHeight
        let maxScroll = oracle.height - topChromeHeight - contentH   // last valid content window
        var positions: [Int] = []
        var s = 0
        var rng = seed
        var frameIndex = 0
        while s < maxScroll {
            positions.append(min(s, maxScroll))
            // LCG (Numerical Recipes constants); deterministic jitter in [-jitter, +jitter].
            rng = 6364136223846793005 &* rng &+ 1442695040888963407
            let j = jitter == 0 ? 0 : Int(rng >> 33) % (2 * jitter + 1) - jitter
            var advance = scrollStep + j
            if frameIndex == flingAtFrame { advance += flingExtra }
            s += max(1, advance)
            frameIndex += 1
        }
        if positions.last != maxScroll { positions.append(maxScroll) }
        return positions
    }

    /// Drive the real driver over the generated stream; return the committed keyframes (including
    /// the trailing finish() commit).
    func run(driver: inout ScrollCaptureDriver) -> [ScrollCaptureDriver.CapturedKeyframe] {
        let chrome = chromeBar()
        var committed: [ScrollCaptureDriver.CapturedKeyframe] = []
        for s in scrollScript() {
            if let kf = driver.ingest(frame(chrome: chrome, contentScroll: s)).keyframe {
                committed.append(kf)
            }
        }
        if let tail = driver.finish() { committed.append(tail) }
        return committed
    }
}
