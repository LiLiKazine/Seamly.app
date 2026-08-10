import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Matcher regression at **real device geometry**. `OffsetMatcherTests` runs on ~100-row
/// hand-built profiles; `ChromeStitchReproTests` runs on 80×264 frames where the profiler
/// barely downscales (`rowScale = sourceWidth/64 ≈ 1.25`). Real frames are ~1150 px wide →
/// `rowScale ≈ 18`, where a normal scroll of tens of px spans a fraction of a profile row.
/// There the pre-fix matcher (`minimumOverlap = 8`, no overlap term) latched onto extreme
/// tiny-overlap boundary offsets (±2000 px) instead of the true small scroll. This drives real
/// frames through `VerticalProfile` + `OffsetMatcher` and asserts the true offset is recovered.
@Suite struct RealGeometryStitchTests {

    // Wide frame → rowScale = W/64 ≈ 18 with the aspect-locked profiler; the finer-resolution
    // fix (`VerticalProfile.maxRows`) brings it down to a resolvable ~3 px/row.
    static let W = 1152
    static let contentWindow = 1600
    static let docH = 5000
    static let scrollStep = 60          // a normal reading scroll, not a fling

    // MARK: - Pixel builders

    private func image(fromGray gray: [UInt8], width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bpr = ctx.bytesPerRow
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * height) { p in
            for r in 0..<height {
                // Buffer row 0 is the produced CGImage's TOP row, so write gray row 0 there:
                // the image is upright (row 0 = top), matching a real top-down capture. (A
                // `height - 1 - r` flip here would invert it, turning a downward scroll into a
                // negative dy the tracker skips — the shattering bug this fixture must not model.)
                let dst = r
                for c in 0..<width {
                    let v = gray[r * width + c]
                    let i = dst * bpr + c * 4
                    p[i] = v; p[i + 1] = v; p[i + 2] = v; p[i + 3] = 255
                }
            }
        }
        return ctx.makeImage()!
    }

    private func hashByte(_ r: Int, _ c: Int, _ seed: Int) -> UInt8 {
        let n = UInt64(bitPattern: Int64((r &* 73856093) ^ (c &* 19349663) ^ (seed &* 83492791)))
        return UInt8((n >> 7) & 0xFF)
    }

    /// Distinct per-row means with strong left/right texture — easy for the matcher to lock onto.
    private func doc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            let base = 20 + Int(hashByte(r / 6, 0, 7)) * 216 / 255   // ~6-row luma blocks
            for c in 0..<Self.W {
                let texture = (Int(hashByte(r, c, 3)) - 128) / 3
                g[r * Self.W + c] = UInt8(min(255, max(0, base + texture)))
            }
        }
        return g
    }

    /// A chrome-free content window at scroll offset `s`.
    private func contentFrame(doc d: [UInt8], scroll s: Int, windowRows: Int) -> CGImage {
        let W = Self.W
        var g = [UInt8](repeating: 0, count: windowRows * W)
        for r in 0..<windowRows {
            let docRow = min(Self.docH - 1, s + r)
            for c in 0..<W { g[r * W + c] = d[docRow * W + c] }
        }
        return image(fromGray: g, width: W, height: windowRows)
    }

    // MARK: - Test

    @Test func matcherResolvesNormalScrollAtRealGeometry() {
        let d = doc()
        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        var errorsPx: [Double] = []
        for k in 0..<6 {
            let s = 400 + k * Self.scrollStep
            let a = profiler.profile(contentFrame(doc: d, scroll: s, windowRows: Self.contentWindow))
            let b = profiler.profile(contentFrame(doc: d, scroll: s + Self.scrollStep, windowRows: Self.contentWindow))
            let n = min(a.rowCount, b.rowCount)
            let bound = max(0, n - matcher.minimumOverlap)
            let m = matcher.match(a, b, searchRange: -bound...bound, rowMasks: nil)
            errorsPx.append(abs(Double(m.dy) * a.rowScale - Double(Self.scrollStep)))
        }
        let maxErr = errorsPx.max() ?? .infinity
        // A correct match lands within a few px of the true 60 px scroll. The pre-fix matcher
        // returned the search boundary (~±2000 px) here.
        #expect(maxErr <= 12, "matched dy off by up to \(Int(maxErr))px from the true 60px scroll")
    }
}
