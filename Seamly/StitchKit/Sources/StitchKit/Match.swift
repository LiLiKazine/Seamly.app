import Foundation

/// The result of aligning one frame profile against another.
///
/// `dy` is the vertical shift, in profile rows, that best maps the second profile
/// onto the first: a positive `dy` means the content scrolled *down* (new rows
/// appeared at the bottom). `dx` is the incidental horizontal component — expected to
/// be ~0 for vertically-locked iOS scroll views; a consistent nonzero value flags a
/// seam low-confidence rather than being modeled.
public struct Match: Sendable, Equatable {
    /// Best vertical offset, in profile rows.
    public let dy: Int
    /// Incidental horizontal offset, in profile columns (0 when not measured).
    public let dx: Int
    /// How decisively the best offset beat the runner-up, in `0...1`.
    /// Higher means a sharper, more trustworthy alignment.
    public let confidence: Double
    /// Goodness-of-fit of the winning offset: the variance-weighted MAD it scored, lower is a
    /// better fit. `.greatestFiniteMagnitude` when no offset could be scored.
    ///
    /// Distinct from `confidence`, and the distinction matters. `confidence` measures how far
    /// the winner beat its runner-up — sharpness — so a badly-fitting alignment can still be
    /// "confident" if the rest of the landscape is worse still. `cost` measures whether the
    /// rows actually agree. Comparing two *different* matches (notably the two scroll
    /// directions of one pair) is a fit question, so it wants this, not `confidence`.
    public let cost: Float

    public init(dy: Int, dx: Int = 0, confidence: Double, cost: Float = .greatestFiniteMagnitude) {
        self.dy = dy
        self.dx = dx
        self.confidence = confidence
        self.cost = cost
    }
}
