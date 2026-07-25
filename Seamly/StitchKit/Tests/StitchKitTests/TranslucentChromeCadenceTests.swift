import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Issue #11: `ContentBandDetector.staticMask` uses the summary-statistics test only, so on iOS 26
/// — where system bars are translucent by default — a bar's rows read as moved content and feed the
/// live scroll measurement. That measurement decides when `KeyframeSelector` banks a keyframe, so
/// the predicted symptom was commit-timing drift and keyframes not holding the intended ~50%
/// overlap.
///
/// These pin the two things the issue asks to be measured, so the trade-off can't quietly rot.
@Suite struct TranslucentChromeCadenceTests {

    private func fixtureImages() throws -> [CGImage] {
        try (0...5).map { i in
            let name = String(format: "youtube-%02d", i)
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "RealDevice"),
                                   "missing fixture RealDevice/\(name).png")
            return try KeyframeIO.read(from: url)
        }
    }

    /// The predicted drift does not materialise. `youtube-*` are the keyframes the live selector
    /// actually banked on a translucent-tab-bar capture, so the offsets between them *are* the
    /// achieved commit cadence — and every one lands within ~3% of `commitFraction`.
    ///
    /// Measured: overlaps 0.481 / 0.500 / 0.494 / 0.473 / 0.497 against an intended 0.50, with dy
    /// 0–17 rows past the 320-row threshold, which is just the quantisation of "commit on the
    /// first frame that crosses the line". Translucent bar rows do reach the matcher, and on this
    /// capture they cost the cadence nothing measurable.
    @Test func commitCadenceHoldsOnATranslucentChromeCapture() throws {
        let stitcher = BatchStitcher()
        let profiles = try fixtureImages().map { stitcher.profiler.profile($0) }
        let n = profiles[0].rowCount
        let selector = KeyframeSelector()

        for i in 0..<(profiles.count - 1) {
            let bound = min(profiles[i].rowCount, profiles[i + 1].rowCount) - stitcher.matcher.minimumOverlap
            let m = stitcher.matcher.match(profiles[i], profiles[i + 1], searchRange: 1...bound,
                                           rowMask: ContentBandDetector().staticMask(profiles[i], profiles[i + 1]))
            let overlap = Double(n - m.dy) / Double(n)
            #expect(abs(overlap - selector.commitFraction) <= 0.05,
                    "kf\(i)->\(i + 1) overlap \(overlap) drifted from commitFraction \(selector.commitFraction)")
        }
    }

    /// The masked/unmasked choice in `BatchStitcher.downwardMatch` never changes the recovered
    /// offset on this capture — it only changes the confidence reported for it. Pinned because the
    /// long-standing rationale for that choice claimed the opposite ("flips the sign on others"),
    /// and a future reader should be able to see which is true without re-deriving it.
    @Test func maskChangesConfidenceNotTheRecoveredOffset() throws {
        let stitcher = BatchStitcher()
        let profiles = try fixtureImages().map { stitcher.profiler.profile($0) }
        let detector = ContentBandDetector(meanTolerance: stitcher.chromeTolerance,
                                           varianceTolerance: stitcher.chromeTolerance)

        var sawConfidenceGain = false
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let bound = min(a.rowCount, b.rowCount) - stitcher.matcher.minimumOverlap
            let masked = stitcher.matcher.match(a, b, searchRange: 1...bound, rowMask: detector.staticMask(a, b))
            let plain = stitcher.matcher.match(a, b, searchRange: 1...bound)
            #expect(masked.dy == plain.dy,
                    "pair \(i)-\(i + 1): mask changed the offset (\(masked.dy) vs \(plain.dy)), not just its score")
            if masked.confidence > plain.confidence + 0.1 { sawConfidenceGain = true }
        }
        #expect(sawConfidenceGain, "masking should measurably sharpen at least one pair, else it earns nothing")
    }
}
