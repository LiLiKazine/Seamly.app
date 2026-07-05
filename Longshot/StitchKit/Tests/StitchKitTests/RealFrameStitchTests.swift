import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import StitchKit

/// End-to-end stitching on **real captured pixels**. Synthetic fixtures proved an unreliable
/// oracle at real geometry (their matching behavior swung with trivial content changes), so this
/// drives the pipeline on a real iOS screenshot (`wikipedia.png`, 1206×2622 — real anti-aliased
/// text, a low-variance sepia photo, a live status bar). Real scrolling is modelled faithfully:
/// the fixed status bar and Safari bar are held constant while the content region between them is
/// windowed in 60 px steps — exactly what scrolling this page produces. This is the oracle that
/// says whether the pipeline actually stitches a real screen, not just synthetic content.
@Suite struct RealFrameStitchTests {

    // Fixed-chrome / content split of the source screenshot (source pixels).
    static let topChromeH = 210        // iOS status bar (clock, dynamic island, indicators)
    static let bottomChromeH = 260     // Safari bottom toolbar
    static let contentWindow = 1500    // on-screen content height per frame
    static let scrollStep = 60         // a normal reading scroll

    private func loadFixture() throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: "wikipedia", withExtension: "png"))
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// Compose one on-screen frame: fixed top chrome, a window of the content region at scroll
    /// `s`, fixed bottom chrome — all real pixels cropped from the source screenshot.
    private func frame(from shot: CGImage, scroll s: Int) -> CGImage {
        let W = shot.width
        let top = shot.cropping(to: CGRect(x: 0, y: 0, width: W, height: Self.topChromeH))!
        let bottomY = shot.height - Self.bottomChromeH
        let bottom = shot.cropping(to: CGRect(x: 0, y: bottomY, width: W, height: Self.bottomChromeH))!
        let content = shot.cropping(to: CGRect(x: 0, y: Self.topChromeH + s, width: W, height: Self.contentWindow))!

        let frameH = Self.topChromeH + Self.contentWindow + Self.bottomChromeH
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: frameH, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(frameH)); ctx.scaleBy(x: 1, y: -1)   // top-left origin
        ctx.draw(top, in: CGRect(x: 0, y: 0, width: W, height: Self.topChromeH))
        ctx.draw(content, in: CGRect(x: 0, y: Self.topChromeH, width: W, height: Self.contentWindow))
        ctx.draw(bottom, in: CGRect(x: 0, y: Self.topChromeH + Self.contentWindow, width: W, height: Self.bottomChromeH))
        return ctx.makeImage()!
    }

    private func scrollPositions(contentDocH: Int) -> [Int] {
        let maxS = contentDocH - Self.contentWindow
        var ps = Array(stride(from: 0, through: maxS, by: Self.scrollStep))
        if ps.last != maxS { ps.append(maxS) }
        return ps
    }

    // MARK: - Faithful mirror of SampleHandler's capture → session pipeline

    private func buildSession(_ frames: [CGImage]) -> (StitchSession, [Int: CGImage]) {
        let profiler = VerticalProfile()
        var tracker = PositionTracker()
        var selector = FrameSelector()
        var session = StitchSession(createdAt: Date(), status: .recording, deviceScale: 1, orientation: .portrait)
        var images: [Int: CGImage] = [:]
        var keyframeIndex = 0, lastKeyframeRow = 0, lastSegment = 0

        func commit(_ image: CGImage, _ profile: FrameProfile, _ result: TrackingResult) {
            session.keyframes.append(Keyframe(filename: "kf-\(keyframeIndex)", pixelWidth: image.width, pixelHeight: image.height, index: keyframeIndex))
            images[keyframeIndex] = image
            if case .segmentBreak(let reason) = result.decision, keyframeIndex > 0 {
                session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: keyframeIndex - 1, reason: reason))
            } else if keyframeIndex > 0, result.segmentIndex == lastSegment {
                let dyRows = max(0, result.position - lastKeyframeRow)
                session.seams.append(Seam(fromIndex: keyframeIndex - 1, provisionalDy: Int(Double(dyRows) * profile.rowScale), confidence: result.confidence, isLowConfidence: result.confidence < 0.4))
            }
            let seg = result.segmentIndex
            while session.contentBands.count <= seg { session.contentBands.append(.unlocked) }
            session.contentBands[seg] = result.contentBand
            lastKeyframeRow = result.position; lastSegment = result.segmentIndex; keyframeIndex += 1
        }

        var lastImage: CGImage?, lastProfile: FrameProfile?, lastResult: TrackingResult?
        for image in frames {
            let profile = profiler.profile(image)
            let result = tracker.process(profile)
            if selector.evaluate(result, bandHeight: profile.rowCount) == .commitKeyframe { commit(image, profile, result) }
            lastImage = image; lastProfile = profile; lastResult = result
        }
        if selector.finish() == .commitKeyframe, let i = lastImage, let p = lastProfile, let r = lastResult { commit(i, p, r) }
        session.status = .complete
        return (session, images)
    }

    @Test func stitchesRealScreenshotScroll() throws {
        let shot = try loadFixture()
        let contentDocH = shot.height - Self.topChromeH - Self.bottomChromeH
        let frames = scrollPositions(contentDocH: contentDocH).map { frame(from: shot, scroll: $0) }

        let (session, images) = buildSession(frames)
        let out = try Compositor().composite(session) { images[$0.index]! }

        let expected = Self.topChromeH + contentDocH + Self.bottomChromeH   // == shot.height
        let band = session.contentBand(forSegment: 0)
        print("── REAL screenshot stitch")
        print("   frames=\(frames.count) keyframes=\(session.keyframes.count) seams=\(session.seams.count) breaks=\(session.segmentBreaks.count) segments=\(session.contentBands.count)")
        print("   band seg0: top=\(band.topChrome) bottom=\(band.bottomChrome) lowConf=\(band.isLowConfidence) (true≈\(Self.topChromeH)/\(Self.bottomChromeH))")
        print("   output=\(out.height)px expected≈\(expected)px ratio=\(String(format: "%.2f", Double(out.height)/Double(expected)))")

        // 1. Stitched, not stacked (too tall) or collapsed (too short): the two shipped bugs.
        #expect(abs(out.height - expected) <= Int(Double(expected) * 0.12),
                "output \(out.height)px should be ≈\(expected)px (ratio \(String(format: "%.2f", Double(out.height)/Double(expected))))")
        // 2. Chrome band detected confidently for the segment (the "never detected" complaint).
        #expect(!band.isLowConfidence, "content band should lock confidently, got \(band)")
        #expect(abs(band.topChrome - Self.topChromeH) <= 60, "top chrome \(band.topChrome) vs ~\(Self.topChromeH)")
        #expect(abs(band.bottomChrome - Self.bottomChromeH) <= 60, "bottom chrome \(band.bottomChrome) vs ~\(Self.bottomChromeH)")
        // 3. Capture stayed a single segment (no thrashing/relocalize breaks on real content).
        #expect(session.segmentBreaks.count == 0, "expected one clean segment, got breaks: \(session.segmentBreaks.count)")
    }
}
