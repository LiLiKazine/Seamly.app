import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// Screenshot sets whose **scroll step is large** — the user swiped hard between shots, so each
/// pair overlaps only a quarter to a half of the page instead of the comfortable two-thirds every
/// earlier fixture happens to have.
///
/// `Fixtures/Screenshots3` (Chrome for iOS, light, a Chinese subsidy article — bottom omnibox that
/// collapses after the first shot) and `Fixtures/Screenshots4` (Chrome for iOS, dark, a Discover
/// feed) are both 1320×2868, ascending filename order is scroll order. Ground truth, measured on
/// the raw pixels at full vertical resolution — no `VerticalProfile` — is in each set's README:
///
/// | set | true dy, px | content overlap |
/// |-----|-------------|-----------------|
/// | `Screenshots3` | 1873 / 1863 / 1635 / 1201 | 28% / 28% / 37% / 54% |
/// | `Screenshots4` | 1666 / 2159 / 1835 / 1543 | 26% / 4.6% / 19% / 32% |
///
/// These pin the ceiling that the masked overlap floor puts on **how far a match can measure**.
/// `docs/logs/2026-08-08-02` moved that floor's reference from the frame's rows to the rows the
/// mask left, which raised the ceiling from `content − 160` to `0.75 · content` — but a ceiling
/// proportional to the countable rows is still a ceiling, and a capture only has to scroll further
/// to cross it. Every set here does, and the failure is the same one that log describes: the
/// masked match discards the true offset, returns the best surviving one, and — because masking
/// usually scores *better* — wins `downwardMatch`'s confidence tie-break over a plain match that
/// had the right answer all along.
///
/// See `docs/logs/2026-08-09-03-geometric-overlap-floor.md`.
@Suite struct LargeScrollStepTests {

    struct Fixture: Sendable {
        let directory: String
        let names: [String]
        /// Consecutive offsets in source pixels, measured on raw pixels (see the set's README).
        let trueDy: [Int]
        /// True chrome in source pixels, measured on raw pixels.
        let topChrome: Int
        let bottomChrome: Int
    }

    static let screenshots3 = Fixture(
        directory: "Screenshots3",
        names: ["IMG_1863", "IMG_1864", "IMG_1865", "IMG_1866", "IMG_1867"],
        trueDy: [1873, 1863, 1635, 1201],
        topChrome: 189, bottomChrome: 88
    )

    static let screenshots4 = Fixture(
        directory: "Screenshots4",
        names: ["IMG_1870", "IMG_1871", "IMG_1872", "IMG_1873", "IMG_1874"],
        trueDy: [1666, 2159, 1835, 1543],
        topChrome: 372, bottomChrome: 234
    )

    static let fixtures = [screenshots3, screenshots4]

    /// Provisional offsets are quantized to profile rows (`rowScale` ≈ 4.5 px at 1320×2868), so a
    /// correct match can sit a row or two off the raw-pixel truth before `Compositor` refines it.
    static let rowTolerance = 10

    static let frameHeight = 2868

