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
/// A value type, mutated in place — no shared state, no actor needed.
///
/// Two distinct halves, with different reach. The **per-pair** queries (`staticMask`, `isStatic`)
/// are what ships: `KeyframeSelector` uses `staticMask` during live capture, and
/// `BatchStitcher.chromeBand` uses `isStatic` to measure the band that ends up in the stitch. The
/// **consensus** half (`observe`, `lockedBand`, `bandChangedSharply`) is used serially by
/// `PositionTracker`, one detector per segment — and `PositionTracker` has no callers outside tests,
/// so nothing it produces reaches a finished capture. Keep that split in mind before tuning: a
/// change to `isStatic`'s defaults moves real output, a change to the consensus parameters moves
/// only tests.
public struct ContentBandDetector: Sendable {
    /// Max mean difference for a row to still count as static (0...1 luminance).
    public let meanTolerance: Float
    /// Max variance difference for a row to still count as static.
    public let varianceTolerance: Float
    /// Max change in a row's **mean-centered** horizontal signature for it to still count as
    /// static. Translucent chrome (a blur / "liquid glass" bar) keeps its own structure while the
    /// content behind it shifts its brightness, so `meanTolerance` alone rejects it as content;
    /// comparing shape with the brightness removed still recognizes it.
    ///
    /// Measured on the `youtube-*` fixture (a real translucent iOS 26 tab bar) at both full and
    /// half resolution: rows inside the bar top out at **0.057**, while the first genuine content
    /// row jumps to **0.449** — an ~8x gap, and the same numbers either way, since the signature is
    /// always 64 columns wide regardless of source size. The default sits in that gap with roughly
    /// 2.7x headroom above chrome and 3x below content. Values near 0.05 clip the top of the bar
    /// (its blur picks up more backdrop the closer it gets to the content edge).
    public let structureTolerance: Float
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
        structureTolerance: Float = 0.15,
        motionThreshold: Int = 2,
        minMovingFrames: Int = 3,
        staticFraction: Float = 0.7,
        jumpThreshold: Int = 3,
        minContentRows: Int = 8
    ) {
        self.meanTolerance = meanTolerance
        self.varianceTolerance = varianceTolerance
        self.structureTolerance = structureTolerance
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

    /// Whether row `row` held still between the two frames.
    ///
    /// `allowingTranslucency` additionally accepts a row whose *shape* is unchanged but whose
    /// brightness shifted — a translucent bar with content moving behind it.
    ///
    /// **Only `BatchStitcher.chromeBand` passes `true`.** The flag exists because that extra
    /// permissiveness is right for one caller and measurably wrong for the others:
    ///
    /// - `staticMask` feeds `OffsetMatcher`. Masking a translucent bar out of the match removes
    ///   signal: on the `youtube-*` fixture it cost pair 3-4 its overlap edge and split the capture
    ///   into two segments. `BatchStitcher.downwardMatch` already picks between the masked and
    ///   unmasked match on confidence alone ("the mask helps some real pairs and flips the sign on
    ///   others"), so retuning it needs its own measurement pass, not a ride-along.
    /// - The incremental consensus (`observe`, `bandChangedSharply`) counts *contiguously* inward and
    ///   locks only when two successive candidates agree. A vertical gradient scrolls as a
    ///   near-uniform brightness shift with its horizontal shape intact — indistinguishable from
    ///   translucency by this measure — so the band creeps into content by a different amount each
    ///   pair and never locks at all: enabling it there regressed `ChromeStitchReproTests` and
    ///   `stitchesRealScreenshotScroll` from a correct band to `0/0, isLowConfidence`.
    ///
    /// Note the second case is not a shipping gap. That consensus API is reachable only from
    /// `PositionTracker`, which nothing in the app or the broadcast extension constructs — the
    /// capture path is `SampleHandler` → `ScrollCaptureDriver` → `KeyframeSelector`, and
    /// `KeyframeSelector` uses this type *only* for `staticMask`. Live capture therefore never
    /// computes a content band at all; the band that reaches the finished stitch is always the one
    /// `BatchStitcher` derives at import (`StitchAssembler.resolveGeometry` overwrites
    /// `contentBands` for every source). So live capture's exposure to translucent chrome is the
    /// first bullet — bar rows counted as scroll signal, which can nudge commit timing — not a
    /// wrong band.
    func isStatic(_ a: FrameProfile, _ b: FrameProfile, row: Int, allowingTranslucency: Bool = false) -> Bool {
        guard abs(a.variances[row] - b.variances[row]) <= varianceTolerance else { return false }
        if abs(a.means[row] - b.means[row]) <= meanTolerance { return true }
        guard allowingTranslucency else { return false }
        return (centeredDifference(a, b, row: row) ?? .greatestFiniteMagnitude) <= structureTolerance
    }

    /// Mean-absolute difference of the two rows' **mean-centered** signatures — how much the row's
    /// horizontal *shape* changed, with any uniform brightness shift removed.
    ///
    /// `nil` when there is no horizontal structure to compare. A single-sample row (the mean-only
    /// `FrameProfile` initializer) centers to `[0]` in *both* frames, so its shape always matches
    /// and every row with a steady variance would read as chrome — inverting the mean-based
    /// contract the profile-level tests rely on. Such rows must stay on the mean test.
    private func centeredDifference(_ a: FrameProfile, _ b: FrameProfile, row: Int) -> Float? {
        let ra = a.rows[row], rb = b.rows[row]
        guard ra.count == rb.count, ra.count > 1 else { return nil }
        let ma = a.means[row], mb = b.means[row]
        var sum: Float = 0
        for c in 0..<ra.count { sum += abs((ra[c] - ma) - (rb[c] - mb)) }
        return sum / Float(ra.count)
    }
}
