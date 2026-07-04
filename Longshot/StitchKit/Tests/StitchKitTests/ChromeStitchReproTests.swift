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
    static let scrollStep = 110
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
                for c in 0..<width {
                    let v = gray[r * width + c]
                    let i = r * bpr + c * 4
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

    /// High-variance document: per-pixel noise — easy for the matcher to lock onto.
    private func highVarDoc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            for c in 0..<Self.W {
                g[r * Self.W + c] = (r >= Self.markerRow && r < Self.markerRow + 4) ? 255 : hashByte(r, c, 3)
            }
        }
        return g
    }

    /// Low-variance document: text-on-white feel — distinct row means, near-zero horizontal
    /// variance, so the variance-weighted matcher has little content structure to hold and
    /// the static chrome dominates the score.
    private func lowVarDoc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            let base = UInt8(220 - (r % 10))           // mostly light, faint per-row variation
            for c in 0..<Self.W {
                var v = base
                if c % 7 == 0 { v = base &- 12 }         // sparse "text" — tiny horizontal variance
                if r >= Self.markerRow && r < Self.markerRow + 4 { v = 0 }   // a dark marker line
                g[r * Self.W + c] = v
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

    // MARK: - Faithful mirror of SampleHandler's capture → session pipeline

    private func buildSession(frames: [CGImage]) -> (StitchSession, [Int: CGImage]) {
        let profiler = VerticalProfile()
        let chromeDetector = ChromeDetector()
        var tracker = PositionTracker()
        var selector = FrameSelector()
        var session = StitchSession(createdAt: Date(), status: .recording, deviceScale: 1, orientation: .portrait)
        var images: [Int: CGImage] = [:]

        var keyframeIndex = 0
        var lastKeyframeProfile: FrameProfile?
        var lastKeyframeRow = 0
        var lastSegment = 0

        func commit(_ image: CGImage, _ profile: FrameProfile, _ result: TrackingResult) {
            if keyframeIndex == 0 {
                session.orientation = image.width > image.height ? .landscape : .portrait
                session.colorSpaceName = image.colorSpace?.name as String?
            }
            session.keyframes.append(Keyframe(filename: "kf-\(keyframeIndex)", pixelWidth: image.width, pixelHeight: image.height, index: keyframeIndex))
            images[keyframeIndex] = image

            if case .segmentBreak(let reason) = result.decision, keyframeIndex > 0 {
                session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: keyframeIndex - 1, reason: reason))
            } else if keyframeIndex > 0, result.segmentIndex == lastSegment, let previous = lastKeyframeProfile {
                let dyRows = max(0, result.position - lastKeyframeRow)
                let dyPixels = Int(Double(dyRows) * profile.rowScale)
                let bands = chromeDetector.detect(previous, profile, dy: dyRows)
                session.seams.append(Seam(
                    fromIndex: keyframeIndex - 1,
                    provisionalDy: dyPixels,
                    confidence: result.confidence,
                    chromeTopPixels: Int(Double(bands.topRows) * profile.rowScale),
                    chromeBottomPixels: Int(Double(bands.bottomRows) * profile.rowScale),
                    isLowConfidence: bands.isAmbiguous || result.confidence < 0.4
                ))
            }
            lastKeyframeProfile = profile
            lastKeyframeRow = result.position
            lastSegment = result.segmentIndex
            keyframeIndex += 1
        }

        var lastImage: CGImage?, lastProfile: FrameProfile?, lastResult: TrackingResult?
        for image in frames {
            let profile = profiler.profile(image)
            let result = tracker.process(profile)
            if selector.evaluate(result, bandHeight: profile.rowCount) == .commitKeyframe {
                commit(image, profile, result)
            }
            lastImage = image; lastProfile = profile; lastResult = result
        }
        if selector.finish() == .commitKeyframe, let i = lastImage, let p = lastProfile, let r = lastResult {
            commit(i, p, r)
        }
        session.status = .complete
        return (session, images)
    }

    // MARK: - Diagnostics

    private func dump(_ label: String, _ session: StitchSession, _ out: CGImage) {
        print("── \(label) ─────────────────────────────")
        print("frames fed: \(frames(doc: highVarDoc()).count)  keyframes: \(session.keyframes.count)  seams: \(session.seams.count)  breaks: \(session.segmentBreaks.count)")
        for s in session.seams {
            print("  seam \(s.fromIndex)->\(s.fromIndex + 1): dy=\(s.provisionalDy)px  chromeTop=\(s.chromeTopPixels)  chromeBottom=\(s.chromeBottomPixels)  conf=\(String(format: "%.2f", s.confidence))  lowConf=\(s.isLowConfidence)")
        }
        for b in session.segmentBreaks { print("  break after kf \(b.afterKeyframeIndex): \(b.reason)") }
        let expected = Self.topChromeH + Self.docH + Self.bottomChromeH
        print("output height: \(out.height)px   expected≈\(expected)px   ratio=\(String(format: "%.2f", Double(out.height) / Double(expected)))")
        print("")
    }

    // MARK: - Tests

    @Test func highVarianceContentShouldStitchNotStack() throws {
        let (session, images) = buildSession(frames: frames(doc: highVarDoc()))
        let out = try Compositor().composite(session) { images[$0.index]! }
        dump("HIGH-variance content", session, out)

        // A correct stitch reproduces the document once, plus one top + one bottom chrome:
        // neither stacked (too tall) nor content-dropped (too short).
        let expected = Self.topChromeH + Self.docH + Self.bottomChromeH
        #expect(abs(out.height - expected) <= Int(Double(expected) * 0.1),
                "output \(out.height)px should be ≈\(expected)px of unique content — got ratio \(String(format: "%.2f", Double(out.height) / Double(expected)))")
    }

    @Test func lowVarianceContentShouldStitchNotStack() throws {
        let (session, images) = buildSession(frames: frames(doc: lowVarDoc()))
        let out = try Compositor().composite(session) { images[$0.index]! }
        dump("LOW-variance content", session, out)

        // A correct stitch reproduces the document once, plus one top + one bottom chrome:
        // neither stacked (too tall) nor content-dropped (too short).
        let expected = Self.topChromeH + Self.docH + Self.bottomChromeH
        #expect(abs(out.height - expected) <= Int(Double(expected) * 0.1),
                "output \(out.height)px should be ≈\(expected)px of unique content — got ratio \(String(format: "%.2f", Double(out.height) / Double(expected)))")
    }
}