    private func load(_ fixture: Fixture) throws -> [CGImage] {
        try fixture.names.map { name in
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "PNG", subdirectory: fixture.directory),
                                   "missing fixture \(fixture.directory)/\(name)")
            return try KeyframeIO.read(from: url)
        }
    }

    // MARK: - The matcher, pair by pair

    /// The measurement underneath everything else: for each consecutive pair, the offset
    /// `BatchStitcher` will actually use must be the one the raw pixels say it is.
    ///
    /// Asserted per pair rather than through `plan`, because a plan-level assertion cannot
    /// distinguish "the matcher found the offset" from "the ordering happened to route around a
    /// bad one".
    ///
    /// The tolerance is `Self.rowTolerance` — two profile rows at this geometry. A provisional
    /// offset is quantized to profile rows (`rowScale` ≈ 4.5 px), and `Compositor` refines it to
    /// pixel-exactness within a ±16 px window, so this asserts the matcher landed in the right
    /// valley rather than pinning a pixel count the refinement pass owns.
    @Test(arguments: fixtures)
    func everyConsecutivePairMeasuresItsTrueOffset(_ fixture: Fixture) throws {
        let images = try load(fixture)
        let profiler = VerticalProfile()
        let profiles = images.map { profiler.profile($0) }
        let stitcher = BatchStitcher()

        var measured: [Int] = []
        for i in 0..<(profiles.count - 1) {
            let m = stitcher.downwardMatch(profiles[i], profiles[i + 1])
            measured.append(Int((Double(m.dy) * profiles[i].rowScale).rounded()))
        }
        for (i, expected) in fixture.trueDy.enumerated() {
            let detail = "\(fixture.directory) pair \(i): measured \(measured[i])px, true \(expected)px (all measured: \(measured))"
            #expect(abs(measured[i] - expected) <= Self.rowTolerance, "\(detail)")
        }
    }

    /// A masked match must be admissible wherever a plain one is. Masking decides how an offset is
    /// *scored*; it must not decide which offsets can be *considered*, or the mask silently caps
    /// the largest scroll the matcher can see — which is the whole defect this suite exists for.
    @Test(arguments: fixtures)
    func maskingNeverRejectsAnOffsetPlainMatchingAccepts(_ fixture: Fixture) throws {
        let images = try load(fixture)
        let profiler = VerticalProfile()
        let profiles = images.map { profiler.profile($0) }
        let matcher = OffsetMatcher()
        let detector = ChromeStaticRowDetector(meanTolerance: 0.02, varianceTolerance: 0.02)

        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let mask = detector.staticMask(a, b)
            let trueRows = Int((Double(fixture.trueDy[i]) / a.rowScale).rounded())
            let plain = matcher.match(a, b, searchRange: trueRows...trueRows)
            let masked = matcher.match(a, b, searchRange: trueRows...trueRows, rowMasks: RowMaskPair(shared: mask))
            guard plain.cost < .greatestFiniteMagnitude else { continue }   // plain can't reach it either
            let detail = "\(fixture.directory) pair \(i): plain scores the true offset dy=\(trueRows) rows but masked rejects it — the mask is capping how far a match can measure"
            #expect(masked.cost < .greatestFiniteMagnitude, "\(detail)")
        }
    }

    // MARK: - Order and segmentation

    /// A single continuous downward scroll must recover as one segment in filename order, however
    /// far each swipe went.
    @Test(arguments: fixtures)
    func aLargeStepScrollStaysOneSegmentInOrder(_ fixture: Fixture) throws {
        let images = try load(fixture)
        let plan = try BatchStitcher().plan(images)

        #expect(plan.order == Array(0..<images.count),
                "\(fixture.directory): recovered \(plan.order.map { fixture.names[$0] })")
        #expect(plan.session.segmentBreaks.isEmpty,
                "\(fixture.directory): split at \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")
        let seamDy = plan.session.seams.map(\.provisionalDy)
        for (i, expected) in fixture.trueDy.enumerated() where i < seamDy.count {
            #expect(abs(seamDy[i] - expected) <= Self.rowTolerance,
                    "\(fixture.directory) seam \(i): \(seamDy[i])px, true \(expected)px")
        }
    }

    // MARK: - Chrome

    /// Chrome is measured against the raw-pixel ground truth, allowing `sourcePixels`' deliberate
    /// outward rounding of one profile row (~4.5 px) — cropping a little extra bar is harmless,
    /// cropping content is not.
    @Test(arguments: [screenshots4])
    func chromeMatchesTheRawPixelGroundTruth(_ fixture: Fixture) throws {
        let plan = try BatchStitcher().plan(try load(fixture))
        let records = Dictionary(uniqueKeysWithValues: plan.session.keyframeChrome.map { ($0.keyframeID, $0) })
        let automatic = try plan.session.keyframes.map { keyframe -> ChromeMeasurement in
            try #require(records[keyframe.id]?.automatic,
                         "\(fixture.directory): missing automatic chrome for keyframe \(keyframe.index)")
        }
        #expect(Set(records.keys) == Set(plan.session.keyframes.map(\.id)),
                "\(fixture.directory): automatic chrome must be keyed by planned keyframe UUIDs")
        #expect(automatic.map(\.insets.top).allSatisfy { (fixture.topChrome...(fixture.topChrome + 16)).contains($0) },
                "\(fixture.directory): per-keyframe tops \(automatic.map(\.insets.top))px, expected ~\(fixture.topChrome)px")
        #expect(automatic.map(\.insets.bottom).allSatisfy { (fixture.bottomChrome...(fixture.bottomChrome + 16)).contains($0) },
                "\(fixture.directory): per-keyframe bottoms \(automatic.map(\.insets.bottom))px, expected ~\(fixture.bottomChrome)px")
    }

    /// `Screenshots3` is a single continuous scroll, but Chrome's bottom UI changes shape after
    /// the first frame: `IMG_1863` has the expanded toolbar (~431 source px in the 640-row
    /// profile), while `IMG_1864`...`IMG_1867` have the collapsed toolbar (~166 px). A
    /// segment-level band has to intersect those states and therefore cannot describe both.
    ///
    /// Per-keyframe automatic chrome is keyed by each planned `Keyframe.id`, never by input
    /// filename or source index, and must preserve the same order, segmentation, and dy values
    /// asserted above.
    @Test func screenshots3RecordsPerKeyframeChromeForTheCollapsingBottomBar() throws {
        let frames = try load(Self.screenshots3)
        let plan = try BatchStitcher().plan(frames)

        #expect(plan.order == Array(0..<frames.count),
                "Screenshots3: recovered \(plan.order.map { Self.screenshots3.names[$0] })")
        #expect(plan.session.segmentBreaks.isEmpty,
                "Screenshots3: split at \(plan.session.segmentBreaks.map(\.afterKeyframeIndex))")
        for (i, expected) in Self.screenshots3.trueDy.enumerated() {
            #expect(abs(plan.session.seams[i].provisionalDy - expected) <= Self.rowTolerance,
                    "Screenshots3 seam \(i): \(plan.session.seams[i].provisionalDy)px, true \(expected)px")
        }

        let records = Dictionary(uniqueKeysWithValues: plan.session.keyframeChrome.map { ($0.keyframeID, $0) })
        #expect(records.count == plan.session.keyframes.count,
                "expected one chrome record per keyframe, got \(records.count)")
        #expect(Set(records.keys) == Set(plan.session.keyframes.map(\.id)),
                "automatic chrome must be keyed by planned keyframe UUIDs")

        let automatic = try plan.session.keyframes.map { keyframe -> ChromeMeasurement in
            try #require(records[keyframe.id]?.automatic,
                         "missing automatic chrome for ordered keyframe \(keyframe.index)")
        }
        let tops = automatic.map(\.insets.top)
        let bottoms = automatic.map(\.insets.bottom)

        #expect(tops.allSatisfy { (180...210).contains($0) },
                "Screenshots3 tops \(tops) should stay around the ~193px status/header chrome")
        #expect((400...455).contains(bottoms[0]),
                "Screenshots3 first bottom \(bottoms[0]) should include the expanded toolbar (~431px)")
        #expect(bottoms.dropFirst().allSatisfy { (145...190).contains($0) },
                "Screenshots3 later bottoms \(bottoms) should collapse to the compact toolbar (~166px)")
        #expect(bottoms[0] - (bottoms.dropFirst().max() ?? 0) >= 200,
                "Screenshots3 first bottom \(bottoms[0]) should be substantially larger than later bottoms \(Array(bottoms.dropFirst()))")
    }

    /// How many times a reference row from `frames[0]` at `sourceRow` survives into `image`.
    /// The technique `DynamicChromeTests` uses, factored out because the two tests below need
    /// opposite answers from it.
    private func barOccurrences(of sourceRow: Int, from frames: [CGImage], in image: CGImage) -> Int {
        let profiler = VerticalProfile()
        let reference = profiler.profile(frames[0], forcingHeight: Self.frameHeight).rows[sourceRow]
        let output = profiler.profile(image, forcingHeight: image.height)
        var runs = 0
        var inRun = false
        for row in output.rows {
            var sum: Float = 0
            for c in 0..<min(row.count, reference.count) { sum += abs(row[c] - reference[c]) }
            let hit = row.count == reference.count && sum / Float(row.count) <= 0.01
            if hit && !inRun { runs += 1 }
            inRun = hit
        }
        return runs
    }

    /// The visible consequence for a set whose bars *are* uniform: the toolbar is cropped from
    /// every strip and survives exactly once, at the bottom.
    ///
    /// The counter-check is what keeps this honest — a green "appears once" proves nothing unless
    /// the same probe can be shown to count the duplicates when the band is zeroed.
    @Test func theBottomBarSurvivesExactlyOnceOnScreenshots4() throws {
        let frames = try load(Self.screenshots4)
        let plan = try BatchStitcher().plan(frames)
        let compositor = Compositor(refinementDelta: 16)
        let source = { (kf: Keyframe) in frames[plan.order[kf.index]] }

        let stitched = try compositor.composite(plan.session, images: source)
        let count = barOccurrences(of: 2700, from: frames, in: stitched)
        #expect(count == 1, "the toolbar appears \(count)x in the \(stitched.width)x\(stitched.height) stitch")

        var unchromed = plan.session
        unchromed.keyframeChrome = unchromed.keyframeChrome.map { KeyframeChrome(keyframeID: $0.keyframeID) }
        let uncropped = try compositor.composite(unchromed, images: source)
        let uncroppedCount = barOccurrences(of: 2700, from: frames, in: uncropped)
        #expect(uncroppedCount == frames.count,
                "with the band zeroed the toolbar should repeat once per keyframe, got \(uncroppedCount); if it does not, the check above cannot see duplicates at all")
    }

    /// A bar that changes size during a capture is cropped using the owning frame's measurement.
    ///
    /// `IMG_1863` carries Chrome's full bottom toolbar (omnibox plus the button row); by `IMG_1864`
    /// it has collapsed to the bare URL pill and stays collapsed. The first keyframe's larger bottom
    /// inset must remove the expanded toolbar while later keyframes use their compact inset.
    ///
    /// Note the shape of this defect: the bar is not *repeated*, it appears exactly once, so the
    /// occurrence-counting check above reports `1` for both the broken and the correct output and
    /// cannot see it. That is why this is a separate test with a different question.
    ///
    @Test func aBarThatCollapsesMidCaptureIsRemovedFromThePage() throws {
        let frames = try load(Self.screenshots3)
        let plan = try BatchStitcher().plan(frames)
        let compositor = Compositor(refinementDelta: 16)
        let stitched = try compositor.composite(plan.session) { frames[plan.order[$0.index]] }

        // Row 2700 sits in IMG_1863's button row, which no other frame has.
        let count = barOccurrences(of: 2700, from: frames, in: stitched)
        #expect(count == 0,
                "IMG_1863's expanded toolbar appears \(count)x in the \(stitched.width)x\(stitched.height) stitch; it is chrome and content continues below it")
    }

    /// A segment break is an evidence boundary: a singleton still owns a chrome record, but no
    /// measurement is borrowed from unrelated frames across the break.
    @Test(arguments: fixtures)
    func singletonSegmentsRemainExplicitlyUnmeasured(_ fixture: Fixture) throws {
        let images = try load(fixture)
        // Force the pathological shape directly rather than waiting for a fixture to break: put the
        // bottom frame first, where nothing above it can overlap, so it lands alone in segment 0
        // while the rest stay a normal multi-frame segment that does measure a band.
        let order = [images.count - 1] + Array(0..<(images.count - 1))
        let plan = try BatchStitcher().plan(images, assumingOrder: order)
        try #require(!plan.session.segmentBreaks.isEmpty,
                     "\(fixture.directory): expected this order to segment")
        let first = try #require(plan.session.keyframes.first)
        let record = try #require(plan.session.keyframeChrome.first { $0.keyframeID == first.id })
        #expect(record.automatic == nil)
        #expect(plan.session.resolvedChrome(for: first).isUnlocked)
    }
}
