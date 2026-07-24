import Foundation

/// A frame reduced to a compact vertical signal.
///
/// Produced by `VerticalProfile` from an aggressively downscaled, grayscale frame. For each
/// row it keeps a short **luminance signature** (the row's downscaled samples across its
/// width), plus that row's mean and horizontal variance. Matching runs on the signatures —
/// a 2-D mean-absolute-difference over the whole row vector — because a per-row *mean alone*
/// is near-degenerate on real content (feed rows of similar brightness make a downward scroll
/// score no better than its mirror, so the matcher picked the wrong offset and real captures
/// shattered). The full horizontal structure disambiguates it. Variance still weights rows so
/// near-uniform bands (solid backgrounds) contribute little, and drives chrome detection.
///
/// `rows[i]`, `means[i]`, `variances[i]` describe row `i`; `means[i]` is the mean of `rows[i]`.
public struct FrameProfile: Sendable, Equatable {
    /// Per-row luminance signature: `rows[i]` holds the row's downscaled samples (`0...1`),
    /// left-to-right. One or more columns; `OffsetMatcher` compares these vectors row-to-row.
    public let rows: [[Float]]
    /// Per-row mean luminance, in `0...1`. Mean of `rows[i]`. One element per sampled row.
    public let means: [Float]
    /// Per-row horizontal variance, `>= 0`. Same length as `means`.
    public let variances: [Float]
    /// Source frame width in pixels, before downscaling (for geometry bookkeeping).
    public let sourceWidth: Int
    /// Source frame height in pixels, before downscaling.
    public let sourceHeight: Int

    /// Full initializer with explicit per-row signatures (used by `VerticalProfile`). `means`
    /// is derived as each row's mean, keeping the mean/variance API for chrome detection.
    public init(rows: [[Float]], variances: [Float], sourceWidth: Int, sourceHeight: Int) {
        precondition(rows.count == variances.count, "rows and variances must be parallel")
        self.rows = rows
        self.means = rows.map { $0.isEmpty ? 0 : $0.reduce(0, +) / Float($0.count) }
        self.variances = variances
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
    }

    /// Mean-only initializer: each row's signature is its single mean value, so the matcher's
    /// 2-D MAD reduces exactly to mean-absolute-difference. Keeps array-built callers and the
    /// matcher's unit tests (which reason about a 1-D mean signal) unchanged.
    public init(means: [Float], variances: [Float], sourceWidth: Int, sourceHeight: Int) {
        precondition(means.count == variances.count, "means and variances must be parallel")
        self.rows = means.map { [$0] }
        self.means = means
        self.variances = variances
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
    }

    /// Number of profiled rows.
    public var rowCount: Int { means.count }

    /// Vertical scale factor from profile rows back to source pixels.
    /// `sourceRow ≈ profileRow * rowScale`.
    public var rowScale: Double {
        rowCount == 0 ? 1 : Double(sourceHeight) / Double(rowCount)
    }
}
