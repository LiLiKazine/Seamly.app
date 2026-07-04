import Foundation

/// Whether a processed frame should be saved as a keyframe.
public enum FrameAction: Equatable, Sendable {
    /// Do nothing — a duplicate/back-scroll frame, or not yet due for a keyframe.
    case ignore
    /// Save this frame's full-resolution pixels as a keyframe checkpoint.
    case commitKeyframe
}

/// Decides which of the densely-delivered frames become saved keyframes.
///
/// Keyframes are checkpoints derived from the running cumulative offset: one is committed
/// each time the captured union advances ~65% of the scroll-band height, which guarantees
/// at least ~30% overlap between consecutive saved keyframes — enough for the app's
/// pixel-exact seam refinement. This is also where low-quality frames are skipped: a frame
/// due for commit but with poor match confidence is deferred until a clean one arrives, so
/// blurry fast-scroll frames aren't checkpointed.
public struct FrameSelector: Sendable {
    /// Fraction of the band height the union must advance before a new keyframe is due.
    public let overlapCommitFraction: Double
    /// Match confidence below which a frame is considered low quality and not committed.
    public let minKeyframeConfidence: Double

    private var currentSegment = -1
    private var lastCommittedMaxY = 0
    /// Highest maxY seen, so `finish()` can detect an uncommitted tail.
    private var highWaterMaxY = 0

    public init(overlapCommitFraction: Double = 0.65, minKeyframeConfidence: Double = 0.4) {
        self.overlapCommitFraction = overlapCommitFraction
        self.minKeyframeConfidence = minKeyframeConfidence
    }

    public mutating func evaluate(_ result: TrackingResult, bandHeight: Int) -> FrameAction {
        highWaterMaxY = max(highWaterMaxY, result.maxY)

        // A new segment (including the very first frame and any post-break frame) always
        // seeds a keyframe.
        if result.segmentIndex != currentSegment {
            currentSegment = result.segmentIndex
            lastCommittedMaxY = result.maxY
            // maxY resets per segment; keep the tail high-water mark per segment too, or
            // finish() would compare across segments and over-commit a duplicate final frame.
            highWaterMaxY = result.maxY
            return .commitKeyframe
        }

        // Only frames that revealed new content are keyframe candidates.
        switch result.decision {
        case .skipped, .segmentBreak:
            return .ignore
        case .appended, .relocalized:
            break
        }

        let advanced = result.maxY - lastCommittedMaxY
        let threshold = Int((overlapCommitFraction * Double(bandHeight)).rounded())
        guard advanced >= threshold else { return .ignore }
        // Due for a keyframe, but defer if this frame is low quality.
        guard result.confidence >= minKeyframeConfidence else { return .ignore }

        lastCommittedMaxY = result.maxY
        return .commitKeyframe
    }

    /// Commit the trailing frame at broadcast end if the tail past the last keyframe is
    /// still uncommitted, so the final content (and bottom chrome) is captured.
    public mutating func finish() -> FrameAction {
        guard highWaterMaxY > lastCommittedMaxY else { return .ignore }
        lastCommittedMaxY = highWaterMaxY
        return .commitKeyframe
    }
}
