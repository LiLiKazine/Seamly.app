import Foundation

/// A frame reduced to a compact 1-D vertical signal.
///
/// Produced by `VerticalProfile` from an aggressively downscaled, grayscale frame:
/// for each row, the mean luminance (sampled over a few column bands) and the
/// horizontal variance of that row. Variance lets matching ignore near-uniform rows
/// (a solid background matches everywhere) and drives chrome detection.
///
/// Stored as parallel `Float` arrays so `OffsetMatcher` can hand them straight to
/// vDSP without per-row boxing. `means[i]` and `variances[i]` describe row `i`.
public struct FrameProfile: Sendable, Equatable {
    /// Per-row mean luminance, in `0...1`. One element per sampled row.
    public let means: [Float]
    /// Per-row horizontal variance, `>= 0`. Same length as `means`.
    public let variances: [Float]
    /// Source frame width in pixels, before downscaling (for geometry bookkeeping).
    public let sourceWidth: Int
    /// Source frame height in pixels, before downscaling.
    public let sourceHeight: Int

    public init(means: [Float], variances: [Float], sourceWidth: Int, sourceHeight: Int) {
        precondition(means.count == variances.count, "means and variances must be parallel")
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
