import Foundation

/// Aligns one frame profile against another by sliding and scoring candidate vertical
/// offsets with a variance-weighted mean-absolute-difference.
///
/// Weighting each row by its horizontal variance means near-uniform rows (solid
/// backgrounds, which match everywhere) contribute little, so the score is driven by
/// rows that actually carry structure. Confidence reports how decisively the best offset
/// beats the next distinct candidate — low confidence flags ambiguous cases (uniform
/// bands, periodic list rows) for the caller to handle (relocalize / flag the seam).
public struct OffsetMatcher: Sendable {
    /// Minimum overlapping rows required for a candidate offset to be considered.
    public let minimumOverlap: Int
    /// Rows within ±`peakExclusion` of the best offset are treated as the same peak when
    /// picking the runner-up for the confidence margin.
    public let peakExclusion: Int

    public init(minimumOverlap: Int = 8, peakExclusion: Int = 2) {
        self.minimumOverlap = minimumOverlap
        self.peakExclusion = peakExclusion
    }

    /// Aligns `b` onto `a`. A positive `dy` means content scrolled *down* by `dy` rows:
    /// `a[dy + k]` corresponds to `b[k]`.
    ///
    /// `rowMask` (screen-row indexed, one entry per row) restricts the score to content
    /// rows: a row contributes only when it is unmasked in *both* frames. Static chrome
    /// sits at the same screen row across frames, so masking those rows out keeps the
    /// alignment content-driven instead of being pinned to `dy=0` by fixed bars. `nil`
    /// scores every overlapping row (unchanged behavior). A candidate offset whose masked
    /// overlap falls below `minimumOverlap` is rejected exactly as an unmasked one would be.
    public func match(_ a: FrameProfile, _ b: FrameProfile, searchRange: ClosedRange<Int>, rowMask: [Bool]? = nil) -> Match {
        var bestOffset = 0
        var bestScore = Float.greatestFiniteMagnitude
        var scored: [(offset: Int, score: Float)] = []

        for offset in searchRange {
            guard let score = weightedMAD(a, b, offset: offset, rowMask: rowMask) else { continue }
            scored.append((offset, score))
            if score < bestScore {
                bestScore = score
                bestOffset = offset
            }
        }

        guard !scored.isEmpty else {
            return Match(dy: 0, confidence: 0)
        }

        // Runner-up = best score among offsets outside the winning peak's neighborhood.
        var runnerUp = Float.greatestFiniteMagnitude
        for entry in scored where abs(entry.offset - bestOffset) > peakExclusion {
            runnerUp = min(runnerUp, entry.score)
        }

        let confidence = confidenceMargin(best: bestScore, runnerUp: runnerUp)
        return Match(dy: bestOffset, confidence: confidence)
    }

    /// Variance-weighted mean absolute difference over the overlap, or `nil` if the
    /// overlap is too small or carries no structure. When `rowMask` is supplied, only rows
    /// unmasked in both frames count toward the score and the `minimumOverlap` guard.
    private func weightedMAD(_ a: FrameProfile, _ b: FrameProfile, offset: Int, rowMask: [Bool]?) -> Float? {
        // b[k] aligns with a[offset + k]; k must be valid in both.
        let kStart = max(0, -offset)
        let kEnd = min(b.rowCount, a.rowCount - offset)

        var weightedSum: Float = 0
        var weightTotal: Float = 0
        var counted = 0
        for k in kStart..<kEnd {
            let ai = offset + k
            if let rowMask {
                // Skip rows masked out in either frame (chrome sits at the same screen row).
                guard ai < rowMask.count, k < rowMask.count, rowMask[ai], rowMask[k] else { continue }
            }
            let weight = (a.variances[ai] + b.variances[k]) * 0.5
            weightedSum += weight * abs(a.means[ai] - b.means[k])
            weightTotal += weight
            counted += 1
        }
        guard counted >= minimumOverlap else { return nil }
        guard weightTotal > 1e-6 else { return nil }
        return weightedSum / weightTotal
    }

    /// Maps how far the best score sits below the runner-up into `0...1`. A best score far
    /// below the runner-up is a decisive, trustworthy match.
    private func confidenceMargin(best: Float, runnerUp: Float) -> Double {
        // No distinct competitor scored at all — a single candidate region, can't judge.
        guard runnerUp < .greatestFiniteMagnitude else { return 0.5 }
        // Both scores essentially zero (two equally-perfect alignments — periodic content, or
        // no signal): ambiguous. Use a tiny epsilon only to avoid a 0/0; the *ratio* below —
        // not an absolute score floor — is what judges decisiveness. An absolute floor wrongly
        // condemns low-variance content (text-on-white), whose MADs are legitimately tiny.
        guard runnerUp > 1e-9 else { return 0 }
        let ratio = Double(best / runnerUp)
        return min(1, max(0, 1 - ratio))
    }
}
