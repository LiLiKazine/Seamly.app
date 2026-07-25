import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import StitchKit

/// `BatchStitcher` stitches a *fixed, unordered* set of overlapping screenshots (the
/// off-device "pick images → stitch" case), as opposed to `ScrollCaptureDriver`, which models a
/// live ordered broadcast stream. The oracle is the three real Chrome/Discover screenshots in
/// `Fixtures/Example`, which the streaming path stacks (wrong order, lost lock on every pair).
@Suite struct BatchStitcherTests {

    static let names = ["20260718-225057", "20260718-225102", "20260718-225107"]

    private func load(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Example"))
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// Frames handed over in *file* (time) order — which is spatial mid, bottom, top — must be
    /// reordered into the true scroll order top→bottom = input indices [2, 0, 1], stitched into
    /// one continuous segment with two downward seams.
    @Test func reordersFileOrderIntoScrollOrder() throws {
        let images = try Self.names.map { try load($0) }
        let plan = try BatchStitcher().plan(images)
        #expect(plan.order == [2, 0, 1])
        #expect(plan.session.segmentBreaks.isEmpty)
        #expect(plan.session.seams.count == 2)
        #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 })
    }

    /// Order detection is independent of how the caller happens to arrange the array: given the
    /// frames in yet another permutation, the plan still recovers scroll order top→bottom.
    @Test func detectsOrderFromADifferentPermutation() throws {
        // Input arrangement [02, 07, 57] → source indices 02=0, 07=1, 57=2.
        // Spatial top→bottom is [07, 57, 02] = input indices [1, 2, 0].
        let images = try [Self.names[1], Self.names[2], Self.names[0]].map { try load($0) }
        let plan = try BatchStitcher().plan(images)
        #expect(plan.order == [1, 2, 0])
    }

    /// The composited output is one continuous long image: taller than a single frame (content
    /// was appended) yet well short of three frames stacked (overlaps removed, repeated chrome
    /// cropped to appear once).
    @Test func stitchesIntoOneContinuousImage() throws {
        let images = try Self.names.map { try load($0) }
        let out = try BatchStitcher().stitch(images)
        let frameH = images[0].height
        #expect(out.width == images[0].width)
        #expect(out.height > frameH)
        #expect(out.height < frameH * 3)
    }

    /// Two frames that don't overlap at all (top of page + bottom of page) can't be stitched
    /// into one continuous run — they must fall into separate segments rather than being
    /// silently forced together.
    @Test func nonOverlappingFramesSplitIntoSegments() throws {
        let top = try load(Self.names[2])      // 07 = page top
        let bottom = try load(Self.names[1])   // 02 = page bottom (no overlap with top)
        let plan = try BatchStitcher().plan([top, bottom])
        #expect(plan.session.segmentBreaks.count == 1)
        #expect(plan.session.seams.isEmpty)
    }

    /// The export path routes through the same recovered order: `writePDF` produces a readable
    /// multi-page-capable PDF from the reordered frames (mirrors `stitch`, for `StitchAssembler`).
    @Test func writesPDFFromRecoveredOrder() throws {
        let images = try Self.names.map { try load($0) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("batch-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try BatchStitcher().writePDF(images, to: url)
        let doc = try #require(CGPDFDocument(url as CFURL))
        #expect(doc.numberOfPages >= 1)
    }

    /// A single image is a degenerate but valid batch: one keyframe, no seams, no breaks.
    @Test func singleImageIsTrivialPlan() throws {
        let one = try load(Self.names[0])
        let plan = try BatchStitcher().plan([one])
        #expect(plan.order == [0])
        #expect(plan.session.keyframes.count == 1)
        #expect(plan.session.seams.isEmpty)
    }

    /// Assembling in a supplied order keeps that order verbatim (no re-sort), and a truly
    /// in-scroll-order set still stitches into one continuous segment with the right seam count.
    @Test func assumingOrderKeepsGivenOrderForOverlappingSet() throws {
        // names are spatial mid, bottom, top; true top→bottom is [2, 0, 1].
        let images = try [Self.names[2], Self.names[0], Self.names[1]].map { try load($0) }  // already top→bottom
        let plan = try BatchStitcher().plan(images, assumingOrder: [0, 1, 2])
        #expect(plan.order == [0, 1, 2])
        #expect(plan.session.segmentBreaks.isEmpty)
        #expect(plan.session.seams.count == 2)
        #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 })
    }

    /// A wrong supplied order is NOT silently corrected — the whole point of the fallback is to
    /// trust the caller's order. Non-overlapping consecutive pairs become segment breaks.
    @Test func assumingOrderDoesNotReorderAndBreaksNonOverlappingNeighbours() throws {
        // Supplied order bottom, top, mid: neighbours (bottom,top) don't overlap → a break.
        let images = try [Self.names[1], Self.names[2], Self.names[0]].map { try load($0) }
        let plan = try BatchStitcher().plan(images, assumingOrder: [0, 1, 2])
        #expect(plan.order == [0, 1, 2])
        #expect(!plan.session.segmentBreaks.isEmpty)
    }

    /// Content whose horizontal pattern repeats identically row to row, over a gentle vertical
    /// ramp, defeats the translucency test: the ramp's mean shift lands under
    /// `translucencyMeanCeiling` while the shared `sin(x)` structure keeps the centered
    /// difference under `structureTolerance`, so **every** row reads as translucent chrome.
    ///
    /// Measured before the guard, on exactly these frames: `topChrome` came back as 361 on a
    /// 360px frame — a band taller than the image — flagged `isLowConfidence: false`, which
    /// collapsed a 640px stitch to 362px. The detector cannot be tuned out of this (the doc on
    /// `translucencyMeanCeiling` records why the shape test alone is insufficient), so the fix
    /// is to refuse the measurement rather than believe it.
    @Test func allStaticMeasurementIsRefusedInsteadOfCroppingTheWholeFrame() throws {
        let W = 120, H = 360, D = 140
        let source = TestImages.make(width: W, height: H + 2 * D) { ctx in
            for y in 0..<(H + 2 * D) {
                for x in 0..<W {
                    let v = 60.0 + Double(y) * (120.0 / Double(H + 2 * D))
                        + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                    ctx.setFillColor(gray: CGFloat(max(0, min(255, v)) / 255), alpha: 1)
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let images = (0..<3).map { source.cropping(to: CGRect(x: 0, y: $0 * D, width: W, height: H))! }

        let plan = try BatchStitcher().plan(images, assumingOrder: [0, 1, 2])
        let band = try #require(plan.session.contentBands.first)
        // Refused, not believed: nothing cropped, and flagged so the editor can override.
        #expect(band.topChrome == 0)
        #expect(band.bottomChrome == 0)
        #expect(band.isLowConfidence)

        // And the stitch keeps its full extent rather than collapsing to ~one frame.
        let out = try Compositor().composite(plan.session) { images[plan.order[$0.index]] }
        #expect(abs(out.height - (H + 2 * D)) <= 24)
    }
}
