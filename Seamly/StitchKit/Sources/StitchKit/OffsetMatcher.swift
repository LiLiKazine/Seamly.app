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
    /// Absolute floor on *scored* rows required for a candidate offset to be considered — the
    /// signal floor. This is the only overlap gate a `rowMask` can affect: a masked match counts
    /// content rows only, and below a handful of them there is nothing to judge an alignment on.
    public let minimumOverlap: Int
    /// Overlap floor as a fraction of the smaller frame's row count, applied to the **geometric**
    /// overlap at a candidate offset (`frameRows − |dy|`). The score is a per-row average, so it
    /// does not penalize small overlaps on its own — an offset that overlaps only a handful of
    /// rows can average a lower error than the true, well-overlapped offset and win, pinning the
    /// match to an extreme boundary shift. Requiring the overlap to be a real fraction of the
    /// frame rejects those. Kept below the ~30% overlap a legitimate fast scroll still reaches
    /// (the safety-cue threshold), so real scrolls are not rejected.
    ///
    /// Geometric on purpose: how much two frames share at offset `dy` is a property of `dy`, not
    /// of what a mask later excluded from scoring. Measuring this against the masked count instead
    /// caps the largest offset a masked match can measure — see `match`.
    public let minimumOverlapFraction: Double
    /// Half-prominence level (0...1) that bounds the winning offset's *valley* when picking the
    /// confidence runner-up. The score curve dips into a valley around the true offset; at
    /// heavily downscaled geometry that valley is several rows wide, so a fixed ±N "same peak"
    /// window leaves the runner-up sitting *inside* the valley — a near-equal score that reports
    /// a correct, unambiguous match as low-confidence and makes the tracker drop it. Instead the
    /// valley is walked out to the score level `best + valleyProminence·(worst − best)`, and the
    /// runner-up is the best score *outside* it: for a single smooth valley that's a genuinely
    /// worse alignment (high confidence); for periodic content it's the next repeat (low).
    public let valleyProminence: Float
    /// How strongly to penalize offsets that explain less of the frame. The per-row average
    /// score is overlap-blind: a partial-overlap offset can average as low as the true,
    /// full-overlap one — winning outright (a boundary shift) or, just short of that, posing as
    /// a near-equal runner-up that sinks confidence. Scaling the score by
    /// `1 + overlapPenalty·(1 − overlapFraction)` makes fuller overlap genuinely cheaper, so the
    /// offset that aligns the *most* content wins and sets the confidence baseline.
    public let overlapPenalty: Float

    public init(minimumOverlap: Int = 8, minimumOverlapFraction: Double = 0.25, valleyProminence: Float = 0.5, overlapPenalty: Float = 0.8) {
        self.minimumOverlap = minimumOverlap
        self.minimumOverlapFraction = minimumOverlapFraction
        self.valleyProminence = valleyProminence
        self.overlapPenalty = overlapPenalty
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
        var scored: [(offset: Int, candidate: CandidateScore)] = []

        // Two separate gates, because "is this a plausible scroll" and "did this offset have enough
        // signal to score" are different questions and only the second is about the mask.
        //
        // **Plausibility is geometric.** Rejecting tiny-overlap offsets is what keeps the matcher
        // from latching onto an extreme boundary shift, and how much two frames overlap at offset
        // `dy` is a fact about `dy` — `frameRows − |dy|` rows, whatever a mask later excludes from
        // scoring. So the fractional floor is applied to that geometric overlap, against the
        // frame's rows.
        //
        // Applying a *fraction of the countable rows* to the masked count instead — what this did
        // before — makes the floor forbid large offsets by construction. A masked match counts only
        // rows that are content at both ends of the shift, so its count falls as `dy` grows; a
        // floor of `0.25 · countable` therefore caps any masked match at `dy ≈ 0.75 · countable`,
        // regardless of how clean the alignment is. That is a limit on the *capture*, not a test of
        // the match. `docs/logs/2026-08-08-02` moved this reference from the frame's rows to the
        // countable rows and so raised the ceiling from `content − 160` to `0.75 · content`, which
        // fixed the fixture in hand; `Screenshots3`/`Screenshots4` simply scroll further and cross
        // it again. Measured at their true offsets (`docs/logs/2026-08-09-03`):
        //
        // | pair | true dy | masked counted | old floor | verdict |
        // |------|---------|----------------|-----------|---------|
        // | `Screenshots4` 1870→1871 | 372 | 96 | 116 | rejected, ceiling 346 |
        // | `Screenshots4` 1872→1873 | 409 | 93 | 116 | rejected, ceiling 348 |
        // | `Screenshots3` 1864→1865 | 416 | 77 |  97 | rejected, ceiling 290 |
        //
        // Each rejection then *won*: `BatchStitcher.downwardMatch` keeps whichever variant is more
        // confident, masking usually scores better, so the masked match's best surviving offset
        // overrode a plain match that had the true one.
        //
        // The invariant this restores is that **masking changes how an offset is scored, never
        // which offsets are admissible** — the unmasked path is unchanged by construction, since
        // without a mask `counted` *is* the geometric overlap.
        //
        // What the mask still gates is signal: `minimumOverlap` rows must survive it, and
        // `weightTotal` must be non-degenerate. `overlapPenalty` below — which deliberately keeps
        // the **frame** as its denominator — is what expresses "more overlap is better" as a
        // continuous preference rather than a cliff. Moving *it* to the countable rows was tried
        // and reverted: it lowers every offset's penalty but lowers a well-overlapped one's much
        // further (at `dy=0`, 1.21 → 1.00; at `dy=354`, 1.65 → 1.59), tilting the whole curve
        // toward `dy=0`, which flipped a real downward baidu pair to `dy=0` outright.
        let frameRows = min(a.rowCount, b.rowCount)
        let referenceRows = frameRows
        let countableRows = countableRows(rowMask, upTo: frameRows)
        let minGeometricOverlap = max(
            minimumOverlap,
            Int((minimumOverlapFraction * Double(frameRows)).rounded())
        )

        for offset in searchRange {
            guard frameRows - abs(offset) >= minGeometricOverlap else { continue }
            guard let candidate = weightedMAD(
                a,
                b,
                offset: offset,
                rowMask: rowMask,
                minOverlap: minimumOverlap,
                referenceRows: referenceRows
            ) else { continue }
            scored.append((offset, candidate))
            if candidate.cost < bestScore {
                bestScore = candidate.cost
                bestOffset = offset
            }
        }

        guard let bestIndex = scored.firstIndex(where: { $0.offset == bestOffset }) else {
            return Match(
                dy: 0,
                confidence: 0,
                overlap: Match.OverlapAccounting(
                    countedRows: 0,
                    countableRows: countableRows,
                    minimumRequiredRows: minimumOverlap,
                    passedMinimumOverlap: false
                )
            )
        }

        // Runner-up = best score *outside the winning offset's valley*. The valley is the
        // contiguous run of offsets around the best whose score stays at or below a
        // half-prominence level; walking it out adapts to the valley's width (a few rows at
        // real geometry, ~1 at 1:1) so the runner-up is a truly distinct alignment, not a
        // near-neighbor of the same peak. `scored` is ordered by offset and contiguous through
        // the central region where the valley lives, so index walking tracks adjacent offsets.
        let worstScore = scored.max { $0.candidate.cost < $1.candidate.cost }!.candidate.cost
        let valleyLevel = bestScore + valleyProminence * (worstScore - bestScore)
        var lo = bestIndex, hi = bestIndex
        while lo - 1 >= 0, scored[lo - 1].candidate.cost <= valleyLevel { lo -= 1 }
        while hi + 1 < scored.count, scored[hi + 1].candidate.cost <= valleyLevel { hi += 1 }

        var runnerUp = Float.greatestFiniteMagnitude
        for i in scored.indices where i < lo || i > hi {
            runnerUp = min(runnerUp, scored[i].candidate.cost)
        }

        let confidence = confidenceMargin(best: bestScore, runnerUp: runnerUp)
        return Match(
            dy: bestOffset,
            confidence: confidence,
            cost: bestScore,
            overlap: Match.OverlapAccounting(
                countedRows: scored[bestIndex].candidate.countedRows,
                countableRows: countableRows,
                minimumRequiredRows: minimumOverlap,
                passedMinimumOverlap: true
            )
        )
    }

    /// The most rows any offset could contribute to the score: every overlapping row for an
    /// unmasked match, and only the content rows for a masked one (`offset = 0` counts exactly
    /// those, and every other offset counts a subset). This is what the overlap *floor* has to be
    /// a fraction of — a floor set against the frame's rows asks a masked match to count rows the
    /// mask already removed.
    private func countableRows(_ rowMask: [Bool]?, upTo rows: Int) -> Int {
        guard let rowMask else { return rows }
        var counted = 0
        for k in 0..<rows where k < rowMask.count && rowMask[k] { counted += 1 }
        return counted
    }

    private struct CandidateScore {
        let cost: Float
        let countedRows: Int
    }

    /// Variance-weighted mean absolute difference and its actual counted overlap, or `nil` if the
    /// overlap is below `minOverlap` or carries no structure. When `rowMask` is supplied, only rows
    /// unmasked in both frames count toward the score and the overlap guard.
    private func weightedMAD(_ a: FrameProfile, _ b: FrameProfile, offset: Int, rowMask: [Bool]?, minOverlap: Int, referenceRows: Int) -> CandidateScore? {
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
            weightedSum += weight * rowDifference(a.rows[ai], b.rows[k])
            weightTotal += weight
            counted += 1
        }
        guard counted >= minOverlap else { return nil }
        guard weightTotal > 1e-6 else { return nil }
        // Reward overlap: an offset that explains more of the frame is genuinely cheaper, so a
        // partial-overlap alignment can't tie the full-overlap true offset on the raw average.
        let overlapFraction = Float(counted) / Float(referenceRows)
        let cost = (weightedSum / weightTotal) * (1 + overlapPenalty * (1 - overlapFraction))
        return CandidateScore(cost: cost, countedRows: counted)
    }

    /// Mean absolute difference between two row luminance signatures. With single-value
    /// signatures this is just `abs(meanA - meanB)`; with the profiler's multi-column
    /// signatures it compares the whole horizontal structure, which is what disambiguates a
    /// real scroll from its mirror (a per-row mean alone is near-degenerate on feed content).
    private func rowDifference(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for c in 0..<n { sum += abs(a[c] - b[c]) }
        return sum / Float(n)
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
