import Testing
import Foundation
import StitchKit
@testable import Seamly

/// Which join the user is taken to, and which they are never offered. Pure, so every case is
/// cheap to pin — and the empty case matters most: offering repair on a capture with nothing to
/// drag would open a screen that cannot do anything.
struct RepairableJoinsTests {

    private func session(seams: [Seam], breaks: [SegmentBreak] = [], keyframes: Int) -> StitchSession {
        StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: (0..<keyframes).map {
                Keyframe(filename: "kf-\($0)", pixelWidth: 100, pixelHeight: 300, index: $0)
            },
            seams: seams,
            segmentBreaks: breaks
        )
    }

    @Test func everyConsecutivePairIsWalkableWhenThereAreNoBreaks() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.8),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.walkable(in: s) == [0, 1])
    }

    /// Nothing overlaps across a break, so there is nothing to line up — and `Compositor.plan`
    /// ignores such a seam anyway, so dragging it would change nothing on screen.
    @Test func aJoinAcrossASegmentBreakIsExcluded() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.8),
            ],
            breaks: [SegmentBreak(afterKeyframeIndex: 0, reason: .lostLock)],
            keyframes: 3
        )
        #expect(RepairableJoins.walkable(in: s) == [1])
    }

    @Test func aCaptureWhoseOnlyJoinIsABreakOffersNothing() {
        let s = session(
            seams: [Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8)],
            breaks: [SegmentBreak(afterKeyframeIndex: 0, reason: .lostLock)],
            keyframes: 2
        )
        #expect(RepairableJoins.walkable(in: s).isEmpty)
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == nil)
    }

    @Test func opensOnTheLeastConfidentJoin() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.9),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.4),
                Seam(fromIndex: 2, provisionalDy: 100, confidence: 0.7),
            ],
            keyframes: 4
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == 1)
    }

    @Test func tiesBreakOnPositionSoTheChoiceIsDeterministic() {
        let s = session(
            seams: [
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.5),
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.5),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == 0)
    }

    /// The loud entry came from a flagged join, so it must land on one — even when an unflagged
    /// join happens to score lower.
    @Test func theLoudEntryPrefersAFlaggedJoinOverALowerScoringUnflaggedOne() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.1, isLowConfidence: false),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.6, isLowConfidence: true),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: true) == 1)
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == 0)
    }

    /// Reachable, not theoretical: "some bars may repeat" is counted from chrome records, not seam
    /// confidence, so a capture can offer repair loudly with every seam unflagged.
    @Test func theLoudEntryFallsBackToAllJoinsWhenNothingIsFlagged() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.9),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.3),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: true) == 1)
    }

    /// A seam pointing at a keyframe that is not there is a malformed manifest, not a join.
    @Test func aSeamWithNoSecondKeyframeIsNotAJoin() {
        // First case: fromIndex itself is missing
        let s1 = session(
            seams: [Seam(fromIndex: 5, provisionalDy: 100, confidence: 0.8)],
            keyframes: 2
        )
        #expect(RepairableJoins.walkable(in: s1).isEmpty)

        // Second case: fromIndex is valid but the next keyframe (fromIndex + 1) is missing
        let s2 = session(
            seams: [Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.8)],
            keyframes: 2
        )
        #expect(RepairableJoins.walkable(in: s2).isEmpty)
    }
}
