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

    private func fixtureURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "DSNN4777", withExtension: "MP4", subdirectory: "Recordings"),
                     "missing video fixture")
    }

    /// Both cadences: the app imports at 30 fps (`LibraryModel.importVideo`), while the test tier
    /// has historically decoded full-rate. A capture that only survives one of them is not fixed.
    @Test(arguments: [nil, 30.0] as [Double?])
    func aHandheldRecordingBecomesALongScreenshot(_ targetFPS: Double?) async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver, targetFPS: targetFPS)

        #expect(r.decodeFailures == 0, "real BGRA decode path must handle every HEVC frame")
        try #require(r.keyframes.count >= 4,
                     "a 6.4s scroll should bank several keyframes, got \(r.keyframes.count)")
        #expect(r.keyframes.map(\.metadata.index) == Array(0..<r.keyframes.count))

        let images = r.keyframes.map(\.image)
        let plan = try BatchStitcher().plan(images)
        #expect(plan.order == Array(0..<images.count),
                "a single downward scroll must recover as capture order, got \(plan.order)")
        #expect(plan.session.segmentBreaks.isEmpty,
                "one continuous scroll must stay one segment, got breaks \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")

        let stitched = try BatchStitcher().stitch(images)
        #expect(stitched.width == images[0].width)
        #expect(stitched.height > images[0].height,
                "a long screenshot must be taller than one frame, got \(stitched.height) vs \(images[0].height)")
    }

    /// Consecutive keyframes must actually overlap — the capture-side contract the assembler
    /// depends on. A collapsed capture can still satisfy "several keyframes" by banking
    /// near-duplicates or disjoint screens; this is what separates those from a real scroll.
    @Test func consecutiveKeyframesOverlapEnoughToStitch() async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver, targetFPS: 30)
        try #require(r.keyframes.count >= 4, "got \(r.keyframes.count) keyframes")

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
                    "overlap[\(i)] = \(overlap): neither a near-duplicate nor a gap")
        }
    }
}
