import Foundation

/// Decides, for one pair of frames, which rows held still — the chrome test.
///
/// Chrome (status/nav/tab bars, home indicator) sits at the *same screen row* across frames, so at
/// a given index it barely changes while content rows differ once the view scrolls. Two consumers,
/// both per-pair:
///
/// - `KeyframeSelector` calls `staticMask` during live capture, so fixed bars can't pin the
///   measured scroll to zero.
/// - `BatchStitcher.chromeBand` calls `isStatic` to measure the band that gets cropped from the
///   finished stitch.
///
/// "Still" is not simply "same brightness": a translucent bar's pixels track whatever scrolls
/// behind it. See `isStatic` and `structureTolerance` / `translucencyMeanCeiling`.
///
/// All row indices are **profile rows**; the caller converts to source pixels via `rowScale`.
///
/// This type used to also accumulate a multi-frame *consensus* band (`observe` / `lockedBand` /
/// `bandChangedSharply`) for `PositionTracker`'s incremental tracking. Both were removed in
/// 2026-07-25-01: capture had moved to `ScrollCaptureDriver`/`KeyframeSelector`, which bank
/// keyframes and leave every geometry decision to `BatchStitcher` at import, so nothing outside
/// tests had constructed a tracker for some time.
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
    /// Largest mean shift (0...1 luminance) still attributable to translucency. A blur material
    /// tints *toward* whatever passes behind it but stays recognizably itself, so its brightness
    /// moves modestly; content can change arbitrarily.
    ///
    /// This ceiling is what keeps the shape test honest, because "shape preserved" alone is not
    /// sufficient: content whose horizontal pattern is row-independent (a vertical stripe, a flat
    /// fill, sparse text at fixed columns) has a centered difference of *exactly* 0 while its
    /// brightness swings wildly. Measured — the real translucent bar in `youtube-*` shifts by
    /// ≤ 0.051, while `ChromeStitchReproTests`' low-horizontal-variance document shifts by
    /// 0.486–0.773 at a centered difference of 0.0000. The default sits between, ~4x above the bar
    /// and ~2.4x below that content.
    public let translucencyMeanCeiling: Float
    /// Fewest content (moved) rows a bootstrap mask must keep, else it returns `nil` so the
    /// caller matches unmasked (pre-scroll / all-static frames).
    public let minContentRows: Int

    public init(
        meanTolerance: Float = 0.02,
        varianceTolerance: Float = 0.02,
        structureTolerance: Float = 0.15,
        translucencyMeanCeiling: Float = 0.20,
        minContentRows: Int = 8
    ) {
        self.meanTolerance = meanTolerance
        self.varianceTolerance = varianceTolerance
        self.structureTolerance = structureTolerance
        self.translucencyMeanCeiling = translucencyMeanCeiling
        self.minContentRows = minContentRows
    }

    // MARK: - Bootstrap

    /// Per-pair content mask for matching: `true` where the row moved (content), `false` where it
    /// held still (chrome). `nil` when too few rows moved — the frames are pre-scroll / still, so
    /// the caller should match unmasked (an unmasked still-frame match correctly yields `dy = 0`).
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

    // MARK: - Helpers

    /// Whether row `row` held still between the two frames.
    ///
    /// `allowingTranslucency` additionally accepts a row whose *shape* is unchanged but whose
    /// brightness shifted — a translucent bar with content moving behind it.
    ///
    /// Acceptance needs **both** halves of the translucency signature, not either alone: a bounded
    /// brightness shift (`translucencyMeanCeiling`) *and* preserved horizontal shape
    /// (`structureTolerance`). Shape alone is not enough — content whose horizontal pattern repeats
    /// identically row to row scores a centered difference of exactly 0 while its brightness swings
    /// by 0.5+, so it would be cropped as chrome.
    ///
    /// **Only `BatchStitcher.chromeBand` passes `true`.** `staticMask` deliberately does not,
    /// because it feeds `OffsetMatcher` rather than the crop: masking a translucent bar out of the
    /// match removes signal rather than cleaning it.
    ///
    /// Re-measured 2026-07-25 (issue #11), and the cost is far higher than previously recorded.
    /// The old note here said enabling it "cost pair 3-4 its overlap edge and split the capture
    /// into two segments". Driving the real `scroll-recording.mp4` through the live selector at
    /// the production 30 fps cadence with `allowingTranslucency: true` in `staticMask` instead
    /// banks **1 keyframe instead of 5** — the capture collapses outright. Enough rows read as
    /// static that the mask starves the match, measured `dy` never reaches `commitFraction`, and
    /// nothing after the first frame commits. This is not a tuning knob; leave it `false` here.
    ///
    /// What the mask *does* buy the matcher, measured across all real fixtures: nothing in the
    /// recovered offset, and a lot in confidence. Masked and unmasked agree on `dy` for every
    /// adjacent pair on `youtube-*`, `baidu-*` and `wechat-*` bar one (baidu 4-5, where both are
    /// wrong). Where they differ is fit — `youtube` 3-4 scores 0.824 masked against 0.340
    /// unmasked. See `BatchStitcher.downwardMatch`.
    func isStatic(_ a: FrameProfile, _ b: FrameProfile, row: Int, allowingTranslucency: Bool = false) -> Bool {
        guard abs(a.variances[row] - b.variances[row]) <= varianceTolerance else { return false }
        if abs(a.means[row] - b.means[row]) <= meanTolerance { return true }
        // Translucency needs BOTH: a bounded brightness shift, and shape preserved under it.
        guard allowingTranslucency,
              abs(a.means[row] - b.means[row]) <= translucencyMeanCeiling else { return false }
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
