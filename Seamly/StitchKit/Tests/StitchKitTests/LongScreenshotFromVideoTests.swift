import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// End-to-end "From Video": an untrimmed real screen recording must come out the other side as a
/// **long screenshot**, not as a manifest that merely looks healthy.
///
/// `Fixtures/Recordings/DSNN4777.MP4` is a 6.4 s, 60 fps, 1320×2868 HEVC recording of the same
/// Google Discover feed as `Fixtures/Screenshots2` — scrolled by hand, so it contains what a real
/// capture contains and the trimmed `RealDevice/scroll-recording.mp4` does not: a **fast flick**
/// that advances more than half a frame between consecutive sampled frames, and pauses where
/// nothing moves at all.
///
/// The assertions are contract-level rather than pinned counts, because the point is the product
/// promise — several overlapping keyframes, in order, assembled into one image taller than the
/// screen — and not any particular commit cadence.
@Suite struct LongScreenshotFromVideoTests {

    /// Clips that must each come out as one long screenshot at **both** decode cadences.
    ///
    /// `KMZK1521` is covered separately below rather than added here: at full decode rate its
    /// recovered order swaps two adjacent keyframes, which this test would assert against. That is
    /// a strictness gap rather than a shipped defect — the app imports video with `.inputOrder`,
    /// because capture chronology is authoritative — so folding it in would mean either a failing
    /// assertion or a weakened one, and its own test states exactly what it guarantees instead.
    ///
    /// `CKHQ1876.MP4` is deliberately absent for a stronger reason: it still splits. Its
    /// measurements are in the fixture README rather than asserted at a lowered threshold.
    static let clips = ["DSNN4777"]

    private func fixtureURL(_ name: String = "DSNN4777") throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "MP4", subdirectory: "Recordings"),
                     "missing video fixture \(name)")
    }

    /// Both cadences: the app imports at 30 fps (`LibraryModel.importVideo`), while the test tier
    /// has historically decoded full-rate. A capture that only survives one of them is not fixed.
    @Test(arguments: [nil, 30.0] as [Double?], clips)
    func aHandheldRecordingBecomesALongScreenshot(_ targetFPS: Double?, _ clip: String) async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(clip), driver: &driver, targetFPS: targetFPS)

        #expect(r.decodeFailures == 0, "real BGRA decode path must handle every HEVC frame")
        try #require(r.keyframes.count >= 4,
                     "\(clip): a multi-second scroll should bank several keyframes, got \(r.keyframes.count)")
        #expect(r.keyframes.map(\.metadata.index) == Array(0..<r.keyframes.count))

        let images = r.keyframes.map(\.image)
        let plan = try BatchStitcher().plan(images)
        #expect(plan.order == Array(0..<images.count),
                "\(clip): a single downward scroll must recover as capture order, got \(plan.order)")
        #expect(plan.session.segmentBreaks.isEmpty,
                "\(clip): one continuous scroll must stay one segment, got breaks \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")

        let stitched = try BatchStitcher().stitch(images)
        #expect(stitched.width == images[0].width)
        #expect(stitched.height > images[0].height,
                "\(clip): a long screenshot must be taller than one frame, got \(stitched.height) vs \(images[0].height)")
    }

    /// `KMZK1521.MP4` at the cadence the app actually imports at.
    ///
    /// Its job is to guard the **selector**, which `DSNN4777` cannot do alone. The masked overlap
    /// floor put a ceiling on how far a match could measure; `docs/logs/2026-08-08-02` raised that
    /// ceiling rather than removing it, and `DSNN4777` cannot tell those two apart because it only
    /// ever needed it lifted as far as its own flick. This clip scrolls past the raised ceiling: it
    /// banked **3 keyframes from 8.5 s of steady scrolling**, in two segments, until the floor was
    /// made geometric (`docs/logs/2026-08-09-03`). It now banks 6.
    ///
    /// The keyframe count is asserted with a floor rather than pinned, but a floor well above the
    /// broken value — 3 was the bug, and any regression toward it fails here.
    @Test func aSteadyScrollBanksKeyframesThroughout() async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(
            url: try fixtureURL("KMZK1521"), driver: &driver, targetFPS: 30)

        #expect(r.decodeFailures == 0)
        #expect(r.keyframes.count >= 6,
                "8.5s of steady scroll banked only \(r.keyframes.count) keyframes; the selector is losing the scroll")

        let images = r.keyframes.map(\.image)
        let plan = try BatchStitcher().plan(images)
        #expect(plan.order == Array(0..<images.count), "recovered \(plan.order)")
        #expect(plan.session.segmentBreaks.isEmpty,
                "one continuous scroll must stay one segment, got breaks \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")
        #expect(plan.session.seams.allSatisfy { !$0.isLowConfidence },
                "confidences \(plan.session.seams.map(\.confidence))")

        // Every segment must carry a real band — a lone-frame segment used to get `.unlocked` and
        // composite its bars into the middle of the page.
        for (i, band) in plan.session.contentBands.enumerated() {
            #expect(band.topChrome > 0, "segment \(i) has no chrome band")
        }

        let stitched = try BatchStitcher().stitch(images)
        #expect(stitched.height > images[0].height * 3,
                "6 keyframes of a continuous scroll should be several screens tall, got \(stitched.height)")
    }

    /// Consecutive keyframes must actually overlap — the capture-side contract the assembler
    /// depends on. A collapsed capture can still satisfy "several keyframes" by banking
    /// near-duplicates or disjoint screens; this is what separates those from a real scroll.
    @Test(arguments: ["DSNN4777", "KMZK1521"])
    func consecutiveKeyframesOverlapEnoughToStitch(_ clip: String) async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(clip), driver: &driver, targetFPS: 30)
        try #require(r.keyframes.count >= 4, "\(clip): got \(r.keyframes.count) keyframes")

        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        let detector = ContentBandDetector()
        let profiles = r.keyframes.map { profiler.profile($0.image) }
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let n = min(a.rowCount, b.rowCount)
            let bound = max(1, n - matcher.minimumOverlap)
            let mask = detector.staticMask(a, b)
            let masked = matcher.match(a, b, searchRange: 1...bound, rowMask: mask)
            let plain = matcher.match(a, b, searchRange: 1...bound)
            let m = masked.confidence >= plain.confidence ? masked : plain
            let overlap = Double(n - min(max(0, m.dy), n)) / Double(n)
            #expect(overlap > 0.25 && overlap < 0.95,
                    "\(clip) overlap[\(i)] = \(overlap): neither a near-duplicate nor a gap")
        }
    }
}
