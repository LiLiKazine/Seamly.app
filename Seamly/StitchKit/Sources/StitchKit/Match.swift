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

    public init(dy: Int, dx: Int = 0, confidence: Double) {
        self.dy = dy
        self.dx = dx
        self.confidence = confidence
    }
}
