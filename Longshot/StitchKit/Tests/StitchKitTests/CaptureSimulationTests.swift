import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import StitchKit

/// The synthetic capture tier. A tall real oracle — our own stitched Chrome page (`BatchStitcher`
/// over the Example fixtures, 5978 px) — is scrolled past a fixed top-chrome bar with seeded
/// jitter (+ one fling in the long scenario), and every frame drives the REAL `ScrollCaptureDriver`.
/// Ground truth is known, so the assertions are precise: capture is non-empty despite the static
/// bar, consecutive overlaps sit near `1 − commitFraction`, and the committed keyframes re-stitch
/// (closed loop through `BatchStitcher`) into a monotonic page.
@Suite struct CaptureSimulationTests {

    /// The stitched Chrome oracle, generated once from the committed Example fixtures.
    private func chromeOracle() throws -> CGImage {
        let names = ["20260718-225057", "20260718-225102", "20260718-225107"]
        let images = try names.map { name -> CGImage in
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Example"))
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            return try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        }
        return try BatchStitcher().stitch(images)
    }

    /// Consecutive overlap fractions between committed keyframes, measured the same way capture
    /// does (downward masked/plain match, taking the more confident) — for asserting cadence.
    private func overlaps(_ kfs: [ScrollCaptureDriver.CapturedKeyframe]) -> [Double] {
        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        let detector = ContentBandDetector()
        let profiles = kfs.map { profiler.profile($0.image) }
        var out: [Double] = []
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let n = min(a.rowCount, b.rowCount)
            let bound = max(1, n - matcher.minimumOverlap)
            let mask = detector.staticMask(a, b)
            let masked = matcher.match(a, b, searchRange: 1...bound, rowMask: mask)
            let plain = matcher.match(a, b, searchRange: 1...bound)
            let m = masked.confidence >= plain.confidence ? masked : plain
            let dy = min(max(0, m.dy), n)
            out.append(Double(n - dy) / Double(n))
        }
        return out
    }

    // MARK: - Scenario 1: faithful ~2868px viewport, gentle jitter, short scroll

    @Test func faithfulViewportCapturesNonEmptyPageDespiteStaticChrome() throws {
        let oracle = try chromeOracle()
        let sim = CaptureSimulator(
            oracle: oracle,
            viewportHeight: 2868,        // faithful device viewport
            topChromeHeight: 210,        // fixed status/search bar
            scrollStep: 40,              // gentle reading scroll
            jitter: 8,
            flingAtFrame: nil,
            flingExtra: 0
        )
        var driver = ScrollCaptureDriver()
        let kfs = sim.run(driver: &driver)

        // Empty-capture regression guard: the static bar must not pin scroll to zero. Observed
        // (deterministic, seeded LCG): 4 keyframes — 3 regular commits + 1 trailing `finish()`
        // commit for the last uncommitted stretch of scroll.
        #expect(kfs.count == 4, "faithful viewport should bank 4 keyframes, got \(kfs.count)")
        #expect(kfs.first?.metadata.index == 0)
        #expect(kfs.map { $0.metadata.index } == Array(0..<kfs.count), "indices must be monotonic 0…n")

        // Cadence: consecutive overlaps ≈ 1 − commitFraction (0.5). The trailing pair (last entry)
        // is the `finish()` commit, which only requires ≥5% uncommitted motion (not the regular
        // 50% commit threshold), so it legitimately sits closer to a near-duplicate than the
        // regular commits — hence its own, looser band. Observed: [0.5, 0.49375, 0.921875].
        let o = overlaps(kfs)
        for i in 0..<(o.count - 1) {
            #expect(o[i] > 0.30 && o[i] < 0.75, "overlap[\(i)] = \(o[i]) outside the sane cadence band")
        }
        #expect(o.last! > 0.30 && o.last! < 0.95, "trailing overlap = \(o.last!) outside the tail-commit band")

        // Closed loop: the captured keyframes re-stitch into a monotonic single segment.
        let plan = try BatchStitcher().plan(kfs.map { $0.image })
        #expect(plan.order == Array(0..<kfs.count), "captured order should already be scroll order")
        #expect(plan.session.segmentBreaks.isEmpty, "faithful capture should be one continuous segment")
        let out = try BatchStitcher().stitch(kfs.map { $0.image })
        #expect(out.width == oracle.width)
        // Stitched height recovers most of the scrolled span (chrome cropped to appear once).
        // Observed: out.height == oracle.height (5978) — this scenario's viewport matches the raw
        // frame height, so re-stitching the captured keyframes reproduces the oracle almost exactly.
        #expect(out.height >= oracle.height - 2868, "stitch collapsed: \(out.height) vs oracle \(oracle.height)")
        #expect(out.height <= oracle.height + 2868, "stitch stacked: \(out.height) vs oracle \(oracle.height)")
    }

    // MARK: - Scenario 2: long-scroll ~1500px viewport, jitter + one fling

    /// Viewport tuned from the brief's ~1400px guess to 1500 (chrome 100, content 1400px): at
    /// smaller content windows (~1100–1250px, tried during calibration at chrome 220–300) this
    /// real oracle's Discover-feed content occasionally starves `BatchStitcher`'s blind pairwise
    /// matcher of enough structure for a confident (≥0.45) edge on one adjacent pair, and/or
    /// confuses the very first (top-of-page, low-structure nav chrome) keyframe's global
    /// ordering — both independent of the fling (reproduced with `flingAtFrame: nil` during
    /// calibration). At content ≈1400px this stabilizes: order recovers correctly and only one
    /// low-confidence internal edge remains (see the `segmentBreaks` assertion below).
    @Test func longScrollViewportCapturesCadenceAcrossJitterAndFling() throws {
        let oracle = try chromeOracle()
        let sim = CaptureSimulator(
            oracle: oracle,
            viewportHeight: 1500,        // long-scroll viewport → more keyframes
            topChromeHeight: 100,        // fixed status/search bar
            scrollStep: 35,
            jitter: 10,
            flingAtFrame: 12,            // one deterministic fast flick
            flingExtra: 260             // large jump that still overlaps (< a full content window)
        )
        var driver = ScrollCaptureDriver()
        let kfs = sim.run(driver: &driver)

        // Observed (deterministic, seeded LCG): 7 keyframes.
        #expect(kfs.count == 7, "long scroll should bank 7 keyframes, got \(kfs.count)")
        #expect(kfs.map { $0.metadata.index } == Array(0..<kfs.count))

        // Selector still commits across the fling; overlaps stay in the sane band (the fling is a
        // fast-but-overlapping scroll, not a lost-lock gap). Observed:
        // [0.4953125, 0.496875, 0.490625, 0.484375, 0.4890625, 0.5578125] — the last entry is the
        // trailing `finish()` commit (see scenario 1), banded slightly looser for the same reason.
        let o = overlaps(kfs)
        for i in 0..<(o.count - 1) {
            #expect(o[i] > 0.30 && o[i] < 0.70, "overlap[\(i)] = \(o[i]) outside the sane band")
        }
        #expect(o.last! > 0.30 && o.last! < 0.80, "trailing overlap = \(o.last!) outside the tail-commit band")

        // Downstream outcome, re-derived blind by `BatchStitcher` (no ordering info passed in):
        // capture order is still recovered correctly end-to-end...
        let plan = try BatchStitcher().plan(kfs.map { $0.image })
        #expect(plan.order == Array(0..<kfs.count), "captured order should already be scroll order")

        // ...but one internal edge (kf 3→4, independent of the fling — reproduced identically with
        // `flingAtFrame: nil` during calibration, just at a shifted index) falls under
        // `BatchStitcher`'s default 0.45 edge-confidence floor: this stretch of the real Discover
        // feed has less differentiated structure than its neighbours, which is a genuine limit of
        // *blind* (order-unaware) pairwise re-matching on real content at this keyframe density —
        // not a capture defect (the driver still committed a correctly-overlapping keyframe here;
        // `overlaps` above confirms its measured overlap sits in the normal cadence band). This is
        // the documented fallback per the calibration decision: assert the break explicitly rather
        // than tune indefinitely for an oracle-content coincidence.
        #expect(plan.session.segmentBreaks.count == 1, "expected exactly the one known low-confidence internal edge, got \(plan.session.segmentBreaks)")
        #expect(plan.session.segmentBreaks.first?.reason == .lostLock)
    }
}
