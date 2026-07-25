import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import StitchKit

/// Order recovery on real device keyframes: `BatchStitcher.layout` must join every frame that
/// genuinely overlaps into one segment, and must still refuse to join frames that don't.
///
/// The guard these pin is the component-merge step. `layout` anchors edges in descending
/// confidence order and reads off a position per frame; when an edge arrives whose endpoints are
/// *both* already positioned, the two components must be slid into a common frame of reference
/// and merged. Dropping such an edge splits a continuous scroll at a point determined purely by
/// the order confidences happened to sort in — which is what used to happen.
@Suite struct OrderRecoveryTests {

    private func load(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "RealDevice"),
                               "missing fixture \(name)")
        return try KeyframeIO.read(from: url)
    }

    private func frames(_ prefix: String, _ range: ClosedRange<Int>) throws -> [CGImage] {
        try range.map { try load(String(format: "\(prefix)-%02d", $0)) }
    }

    /// The regression. Every adjacent `youtube-*` pair produces a strong accepted edge
    /// (confidence 0.762 … 0.942), so recovered order must be one unbroken segment.
    ///
    /// It previously broke after slot 1, and not because any edge was rejected: edges anchor in
    /// descending confidence, so 2-3 (0.942) and 0-1 (0.932) each seeded their own component,
    /// and 1-2 (0.922) — the edge that joins them — then found both endpoints already placed and
    /// was discarded. The break location was an artifact of confidence ordering, nothing to do
    /// with the capture.
    @Test func continuousScrollRecoversAsOneSegment() throws {
        let plan = try BatchStitcher().plan(try frames("youtube", 0...5))
        #expect(plan.order == [0, 1, 2, 3, 4, 5])
        #expect(plan.session.segmentBreaks.isEmpty,
                "continuous scroll split at \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")
        #expect(plan.session.seams.count == 5)
        #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 }, "every seam must scroll downward")
    }

    /// Recovering order must agree with trusting it. Same frames, same result — if these diverge,
    /// one of the two paths is wrong and the manifest depends on which import route was used.
    @Test func recoveredOrderMatchesAssumedOrderOnAContinuousScroll() throws {
        let images = try frames("youtube", 0...5)
        let recovered = try BatchStitcher().plan(images)
        let assumed = try BatchStitcher().plan(images, assumingOrder: Array(0..<images.count))
        #expect(recovered.order == assumed.order)
        #expect(recovered.session.segmentBreaks.map(\.afterKeyframeIndex)
                == assumed.session.segmentBreaks.map(\.afterKeyframeIndex))
    }

    /// The other half of the contract, and the risk the merge fix carries: frames that genuinely
    /// do not overlap must still break apart. `wechat-00` is the iOS home screen and `wechat-01`
    /// an app-launch animation — neither overlaps the chat list, ground truth −767 and −679.
    /// Over-merging these would stack unrelated screens into one image.
    @Test func wechatNonOverlapStillBreaks() throws {
        let plan = try BatchStitcher().plan(try frames("wechat", 0...4))
        let breaks = Set(plan.session.segmentBreaks.map(\.afterKeyframeIndex))
        #expect(breaks.contains(0), "home screen must not merge into the launch animation")
        #expect(breaks.contains(1), "launch animation must not merge into the chat list")
    }

    /// Baidu is a clean downward scroll that does **not** yet recover as one segment — pairs 0-1
    /// and 3-4 lose the direction tie-break to a spurious low-`dy` reverse match, and 4-5 is a
    /// genuine forward-match failure (see issue #2, still open). What must hold regardless is
    /// that nothing is reordered: a wrong order is far worse than a break, because a break is
    /// visible and honest while a scrambled order silently produces a wrong image.
    @Test func baiduDownwardScrollStaysSane() throws {
        let plan = try BatchStitcher().plan(try frames("baidu", 0...6))
        #expect(plan.order == [0, 1, 2, 3, 4, 5, 6], "keyframes reordered: \(plan.order)")
        #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 },
                "a recovered seam pointed backwards: \(plan.session.seams.map(\.provisionalDy))")
    }
}
