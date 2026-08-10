import Testing
@testable import StitchKit

/// Build a profile straight from arrays (bypassing image rendering) so matcher tests
/// are deterministic and independent of `VerticalProfile`.
private func profile(_ means: [Float], variance: Float = 0.1) -> FrameProfile {
    FrameProfile(
        means: means,
        variances: [Float](repeating: variance, count: means.count),
        sourceWidth: 100,
        sourceHeight: means.count * 10
    )
}

/// A pseudo-random-but-deterministic content signal with distinct rows.
private func contentSignal(count: Int, seed: Int = 1) -> [Float] {
    var out = [Float]()
    var x = UInt64(seed &+ 1)
    for _ in 0..<count {
        x = x &* 6364136223846793005 &+ 1442695040888963407
        out.append(Float((x >> 33) & 0xFFFF) / Float(0xFFFF))
    }
    return out
}

private func spatialProfile(_ rows: [[Float]]) -> FrameProfile {
    let variances = rows.map { row -> Float in
        let mean = row.reduce(0, +) / Float(row.count)
        return row.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(row.count)
    }
    return FrameProfile(
        rows: rows,
        variances: variances,
        sourceWidth: rows.first?.count ?? 0,
        sourceHeight: rows.count
    )
}

/// Two profiles whose quiet majority follows `trueDy`, while one high-contrast horizontal
/// region follows `lureDy`. The existing whole-frame MAD is deliberately fooled by the lure;
/// a spatial consensus should give the three agreeing content regions one vote each and reject
/// the lone dynamic region as an outlier.
private func locallyCorruptedProfiles(trueDy: Int = 15, lureDy: Int = 5) -> (FrameProfile, FrameProfile) {
    let height = 100
    let columns = 8
    let fullHeight = height + max(trueDy, lureDy)

    func quiet(_ y: Int, _ column: Int) -> Float {
        let mixed = (y &* 73 &+ column &* 151 &+ y &* column &* 17) % 997
        return 0.49 + 0.02 * Float(mixed) / 996
    }

    func lure(_ y: Int, _ column: Int) -> Float {
        let mixed = (y &* 37 &+ column &* 211 &+ y &* column &* 29) % 101
        return mixed.isMultiple(of: 2) ? 0.05 : 0.95
    }

    let source = (0..<fullHeight).map { y in
        (0..<columns).map { column in
            column < 6 ? quiet(y, column) : lure(y, column)
        }
    }
    let aRows = Array(source[0..<height])
    let bRows = (0..<height).map { row in
        (0..<columns).map { column in
            column < 6 ? quiet(row + trueDy, column) : lure(row + lureDy, column)
        }
    }

    return (spatialProfile(aRows), spatialProfile(bRows))
}

/// Half the frame follows each of two equally strong offsets. Neither alignment has a spatial
/// majority, so a consensus matcher must report ambiguity instead of manufacturing confidence
/// from whichever pattern happens to have the slightly lower residual.
private func evenlyDividedProfiles(firstDy: Int = 15, secondDy: Int = 5) -> (FrameProfile, FrameProfile) {
    let height = 100
    let columns = 8
    let fullHeight = height + max(firstDy, secondDy)

    func sample(_ y: Int, _ column: Int) -> Float {
        let mixed = (y &* 83 &+ column &* 197 &+ y &* column &* 31) % 103
        return mixed.isMultiple(of: 2) ? 0.08 : 0.92
    }

    let source = (0..<fullHeight).map { y in
        (0..<columns).map { sample(y, $0) }
    }
    let aRows = Array(source[0..<height])
    let bRows = (0..<height).map { row in
        (0..<columns).map { column in
            sample(row + (column < columns / 2 ? firstDy : secondDy), column)
        }
    }

    return (spatialProfile(aRows), spatialProfile(bRows))
}

@Suite struct OffsetMatcherTests {
    let matcher = OffsetMatcher()

    @Test func manuallyConstructedMatchLeavesOverlapAccountingUnavailable() {
        let match = Match(dy: 12, confidence: 0.8)
        #expect(match.overlap == nil)
    }

