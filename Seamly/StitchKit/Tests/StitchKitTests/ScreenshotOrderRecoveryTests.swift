import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Order recovery on real **Photos-app screenshots** — the "From Photos" import shape, as opposed
/// to the ReplayKit keyframes in `RealDevice`. Six consecutive full-resolution captures
/// (1320×2868) of a Google Discover feed: `IMG_1757`…`IMG_1762`, ascending filename order *is*
/// scroll order top→bottom (verified by rendering the stitch — it reads as one continuous page).
///
/// These pin the two facts that together made an app-level bug diagnosable, because each one
/// alone is unremarkable:
///
/// 1. Recovery on this set is exact and **permutation-invariant** — feed the six in any order and
///    `plan` returns the same scroll order and the same five seams.
/// 2. Its weakest seam historically scored **0.368**, under the shipping 0.4 flag threshold,
///    while the chain itself was complete. It now scores about 0.726 after the masked-overlap-floor
///    fix, so the regression test injects a 0.8 threshold to keep that policy condition alive.
///
/// `StitchAssembler.resolveGeometry` used to read that flag as "the recovered order can't be
/// trusted" and fall back to the user's pick order, so on this set a *correct* recovered order was
/// thrown away every time — invisible when the photos happened to be picked in order, and a
/// scrambled stitch when they weren't. A low seam confidence says the seam's *offset* is fuzzy; it
/// says nothing about whether the ordering is right. Fallback is now triggered only by a segment
/// break, where recovery has not established one continuous ordering.
@Suite struct ScreenshotOrderRecoveryTests {

    /// Scroll order, top→bottom.
    static let names = ["IMG_1757", "IMG_1758", "IMG_1759", "IMG_1760", "IMG_1761", "IMG_1762"]

    private func load(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "PNG", subdirectory: "Screenshots"),
                               "missing fixture \(name)")
        return try KeyframeIO.read(from: url)
    }

    private func framesInScrollOrder() throws -> [CGImage] { try Self.names.map { try load($0) } }

    // MARK: - Permutation invariance

    /// The reported bug's ground truth: recovery does not depend on the order the screenshots
    /// arrive in. `permutation[k]` is the true scroll slot of input `k`, so mapping the recovered
    /// input indices back through it must yield 0…5.
    ///
    /// Both permutations are checked because a single one can pass by luck: `layout` breaks
    /// position ties and orders components by *lowest input index*, so an ordering bug can hide
    /// behind an input arrangement that happens to agree with those tie-breaks.
    @Test(arguments: [
        [2, 0, 5, 1, 4, 3],   // IMG_1759, 1757, 1762, 1758, 1761, 1760
        [5, 3, 1, 4, 0, 2],   // IMG_1762, 1760, 1758, 1761, 1757, 1759
    ])
    func recoversScrollOrderFromAnyPickOrder(_ permutation: [Int]) throws {
        let inScrollOrder = try framesInScrollOrder()
        let shuffled = permutation.map { inScrollOrder[$0] }

        let plan = try BatchStitcher().plan(shuffled)

        #expect(plan.order.map { permutation[$0] } == Array(0..<inScrollOrder.count),
                "recovered \(plan.order.map { Self.names[permutation[$0]] })")
        #expect(plan.session.segmentBreaks.isEmpty,
                "continuous scroll split at \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")
        #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 }, "every seam must scroll downward")
    }

    /// Recovering the order agrees with trusting it, so the two import routes cannot disagree
    /// about this set — the same contract `OrderRecoveryTests` holds for `youtube-*`.
    @Test func recoveredOrderMatchesAssumedOrder() throws {
        let images = try framesInScrollOrder()
        let recovered = try BatchStitcher().plan(images)
        let assumed = try BatchStitcher().plan(images, assumingOrder: Array(0..<images.count))
        #expect(recovered.order == assumed.order)
        #expect(recovered.session.seams.map(\.provisionalDy) == assumed.session.seams.map(\.provisionalDy))
        #expect(recovered.session.segmentBreaks.isEmpty && assumed.session.segmentBreaks.isEmpty)
    }

    // MARK: - The trap

    /// A complete chain can still carry a seam flagged `isLowConfidence`. This is the combination
    /// `StitchAssembler` mishandled, and it is pinned here so the app-level policy test in
    /// `PhotoPickOrderTests` keeps a real measurement behind it rather than a guess.
    ///
    /// The flag threshold is raised rather than left at its shipping 0.4, because this set no
    /// longer trips 0.4 on its own: its weakest seam was 0.368 until the masked overlap floor was
    /// corrected (`docs/logs/2026-08-08-02`), which left the same offsets — 1326 / 1636 / 1416 /
    /// 1533 / 1537 px, unchanged — measured against the full score curve instead of a truncated
    /// one, and re-scored that seam at 0.726.
    ///
    /// Waiting for a fixture to happen to score under 0.4 is what made this test and its app-side
    /// partner both go vacuous in the same commit. Raising the threshold reproduces the condition
    /// deliberately, from the same real pixels: the chain is complete *and* seams are flagged, so
    /// anything that conflates the two still has something to fail against.
    @Test func aCompleteChainStillCarriesALowConfidenceSeam() throws {
        let plan = try BatchStitcher(lowConfidenceSeam: 0.8).plan(try framesInScrollOrder())
        #expect(plan.session.segmentBreaks.isEmpty)
        let flagged = plan.session.seams.filter(\.isLowConfidence)
        #expect(!flagged.isEmpty,
                "no seam under the 0.8 flag; confidences \(plan.session.seams.map { ($0.fromIndex, $0.confidence) })")
    }

    /// …and at the shipping threshold this set is now entirely clean, which is worth pinning
    /// separately: it is the measurement the sentence above rests on, and a matcher regression
    /// that pushed a seam back under 0.4 would otherwise pass silently.
    @Test func atTheShippingThresholdEverySeamIsConfident() throws {
        let plan = try BatchStitcher().plan(try framesInScrollOrder())
        let flagged = plan.session.seams.filter(\.isLowConfidence)
        #expect(flagged.isEmpty,
                "expected every seam over 0.4; confidences \(plan.session.seams.map { ($0.fromIndex, $0.confidence) })")
    }
}
