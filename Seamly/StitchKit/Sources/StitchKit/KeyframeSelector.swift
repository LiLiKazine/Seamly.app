import Foundation

/// Decides, per live frame, whether to commit a keyframe — the extension's capture policy.
///
/// This is deliberately *dumb* compared to `PositionTracker`: it keeps only the last committed
/// frame's profile and commits whenever the view has scrolled at least `commitFraction` of a
/// frame since then. It does not track absolute position, relocalize, break segments, or build
/// seams or chrome measurements — the app re-derives all geometry from captured keyframes with
/// `BatchStitcher`. Moving that intelligence off the real-time, memory-constrained extension
/// path is what makes capture robust: the extension's one job is to bank overlapping keyframes.
///
/// Matching uses the adaptive static-chrome mask so fixed bars (status/nav) can't pin the
/// measured scroll to zero, and searches downward only (a capture scrolls one way), which avoids
/// the sign ambiguity that made the streaming tracker mis-read large gaps.
public struct KeyframeSelector: Sendable {

    public struct Result: Equatable, Sendable {
        /// Commit the current frame as a keyframe.
        public let commit: Bool
        /// Overlap with the last committed keyframe (`0...1`); drives the safety cue. `1` when
        /// there is no prior keyframe or no detected motion.
        public let overlapFraction: Double
    }

    private let matcher: OffsetMatcher
    private let detector: ChromeStaticRowDetector
    /// Fraction of a frame the view must scroll past the last keyframe before the next commit.
    /// The complement is the guaranteed overlap between consecutive keyframes.
    public let commitFraction: Double

    private var lastCommitted: FrameProfile?

    public init(
        matcher: OffsetMatcher = OffsetMatcher(),
        chromeDetector: ChromeStaticRowDetector = ChromeStaticRowDetector(),
        commitFraction: Double = 0.5
    ) {
        self.matcher = matcher
        self.detector = chromeDetector
        self.commitFraction = commitFraction
    }

    /// Fold in one frame profile and decide whether to commit it as a keyframe.
    public mutating func evaluate(_ profile: FrameProfile) -> Result {
        guard let last = lastCommitted else {
            lastCommitted = profile   // first frame is always the first keyframe (top of capture)
            return Result(commit: true, overlapFraction: 1)
        }
        let n = profile.rowCount
        guard n > 0 else { return Result(commit: false, overlapFraction: 1) }
        let bound = max(1, n - matcher.minimumOverlap)
        let mask = detector.staticMask(last, profile)
        let m = matcher.match(last, profile, searchRange: 0...bound, rowMasks: RowMaskPair(shared: mask))
        let dy = min(max(0, m.dy), n)
        let overlap = Double(n - dy) / Double(n)
        if dy >= Int(commitFraction * Double(n)) {
            lastCommitted = profile
            return Result(commit: true, overlapFraction: overlap)
        }
        return Result(commit: false, overlapFraction: overlap)
    }

    /// Whether there is uncommitted downward motion since the last keyframe — used at
    /// `broadcastFinished` to decide if the trailing frame should be committed so content
    /// scrolled past the last keyframe isn't dropped. `minMotion` rejects a near-duplicate tail.
    public func hasUncommittedMotion(_ profile: FrameProfile, minMotion: Double = 0.05) -> Bool {
        guard let last = lastCommitted else { return false }
        let n = profile.rowCount
        guard n > 0 else { return false }
        let bound = max(1, n - matcher.minimumOverlap)
        let m = matcher.match(last, profile, searchRange: 0...bound, rowMasks: RowMaskPair(shared: detector.staticMask(last, profile)))
        return Double(min(max(0, m.dy), n)) / Double(n) >= minMotion
    }

    /// Mark the current frame as committed (baseline reset) — call after `hasUncommittedMotion`
    /// triggers a trailing commit so state stays consistent.
    public mutating func markCommitted(_ profile: FrameProfile) { lastCommitted = profile }
}
