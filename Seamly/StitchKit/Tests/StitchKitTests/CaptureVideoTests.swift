import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// The video capture tier — highest fidelity. A trimmed real screen recording is decoded through
/// the exact on-device path (`AVAssetReader` → `PixelBufferImage` → `ScrollCaptureDriver`) and the
/// committed keyframes are re-stitched with `BatchStitcher`. Ground truth is fuzzy, so numeric
/// assertions are tolerant; the structural ones (0 decode failures, non-empty, sane overlap band,
/// monotonic order, and — since 2026-08-08 — a single continuous segment) are hard gates.
///
/// Literals below are pinned to the trimmed fixture's observed ground truth (362 frames decoded, 0
/// failures, 5 committed keyframes, consecutive overlaps 0.469–0.536), with tolerance around it —
/// not the full 11.2s spike's numbers (671 frames / 4 keyframes), which don't apply to this ~6s clip.
///
/// This clip is **trimmed to a steady scroll**, which is its limitation as much as its value: it
/// never flicks fast enough to cross the offset ceiling a masked match used to impose, so it could
/// not have caught the defect in `docs/logs/2026-08-08-02`. `LongScreenshotFromVideoTests` drives
/// an untrimmed handheld recording for exactly that reason; the two tiers are complementary.
@Suite struct CaptureVideoTests {

    private func fixtureURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "scroll-recording", withExtension: "mp4", subdirectory: "RealDevice"),
                     "missing trimmed video fixture (see plan Task 3 Step 1)")
    }

    @Test func everyFrameDecodesThroughTheRealPath() async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        // Observed: 362 frames. Floor well below that so a slightly shorter re-trim still passes.
        #expect(r.frames > 300, "expected a real frame stream, got \(r.frames)")
        #expect(r.decodeFailures == 0, "real BGRA decode path must handle every HEVC frame")
    }

    @Test func captureIsNonEmptyWithSaneOverlaps() async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        // Observed: 5 keyframes. `try #require` (not `#expect`): the loop below indexes
        // 0..<(profiles.count - 1), so a 0/1-keyframe regression must fail here, not trap on a
        // negative range down there.
        try #require(r.keyframes.count >= 4, "capture should bank several keyframes, got \(r.keyframes.count)")
        #expect(r.keyframes.map { $0.metadata.index } == Array(0..<r.keyframes.count))

        // Consecutive overlaps sit in a sane band (observed 0.469–0.536; spike measured ≈ 0.47–0.49
        // on the full clip).
        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        let detector = ChromeStaticRowDetector()
        let profiles = r.keyframes.map { profiler.profile($0.image) }
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let n = min(a.rowCount, b.rowCount)
            let bound = max(1, n - matcher.minimumOverlap)
            let mask = detector.staticMask(a, b)
            let masked = matcher.match(a, b, searchRange: 1...bound, rowMasks: RowMaskPair(shared: mask))
            let plain = matcher.match(a, b, searchRange: 1...bound)
            let m = masked.confidence >= plain.confidence ? masked : plain
            let overlap = Double(n - min(max(0, m.dy), n)) / Double(n)
            #expect(overlap > 0.35 && overlap < 0.65, "video overlap[\(i)] = \(overlap) outside sane band")
        }
    }

    @Test func batchStitcherRecoversMonotonicOrder() async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        let plan = try BatchStitcher().plan(r.keyframes.map { $0.image })
        // A single forward scroll: recovered order is the capture order. Segment breaks occur on
        // current code — an assembly-side BatchStitcher limitation deferred to a follow-up (see
        // docs/logs/2026-07-23-01-batch-stitcher-direction-on-image-heavy-content.md). NOT the
        // originally-planned edgeConfidence-threshold fix, which a measurement pass disproved. The
        // withKnownIssue block below tracks the intended end-state.
        #expect(plan.order == Array(0..<r.keyframes.count), "expected monotonic scroll order, got \(plan.order)")

        // A single continuous downward scroll re-stitches into ONE segment. This was
        // `withKnownIssue` across three fix cycles — breaks [2, 3], then [3] — and is now a hard
        // assertion. It is the last acceptance criterion of issue #2.
        //
        // Pair 2-3 was recovered in 2026-07-25-07: its real downward edge (dy=344) was losing the
        // direction tie-break to a spurious dy=1 reverse match that scored higher on *confidence*
        // while fitting far worse, so direction is now settled on fit.
        //
        // Pair 3-4 was blamed on the fixture. Keyframe 4 read as a trailing `finish()` commit that
        // barely overlapped its predecessor — edge confidence 0.047, fitting 0.953 as well as its
        // own reverse — and the recorded diagnosis was "needs the fixture re-trimmed, not another
        // threshold." Half right: it was not a threshold, but the fixture was not at fault either.
        // The masked overlap floor was rejecting large offsets outright (`docs/logs/2026-08-08-02`),
        // which both moved where the selector committed and left that pair unmeasurable. With it
        // corrected, this same clip banks 5 keyframes whose weakest seam scores 0.732, and the
        // supposedly unmatchable pair 3-4 measures dy=1268 px at **0.945**.
        #expect(plan.session.segmentBreaks.isEmpty,
                "real single scroll should re-stitch into one continuous segment, got breaks \(plan.session.segmentBreaks.map { $0.afterKeyframeIndex })")
        #expect(plan.session.seams.count == r.keyframes.count - 1,
                "expected \(r.keyframes.count - 1) seams for one segment, got \(plan.session.seams.count)")
    }

    /// Re-validation gate: at the production sampling cadence (30 fps by timestamp) the driver must
    /// still bank the same handful of keyframes with sane overlaps as full-rate decode. If this ever
    /// fails, the cadence is too coarse — raise targetFPS until it holds, then pin the new value here
    /// and in LibraryModel.importVideo.
    ///
    /// Cadence tuning history on this fixture: 12 fps left the trailing finish() pair at overlap
    /// 0.666 (just over the 0.65 band); 20 fps shifted the banked set enough to produce a
    /// near-duplicate pair (overlap 0.998). Coarse sampling gives the matcher fewer chances to
    /// measure scroll, so a single mis-scored intermediate frame shifts commit timing — the same
    /// image-heavy matcher limitation deferred in batchStitcherRecoversMonotonicOrder. 30 fps is the
    /// coarsest cadence that reproduces the full-rate 5-keyframe set with all pairs in band, still
    /// ~2.7x less profiling work than full rate.
    @Test func throttledCadenceKeepsKeyframesHealthy() async throws {
        var driver = ScrollCaptureDriver()
        let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver, targetFPS: 30)
        #expect(r.decodeFailures == 0)
        try #require(r.keyframes.count >= 4, "throttled decode should still bank several keyframes, got \(r.keyframes.count)")
        #expect(r.keyframes.count <= 6, "throttled decode should not over-bank, got \(r.keyframes.count)")

        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        let detector = ChromeStaticRowDetector()
        let profiles = r.keyframes.map { profiler.profile($0.image) }
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let n = min(a.rowCount, b.rowCount)
            let bound = max(1, n - matcher.minimumOverlap)
            let mask = detector.staticMask(a, b)
            let masked = matcher.match(a, b, searchRange: 1...bound, rowMasks: RowMaskPair(shared: mask))
            let plain = matcher.match(a, b, searchRange: 1...bound)
            let m = masked.confidence >= plain.confidence ? masked : plain
            let overlap = Double(n - min(max(0, m.dy), n)) / Double(n)
            #expect(overlap > 0.35 && overlap < 0.65, "throttled overlap[\(i)] = \(overlap) outside sane band")
        }
    }
}