    @Test func recoversExactPositiveShift() {
        let full = contentSignal(count: 120)
        let a = profile(Array(full[0..<100]))
        let b = profile(Array(full[15..<115]))   // scrolled down 15 rows
        let m = matcher.match(a, b, searchRange: -40...40)
        #expect(m.dy == 15)
        #expect(m.confidence > 0.5)
    }

    @Test func recoversZeroShift() {
        let a = profile(contentSignal(count: 100))
        let m = matcher.match(a, a, searchRange: -20...20)
        #expect(m.dy == 0)
        #expect(m.confidence > 0.7)
    }

    @Test func recoversNegativeShiftWhenScrollingUp() {
        let full = contentSignal(count: 120)
        let a = profile(Array(full[20..<120]))
        let b = profile(Array(full[8..<108]))     // scrolled up 12 rows
        let m = matcher.match(a, b, searchRange: -40...40)
        #expect(m.dy == -12)
    }

    @Test func uniformProfilesAreLowConfidence() {
        let a = profile([Float](repeating: 0.5, count: 100), variance: 0.0)
        let b = profile([Float](repeating: 0.5, count: 100), variance: 0.0)
        let m = matcher.match(a, b, searchRange: -20...20)
        #expect(m.confidence < 0.3)
    }

    @Test func periodicPatternIsLowConfidence() {
        // A repeating list-row pattern matches at many offsets -> ambiguous.
        let pattern: [Float] = (0..<100).map { $0 % 5 == 0 ? 0.9 : 0.2 }
        let a = profile(pattern)
        let b = profile(Array(pattern[5..<100]) + [0.9, 0.2, 0.2, 0.2, 0.2])
        let m = matcher.match(a, b, searchRange: -20...20)
        #expect(m.confidence < 0.5)
    }

    @Test func varianceWeightingIgnoresUniformBands() {
        // Two frames identical in a textured middle band but differing in flat margins;
        // low-variance flat rows shouldn't dominate the score.
        var full = contentSignal(count: 140)
        for i in 0..<20 { full[i] = 0.5 }          // flat top
        for i in 120..<140 { full[i] = 0.5 }       // flat bottom
        let variances = full.map { _ in Float(0.1) }
        var flatVar = variances
        for i in 0..<20 { flatVar[i] = 0.0 }
        for i in 120..<140 { flatVar[i] = 0.0 }
        let a = FrameProfile(means: Array(full[0..<120]), variances: Array(flatVar[0..<120]), sourceWidth: 100, sourceHeight: 1200)
        let b = FrameProfile(means: Array(full[10..<130]), variances: Array(flatVar[10..<130]), sourceWidth: 100, sourceHeight: 1200)
        let m = matcher.match(a, b, searchRange: -40...40)
        #expect(m.dy == 10)
    }

    @Test func respectsMinimumOverlap() {
        // A large shift leaving < minimumOverlap rows must not win on a lucky few rows.
        let full = contentSignal(count: 200)
        let a = profile(Array(full[0..<100]))
        let b = profile(Array(full[15..<115]))
        let m = matcher.match(a, b, searchRange: -95...95)
        #expect(m.dy == 15)   // the true, well-overlapped offset still wins
    }

    // MARK: - Spatial consensus

    @Test func aggregateScoreCanBeFooledByOneHighContrastRegion() {
        let (a, b) = locallyCorruptedProfiles()
        let m = OffsetMatcher(aggregation: .weightedMean).match(a, b, searchRange: 1...30)
        #expect(m.dy == 5, "the fixture no longer reproduces the aggregate matcher's false offset")
    }

    @Test func lightweightMatcherRemainsTheDefaultForLiveCapture() {
        #expect(OffsetMatcher().aggregation == .weightedMean)
    }

    @Test func tileConsensusFallsBackForProfilesTooSmallForSpatialVoting() {
        let full = contentSignal(count: 64)
        let a = profile(Array(full[0..<48]))
        let b = profile(Array(full[8..<56]))
        let weighted = OffsetMatcher(aggregation: .weightedMean).match(a, b, searchRange: 1...20)
        let consensus = OffsetMatcher(aggregation: .tileConsensus).match(a, b, searchRange: 1...20)
        #expect(consensus == weighted)
    }

