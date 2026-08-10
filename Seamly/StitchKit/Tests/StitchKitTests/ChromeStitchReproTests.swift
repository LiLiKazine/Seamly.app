import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Reproduction harness for the "output is just stacked screenshots" bug.
///
/// Simulates a real app screen — a fixed top chrome band (nav bar), a scrolling content
/// region, and a fixed bottom chrome band (tab bar) — then drives the *real* StitchKit
/// pipeline in the same order `SampleHandler` does, and composites the result. Two content
/// variants isolate the two suspected gaps:
///   • high-variance content  → the matcher should track easily; if it still stacks, the
///     fault is in the wiring / compositor (Gap 2).
///   • low-variance content + strong chrome → if it stacks only here, the matcher is being
///     biased by the static chrome (Gap 1).
@Suite struct ChromeStitchReproTests {

    // MARK: - Geometry

    static let W = 80
    static let topChromeH = 24
    static let bottomChromeH = 20
    static let contentWindow = 220
    static var frameH: Int { topChromeH + contentWindow + bottomChromeH }   // 264
    static let docH = 1200
    static let scrollStep = 44      // ~83% frame overlap — dense, like real 60fps capture
    static let markerRow = 600     // a unique bright stripe in the document

    // MARK: - Pixel builders (row 0 = top, matching the `noise` convention)

    private func image(fromGray gray: [UInt8], width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bpr = ctx.bytesPerRow
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * height) { p in
            for r in 0..<height {
                // Buffer row 0 is the produced CGImage's TOP row, so write gray row 0 there and
                // the image is upright (row 0 = top), like a real ReplayKit frame. (A
                // `height - 1 - r` flip here would invert it — a downward scroll would read as a
                // negative dy the tracker skips, the shattering bug this fixture must not model.)
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

    /// A text-line luminance model: a distinct pseudo-random luma per ~8-row block (strong
    /// vertical contrast between "lines"), held constant within the block so it survives the
    /// profiler's nearest-neighbor height downscale — the strong, resampling-robust vertical
    /// structure real screen content carries and that a mean+variance row profiler tracks.
    /// (Per-pixel noise, by contrast, averages every row to mid-gray leaving no vertical
    /// signal; a per-row-independent ramp is scrambled by sub-pixel resampling — see
    /// DECISIONS.md CB-fixtures.)
    private func rowLuma(_ r: Int) -> Int {
        let block = UInt64(bitPattern: Int64(max(0, r) / 8 &* 2_654_435_761))
        return 20 + Int((block >> 11) % 216)
    }

    /// High-variance document: distinct per-row means with strong left/right texture — easy
    /// for the matcher to lock onto (isolates Gap 2: wiring / compositor).
    private func highVarDoc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            let base = rowLuma(r)
            for c in 0..<Self.W {
                if r >= Self.markerRow && r < Self.markerRow + 4 { g[r * Self.W + c] = 255; continue }
                let texture = (Int(hashByte(r, c, 3)) - 128) / 3   // ~[-42, 42] horizontal noise
                g[r * Self.W + c] = UInt8(min(255, max(0, base + texture)))
            }
        }
        return g
    }

