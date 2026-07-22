import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// `ScrollCaptureDriver` is the pure capture loop extracted from `SampleHandler`: profile each
/// frame, ask `KeyframeSelector` whether to bank it, decide the safety cue, and build `Keyframe`
/// metadata — with the `broadcastFinished` trailing commit as `finish()`. These tests assert the
/// plumbing (commit decisions, monotonic indices, first-frame metadata, trailing commit) on
/// generated textured frames; Tasks 2 & 3 prove it against real content end-to-end.
@Suite struct ScrollCaptureDriverTests {

    static let W = 1152
    static let docH = 6000
    static let window = 1600

    private func hashByte(_ r: Int, _ c: Int, _ seed: Int) -> UInt8 {
        let n = UInt64(bitPattern: Int64((r &* 73856093) ^ (c &* 19349663) ^ (seed &* 83492791)))
        return UInt8((n >> 7) & 0xFF)
    }

    /// A tall document with distinct per-row luma blocks plus left/right texture (high per-row
    /// horizontal variance) so the matcher locks onto vertical offsets unambiguously.
    private func doc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            let base = 20 + Int(hashByte(r / 6, 0, 7)) * 216 / 255
            for c in 0..<Self.W {
                let texture = (Int(hashByte(r, c, 3)) - 128) / 3
                g[r * Self.W + c] = UInt8(min(255, max(0, base + texture)))
            }
        }
        return g
    }

    private func frame(_ d: [UInt8], scroll s: Int) -> CGImage {
        let W = Self.W, h = Self.window
        var g = [UInt8](repeating: 0, count: h * W)
        for r in 0..<h {
            let docRow = min(Self.docH - 1, s + r)
            for c in 0..<W { g[r * W + c] = d[docRow * W + c] }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bpr = ctx.bytesPerRow
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * h) { p in
            for r in 0..<h { for c in 0..<W {
                let v = g[r * W + c]; let i = r * bpr + c * 4
                p[i] = v; p[i+1] = v; p[i+2] = v; p[i+3] = 255
            } }
        }
        return ctx.makeImage()!
    }

    @Test func firstFrameAlwaysCommitsAsIndexZero() {
        var driver = ScrollCaptureDriver()
        let step = driver.ingest(frame(doc(), scroll: 0))
        let kf = step.keyframe
        #expect(kf != nil)
        #expect(kf?.metadata.index == 0)
        #expect(kf?.metadata.filename == "kf-0000.bgra")
        #expect(kf?.metadata.pixelWidth == Self.W)
        #expect(kf?.metadata.pixelHeight == Self.window)
        #expect(step.fireSafetyCue == false)   // overlap 1.0 on the first frame
    }

    @Test func commitsMonotonicIndicesAsViewScrolls() {
        let d = doc()
        var driver = ScrollCaptureDriver()
        _ = driver.ingest(frame(d, scroll: 0))          // index 0
        // Scroll ~half a window (commitFraction 0.5 of 1600 rows ≈ 800 px) → next commit.
        let mid = driver.ingest(frame(d, scroll: 200))
        #expect(mid.keyframe == nil, "200px < half-window scroll should not commit")
        let next = driver.ingest(frame(d, scroll: 1000))
        #expect(next.keyframe?.metadata.index == 1, "past-threshold scroll commits index 1")
    }

    @Test func finishCommitsTrailingFrameWhenMotionUncommitted() {
        let d = doc()
        var driver = ScrollCaptureDriver()
        _ = driver.ingest(frame(d, scroll: 0))          // index 0 committed
        _ = driver.ingest(frame(d, scroll: 300))        // motion, but below commit threshold
        let tail = driver.finish()
        #expect(tail?.metadata.index == 1, "trailing frame with uncommitted motion is banked")
    }

    @Test func finishReturnsNilWhenNoUncommittedMotion() {
        let d = doc()
        var driver = ScrollCaptureDriver()
        _ = driver.ingest(frame(d, scroll: 0))          // index 0 committed, baseline = 0
        _ = driver.ingest(frame(d, scroll: 0))          // no scroll since baseline
        #expect(driver.finish() == nil, "a near-duplicate tail must not be banked")
    }
}
