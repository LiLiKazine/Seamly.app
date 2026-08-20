import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// `Placement` is the public face of `Compositor.plan`'s layout. It exists so the app can
/// position a margin marker without re-deriving the rule a third time (`JoinAlignment` is the
/// second copy, and it is asserted against a real composite for exactly this reason). So the
/// gate here is the same one: the numbers must agree with real pixels, not with themselves.
struct PlacementTests {

    /// Per-pixel noise: distinct rows with real horizontal variance, so refinement has
    /// structure to lock onto. Buffer row 0 is the image's top row.
    private func noise(width: Int, height: Int, seed: Int = 5) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let bpr = ctx.bytesPerRow
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * height) { p in
            for r in 0..<height {
                for c in 0..<width {
                    let n = UInt64(bitPattern: Int64((r &* 73856093) ^ (c &* 19349663) ^ (seed &* 83492791)))
                    let v = UInt8((n >> 7) & 0xFF)
                    let i = r * bpr + c * 4
                    p[i] = v; p[i + 1] = v; p[i + 2] = v; p[i + 3] = 255
                }
            }
        }
        return ctx.makeImage()!
    }

    /// `count` frames of `height` rows, cropped from one tall source at `dy` intervals, with
    /// optional chrome and optional segment breaks. Returns the session and an image lookup.
    private func session(
        count: Int,
        width: Int = 120,
        height: Int = 300,
        dy: Int = 180,
        topChrome: Int = 0,
        bottomChrome: Int = 0,
        breaksAfter: [Int] = []
    ) -> (StitchSession, (Keyframe) throws -> CGImage) {
        let source = noise(width: width, height: height + dy * count)
        var images: [Int: CGImage] = [:]
        let keyframes: [Keyframe] = (0..<count).map { index in
            images[index] = source.cropping(
                to: CGRect(x: 0, y: index * dy, width: width, height: height)
            )!
            return Keyframe(filename: "kf-\(index).bgra", pixelWidth: width, pixelHeight: height, index: index)
        }
        var s = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: keyframes,
            seams: (0..<max(0, count - 1)).map { Seam(fromIndex: $0, provisionalDy: dy, confidence: 0.9) },
            segmentBreaks: breaksAfter.map { SegmentBreak(afterKeyframeIndex: $0, reason: .lostLock) }
        )
        s.keyframeChrome = keyframes.map {
            KeyframeChrome(
                keyframeID: $0.id,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: topChrome, bottom: bottomChrome),
                    confidence: 0.9
                )
            )
        }
        return (s, { kf in images[kf.index]! })
    }

    // MARK: - The gate: agreement with real pixels

    @Test func totalHeightMatchesTheCompositedImage() throws {
        let compositor = Compositor(refinementDelta: 0)
        for (count, breaks) in [(2, [Int]()), (4, []), (4, [1]), (5, [1, 3])] {
            let (s, images) = session(count: count, breaksAfter: breaks)
            let composite = try compositor.composite(s, images: images)
            #expect(
                compositor.placement(s).totalHeight == composite.height,
                "count=\(count) breaks=\(breaks)"
            )
        }
    }

    @Test func totalHeightMatchesWithChrome() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, images) = session(count: 4, topChrome: 24, bottomChrome: 18)
        let composite = try compositor.composite(s, images: images)
        #expect(compositor.placement(s).totalHeight == composite.height)
    }

    // MARK: - Spans

    @Test func spansAreContiguousAndCoverTheWholeHeight() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, _) = session(count: 5, breaksAfter: [2])
        let placement = compositor.placement(s)
        var cursor = 0
        for span in placement.spans {
            #expect(span.destY == cursor)
            #expect(span.height > 0)
            cursor += span.height
        }
        #expect(cursor == placement.totalHeight)
    }

    @Test func aSegmentBreakInsertsASeparatorSpan() throws {
        let compositor = Compositor(refinementDelta: 0, separatorHeight: 8)
        let (s, _) = session(count: 4, breaksAfter: [1])
        let placement = compositor.placement(s)
        let separators = placement.spans.filter { $0.keyframeIndex == nil }
        #expect(separators.count == 1)
        #expect(separators[0].height == 8)
        #expect(placement.segmentCount == 2)
        #expect(placement.destY(forBreakAfter: 1) == separators[0].destY)
        #expect(placement.destY(forBreakAfter: 0) == nil)
    }

    @Test func aJoinSitsWhereItsLowerFrameStarts() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, _) = session(count: 3, height: 300, dy: 180)
        let placement = compositor.placement(s)
        // Frame 0 contributes all 300 rows; frame 1 then starts at 300.
        #expect(placement.destY(forJoin: 0) == 300)
        #expect(placement.firstSpan(forKeyframeIndex: 1)?.destY == 300)
        // dy 180 into a 300-row frame: frame 1 contributes rows [120, 300) = 180 rows.
        #expect(placement.destY(forJoin: 1) == 480)
    }

    @Test func thereIsNoJoinAcrossASegmentBreak() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, _) = session(count: 4, breaksAfter: [1])
        let placement = compositor.placement(s)
        #expect(placement.destY(forJoin: 1) == nil, "keyframe 2 opens a new segment, so there is no join here")
        #expect(placement.destY(forJoin: 0) != nil)
        #expect(placement.destY(forJoin: 2) != nil)
    }

    @Test func anEmptySessionPlacesNothing() {
        var s = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 1, orientation: .portrait)
        s.status = .complete
        let placement = Compositor(refinementDelta: 0).placement(s)
        #expect(placement.spans.isEmpty)
        #expect(placement.totalHeight == 0)
        #expect(placement.destY(forJoin: 0) == nil)
    }

    /// A duplicated seam is a malformed manifest, not a crash. The shared walk builds its
    /// offset lookup with `uniquingKeysWith:` rather than `uniqueKeysWithValues:`, which used
    /// to trap here.
    @Test func aDuplicatedSeamDoesNotTrap() {
        var (s, _) = session(count: 3)
        s.seams.append(Seam(fromIndex: 0, provisionalDy: 999, confidence: 0.1))
        let placement = Compositor(refinementDelta: 0).placement(s)
        #expect(placement.totalHeight > 0)
    }
}
