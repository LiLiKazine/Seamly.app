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

/// The static top/bottom bands of a seam — window chrome (status bar, nav bar, tab
/// bar, home indicator) that repeats across frames and must be cropped from
/// intermediate frames so it isn't stamped into the middle of the long image.
public struct ChromeBands: Sendable, Equatable {
    /// Number of contiguous static rows at the top of the frame, in profile rows.
    public let topRows: Int
    /// Number of contiguous static rows at the bottom, in profile rows.
    public let bottomRows: Int
    /// True when a band shifted versus the previous seam (e.g. a collapsing header),
    /// which makes this seam's chrome untrustworthy — flag rather than model it.
    public let isAmbiguous: Bool

    public init(topRows: Int, bottomRows: Int, isAmbiguous: Bool = false) {
        self.topRows = topRows
        self.bottomRows = bottomRows
        self.isAmbiguous = isAmbiguous
    }

    /// No chrome detected.
    public static let none = ChromeBands(topRows: 0, bottomRows: 0)
}