    /// Low-variance document: the same distinct per-row means but near-zero horizontal
    /// variance (text-on-white feel), so the variance-weighted matcher has little content
    /// weight and static high-variance chrome dominates the score unless masked (Gap 1).
    private func lowVarDoc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            let base = rowLuma(r)
            for c in 0..<Self.W {
                var v = base
                if c % 7 == 0 { v = base - 12 }         // sparse "text" — tiny horizontal variance
                if r >= Self.markerRow && r < Self.markerRow + 4 { v = 0 }   // a dark marker line
                g[r * Self.W + c] = UInt8(min(255, max(0, v)))
            }
        }
        return g
    }

    private func chromeBand(height: Int, seed: Int) -> [UInt8] {
        var g = [UInt8](repeating: 0, count: height * Self.W)
        for r in 0..<height {
            for c in 0..<Self.W { g[r * Self.W + c] = hashByte(r, c, seed) }  // high-variance icons/text
        }
        return g
    }

    /// Assemble one on-screen frame at scroll offset `s`: fixed top chrome, a window of the
    /// document, fixed bottom chrome.
    private func frame(doc: [UInt8], top: [UInt8], bottom: [UInt8], scroll s: Int) -> CGImage {
        let W = Self.W, CT = Self.topChromeH, CB = Self.bottomChromeH, CW = Self.contentWindow
        var g = [UInt8](repeating: 0, count: Self.frameH * W)
        for r in 0..<CT { for c in 0..<W { g[r * W + c] = top[r * W + c] } }
        for r in 0..<CW {
            let docRow = min(Self.docH - 1, s + r)
            for c in 0..<W { g[(CT + r) * W + c] = doc[docRow * W + c] }
        }
        for r in 0..<CB { for c in 0..<W { g[(CT + CW + r) * W + c] = bottom[r * W + c] } }
        return image(fromGray: g, width: W, height: Self.frameH)
    }

    private func frames(doc: [UInt8]) -> [CGImage] {
        let top = chromeBand(height: Self.topChromeH, seed: 11)
        let bottom = chromeBand(height: Self.bottomChromeH, seed: 22)
        var out: [CGImage] = []
        var s = 0
        while s <= Self.docH - Self.contentWindow {
            out.append(frame(doc: doc, top: top, bottom: bottom, scroll: s))
            s += Self.scrollStep
        }
        return out
    }

    // MARK: - Full pipeline (see `CaptureHarness`)

    // MARK: - Diagnostics

    private func dump(_ label: String, _ session: StitchSession, _ out: CGImage) {
        print("── \(label) ─────────────────────────────")
        print("frames fed: \(frames(doc: highVarDoc()).count)  keyframes: \(session.keyframes.count)  seams: \(session.seams.count)  breaks: \(session.segmentBreaks.count)")
        for s in session.seams {
            print("  seam \(s.fromIndex)->\(s.fromIndex + 1): dy=\(s.provisionalDy)px  conf=\(String(format: "%.2f", s.confidence))  lowConf=\(s.isLowConfidence)")
        }
        for keyframe in session.keyframes.sorted(by: { $0.index < $1.index }) {
            let chrome = session.resolvedChrome(for: keyframe)
            print("  frame \(keyframe.index) chrome: top=\(chrome.insets.top)px  bottom=\(chrome.insets.bottom)px  unlocked=\(chrome.isUnlocked)")
        }
        for b in session.segmentBreaks { print("  break after kf \(b.afterKeyframeIndex): \(b.reason)") }
        let expected = Self.topChromeH + Self.docH + Self.bottomChromeH
        print("output height: \(out.height)px   expected≈\(expected)px   ratio=\(String(format: "%.2f", Double(out.height) / Double(expected)))")
        print("")
    }

    // MARK: - Pixel inspection

    /// Per-row mean luminance (0...1) of the composited image, for counting repeated bands.
    private func rowMeans(_ image: CGImage) -> [Float] {
        let w = image.width, h = image.height
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bpr = ctx.bytesPerRow
        var means = [Float](repeating: 0, count: h)
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * h) { p in
            for r in 0..<h {
                var s = 0; for c in 0..<w { s += Int(p[r * bpr + c]) }
                means[r] = Float(s) / Float(w * 255)
            }
        }
        return means
    }

    /// Number of contiguous row-bands satisfying `pred` — how many times a feature repeats.
    private func bandCount(_ means: [Float], where pred: (Float) -> Bool) -> Int {
        var bands = 0, inBand = false
        for m in means {
            if pred(m) { if !inBand { bands += 1; inBand = true } } else { inBand = false }
        }
        return bands
    }

    // MARK: - Tests

    @Test func highVarianceContentShouldStitchNotStack() throws {
        let capture = try CaptureHarness.capture(frames(doc: highVarDoc()))
        let session = capture.session
        let out = try capture.composite()
        dump("HIGH-variance content", session, out)

        // A correct stitch reproduces the document once, plus one top + one bottom chrome:
        // neither stacked (too tall) nor content-dropped (too short).
        let expected = Self.topChromeH + Self.docH + Self.bottomChromeH
        #expect(abs(out.height - expected) <= Int(Double(expected) * 0.1),
                "output \(out.height)px should be ≈\(expected)px of unique content — got ratio \(String(format: "%.2f", Double(out.height) / Double(expected)))")

        let chrome = session.keyframes.map { session.resolvedChrome(for: $0) }
        #expect(chrome.allSatisfy { !$0.isUnlocked })
        #expect(chrome.allSatisfy { abs($0.insets.top - Self.topChromeH) <= 6 })
        #expect(chrome.allSatisfy { abs($0.insets.bottom - Self.bottomChromeH) <= 6 })

        // The unique bright marker stripe appears exactly once (not duplicated at a seam).
        #expect(bandCount(rowMeans(out), where: { $0 > 0.97 }) == 1)
    }

    @Test func lowVarianceContentShouldStitchNotStack() throws {
        let capture = try CaptureHarness.capture(frames(doc: lowVarDoc()))
        let session = capture.session
        let out = try capture.composite()
        dump("LOW-variance content", session, out)

        // A correct stitch reproduces the document once, plus one top + one bottom chrome:
        // neither stacked (too tall) nor content-dropped (too short).
        let expected = Self.topChromeH + Self.docH + Self.bottomChromeH
        #expect(abs(out.height - expected) <= Int(Double(expected) * 0.1),
                "output \(out.height)px should be ≈\(expected)px of unique content — got ratio \(String(format: "%.2f", Double(out.height) / Double(expected)))")

        let chrome = session.keyframes.map { session.resolvedChrome(for: $0) }
        #expect(chrome.allSatisfy { !$0.isUnlocked })
        #expect(chrome.allSatisfy { abs($0.insets.top - Self.topChromeH) <= 6 })
        #expect(chrome.allSatisfy { abs($0.insets.bottom - Self.bottomChromeH) <= 6 })

        // The unique dark marker line appears exactly once.
        #expect(bandCount(rowMeans(out), where: { $0 < 0.03 }) == 1)
    }
}