    @Test func tileConsensusRecoversTheMajorityContentShift() {
        let (a, b) = locallyCorruptedProfiles()
        let m = OffsetMatcher(aggregation: .tileConsensus).match(a, b, searchRange: 1...30)
        #expect(m.dy == 15)
        #expect(m.confidence > 0.5)
    }

    @Test func tileConsensusReportsAnEvenlyDividedFrameAsAmbiguous() {
        let (a, b) = evenlyDividedProfiles()
        let m = OffsetMatcher(aggregation: .tileConsensus).match(a, b, searchRange: 1...30)
        #expect(m.confidence < 0.3, "a 50/50 spatial vote reported confidence \(m.confidence) at dy=\(m.dy)")
    }

    @Test func batchStitcherUsesTileConsensusForOfflineGeometry() {
        let (a, b) = locallyCorruptedProfiles()
        let m = BatchStitcher().downwardMatch(a, b)
        #expect(m.dy == 15)
    }

    // MARK: - Row mask (chrome exclusion) — Gap 1

    /// Build a framed profile: `chrome` static rows at top+bottom (high variance, so they
    /// dominate the weighted MAD) wrapping a low-variance content window.
    private func framedProfile(chrome: Int, total: Int, content: [Float], chromePattern: [Float]) -> FrameProfile {
        precondition(content.count == total - 2 * chrome)
        var means = [Float](repeating: 0, count: total)
        var vars = [Float](repeating: 0, count: total)
        for i in 0..<total {
            if i < chrome {
                means[i] = chromePattern[i]; vars[i] = 0.3
            } else if i >= total - chrome {
                means[i] = chromePattern[chrome + (i - (total - chrome))]; vars[i] = 0.3
            } else {
                means[i] = content[i - chrome]; vars[i] = 0.01   // faint content, low weight
            }
        }
        return FrameProfile(means: means, variances: vars, sourceWidth: 100, sourceHeight: total * 10)
    }

    @Test func staticChromeBiasesUnmaskedMatchToZero() {
        // Regression proof of Gap 1: identical high-variance chrome pins the unmasked match
        // to dy=0 even though the low-variance content scrolled by 15.
        let full = contentSignal(count: 140).map { 0.5 + ($0 - 0.5) * 0.05 }   // faint content
        let chrome = (0..<40).map { Float(($0 * 37) % 100) / 100 }              // strong pattern
        let a = framedProfile(chrome: 20, total: 140, content: Array(full[0..<100]), chromePattern: chrome)
        let b = framedProfile(chrome: 20, total: 140, content: Array(full[15..<115]), chromePattern: chrome)
        let m = matcher.match(a, b, searchRange: -30...30)
        #expect(m.dy == 0)   // chrome wins — the bug we are fixing
    }

    @Test func rowMaskExcludesChromeAndRecoversContentShift() throws {
        let full = contentSignal(count: 140).map { 0.5 + ($0 - 0.5) * 0.05 }
        let chrome = (0..<40).map { Float(($0 * 37) % 100) / 100 }
        let a = framedProfile(chrome: 20, total: 140, content: Array(full[0..<100]), chromePattern: chrome)
        let b = framedProfile(chrome: 20, total: 140, content: Array(full[15..<115]), chromePattern: chrome)
        // Mask: content rows [20, 120) true, chrome rows false. Same screen-row mask for both.
        var mask = [Bool](repeating: true, count: 140)
        for i in 0..<20 { mask[i] = false }
        for i in 120..<140 { mask[i] = false }
        let m = matcher.match(a, b, searchRange: -30...30, rowMask: mask)
        #expect(m.dy == 15)   // chrome excluded -> the true content shift wins
        #expect(m.confidence > 0.3)
        let overlap = try #require(m.overlap)
        #expect(overlap.countedRows == 85)
        #expect(overlap.countableRows == 100)
        // The floor reported here is the *absolute* signal floor, the only overlap gate a mask
        // governs. The fractional floor is a separate, geometric test on the candidate offset and
        // is deliberately not expressed in counted rows — see `maskingDoesNotNarrowAdmissibility`.
        #expect(overlap.minimumRequiredRows == matcher.minimumOverlap)
        #expect(abs(overlap.fraction - 0.85) < 0.000_001)
        #expect(overlap.passedMinimumOverlap)

        let geometricFraction = Double(140 - abs(m.dy)) / 140
        #expect(abs(overlap.fraction - geometricFraction) > 0.04)
    }

