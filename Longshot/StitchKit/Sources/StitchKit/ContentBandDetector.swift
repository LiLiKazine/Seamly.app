import Foundation

/// Locks the scrolling content band of a segment by **multi-frame consensus**, and supplies
/// an **adaptive per-pair mask** for bootstrap matching before the lock.
///
/// Chrome (status/nav/tab bars, home indicator) sits at the *same screen row* across frames,
/// so at a given index its mean and variance barely change while content rows differ once the
/// view scrolls. A single pair is unreliable (a paused frame, a clock tick, a momentarily
/// still content row), so this detector accumulates a per-row "static across moving frames"
/// vote and locks a band only once a stable consensus emerges — the fix for `ChromeDetector`'s
/// single-pair inaccuracy (76 vs 24 px; 23→73).
///
/// All row indices are **profile rows**; the caller converts to source pixels via `rowScale`.
/// Used serially by `PositionTracker`, one detector per segment (a value type, mutated in
/// place — no shared state, no actor needed).
public struct ContentBandDetector: Sendable {
    /// Max mean difference for a row to still count as static (0...1 luminance).
    public let meanTolerance: Float
    /// Max variance difference for a row to still count as static.
    public let varianceTolerance: Float
    /// Minimum |dy| (rows) that counts as real scroll; pairs below this don't vote.
    public let motionThreshold: Int
    /// Moving pairs required before a band may lock.
    public let minMovingFrames: Int
    /// Fraction of moving pairs a row must be static in to count as chrome.
    public let staticFraction: Float
    /// Band-size change (rows) versus the locked band that counts as a sharp change.
    public let jumpThreshold: Int
    /// Fewest content (moved) rows a bootstrap mask must keep, else it returns `nil` so the
    /// caller matches unmasked (pre-scroll / all-static frames).
    public let minContentRows: Int

    public init(
        meanTolerance: Float = 0.02,
        varianceTolerance: Float = 0.02,
        motionThreshold: Int = 2,
        minMovingFrames: Int = 3,
        staticFraction: Float = 0.7,
        jumpThreshold: Int = 3,
        minContentRows: Int = 8
    ) {
        self.meanTolerance = meanTolerance
        self.varianceTolerance = varianceTolerance
        self.motionThreshold = motionThreshold
        self.minMovingFrames = minMovingFrames
        self.staticFraction = staticFraction
        self.jumpThreshold = jumpThreshold
        self.minContentRows = minContentRows
    }

    // Consensus state.
    private var staticVotes: [Int] = []
    private var movingPairs = 0
    private var lastCandidate: (top: Int, bottom: Int)?
    private var locked: (top: Int, bottom: Int)?

    /// The locked content band (profile rows), or `nil` until consensus is confident.
    public var lockedBand: (top: Int, bottom: Int)? { locked }

    // MARK: - Bootstrap

    /// Per-pair content mask for bootstrap matching: `true` where the row moved (content),
    /// `false` where it held still (chrome). `nil` when too few rows moved — the frames are
    /// pre-scroll / still, so the caller should match unmasked (an unmasked still-frame match
    /// correctly yields `dy = 0`).
    public func staticMask(_ a: FrameProfile, _ b: FrameProfile) -> [Bool]? {
        let n = min(a.rowCount, b.rowCount)
        guard n > 0 else { return nil }
        var mask = [Bool](repeating: false, count: n)
        var moved = 0
        for i in 0..<n where !isStatic(a, b, row: i) {
            mask[i] = true
            moved += 1
        }
        return moved >= minContentRows ? mask : nil
    }

    // MARK: - Consensus

    /// Fold one consecutive pair into the consensus. Only pairs with clear motion vote, so a
    /// paused frame can't stuff the ballot. Locks once `minMovingFrames` moving pairs agree on
    /// a stable band.
    public mutating func observe(_ a: FrameProfile, _ b: FrameProfile, dy: Int) {
        guard abs(dy) >= motionThreshold else { return }
        let n = min(a.rowCount, b.rowCount)
        guard n > 0 else { return }
        if staticVotes.count != n { staticVotes = [Int](repeating: 0, count: n) }

        for i in 0..<n where isStatic(a, b, row: i) { staticVotes[i] += 1 }
        movingPairs += 1

        let candidate = consensusBand(rowCount: n)
        defer { lastCandidate = candidate }
        guard locked == nil, movingPairs >= minMovingFrames else { return }
        // Require the candidate to repeat (two consecutive equal reads) so a band still
        // settling doesn't lock a transient value.
        if let last = lastCandidate, last == candidate {
            locked = candidate
        }
    }

    /// Chrome from the accumulated votes: rows static in at least `staticFraction` of the
    /// moving pairs, counted contiguously inward from each edge.
    private func consensusBand(rowCount n: Int) -> (top: Int, bottom: Int) {
        guard movingPairs > 0 else { return (0, 0) }
        let need = staticFraction * Float(movingPairs)
        var top = 0
        while top < n, Float(staticVotes[top]) >= need { top += 1 }
        var bottom = 0
        while bottom < n - top, Float(staticVotes[n - 1 - bottom]) >= need { bottom += 1 }
        return (top, bottom)
    }

    // MARK: - Sharp change

    /// After lock, whether this pair's static edges differ sharply from the locked band (a
    /// collapsing header, a keyboard). Only judged when the pair shows motion — a paused pair
    /// (everything static) is not a band change.
    public func bandChangedSharply(_ a: FrameProfile, _ b: FrameProfile) -> Bool {
        guard let locked, staticMask(a, b) != nil else { return false }
        let n = min(a.rowCount, b.rowCount)
        var top = 0
        while top < n, isStatic(a, b, row: top) { top += 1 }
        var bottom = 0
        while bottom < n - top, isStatic(a, b, row: n - 1 - bottom) { bottom += 1 }
        return abs(top - locked.top) > jumpThreshold || abs(bottom - locked.bottom) > jumpThreshold
    }

    // MARK: - Helpers

    private func isStatic(_ a: FrameProfile, _ b: FrameProfile, row: Int) -> Bool {
        abs(a.means[row] - b.means[row]) <= meanTolerance
            && abs(a.variances[row] - b.variances[row]) <= varianceTolerance
    }
}
