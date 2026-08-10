import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Translucent (blur / "liquid glass") chrome — the case pixel-only static-row detection used to
/// miss. A blurred bar keeps its own horizontal structure while the content scrolling *behind* it
/// shifts its overall brightness, so comparing per-row **means** rejects it as "moving content"
/// and the chrome band collapses to zero. The bar then gets baked into the stitch once per
/// keyframe, hiding real content underneath each copy.
///
/// Fixture `youtube-00..05.png`: six real committed keyframes from an iPhone 17 Pro Max screen
/// recording of the YouTube feed (iOS 26), half resolution. Its bottom tab bar is translucent;
/// as bright thumbnails scroll behind it the bar's row means shift by up to 0.051 (2.5x the 0.02
/// tolerance) while its row variances stay within 0.0007. That is the signature this suite pins.
@Suite struct TranslucentChromeTests {

    // MARK: - The discriminator, in isolation

    /// A row whose horizontal structure is unchanged but whose brightness shifted is chrome under
    /// a translucent bar, not scrolled content — for **band detection**. Uses the multi-column
    /// `FrameProfile` initializer because the structural comparison needs real horizontal samples.
    ///
    /// Also pins the deliberate scope: the same row still reads as *moved* without
    /// `allowingTranslucency`, because `staticMask` feeds `OffsetMatcher` and widening it there
    /// costs real overlap edges (see `isStatic`).
    @Test func translucentChromeRowIsNotMistakenForScrolledContent() {
        let columns = 64, total = 100, chrome = 10
        // A fixed, textured chrome pattern (like tab-bar icons and labels).
        let chromeRow = (0..<columns).map { Float(($0 * 17) % 100) / 100 }

        /// Content rows are made *unambiguously* different between the two frames (a large mean
        /// shift on top of a different texture). Anything subtler risks accidentally reproducing
        /// the translucency signature itself — a constant brightness offset cancels under
        /// mean-centering, and two independent random rows share a mean and variance — either of
        /// which would make "content" read as chrome and quietly void the boundary assertion.
        /// Realistic content is covered by the fixture tests below.
        func profile(brightnessOffset: Float, contentBase: Float, contentSeed: Int) -> FrameProfile {
            var rows: [[Float]] = [], variances: [Float] = []
            for i in 0..<total {
                if i < chrome {
                    // Same structure, shifted brightness: the translucent-bar signature.
                    rows.append(chromeRow.map { min(1, $0 + brightnessOffset) })
                } else {
                    // Wide-amplitude texture, so the two frames' shapes genuinely differ (a small
                    // amplitude shrinks the centered difference below `structureTolerance` no
                    // matter how uncorrelated the patterns are), offset in brightness so the means
                    // differ too while the amplitude — and thus the variance — stays matched.
                    rows.append((0..<columns).map { c in
                        var h = UInt32(truncatingIfNeeded: c &* 73 &+ i &* 9176 &+ contentSeed &* 15487)
                        h ^= h >> 15; h = h &* 2246822519; h ^= h >> 13
                        return contentBase + Float(h % 1000) / 1000 * 0.8
                    })
                }
                let r = rows[i]
                let mean = r.reduce(0, +) / Float(r.count)
                variances.append(r.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(r.count))
            }
            return FrameProfile(rows: rows, variances: variances, sourceWidth: columns, sourceHeight: total)
        }

        let a = profile(brightnessOffset: 0, contentBase: 0, contentSeed: 0)
        let b = profile(brightnessOffset: 0.06, contentBase: 0.2, contentSeed: 40)

        // Sanity: this really is the case under test — the mean moved well past tolerance while
        // the variance held. Otherwise the test proves nothing.
        let detector = ChromeStaticRowDetector()
        #expect(abs(a.means[0] - b.means[0]) > detector.meanTolerance,
                "fixture should shift the chrome row's mean past tolerance")
        #expect(abs(a.variances[0] - b.variances[0]) <= detector.varianceTolerance,
                "fixture should keep the chrome row's variance within tolerance")

        // Band detection counts contiguously inward from the edge, so the quantity that matters is
        // where it stops: through the whole bar (detecting it) and not one row further (not eating
        // content).
        var top = 0
        while top < total, detector.isStatic(a, b, row: top, allowingTranslucency: true) { top += 1 }
        #expect(top == chrome,
                "chrome band should span exactly the \(chrome) translucent rows, stopped at \(top)")

        // Scope: matching still treats them as moved, so `OffsetMatcher` input is unchanged.
        #expect((0..<chrome).allSatisfy { !detector.isStatic(a, b, row: $0) },
                "without allowingTranslucency the mean test must still reject these rows")
        let mask = try! #require(detector.staticMask(a, b))
        #expect(mask[0..<chrome].allSatisfy { $0 == true },
                "staticMask is deliberately left on the mean test — see isStatic")
    }

    /// A single-column profile carries no horizontal structure, so the structural comparison must
    /// not fire there — otherwise every row with a matching variance would read as chrome and the
    /// mean-based contract used throughout `ChromeStaticRowDetectorTests` would silently invert.
    @Test func singleColumnProfilesStayOnTheMeanTest() {
        let total = 20
        func profile(_ base: Float) -> FrameProfile {
            FrameProfile(
                means: (0..<total).map { base + Float($0) / 100 },
                variances: [Float](repeating: 0.1, count: total),
                sourceWidth: 1, sourceHeight: total
            )
        }
        let detector = ChromeStaticRowDetector()
        let a = profile(0), b = profile(0.5)
        // Same variance everywhere, means differ by 0.5: without the guard the structural test
        // would call these identical (a 1-column centered signature is always [0]), so every row
        // would read as chrome even with translucency explicitly allowed.
        #expect((0..<total).allSatisfy { !detector.isStatic(a, b, row: $0, allowingTranslucency: true) },
                "single-column rows differing only in mean must read as moved content")
    }

    // MARK: - Real fixture

    private func fixtureImages() throws -> [CGImage] {
        try (0...5).map { i in
            let name = String(format: "youtube-%02d", i)
            let url = try #require(
                Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "RealDevice"),
                "missing fixture RealDevice/\(name).png"
            )
            return try KeyframeIO.read(from: url)
        }
    }

    /// The headline regression: the translucent tab bar must be detected as bottom chrome on every
    /// keyframe. A zero measurement means the bar is baked into the stitch again.
    @Test func translucentTabBarIsDetectedAsBottomChrome() throws {
        let images = try fixtureImages()
        let plan = try BatchStitcher().plan(images, assumingOrder: Array(0..<images.count))
        let chrome = plan.session.keyframes.map { plan.session.resolvedChrome(for: $0).insets }

        // The bar's top edge sits ~124px above the frame bottom at this fixture's half resolution
        // (measured against the source frames); allow room for profile-row quantization.
        #expect(chrome.allSatisfy { $0.bottom > 0 },
                "translucent tab bar not detected — it will repeat once per keyframe")
        #expect(chrome.allSatisfy { (100...170).contains($0.bottom) },
                "bottom chrome \(chrome.map(\.bottom))px should be ≈124px (the tab bar)")
        // The opaque status bar was always detectable; it must not regress.
        #expect(chrome.allSatisfy { (80...130).contains($0.top) },
                "top chrome \(chrome.map(\.top))px should be ≈94px (the status bar)")
    }

    /// Cropping the *right amount* of chrome, not merely a nonzero amount. Each frame's strip is
    /// cut at `height - bottomChrome`, so the last row of frame `j` must be the same content as
    /// frame `j+1`'s row one scroll-step higher. Residual chrome left in the strip makes those two
    /// rows disagree sharply and shows up as a dark line at every seam in the finished stitch.
    @Test func chromeCropLeavesNoResidualBarAtSeams() throws {
        let images = try fixtureImages()
        let stitcher = BatchStitcher()
        let plan = try stitcher.plan(images, assumingOrder: Array(0..<images.count))
        // Refine through the same compositor the app assembles with, so the offsets are the ones
        // the cut actually uses.
        let refined = try Compositor(refinementDelta: 16)
            .refineSeams(plan.session) { images[plan.order[$0.index]] }
        try #require(refined.count == images.count - 1)

        for (pair, seam) in refined.enumerated() {
            let bottom = plan.session.resolvedChrome(for: plan.session.keyframes[pair]).insets.bottom
            let cutRow = images[pair].height - bottom - 1
            try #require(cutRow > 0, "bottom chrome \(bottom) leaves no content")
            let sameContentRow = cutRow - seam.provisionalDy
            guard sameContentRow - Self.probeRows + 1 >= 0 else { continue }
            let a = try bandMean(images[pair], endingAt: cutRow)
            let b = try bandMean(images[pair + 1], endingAt: sameContentRow)
            #expect(abs(a - b) < 0.02, """
                seam \(pair)-\(pair + 1) cuts through chrome: the \(Self.probeRows) rows ending at \
                \(cutRow) in frame \(pair) (mean \(a)) should match those ending at \
                \(sameContentRow) in frame \(pair + 1) (mean \(b)). A large gap means residual bar \
                pixels are left in the strip.
                """)
        }
    }

    /// Rows averaged by the seam probe. More than one, because this fixture is stored at half
    /// resolution: an odd full-res scroll offset lands on a half-pixel here, and at a sharp
    /// horizontal edge that resampling difference alone can exceed the tolerance on a single row.
    /// Averaging a few rows absorbs it while still catching a whole bar left in the strip (which
    /// moves the mean by 0.3+, an order of magnitude more).
    private static let probeRows = 4

    /// Mean luminance of the `probeRows` pixel rows ending at `endingAt`, skipping the leftmost
    /// columns so a badge or avatar clipped at the frame edge can't dominate the average.
    private func bandMean(_ image: CGImage, endingAt endRow: Int) throws -> Float {
        let width = image.width, rows = Self.probeRows
        let top = endRow - rows + 1
        let crop = try #require(
            image.cropping(to: CGRect(x: 0, y: top, width: width, height: rows)),
            "rows \(top)..\(endRow) out of bounds for \(image.width)x\(image.height)"
        )
        let ctx = try #require(CGContext(
            data: nil, width: width, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ))
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: rows))
        let data = try #require(ctx.data)
        let bytesPerRow = ctx.bytesPerRow
        let skip = 40
        var sum: Float = 0, count: Float = 0
        data.withMemoryRebound(to: UInt8.self, capacity: bytesPerRow * rows) { base in
            for r in 0..<rows {
                for c in skip..<width { sum += Float(base[r * bytesPerRow + c]) / 255; count += 1 }
            }
        }
        return sum / count
    }
}
