import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Issue #9: `Compositor.refineVertical` is supposed to snap a provisional offset to pixel
/// precision, but it was the one matching path that scored the chrome band as content. These
/// tests pin the refined offsets against a full-width brute-force ground truth computed from
/// raw pixels, and pin the confidence that decides whether refinement is used at all.
@Suite struct SeamRefinementTests {

    private func fixtureImages() throws -> [CGImage] {
        try (0...5).map { i in
            let name = String(format: "youtube-%02d", i)
            let url = try #require(
                Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "RealDevice"),
                "missing fixture RealDevice/\(name).png"
            )
            return try KeyframeIO.read(from: url)
        }
    }

    /// Ground truth, independent of `VerticalProfile` and `OffsetMatcher`: mean absolute
    /// difference over the raw grayscale pixels of the whole content band, at every candidate
    /// offset in `range`. Deliberately the dumbest possible measurement — its value is that it
    /// shares no code with the thing under test.
    private func bruteForceDy(_ a: CGImage, _ b: CGImage, range: ClosedRange<Int>, bandTop: Int, bandBottom: Int) -> (dy: Int, costs: [Int: Double]) {
        let w = a.width, h = a.height
        func gray(_ img: CGImage) -> [Float] {
            let cs = CGColorSpaceCreateDeviceGray()
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
            return (0..<(w * h)).map { Float(p[$0]) / 255 }
        }
        let ga = gray(a), gb = gray(b)
        let lo = bandTop, hi = h - bandBottom
        var best = (dy: range.lowerBound, cost: Double.greatestFiniteMagnitude)
        var costs: [Int: Double] = [:]
        for dy in range {
            var sum = 0.0, n = 0
            // Row r of B holds the content that sits at row r+dy of A on a downward scroll.
            for r in lo..<max(lo, hi - dy) {
                let ra = r + dy
                guard ra < hi else { break }
                for c in 0..<w { sum += Double(abs(ga[ra * w + c] - gb[r * w + c])) }
                n += w
            }
            guard n > 0 else { continue }
            costs[dy] = sum / Double(n)
            if costs[dy]! < best.cost { best = (dy, costs[dy]!) }
        }
        return (best.dy, costs)
    }

    /// Full-resolution ground truth for this capture is 1488 / 1433 / 1452 / 1509 / 1442 px.
    /// The stored fixtures are half resolution, so pairs 1-2 and 3-4 land on 716.5 and 754.5 —
    /// no integer answer exists for those, and the brute-force costs at the two neighbours are
    /// a near tie. Only the three pairs with an exact integer truth can be asserted to 0px.
    private static let unambiguousPairs = [0, 2, 4]

    /// Note this pins the acceptance criterion rather than guarding the fix: it passes both with
    /// and without chrome masking, because on these three pairs the argmin was never in doubt.
    /// `chromeMaskingKeepsEverySeamAboveTheRefinementThreshold` is the one that goes red on a
    /// regression.
    @Test func refinedOffsetsMatchFullWidthBruteForceGroundTruth() throws {
        let images = try fixtureImages()
        let h = images[0].height
        let plan = try BatchStitcher().plan(images, assumingOrder: Array(0..<images.count))
        let band = plan.session.contentBand(forSegment: 0)
        let compositor = Compositor()

        let refined = try compositor.refineSeams(plan.session) { images[$0.index] }
        let refinedByFrom = Dictionary(uniqueKeysWithValues: refined.map { ($0.fromIndex, $0.provisionalDy) })

        for pair in Self.unambiguousPairs {
            let dy = try #require(refinedByFrom[pair], "no refined seam for pair \(pair)-\(pair + 1)")
            let truth = bruteForceDy(images[pair], images[pair + 1],
                                     range: (dy - 4)...(dy + 4),
                                     bandTop: band.topChrome, bandBottom: band.bottomChrome)
            #expect(dy == truth.dy,
                    "pair \(pair)-\(pair + 1): refined \(dy)px, full-width brute force says \(truth.dy)px")
        }
    }

    /// The defect that actually bit: with chrome scored as content the score valley is shallow,
    /// so the hardest pair fell under `refinementConfidence` and its refinement was **discarded**
    /// in favour of the coarse provisional. Masking the band roughly doubles the valley depth —
    /// pair 3-4 measured 0.16 unmasked and 0.73 masked.
    ///
    /// Asserted through the public surface: no seam may come back flagged low-confidence on a
    /// clean single scroll whose chrome is correctly detected.
    @Test func chromeMaskingKeepsEverySeamAboveTheRefinementThreshold() throws {
        let images = try fixtureImages()
        let plan = try BatchStitcher().plan(images, assumingOrder: Array(0..<images.count))
        let refined = try Compositor().refineSeams(plan.session) { images[$0.index] }

        let flagged = refined.filter(\.isLowConfidence).map(\.fromIndex)
        #expect(flagged.isEmpty,
                "seams \(flagged) fell below refinementConfidence — refinement was discarded and the coarse provisional kept")
    }

    /// Issue #9 proposed refining on full-width columns. Measured across 64…660 columns every
    /// pair returns the same `dy`, so the 1px discrepancy is not a horizontal-sampling artifact
    /// and the extra render cost buys nothing. Pinned so the proposal isn't retried blind.
    @Test func profileWidthDoesNotChangeRefinedOffsets() throws {
        let images = try fixtureImages()
        let plan = try BatchStitcher().plan(images, assumingOrder: Array(0..<images.count))

        let baseline = try Compositor(profiler: VerticalProfile(targetWidth: 64))
            .refineSeams(plan.session) { images[$0.index] }
            .map(\.provisionalDy)

        for width in [128, 256, 660] {
            let wide = try Compositor(profiler: VerticalProfile(targetWidth: width))
                .refineSeams(plan.session) { images[$0.index] }
                .map(\.provisionalDy)
            #expect(wide == baseline, "width \(width) changed refined offsets: \(wide) vs \(baseline)")
        }
    }
}
