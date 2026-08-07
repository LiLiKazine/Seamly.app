import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Chrome measurement on a screenshot set whose bars are **not uniformly static**.
///
/// `Fixtures/Screenshots2` is five real Chrome-for-iOS screenshots of a Google Discover feed
/// (1320×2868, `IMG_1850`…`IMG_1854`, ascending filename order is scroll order). Unlike the
/// `Screenshots` set, each bar here contains a strip that changes between shots — the status
/// bar's clock and indicators at the top, and a 15 px strip above the home indicator at the
/// bottom. Measured on the raw pixels across all five frames (see the fixture README):
///
/// | rows       | what        |
/// |------------|-------------|
/// | 0…77       | status bar, identical |
/// | 78…116     | clock / status icons — **moves** |
/// | 117…371    | rest of the status bar + the omnibox, identical |
/// | 372…2633   | the scrolling content |
/// | 2634…2828  | the bottom toolbar, identical |
/// | 2829…2843  | **moves** |
/// | 2844…2867  | home indicator, identical |
///
/// So the true chrome is 372 px at the top and 234 px at the bottom, and any measurement that
/// scans inward from an edge and halts at the first row that moved reports a small fraction of
/// it — which then repeats once per keyframe in the composite.
@Suite struct DynamicChromeBandTests {

    static let names = ["IMG_1850", "IMG_1851", "IMG_1852", "IMG_1853", "IMG_1854"]

    /// First and last row of the scrolling content, measured from the raw pixels.
    static let contentTop = 372
    static let contentBottom = 2633
    static let frameHeight = 2868

    private func load(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "PNG", subdirectory: "Screenshots2"),
                               "missing fixture \(name)")
        return try KeyframeIO.read(from: url)
    }

    private func framesInScrollOrder() throws -> [CGImage] { try Self.names.map { try load($0) } }

    /// The band must cover a whole bar, not just the part of it above the first row that moved.
    ///
    /// The upper bounds allow the outward rounding `sourcePixels` applies (one profile row, and
    /// the profile quantizes 2868 px into 640 rows, so ~4.5 px each) — cropping a little extra
    /// chrome is harmless, cropping content is not.
    @Test func chromeBandCoversEachBarThoughBothContainAMovingStrip() throws {
        let plan = try BatchStitcher().plan(try framesInScrollOrder())
        #expect(plan.order == Array(0..<Self.names.count), "recovered \(plan.order)")
        #expect(plan.session.segmentBreaks.isEmpty, "one continuous scroll must stay one segment")
        let band = try #require(plan.session.contentBands.first)

        let trueTop = Self.contentTop
        let trueBottom = Self.frameHeight - 1 - Self.contentBottom
        #expect((trueTop...(trueTop + 16)).contains(band.topChrome),
                "top chrome \(band.topChrome)px, expected ~\(trueTop)px")
        #expect((trueBottom...(trueBottom + 16)).contains(band.bottomChrome),
                "bottom chrome \(band.bottomChrome)px, expected ~\(trueBottom)px")
    }

    /// The visible consequence, asserted on the pixels rather than on the manifest: an
    /// under-measured bottom band leaves the toolbar inside every keyframe's strip, so the
    /// finished image carries a row of browser buttons through the middle of the page — four
    /// times over, on this set. Correctly cropped it survives exactly once, at the very bottom.
    @Test func theToolbarSurvivesExactlyOnceInTheStitchedImage() throws {
        let frames = try framesInScrollOrder()
        let stitched = try BatchStitcher().stitch(frames)

        // A row from the middle of the toolbar, and every row of the output, in the same space.
        let profiler = VerticalProfile()
        let reference = profiler.profile(frames[0], forcingHeight: Self.frameHeight).rows[2700]
        let output = profiler.profile(stitched, forcingHeight: stitched.height)

        func matchesToolbar(_ row: [Float]) -> Bool {
            guard row.count == reference.count else { return false }
            var sum: Float = 0
            for c in 0..<row.count { sum += abs(row[c] - reference[c]) }
            return sum / Float(row.count) <= 0.01
        }

        var bands = 0
        var inBand = false
        for row in output.rows {
            let hit = matchesToolbar(row)
            if hit && !inBand { bands += 1 }
            inBand = hit
        }
        #expect(bands == 1, "the toolbar appears \(bands)x in the \(stitched.width)x\(stitched.height) stitch")
    }

    /// The other half of the inference, on the fixture that would be destroyed without it.
    ///
    /// Reading chrome as "everything outside the longest moving run" is only sound while the
    /// content really is one run. On the `Screenshots` set it is not — that page has interior rows
    /// that hold still across every pair, so the longest run starts 251 profile rows in, and
    /// believing it would crop **1130 px** of the page away as chrome (against a true 242 px bar).
    /// `minChromeStaticFraction` refuses it: only 0.303 of that candidate band actually held still.
    ///
    /// Both halves are asserted, so neither can pass vacuously — a guard that never fires and a
    /// guard that always fires look identical from the first assertion alone.
    @Test func aContentRunThatSwallowsThePageIsRefused() throws {
        let names = ["IMG_1757", "IMG_1758", "IMG_1759", "IMG_1760", "IMG_1761", "IMG_1762"]
        let frames = try names.map { name -> CGImage in
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "PNG", subdirectory: "Screenshots"))
            return try KeyframeIO.read(from: url)
        }
        let order = Array(0..<frames.count)

        let guarded = try #require(try BatchStitcher().plan(frames, assumingOrder: order).session.contentBands.first)
        #expect(guarded.topChrome == 242,
                "the measured bar, unchanged — see Fixtures/Screenshots/README.md")

        let unguarded = try #require(try BatchStitcher(minChromeStaticFraction: 0)
            .plan(frames, assumingOrder: order).session.contentBands.first)
        #expect(unguarded.topChrome > 1000,
                "the guard is inert here: the candidate band no longer swallows the page, so this fixture has stopped exercising the hazard and something else must")
    }
}
