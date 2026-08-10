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
@Suite struct DynamicChromeTests {

    static let names = ["IMG_1850", "IMG_1851", "IMG_1852", "IMG_1853", "IMG_1854"]

    /// First and last row of the scrolling content, measured from the raw pixels.
    static let contentTop = 372
    static let contentBottom = 2633
    static let frameHeight = 2868

    /// Both Chrome-for-iOS screenshot sets, at the same resolution and with the same bottom
    /// toolbar — so the same reference row identifies it in either.
    static let sets = [
        "Screenshots2": names,
        "Screenshots": ["IMG_1757", "IMG_1758", "IMG_1759", "IMG_1760", "IMG_1761", "IMG_1762"],
    ]

    private func load(_ name: String, from subdirectory: String = "Screenshots2") throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "PNG", subdirectory: subdirectory),
                               "missing fixture \(subdirectory)/\(name)")
        return try KeyframeIO.read(from: url)
    }

    private func framesInScrollOrder(_ subdirectory: String = "Screenshots2") throws -> [CGImage] {
        try #require(Self.sets[subdirectory]).map { try load($0, from: subdirectory) }
    }

    /// The band must cover a whole bar, not just the part of it above the first row that moved.
    ///
    /// The upper bounds allow the outward rounding `sourcePixels` applies (one profile row, and
    /// the profile quantizes 2868 px into 640 rows, so ~4.5 px each) — cropping a little extra
    /// chrome is harmless, cropping content is not.
    @Test func perKeyframeChromeCoversEachBarThoughBothContainAMovingStrip() throws {
        let plan = try BatchStitcher().plan(try framesInScrollOrder())
        #expect(plan.order == Array(0..<Self.names.count), "recovered \(plan.order)")
        #expect(plan.session.segmentBreaks.isEmpty, "one continuous scroll must stay one segment")
        let trueTop = Self.contentTop
        let trueBottom = Self.frameHeight - 1 - Self.contentBottom

        let records = Dictionary(uniqueKeysWithValues: plan.session.keyframeChrome.map { ($0.keyframeID, $0) })
        let automatic = try plan.session.keyframes.map { keyframe -> ChromeMeasurement in
            try #require(records[keyframe.id]?.automatic,
                         "missing automatic chrome for ordered keyframe \(keyframe.index)")
        }
        #expect(Set(records.keys) == Set(plan.session.keyframes.map(\.id)),
                "automatic chrome must be keyed by planned keyframe UUIDs")
        #expect(automatic.map(\.insets.top).allSatisfy { (trueTop...(trueTop + 16)).contains($0) },
                "per-keyframe top chrome \(automatic.map(\.insets.top))px, expected ~\(trueTop)px")
        #expect(automatic.map(\.insets.bottom).allSatisfy { (trueBottom...(trueBottom + 16)).contains($0) },
                "per-keyframe bottom chrome \(automatic.map(\.insets.bottom))px, expected ~\(trueBottom)px")
    }

    /// The visible consequence, asserted on the pixels rather than on the manifest: an
    /// under-measured bottom band leaves the toolbar inside every keyframe's strip, so the
    /// finished image carries a row of browser buttons through the middle of the page. Correctly
    /// cropped it survives exactly once, at the very bottom.
    ///
    /// Run over **both** screenshot sets, because they reach that outcome by opposite routes and
    /// only one of them was ever broken: `Screenshots2` needs the content-run inference (its bars
    /// contain moving strips), while `Screenshots` needs it *refused* (its page contains static
    /// rows) and is served by the inward scan. A change that fixes one by breaking the other
    /// passes neither.
    ///
    /// Each set also composites once with the band zeroed, which is what a failed measurement
    /// looks like downstream. That counter-check is what keeps this test honest: a green
    /// "appears once" proves nothing on its own unless the same code can be shown to count the
    /// duplicates when they are there.
    @Test(arguments: sets.keys.sorted())
    func theToolbarSurvivesExactlyOnceInTheStitchedImage(_ fixture: String) throws {
        let frames = try framesInScrollOrder(fixture)
        let plan = try BatchStitcher().plan(frames)
        let compositor = Compositor(refinementDelta: 16)
        let source = { (kf: Keyframe) in frames[plan.order[kf.index]] }

        // A row from the middle of the toolbar, and every row of the output, in the same space.
        let profiler = VerticalProfile()
        let reference = profiler.profile(frames[0], forcingHeight: Self.frameHeight).rows[2700]

        func toolbarOccurrences(in image: CGImage) -> Int {
            let output = profiler.profile(image, forcingHeight: image.height)
            var runs = 0
            var inRun = false
            for row in output.rows {
                var sum: Float = 0
                for c in 0..<min(row.count, reference.count) { sum += abs(row[c] - reference[c]) }
                let hit = row.count == reference.count && sum / Float(row.count) <= 0.01
                if hit && !inRun { runs += 1 }
                inRun = hit
            }
            return runs
        }

        let stitched = try compositor.composite(plan.session, images: source)
        #expect(toolbarOccurrences(in: stitched) == 1,
                "\(fixture): the toolbar appears \(toolbarOccurrences(in: stitched))x in the \(stitched.width)x\(stitched.height) stitch")

        var unchromed = plan.session
        unchromed.keyframeChrome = unchromed.keyframeChrome.map { KeyframeChrome(keyframeID: $0.keyframeID) }
        let uncropped = try compositor.composite(unchromed, images: source)
        #expect(toolbarOccurrences(in: uncropped) == frames.count,
                "\(fixture): with the band zeroed the toolbar should repeat once per keyframe; if it does not, the check above cannot see duplicates at all")
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

        let guardedSession = try BatchStitcher().plan(frames, assumingOrder: order).session
        let guarded = guardedSession.resolvedChrome(for: try #require(guardedSession.keyframes.first)).insets
        #expect(guarded.top == 242,
                "the measured bar, unchanged — see Fixtures/Screenshots/README.md")

        let unguardedSession = try BatchStitcher(minChromeStaticFraction: 0)
            .plan(frames, assumingOrder: order).session
        let unguarded = unguardedSession.resolvedChrome(for: try #require(unguardedSession.keyframes.first)).insets
        #expect(unguarded.top > 1000,
                "the guard is inert here: the candidate band no longer swallows the page, so this fixture has stopped exercising the hazard and something else must")
    }
}
