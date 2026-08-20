import CoreGraphics
import Foundation
import StitchKit

/// The geometry of one join, and what a finger does to it.
///
/// This mirrors the placement rule in `Compositor.plan` — deliberately, and at a real cost. `plan`
/// is private and its layout type is internal, so the app cannot ask `StitchKit` where a join sits;
/// the only alternative to re-deriving it here is changing the pipeline. Duplicated layout maths
/// that drifts is how a preview starts promising something the exported image will not honour, so
/// `JoinAlignmentTests` asserts this against a real composite instead of trusting it.
///
/// Holds no images: this supplies the numbers, `RepairQueueView` supplies the pixels.
///
/// `nonisolated` because this target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), and drag arithmetic has no business being pinned
/// to an actor.
nonisolated struct JoinAlignment: Equatable {
    /// One past the upper frame's last content row — where the strip stops using it.
    let upperContentBottom: Int
    /// The lower frame's first content row.
    let lowerContentTop: Int
    /// One past the lower frame's last content row.
    let lowerContentBottom: Int
    /// The lower frame's full height, including any bottom chrome.
    ///
    /// Whether the strip *keeps* that chrome depends on where the join sits, and this is a
    /// duplicate of `Compositor.plan`'s rule, so the distinction matters: `plan` appends the bottom
    /// chrome of a segment's **last** frame only (`Compositor.swift:275`), while its per-pair `add`
    /// stops every other frame at `currentContentBottom`. So for the final join in a segment this
    /// height is the finished image's own bottom edge; for an interior join the strip continues
    /// into the next frame instead and these rows are never drawn.
    let lowerPixelHeight: Int
    /// The offset being edited, in source pixels: the join's `Seam.provisionalDy`.
    private(set) var dy: Int

    /// Fails when the manifest does not actually describe this join — a missing keyframe either
    /// side, or no seam for the pair. Better than inventing a placement for a malformed manifest.
    init?(session: StitchSession, joinIndex: Int) {
        guard let upper = session.keyframes.first(where: { $0.index == joinIndex }),
              let lower = session.keyframes.first(where: { $0.index == joinIndex + 1 }),
              let seam = session.seams.first(where: { $0.fromIndex == joinIndex })
        else { return nil }

        let upperChrome = Self.effectiveInsets(session.resolvedChrome(for: upper), height: upper.pixelHeight)
        let lowerChrome = Self.effectiveInsets(session.resolvedChrome(for: lower), height: lower.pixelHeight)

        upperContentBottom = upper.pixelHeight - upperChrome.bottom
        lowerContentTop = lowerChrome.top
        lowerContentBottom = lower.pixelHeight - lowerChrome.bottom
        lowerPixelHeight = lower.pixelHeight
        dy = seam.provisionalDy
    }

    /// `Compositor` falls back to a zero crop when resolved insets are not plausible for the frame
    /// height, so this must too — otherwise the preview would crop rows the export keeps.
    private static func effectiveInsets(_ chrome: ResolvedChrome, height: Int) -> ChromeInsets {
        chrome.insets.isPlausible(forPixelHeight: height) ? chrome.insets : .zero
    }

    /// The lower frame's first drawn row — `Compositor.plan`'s `sourceStart`, clamp included.
    var lowerSourceStart: Int {
        min(max(upperContentBottom - dy, lowerContentTop), lowerContentBottom)
    }

    /// The offsets worth allowing: exactly the span over which `lowerSourceStart` still moves.
    /// Past either edge the compositor's own clamp pins the picture while the finger keeps going,
    /// which reads as a broken control, so the drag stops at the edge instead. No rubber-banding —
    /// a bounce would imply there is something past it.
    var dyRange: ClosedRange<Int> {
        // 1, not 0: a non-advancing join stacks two frames on the same rows, which is not a
        // placement any drag should be able to ask for.
        let lowest = max(1, upperContentBottom - lowerContentBottom)
        let highest = max(lowest, upperContentBottom - lowerContentTop)
        return lowest...highest
    }

    /// The offset for a drag of `translation` points that began with the join at `start`.
    ///
    /// `translation` is SwiftUI's cumulative gesture translation, positive downward, so this is
    /// computed fresh from the gesture's origin on every update rather than accumulated — there is
    /// no running total to drift, and a slow drag cannot judder.
    ///
    /// `sourcePixelsPerPoint` is the 1× ratio of source pixels to points across the frame's width;
    /// dividing by `zoom` is what makes magnification the precision mechanism.
    ///
    /// Dragging **down** raises `dy`, which starts repeating rows the upper frame already showed;
    /// dragging **up** lowers it and starts dropping rows. Lined up is where neither happens.
    func dy(draggedBy translation: CGFloat, from start: Int, sourcePixelsPerPoint: CGFloat, zoom: CGFloat) -> Int {
        let pixels = Double(translation) * Double(sourcePixelsPerPoint) / Double(max(zoom, 0.001))
        return Self.clamp(start + Int(pixels.rounded()), to: dyRange)
    }

    mutating func setDy(_ value: Int) {
        dy = Self.clamp(value, to: dyRange)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
