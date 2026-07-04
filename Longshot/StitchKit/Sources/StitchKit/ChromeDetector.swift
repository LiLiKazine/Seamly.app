import Foundation

/// Finds the static top/bottom bands of a seam — window chrome (status bar, nav bar, tab
/// bar, home indicator) that stays fixed on screen while content scrolls beneath it.
///
/// Works purely from the two 1-D profiles (no full previous frame needed): chrome sits at
/// the *same screen row* across frames, so at a given index its mean and variance barely
/// change, while content rows differ once the view scrolls. A row counts as static when
/// both its mean and variance are within a tolerance of the other frame's — not
/// byte-identical, so clock ticks and anti-aliasing don't break detection.
///
/// **Motion-gated**: only classifies when the pair shows clear scroll, so two identical
/// pre-scroll frames aren't mistaken for an all-chrome screen. A band that jumps versus
/// the previous seam (a collapsing header) flags the seam rather than being modeled.
public struct ChromeDetector: Sendable {
    /// Max mean difference for a row to still count as static (0...1 luminance).
    public let meanTolerance: Float
    /// Max variance difference for a row to still count as static.
    public let varianceTolerance: Float
    /// Minimum |dy| (rows) that counts as real scroll; below this, detection is skipped.
    public let motionThreshold: Int
    /// Band-size change (rows) versus the previous seam that flags a collapsing header.
    public let jumpThreshold: Int

    public init(
        meanTolerance: Float = 0.02,
        varianceTolerance: Float = 0.02,
        motionThreshold: Int = 2,
        jumpThreshold: Int = 3
    ) {
        self.meanTolerance = meanTolerance
        self.varianceTolerance = varianceTolerance
        self.motionThreshold = motionThreshold
        self.jumpThreshold = jumpThreshold
    }

    public func detect(_ a: FrameProfile, _ b: FrameProfile, dy: Int, previous: ChromeBands? = nil) -> ChromeBands {
        // Motion gate: identical / near-still frames carry no scroll to distinguish chrome
        // from a temporarily-static content screen.
        guard abs(dy) >= motionThreshold else { return .none }

        let count = min(a.rowCount, b.rowCount)
        guard count > 0 else { return .none }

        var topRows = 0
        while topRows < count, isStatic(a, b, row: topRows) {
            topRows += 1
        }

        var bottomRows = 0
        while bottomRows < count - topRows, isStatic(a, b, row: count - 1 - bottomRows) {
            bottomRows += 1
        }

        let ambiguous = isAmbiguous(topRows: topRows, bottomRows: bottomRows, previous: previous)
        return ChromeBands(topRows: topRows, bottomRows: bottomRows, isAmbiguous: ambiguous)
    }

    private func isStatic(_ a: FrameProfile, _ b: FrameProfile, row: Int) -> Bool {
        abs(a.means[row] - b.means[row]) <= meanTolerance
            && abs(a.variances[row] - b.variances[row]) <= varianceTolerance
    }

    private func isAmbiguous(topRows: Int, bottomRows: Int, previous: ChromeBands?) -> Bool {
        guard let previous else { return false }
        return abs(topRows - previous.topRows) > jumpThreshold
            || abs(bottomRows - previous.bottomRows) > jumpThreshold
    }
}
