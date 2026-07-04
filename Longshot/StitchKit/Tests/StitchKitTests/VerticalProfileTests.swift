import Testing
import CoreGraphics
@testable import StitchKit

@Suite struct VerticalProfileTests {
    let profiler = VerticalProfile(targetWidth: 64)

    @Test func uniformImageHasFlatMeanAndZeroVariance() {
        let img = TestImages.solid(width: 640, height: 1280, gray: 0.5)
        let p = profiler.profile(img)
        #expect(p.rowCount > 0)
        for m in p.means { #expect(abs(m - 0.5) < 0.02) }
        for v in p.variances { #expect(v < 0.001) }
    }

    @Test func horizontalSplitShowsDarkTopBrightBottom() {
        let img = TestImages.horizontalSplit(width: 640, height: 1280, topHeight: 640, topGray: 0.0, bottomGray: 1.0)
        let p = profiler.profile(img)
        #expect(p.means.first! < 0.1)   // top rows dark
        #expect(p.means.last! > 0.9)    // bottom rows bright
        // Overall mean is ~0.5 for an even split.
        let avg = p.means.reduce(0, +) / Float(p.rowCount)
        #expect(abs(avg - 0.5) < 0.1)
    }

    @Test func verticalSplitProducesHighPerRowVariance() {
        let img = TestImages.verticalSplit(width: 640, height: 1280, leftGray: 0.0, rightGray: 1.0)
        let p = profiler.profile(img)
        // Half black / half white per row: mean ~0.5, variance ~0.25.
        for m in p.means { #expect(abs(m - 0.5) < 0.05) }
        for v in p.variances { #expect(abs(v - 0.25) < 0.03) }
    }

    @Test func profileRecordsSourceGeometry() {
        let img = TestImages.solid(width: 1290, height: 2796, gray: 0.3)
        let p = profiler.profile(img)
        #expect(p.sourceWidth == 1290)
        #expect(p.sourceHeight == 2796)
        // rowScale maps profile rows back to source pixels.
        #expect(p.rowScale > 1)
        #expect(abs(Double(p.rowCount) * p.rowScale - 2796) < p.rowScale)
    }

    @Test func downscalePreservesVerticalStructure() {
        // A bright band in the top quarter should show as bright rows near the top.
        let img = TestImages.horizontalSplit(width: 640, height: 1600, topHeight: 400, topGray: 1.0, bottomGray: 0.0)
        let p = profiler.profile(img)
        let quarter = p.rowCount / 4
        let topBandMean = p.means[0..<quarter].reduce(0, +) / Float(quarter)
        let bottomMean = p.means[(p.rowCount - quarter)...].reduce(0, +) / Float(quarter)
        #expect(topBandMean > 0.8)
        #expect(bottomMean < 0.2)
    }
}
