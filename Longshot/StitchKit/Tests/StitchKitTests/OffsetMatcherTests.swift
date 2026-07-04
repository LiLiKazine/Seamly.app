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

@Suite struct OffsetMatcherTests {
    let matcher = OffsetMatcher()

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
}
