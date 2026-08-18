import Foundation
import StitchKit

/// Which joins a user can be shown, and which one to open on.
///
/// A "join" is the boundary between keyframe `index` and `index + 1` — the same pair a `Seam`
/// describes. This lives outside the view so the decision is pure and testable: the difference
/// between taking someone to the problem and opening a screen with nothing to drag.
///
/// `nonisolated` because this target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
nonisolated enum RepairableJoins {

    /// Joins the user can actually line up, top to bottom.
    ///
    /// A join across a segment break is excluded: nothing overlaps across a break, so there is
    /// nothing to line up, and `Compositor.plan` ignores that seam when laying out the strip — so
    /// dragging it would move nothing.
    static func walkable(in session: StitchSession) -> [Int] {
        let indices = Set(session.keyframes.map(\.index))
        return session.seams
            .filter { seam in
                indices.contains(seam.fromIndex)
                    && indices.contains(seam.fromIndex + 1)
                    && !session.hasSegmentBreak(after: seam.fromIndex)
            }
            .map(\.fromIndex)
            .sorted()
    }

    /// The join to open on: the least confident, since that is the likeliest reason the user came.
    /// Ties break on position so the choice is deterministic rather than dependent on storage order.
    ///
    /// `flaggedOnly` narrows the ranking to seams the pipeline flagged — the loud entry, which
    /// arrived from a specific complaint. It falls back to the full set when nothing is flagged,
    /// which is reachable rather than theoretical: "some bars may repeat" is counted from chrome
    /// records, not seam confidence, so a capture can offer repair with every seam unflagged.
    static func opening(in session: StitchSession, flaggedOnly: Bool) -> Int? {
        let walkableIndices = Set(walkable(in: session))
        guard !walkableIndices.isEmpty else { return nil }
        let candidates = session.seams.filter { walkableIndices.contains($0.fromIndex) }
        let flagged = candidates.filter(\.isLowConfidence)
        let ranked = (flaggedOnly && !flagged.isEmpty) ? flagged : candidates
        return ranked.min { a, b in
            a.confidence == b.confidence ? a.fromIndex < b.fromIndex : a.confidence < b.confidence
        }?.fromIndex
    }
}
