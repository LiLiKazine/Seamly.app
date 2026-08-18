import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// `JoinAlignment` is a second copy of the placement rule inside `Compositor.plan`, because `plan`
/// is private and its layout type is internal. Duplicated layout maths that drifts is how a
/// preview starts promising something the exported image will not honour — so the copy is asserted
/// against a real composite here, not trusted.
struct JoinAlignmentTests {

    // MARK: - Helpers

    private func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private func crop(_ image: CGImage, y: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))!
    }

    private func twoFrameSession(
        height: Int = 600,
        dy: Int,
        topChrome: Int = 0,
        bottomChrome: Int = 0
    ) -> StitchSession {
        let keyframes = (0..<2).map {
            Keyframe(filename: "kf-\($0).bgra", pixelWidth: 240, pixelHeight: height, index: $0)
        }
        var session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: keyframes,
            seams: [Seam(fromIndex: 0, provisionalDy: dy, confidence: 0.5)]
        )
        session.ensureChromeRecordsForKeyframes()
        if topChrome > 0 || bottomChrome > 0 {
            for keyframe in keyframes {
                session.setChromeOverride(topChrome, for: .top, keyframeID: keyframe.id)
                session.setChromeOverride(bottomChrome, for: .bottom, keyframeID: keyframe.id)
            }
        }
        return session
    }

    // MARK: - Geometry

    @Test func theLowerFrameStartsWhereTheUpperFrameStopsShowingContent() throws {
        let session = twoFrameSession(dy: 250)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(alignment.upperContentBottom == 600)
        #expect(alignment.lowerSourceStart == 350)   // 600 - 250
    }

    @Test func chromeShortensTheUpperFrameAndMovesTheLowerFramesFirstRow() throws {
        let session = twoFrameSession(dy: 250, topChrome: 40, bottomChrome: 30)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(alignment.upperContentBottom == 570)   // 600 - 30
        #expect(alignment.lowerContentTop == 40)
        #expect(alignment.lowerContentBottom == 570)
        #expect(alignment.lowerSourceStart == 320)     // 570 - 250
    }

    /// `Compositor` clamps the lower frame's first row into its content band. The preview must
    /// clamp identically, or it would show rows the export does not draw.
    @Test func theLowerFramesFirstRowIsClampedIntoItsContentBand() throws {
        var session = twoFrameSession(dy: 250, topChrome: 40, bottomChrome: 30)
        session.seams[0].provisionalDy = 10_000
        let wide = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(wide.lowerSourceStart == 40)           // clamped to the top of the content band

        session.seams[0].provisionalDy = -10_000
        let narrow = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(narrow.lowerSourceStart == 570)        // clamped to the bottom
    }

    @Test func aJoinWithNoSecondKeyframeCannotBeBuilt() {
        var session = twoFrameSession(dy: 250)
        session.keyframes.removeLast()
        session.keyframeChrome = []
        #expect(JoinAlignment(session: session, joinIndex: 0) == nil)
    }

    // MARK: - The drag

    /// The sign is the load-bearing part of the whole interaction. Dragging down must reveal
    /// earlier content — the lower half's pixels follow the finger.
    @Test func draggingDownRaisesTheOffsetAndDraggingUpLowersIt() throws {
        let session = twoFrameSession(dy: 300)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        let down = alignment.dy(draggedBy: 10, from: 300, sourcePixelsPerPoint: 3, zoom: 1)
        let up = alignment.dy(draggedBy: -10, from: 300, sourcePixelsPerPoint: 3, zoom: 1)

        #expect(down == 330)
        #expect(up == 270)
    }

    /// Zoom is the precision mechanism: magnifying divides how many source pixels a point covers,
    /// which is what makes single-pixel work possible without a separate fine-adjust control.
    @Test func zoomingDividesHowFarTheContentMovesPerPoint() throws {
        let session = twoFrameSession(dy: 300)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        #expect(alignment.dy(draggedBy: 10, from: 300, sourcePixelsPerPoint: 3.3, zoom: 3.3) == 310)
        #expect(alignment.dy(draggedBy: 10, from: 300, sourcePixelsPerPoint: 3.3, zoom: 1) == 333)
    }

    /// Outside this range the compositor's own clamp pins the picture while the finger keeps
    /// going — a dead zone that reads as a broken control. It stops at the edge instead.
    @Test func theOffsetStopsAtTheEdgesOfTheRangeThatActuallyMovesAnything() throws {
        let session = twoFrameSession(dy: 300, topChrome: 40, bottomChrome: 30)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        #expect(alignment.dyRange.lowerBound == 1)
        #expect(alignment.dyRange.upperBound == 530)   // upperContentBottom 570 - lowerContentTop 40
        #expect(alignment.dy(draggedBy: 100_000, from: 300, sourcePixelsPerPoint: 3, zoom: 1) == 530)
        #expect(alignment.dy(draggedBy: -100_000, from: 300, sourcePixelsPerPoint: 3, zoom: 1) == 1)
    }

    @Test func settingTheOffsetDirectlyIsAlsoClamped() throws {
        let session = twoFrameSession(dy: 300)
        var alignment = try #require(JoinAlignment(session: session, joinIndex: 0))
        alignment.setDy(999_999)
        #expect(alignment.dy == alignment.dyRange.upperBound)
    }

    // MARK: - Equivalence with the real compositor

    /// The test that keeps the duplicated layout maths honest. A real `Compositor` composite of the
    /// same two frames must place the join exactly where `JoinAlignment` says — checked two ways:
    /// the strip's height (a direct read-out of the placement) and the pixels either side of the
    /// boundary.
    @Test func theRealCompositorPlacesTheJoinWhereThisSaysItWill() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("align-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let source = makeSource(width: 240, height: 1400)
        let session = twoFrameSession(dy: 271)          // deliberately not the true offset
        for (i, keyframe) in session.keyframes.enumerated() {
            try KeyframeIO.writeRaw(
                crop(source, y: i * 300, height: 600),
                to: folder.appendingPathComponent(keyframe.filename)
            )
        }
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        let image = try StitchAssembler.composite(session, in: folder)

        // The strip is: the upper frame's content, then the lower frame from `lowerSourceStart`
        // to its very bottom (content plus whatever bottom chrome it has).
        let expectedHeight = alignment.upperContentBottom
            + alignment.lowerPixelHeight - alignment.lowerSourceStart
        #expect(image.height == expectedHeight)

        // Height alone cannot catch a mirrored axis, so also check the pixels: the composite's
        // first row below the boundary must look far more like the lower frame's
        // `lowerSourceStart` row than like a row well away from it.
        let cs = StitchAssembler.colorSpace(for: session)
        let lower = try StitchAssembler.loadKeyframe(session.keyframes[1], in: folder, colorSpace: cs)
        let atBoundary = try rowDifference(image, row: alignment.upperContentBottom,
                                          lower, row: alignment.lowerSourceStart)
        let wellAway = try rowDifference(image, row: alignment.upperContentBottom,
                                        lower, row: alignment.lowerSourceStart + 40)
        #expect(atBoundary < wellAway / 2)
    }

    /// Mean absolute per-byte difference between one row of each image. Tolerant of colour-space
    /// and alpha handling, discriminating about which row was drawn.
    private func rowDifference(_ a: CGImage, row rowA: Int, _ b: CGImage, row rowB: Int) throws -> Double {
        func bytes(_ image: CGImage, _ row: Int) throws -> [UInt8] {
            let width = image.width
            let cs = CGColorSpaceCreateDeviceGray()
            let ctx = try #require(CGContext(
                data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width,
                space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            let crop = try #require(image.cropping(to: CGRect(x: 0, y: row, width: width, height: 1)))
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: 1))
            let data = try #require(ctx.data)
            return (0..<width).map { data.load(fromByteOffset: $0, as: UInt8.self) }
        }
        let left = try bytes(a, rowA), right = try bytes(b, rowB)
        let total = zip(left, right).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
        return total / Double(min(left.count, right.count))
    }
}