    /// Masking changes how an offset is *scored*, never which offsets are *admissible*.
    ///
    /// The fractional overlap floor used to be applied to the masked row count, and a masked match
    /// only counts rows that are content at both ends of the shift — so its count falls as `dy`
    /// grows and the floor capped any masked match at `dy ≈ 0.75 · countable`, however clean the
    /// alignment. That ceiling is what discarded the true offset on four of the eight pairs in
    /// `Fixtures/Screenshots3`/`Screenshots4` (`docs/logs/2026-08-09-03`).
    ///
    /// Asserted as an equivalence over the whole search range rather than at one offset, because a
    /// ceiling is invisible at any offset below it — which is exactly why the previous correction
    /// (`2026-08-08-02`) looked complete while only raising it.
    @Test func maskingDoesNotNarrowAdmissibility() {
        let a = profile(contentSignal(count: 200))
        let b = profile(contentSignal(count: 200, seed: 2))
        // Mask out 100 of 200 rows, so a masked match can never count more than half the frame.
        var mask = [Bool](repeating: true, count: 200)
        for i in 0..<50 { mask[i] = false }
        for i in 150..<200 { mask[i] = false }

        var checked = 0
        for aggregation in [OffsetMatcher.Aggregation.weightedMean, .tileConsensus] {
            let matcher = OffsetMatcher(aggregation: aggregation)
            for dy in 1...199 {
                // Rows the mask actually leaves at this offset. Below `minimumOverlap` the match is
                // rejected for want of *signal*, which is the mask's legitimate business; this test is
                // about everything above that line.
                let achievable = (0..<(200 - dy)).count { mask[$0] && mask[$0 + dy] }
                guard achievable >= matcher.minimumOverlap else { continue }
                guard matcher.match(a, b, searchRange: dy...dy).cost < .greatestFiniteMagnitude else { continue }
                let masked = matcher.match(a, b, searchRange: dy...dy, rowMask: mask)
                #expect(masked.cost < .greatestFiniteMagnitude,
                        "\(aggregation) dy=\(dy): plain scores this offset and the mask leaves \(achievable) rows, but masked rejects it — the mask is capping how far a match can measure")
                checked += 1
            }
        }
        // The old floor capped this mask at dy ≈ 75; without a range that reaches past it the
        // equivalence above would hold vacuously.
        #expect(checked > 160, "only \(checked) offsets exercised — both modes must cross the old ceiling")
    }

    @Test func rowMaskWithTooFewContentRowsYieldsNoMatch() throws {
        // A mask leaving fewer than minimumOverlap content rows -> no candidate qualifies.
        let a = profile(contentSignal(count: 100))
        let b = profile(contentSignal(count: 100, seed: 2))
        var mask = [Bool](repeating: false, count: 100)
        for i in 40..<44 { mask[i] = true }   // 4 rows < minimumOverlap (8)
        let m = matcher.match(a, b, searchRange: -20...20, rowMask: mask)
        #expect(m.dy == 0)
        #expect(m.confidence == 0)
        let overlap = try #require(m.overlap)
        #expect(overlap.countedRows == 0)
        #expect(overlap.countableRows == 4)
        #expect(overlap.minimumRequiredRows == 8)
        #expect(overlap.fraction == 0)
        #expect(!overlap.passedMinimumOverlap)
    }

    @Test func nilMaskIsIdenticalToUnmasked() {
        let full = contentSignal(count: 120)
        let a = profile(Array(full[0..<100]))
        let b = profile(Array(full[15..<115]))
        let plain = matcher.match(a, b, searchRange: -40...40)
        let masked = matcher.match(a, b, searchRange: -40...40, rowMask: nil)
        #expect(plain == masked)
    }
}
