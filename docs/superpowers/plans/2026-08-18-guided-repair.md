# Guided Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user fix a bad stitch by dragging the two halves of a join until they line up, with the pixels under the finger being the pixels that get exported.

**Architecture:** Three pure, `nonisolated` value types carry all the logic — which joins are repairable, one join's geometry and drag maths, and whether a condition offers repair — and a single SwiftUI screen renders two full-resolution keyframes with a pinned boundary. Underneath, seam offsets are **frozen into the manifest once at import** so the compositor stops re-deriving geometry on every draw; that is what makes a hand-made alignment survive. Committing goes through `CaptureModel.update(_:)`, which has been waiting for this caller since Spec 1.

**Tech Stack:** SwiftUI (iOS 26), Swift 6 language mode, Swift Concurrency, Core Graphics, Swift Testing, XCTest for UI tests only. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-17-guided-repair-design.md` — read it before starting. Every task argues from it.

## Global Constraints

- **Deployment target is iOS 26.0.** App, extension and `StitchKit` are Swift 6; the Xcode *test* targets are `SWIFT_VERSION = 5.0`.
- **`StitchKit` is not edited.** No source change, no manifest schema change. Its baseline is **180 tests / 28 suites / 1 known issue** and must not move. Verify with `swift test --package-path Seamly/StitchKit`.
- **`SeamlyTests` baseline is 42 passing / 0 failing.** It may only grow.
- **This target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Any type meant to be usable off the main actor must say `nonisolated`. SwiftUI views must **not**.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) everywhere except `SeamlyUITests`, which needs XCTest.
- **`#expect` over `contains(where:)` / `allSatisfy` will not compile** — the macro loses the `rethrows` conversion. Bind to a local first.
- **No pipeline vocabulary in any user-facing string:** never "seam", "chrome", "confidence", "offset", "segment". All user-facing copy goes through `CaptureCondition`. The repair's label is exactly `"Line it up"`, in one place.
- **Never swallow an error.** No `try?` that drops the error, no empty `catch`, no `?? someDefault` masking fallback. Propagate, or handle at the boundary with `Diagnostics` getting the raw error and the user getting `CaptureCondition.message(for:)`.
- **`-only-testing:` needs a trailing `()`** on a Swift Testing function name. Without it xcodebuild matches **zero** tests and still prints "TEST SUCCEEDED". Always read real counts:
  `xcrun xcresulttool get test-results summary --path <result bundle>.xcresult`
- Commit after every task using the `structured-commit` skill.

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `Seamly/Seamly/Features/Repair/RepairableJoins.swift` | Pure: which joins can be lined up, and which one to open on. |
| `Seamly/Seamly/Features/Repair/JoinAlignment.swift` | Pure: one join's geometry, the drag→`dy` mapping, and the clamp. Holds no images. |
| `Seamly/Seamly/Features/Repair/RepairView.swift` | The guided screen: two frames, pinned boundary, one finger, pinch. |
| `Seamly/Seamly/Core/DebugSeed.swift` | `#if DEBUG` only: synthesize a deliberately misaligned capture for the UI test. |
| `Seamly/SeamlyTests/FrozenGeometryTests.swift` | The freeze's safety argument, incl. a real-fixture equivalence. |
| `Seamly/SeamlyTests/RepairableJoinsTests.swift` | Join selection and exclusion. |
| `Seamly/SeamlyTests/JoinAlignmentTests.swift` | Drag maths + the preview-vs-`Compositor` equivalence. |
| `Seamly/SeamlyUITests/RepairUITests.swift` | End-to-end: seeded capture → drag → commit → notice gone. |

**Modified**

| File | Change |
|---|---|
| `Seamly/Seamly/Core/StitchAssembler.swift` | Add `freezeGeometry`; `composite`/`writePDF` default to `refinementDelta: 0`. |
| `Seamly/Seamly/Core/MediaImporter.swift` | Freeze after `resolveGeometry`. |
| `Seamly/Seamly/Core/CaptureModel.swift` | Freeze after `resolveGeometry` in the App Group import; add `joinFrames`. |
| `Seamly/Seamly/DesignSystem/CaptureCondition.swift` | `Imperfection.canBeLinedUp`; `CaptureCondition.offersLiningUp`; the action's title. |
| `Seamly/Seamly/DesignSystem/ConditionNotice.swift` | Optional repair action. |
| `Seamly/Seamly/Features/Result/ResultView.swift` | Loud + quiet entries; `fullScreenCover`. |
| `Seamly/Seamly/Features/Home/HomeView.swift` | An accessibility identifier on the recents thumbnail. |
| `Seamly/Seamly/SeamlyApp.swift` | Call the debug seed. |
| `Seamly/SeamlyTests/CaptureConditionTests.swift` | Extend with the new flags. |

**Why `Features/Repair/` holds three files rather than one:** `RepairableJoins` answers "which join", `JoinAlignment` answers "where do these two frames sit", and `RepairView` draws. Splitting them keeps each reviewable on its own and keeps both pure types testable without a view in the way.

---

### Task 1: Freeze seam offsets into the manifest

This comes first because everything else depends on it. Until the manifest is the authority, a user's drag is re-guessed by the matcher on the next draw.

**Files:**
- Modify: `Seamly/Seamly/Core/StitchAssembler.swift` (add `freezeGeometry`; change `composite` at :97 and `writePDF` at :105)
- Modify: `Seamly/Seamly/Core/MediaImporter.swift:44-45`
- Modify: `Seamly/Seamly/Core/CaptureModel.swift:305-313`
- Test: `Seamly/SeamlyTests/FrozenGeometryTests.swift`

**Interfaces:**
- Consumes: `Compositor.refineSeams(_:images:)`, `StitchAssembler.loadKeyframe(_:in:colorSpace:)`, `StitchAssembler.colorSpace(for:)` — all already exist.
- Produces: `StitchAssembler.freezeGeometry(_ session: StitchSession, in folder: URL, compositor: Compositor = Compositor(refinementDelta: 16)) throws -> StitchSession`

- [ ] **Step 1: Write the failing tests**

Create `Seamly/SeamlyTests/FrozenGeometryTests.swift`:

```swift
import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// Freezing moves seam refinement out of the draw path and into import, so the manifest becomes
/// the authority on geometry. That is what lets a user's hand-made alignment survive — and it is
/// only safe if it changes nothing else, which is what these pin.
struct FrozenGeometryTests {

    // MARK: - Helpers

    /// A tall source with a monotonic vertical ramp (so scroll position is unambiguous) plus
    /// horizontal structure that survives downscaling. Same shape as `BatchAssemblyTests`.
    private func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private func crop(_ image: CGImage, y: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))!
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("frozen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Write `images` as raw keyframes into `folder` and return a manifest referencing them.
    private func stage(_ images: [CGImage], in folder: URL) throws -> StitchSession {
        var session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            colorSpaceName: images[0].colorSpace?.name as String?
        )
        for (i, image) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(image, to: folder.appendingPathComponent(name))
            session.keyframes.append(
                Keyframe(filename: name, pixelWidth: image.width, pixelHeight: image.height, index: i)
            )
        }
        return session
    }

    private func loader(_ session: StitchSession, _ folder: URL) -> (Keyframe) throws -> CGImage {
        let cs = StitchAssembler.colorSpace(for: session)
        return { try StitchAssembler.loadKeyframe($0, in: folder, colorSpace: cs) }
    }

    private func pixelsAreIdentical(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height,
              let da = a.dataProvider?.data, let db = b.dataProvider?.data else { return false }
        return (da as Data) == (db as Data)
    }

    /// The three `Screenshots` fixtures, full resolution (1320×2868), in scroll order. Real
    /// pixels: a synthetic ramp has one unambiguous score minimum, which is exactly the property
    /// that let a green synthetic suite hide a real bug here three times.
    private func realScreenshots() throws -> [CGImage] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // SeamlyTests
            .deletingLastPathComponent()            // Seamly
            .appendingPathComponent("StitchKit/Tests/StitchKitTests/Fixtures/Screenshots")
        return try ["IMG_1757.PNG", "IMG_1758.PNG", "IMG_1759.PNG"].map {
            try KeyframeIO.read(from: dir.appendingPathComponent($0))
        }
    }

    // MARK: - Tests

    /// The contract: a stored offset that is wrong by less than the refinement window is corrected
    /// to the pixel-exact value and *persisted*, instead of being corrected invisibly on every draw.
    @Test func freezingCorrectsAStoredOffsetToThePixelExactValue() throws {
        let folder = try temporaryFolder()
        let source = makeSource(width: 240, height: 1200)
        let trueDy = 300
        var session = try stage([crop(source, y: 0, height: 600), crop(source, y: trueDy, height: 600)], in: folder)
        session.seams = [Seam(fromIndex: 0, provisionalDy: trueDy + 9, confidence: 0.5)]

        let frozen = try StitchAssembler.freezeGeometry(session, in: folder)

        #expect(frozen.seams[0].provisionalDy == trueDy)
        // Everything the planner decided about this seam is left alone, so no user-facing wording
        // shifts as a side effect of freezing.
        #expect(frozen.seams[0].confidence == 0.5)
        #expect(frozen.seams[0].isLowConfidence == false)
    }

    /// The property repair depends on: once frozen, the draw path uses the stored number verbatim.
    /// Output height is a direct read-out of the offset used — with no chrome, a two-frame strip is
    /// `upperHeight + dy` tall — so a re-derived offset would change it.
    @Test func theDrawPathUsesTheStoredOffsetVerbatim() throws {
        let folder = try temporaryFolder()
        let source = makeSource(width: 240, height: 1200)
        var session = try stage([crop(source, y: 0, height: 600), crop(source, y: 300, height: 600)], in: folder)
        // Deliberately not the right answer, and deliberately inside the ±16 window that the old
        // draw path would have "corrected".
        session.seams = [Seam(fromIndex: 0, provisionalDy: 291, confidence: 0.5)]

        let image = try StitchAssembler.composite(session, in: folder)

        #expect(image.height == 600 + 291)
    }

    /// The whole safety argument for moving refinement: today's image is `refine(stored)`, and the
    /// new path is `composite(freeze(stored))` with refinement disabled. Same function, same
    /// inputs, so the bytes must match. On real pixels, because this is precisely where synthetic
    /// fixtures have lied before.
    @Test func freezingThenDrawingMatchesRefiningWhileDrawing() throws {
        let folder = try temporaryFolder()
        let base = try stage(try realScreenshots(), in: folder)
        let coarse = try StitchAssembler.resolveGeometry(base, in: folder, strategy: .recoverOrInputOrder)
        let load = loader(coarse, folder)

        let today = try Compositor(refinementDelta: 16).composite(coarse, images: load)
        let frozen = try StitchAssembler.freezeGeometry(coarse, in: folder)
        let now = try Compositor(refinementDelta: 0).composite(frozen, images: load)

        #expect(pixelsAreIdentical(today, now))
    }

    /// The call site: an import must leave a frozen manifest on disk, or every capture silently
    /// composites from coarse offsets. Compared against the same reference image as above.
    @Test func importingThroughMediaImporterLeavesAFrozenManifest() throws {
        let container = try temporaryFolder()
        let store = SessionStore(containerURL: container)
        let diag = Diagnostics(containerURL: nil, category: .app)
        let images = try realScreenshots()

        let id = try MediaImporter.write(
            images: images, into: store, strategy: .recoverOrInputOrder, source: .photos, diag: diag
        )
        let stored = try store.readManifest(for: id)
        let imported = try StitchAssembler.composite(stored, in: store.folder(for: id))

        let reference = try temporaryFolder()
        let base = try stage(images, in: reference)
        let coarse = try StitchAssembler.resolveGeometry(base, in: reference, strategy: .recoverOrInputOrder)
        let expected = try Compositor(refinementDelta: 16).composite(coarse, images: loader(coarse, reference))

        #expect(pixelsAreIdentical(imported, expected))
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail for the right reason**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t1.xcresult \
  -only-testing:SeamlyTests/FrozenGeometryTests test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/seamly-t1.xcresult
```

Expected: a compile failure — `freezeGeometry` does not exist. **Read the count from `xcresulttool`, not from "TEST SUCCEEDED".**

- [ ] **Step 3: Add `freezeGeometry`**

In `Seamly/Seamly/Core/StitchAssembler.swift`, after `resolveGeometry`:

```swift
    /// Resolve every seam's offset to the pixel-exact value the compositor would have chosen, and
    /// return a manifest that **stores** it.
    ///
    /// Run once, at import, right beside `resolveGeometry` — never on the way to the screen.
    /// `Compositor.composite` used to refine on every draw, which meant the matcher had the last
    /// word on geometry forever: a user's hand-aligned join would be re-searched ±16 px and moved,
    /// silently, the next time anything was drawn. Freezing makes the manifest the authority, so
    /// the composite becomes a pure function of it — which is what non-destructive editing has
    /// always claimed and, until now, was not.
    ///
    /// **Do not call this from `assemble` or any other draw path.** A second pass re-centres the
    /// search window on the new value, so it is not idempotent, and the user's value is by
    /// definition not the matcher's argmin — that is why they had to drag it.
    ///
    /// Only `provisionalDy` is taken from refinement. `confidence`, `isLowConfidence` and
    /// `provisionalDx` stay as the planner left them, so no user-facing wording shifts as a side
    /// effect of freezing.
    nonisolated static func freezeGeometry(
        _ session: StitchSession,
        in folder: URL,
        compositor: Compositor = Compositor(refinementDelta: 16)
    ) throws -> StitchSession {
        let cs = colorSpace(for: session)
        let refined = try compositor.refineSeams(session) { keyframe in
            try loadKeyframe(keyframe, in: folder, colorSpace: cs)
        }
        var frozen = session
        // `refineSeams` maps over `session.seams`, so order and count match exactly. Zipping
        // rather than keying by `fromIndex` avoids trapping on a malformed manifest with a
        // duplicated seam.
        frozen.seams = zip(session.seams, refined).map { stored, refined in
            var updated = stored
            updated.provisionalDy = refined.provisionalDy
            return updated
        }
        return frozen
    }
```

- [ ] **Step 4: Stop the draw path re-deriving geometry**

In the same file, change both defaults. `composite` (currently line 97):

```swift
    /// Composite a session's keyframes into the full-resolution long image.
    ///
    /// `refinementDelta: 0` is load-bearing, not a tuning choice: at delta 0 the search range in
    /// `Compositor.refineVertical` collapses to `lo == hi == provisional`, so the stored offset is
    /// returned untouched. The manifest is the authority — see `freezeGeometry`, which is where
    /// the ±16 px refinement now happens, once, at import.
    nonisolated static func composite(_ session: StitchSession, in folder: URL, compositor: Compositor = Compositor(refinementDelta: 0)) throws -> CGImage {
```

`writePDF` (currently line 105):

```swift
    /// Write a session's PDF to `url`. Frozen geometry for the same reason as `composite`.
    nonisolated static func writePDF(_ session: StitchSession, in folder: URL, to url: URL, compositor: Compositor = Compositor(refinementDelta: 0)) throws {
```

- [ ] **Step 5: Freeze at the two import call sites**

In `Seamly/Seamly/Core/MediaImporter.swift`, replace the `resolveGeometry` + `writeManifest` pair:

```swift
        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: strategy)
        // Freeze here, next to where geometry is derived — never on the draw path. From this point
        // the manifest is the authority on where every join sits.
        let frozen = try StitchAssembler.freezeGeometry(resolved, in: folder)
        try store.writeManifest(frozen)
        diag.log("import[\(source.rawValue)]: \(id.uuidString.prefix(8)) wrote \(images.count) kf, resolved \(frozen.seams.count) seams, \(frozen.segmentBreaks.count) breaks, orderAssumed=\(frozen.orderAssumed)")
        return id
```

In `Seamly/Seamly/Core/CaptureModel.swift`, inside `importFromGroup`'s inner `do` (currently lines 305-313) — note this block already runs only for a session just moved out of the App Group, i.e. exactly a new arrival:

```swift
                            do {
                                let resolved = try StitchAssembler.resolveGeometry(session, in: dest, strategy: .recoverOrInputOrder)
                                // Freeze beside resolution, once. See StitchAssembler.freezeGeometry:
                                // the draw path must never re-derive geometry, or a repaired join
                                // is silently un-repaired on the next launch.
                                let frozen = try StitchAssembler.freezeGeometry(resolved, in: dest)
                                try appStore.writeManifest(frozen)
                                diag.log("import: \(shortID) geometry resolved + frozen (\(frozen.keyframes.count) kf, \(frozen.seams.count) seams, \(frozen.segmentBreaks.count) breaks, orderAssumed=\(frozen.orderAssumed))")
                            } catch {
                                // Non-fatal: keep the extension's manifest so the capture still
                                // imports (it may stitch imperfectly) rather than being lost.
                                diag.log("import: \(shortID) geometry resolve/freeze FAILED, keeping extension manifest: \(error.localizedDescription)")
                            }
```

- [ ] **Step 6: Run the new tests**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t1.xcresult \
  -only-testing:SeamlyTests/FrozenGeometryTests test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/seamly-t1.xcresult
```

Expected: 4 passed, 0 failed. The two real-fixture tests take tens of seconds — that is the fixtures, not a hang.

If `freezingThenDrawingMatchesRefiningWhileDrawing` fails, **stop and report**. It is the one test that can invalidate the whole approach rather than merely the implementation; do not weaken it.

- [ ] **Step 7: Run the whole app suite and the package suite**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-all.xcresult test 2>&1 | tail -5
xcrun xcresulttool get test-results summary --path /tmp/seamly-all.xcresult
swift test --package-path Seamly/StitchKit 2>&1 | tail -5
```

Expected: `SeamlyTests` 46 passing / 0 failing (42 + 4); `StitchKit` 180 tests / 28 suites / 1 known issue, unchanged.

- [ ] **Step 8: Write the decision log**

Create `docs/logs/<today>-01-frozen-geometry.md` using the `structured-commit` skill's log template. It must record: the three approaches from the spec's "Making the drag survive" table and why B and C were rejected; that `assemble` must never freeze and why the idempotence argument is false; and the accepted consequence for dev captures already on disk.

- [ ] **Step 9: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/Core/StitchAssembler.swift Seamly/Seamly/Core/MediaImporter.swift \
        Seamly/Seamly/Core/CaptureModel.swift Seamly/SeamlyTests/FrozenGeometryTests.swift \
        docs/logs/
```

Then commit with the `structured-commit` skill. "What was discovered" must state whether the real-fixture equivalence held byte-for-byte.

---

### Task 2: Decide which joins are repairable

**Files:**
- Create: `Seamly/Seamly/Features/Repair/RepairableJoins.swift`
- Test: `Seamly/SeamlyTests/RepairableJoinsTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `RepairableJoins.walkable(in session: StitchSession) -> [Int]`
  - `RepairableJoins.opening(in session: StitchSession, flaggedOnly: Bool) -> Int?`

- [ ] **Step 1: Write the failing test**

Create `Seamly/SeamlyTests/RepairableJoinsTests.swift`:

```swift
import Testing
import Foundation
import StitchKit
@testable import Seamly

/// Which join the user is taken to, and which they are never offered. Pure, so every case is
/// cheap to pin — and the empty case matters most: offering repair on a capture with nothing to
/// drag would open a screen that cannot do anything.
struct RepairableJoinsTests {

    private func session(seams: [Seam], breaks: [SegmentBreak] = [], keyframes: Int) -> StitchSession {
        StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: (0..<keyframes).map {
                Keyframe(filename: "kf-\($0)", pixelWidth: 100, pixelHeight: 300, index: $0)
            },
            seams: seams,
            segmentBreaks: breaks
        )
    }

    @Test func everyConsecutivePairIsWalkableWhenThereAreNoBreaks() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.8),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.walkable(in: s) == [0, 1])
    }

    /// Nothing overlaps across a break, so there is nothing to line up — and `Compositor.plan`
    /// ignores such a seam anyway, so dragging it would change nothing on screen.
    @Test func aJoinAcrossASegmentBreakIsExcluded() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.8),
            ],
            breaks: [SegmentBreak(afterKeyframeIndex: 0, reason: .lostLock)],
            keyframes: 3
        )
        #expect(RepairableJoins.walkable(in: s) == [1])
    }

    @Test func aCaptureWhoseOnlyJoinIsABreakOffersNothing() {
        let s = session(
            seams: [Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.8)],
            breaks: [SegmentBreak(afterKeyframeIndex: 0, reason: .lostLock)],
            keyframes: 2
        )
        #expect(RepairableJoins.walkable(in: s).isEmpty)
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == nil)
    }

    @Test func opensOnTheLeastConfidentJoin() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.9),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.4),
                Seam(fromIndex: 2, provisionalDy: 100, confidence: 0.7),
            ],
            keyframes: 4
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == 1)
    }

    @Test func tiesBreakOnPositionSoTheChoiceIsDeterministic() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.5),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.5),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == 0)
    }

    /// The loud entry came from a flagged join, so it must land on one — even when an unflagged
    /// join happens to score lower.
    @Test func theLoudEntryPrefersAFlaggedJoinOverALowerScoringUnflaggedOne() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.1, isLowConfidence: false),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.6, isLowConfidence: true),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: true) == 1)
        #expect(RepairableJoins.opening(in: s, flaggedOnly: false) == 0)
    }

    /// Reachable, not theoretical: "some bars may repeat" is counted from chrome records, not seam
    /// confidence, so a capture can offer repair loudly with every seam unflagged.
    @Test func theLoudEntryFallsBackToAllJoinsWhenNothingIsFlagged() {
        let s = session(
            seams: [
                Seam(fromIndex: 0, provisionalDy: 100, confidence: 0.9),
                Seam(fromIndex: 1, provisionalDy: 100, confidence: 0.3),
            ],
            keyframes: 3
        )
        #expect(RepairableJoins.opening(in: s, flaggedOnly: true) == 1)
    }

    /// A seam pointing at a keyframe that is not there is a malformed manifest, not a join.
    @Test func aSeamWithNoSecondKeyframeIsNotAJoin() {
        let s = session(
            seams: [Seam(fromIndex: 5, provisionalDy: 100, confidence: 0.8)],
            keyframes: 2
        )
        #expect(RepairableJoins.walkable(in: s).isEmpty)
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t2.xcresult \
  -only-testing:SeamlyTests/RepairableJoinsTests test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/seamly-t2.xcresult
```

Expected: compile failure — no such type `RepairableJoins`.

- [ ] **Step 3: Implement it**

Create `Seamly/Seamly/Features/Repair/RepairableJoins.swift`:

```swift
import Foundation
import StitchKit

/// Which joins a user can be shown, and which one to open on.
///
/// A "join" is the boundary between keyframe `index` and `index + 1` — the same pair a `Seam`
/// describes. This lives outside the view so the decision is pure and testable: the difference
/// between taking someone to the problem and opening a screen with nothing to drag.
///
/// `nonisolated` because this target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
nonisolated enum RepairableJoins {

    /// Joins the user can actually line up, top to bottom.
    ///
    /// A join across a segment break is excluded: nothing overlaps across a break, so there is
    /// nothing to line up, and `Compositor.plan` ignores that seam when laying out the strip — so
    /// dragging it would move nothing.
    static func walkable(in session: StitchSession) -> [Int] {
        let indices = Set(session.keyframes.map(\.index))
        return session.seams
            .filter { seam in
                indices.contains(seam.fromIndex)
                    && indices.contains(seam.fromIndex + 1)
                    && !session.hasSegmentBreak(after: seam.fromIndex)
            }
            .map(\.fromIndex)
            .sorted()
    }

    /// The join to open on: the least confident, since that is the likeliest reason the user came.
    /// Ties break on position so the choice is deterministic rather than dependent on storage order.
    ///
    /// `flaggedOnly` narrows the ranking to seams the pipeline flagged — the loud entry, which
    /// arrived from a specific complaint. It falls back to the full set when nothing is flagged,
    /// which is reachable rather than theoretical: "some bars may repeat" is counted from chrome
    /// records, not seam confidence, so a capture can offer repair with every seam unflagged.
    static func opening(in session: StitchSession, flaggedOnly: Bool) -> Int? {
        let walkableIndices = Set(walkable(in: session))
        guard !walkableIndices.isEmpty else { return nil }
        let candidates = session.seams.filter { walkableIndices.contains($0.fromIndex) }
        let flagged = candidates.filter(\.isLowConfidence)
        let ranked = (flaggedOnly && !flagged.isEmpty) ? flagged : candidates
        return ranked.min { a, b in
            a.confidence == b.confidence ? a.fromIndex < b.fromIndex : a.confidence < b.confidence
        }?.fromIndex
    }
}
```

- [ ] **Step 4: Run the tests**

Same command as Step 2. Expected: 8 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/Features/Repair/RepairableJoins.swift Seamly/SeamlyTests/RepairableJoinsTests.swift
```

Then commit with the `structured-commit` skill.

---

### Task 3: One join's geometry and the drag maths

**Files:**
- Create: `Seamly/Seamly/Features/Repair/JoinAlignment.swift`
- Test: `Seamly/SeamlyTests/JoinAlignmentTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (`StitchAssembler.composite` from Task 1 is used by a test).
- Produces:
  - `JoinAlignment.init?(session: StitchSession, joinIndex: Int)`
  - `alignment.upperContentBottom: Int`, `.lowerContentTop: Int`, `.lowerContentBottom: Int`, `.lowerPixelHeight: Int`, `.dy: Int`
  - `alignment.lowerSourceStart: Int`
  - `alignment.dyRange: ClosedRange<Int>`
  - `alignment.dy(draggedBy: CGFloat, from: Int, sourcePixelsPerPoint: CGFloat, zoom: CGFloat) -> Int`
  - `mutating alignment.setDy(_ value: Int)`

- [ ] **Step 1: Write the failing test**

Create `Seamly/SeamlyTests/JoinAlignmentTests.swift`:

```swift
import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// `JoinAlignment` is a second copy of the placement rule inside `Compositor.plan`, because `plan`
/// is private and its layout type is internal. Duplicated layout maths that drifts is how a
/// preview starts promising something the exported image will not honour — so the copy is asserted
/// against a real composite here, not trusted.
struct JoinAlignmentTests {

    // MARK: - Helpers

    private func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private func crop(_ image: CGImage, y: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: 0, y: y, width: image.width, height: height))!
    }

    private func twoFrameSession(
        height: Int = 600,
        dy: Int,
        topChrome: Int = 0,
        bottomChrome: Int = 0
    ) -> StitchSession {
        let keyframes = (0..<2).map {
            Keyframe(filename: "kf-\($0).bgra", pixelWidth: 240, pixelHeight: height, index: $0)
        }
        var session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: keyframes,
            seams: [Seam(fromIndex: 0, provisionalDy: dy, confidence: 0.5)]
        )
        session.ensureChromeRecordsForKeyframes()
        if topChrome > 0 || bottomChrome > 0 {
            for keyframe in keyframes {
                session.setChromeOverride(topChrome, for: .top, keyframeID: keyframe.id)
                session.setChromeOverride(bottomChrome, for: .bottom, keyframeID: keyframe.id)
            }
        }
        return session
    }

    // MARK: - Geometry

    @Test func theLowerFrameStartsWhereTheUpperFrameStopsShowingContent() throws {
        let session = twoFrameSession(dy: 250)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(alignment.upperContentBottom == 600)
        #expect(alignment.lowerSourceStart == 350)   // 600 - 250
    }

    @Test func chromeShortensTheUpperFrameAndMovesTheLowerFramesFirstRow() throws {
        let session = twoFrameSession(dy: 250, topChrome: 40, bottomChrome: 30)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(alignment.upperContentBottom == 570)   // 600 - 30
        #expect(alignment.lowerContentTop == 40)
        #expect(alignment.lowerContentBottom == 570)
        #expect(alignment.lowerSourceStart == 320)     // 570 - 250
    }

    /// `Compositor` clamps the lower frame's first row into its content band. The preview must
    /// clamp identically, or it would show rows the export does not draw.
    @Test func theLowerFramesFirstRowIsClampedIntoItsContentBand() throws {
        var session = twoFrameSession(dy: 250, topChrome: 40, bottomChrome: 30)
        session.seams[0].provisionalDy = 10_000
        let wide = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(wide.lowerSourceStart == 40)           // clamped to the top of the content band

        session.seams[0].provisionalDy = -10_000
        let narrow = try #require(JoinAlignment(session: session, joinIndex: 0))
        #expect(narrow.lowerSourceStart == 570)        // clamped to the bottom
    }

    @Test func aJoinWithNoSecondKeyframeCannotBeBuilt() {
        var session = twoFrameSession(dy: 250)
        session.keyframes.removeLast()
        session.keyframeChrome = []
        #expect(JoinAlignment(session: session, joinIndex: 0) == nil)
    }

    // MARK: - The drag

    /// The sign is the load-bearing part of the whole interaction. Dragging down must reveal
    /// earlier content — the lower half's pixels follow the finger.
    @Test func draggingDownRaisesTheOffsetAndDraggingUpLowersIt() throws {
        let session = twoFrameSession(dy: 300)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        let down = alignment.dy(draggedBy: 10, from: 300, sourcePixelsPerPoint: 3, zoom: 1)
        let up = alignment.dy(draggedBy: -10, from: 300, sourcePixelsPerPoint: 3, zoom: 1)

        #expect(down == 330)
        #expect(up == 270)
    }

    /// Zoom is the precision mechanism: magnifying divides how many source pixels a point covers,
    /// which is what makes single-pixel work possible without a separate fine-adjust control.
    @Test func zoomingDividesHowFarTheContentMovesPerPoint() throws {
        let session = twoFrameSession(dy: 300)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        #expect(alignment.dy(draggedBy: 10, from: 300, sourcePixelsPerPoint: 3.3, zoom: 3.3) == 310)
        #expect(alignment.dy(draggedBy: 10, from: 300, sourcePixelsPerPoint: 3.3, zoom: 1) == 333)
    }

    /// Outside this range the compositor's own clamp pins the picture while the finger keeps
    /// going — a dead zone that reads as a broken control. It stops at the edge instead.
    @Test func theOffsetStopsAtTheEdgesOfTheRangeThatActuallyMovesAnything() throws {
        let session = twoFrameSession(dy: 300, topChrome: 40, bottomChrome: 30)
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        #expect(alignment.dyRange.lowerBound == 1)
        #expect(alignment.dyRange.upperBound == 530)   // upperContentBottom 570 - lowerContentTop 40
        #expect(alignment.dy(draggedBy: 100_000, from: 300, sourcePixelsPerPoint: 3, zoom: 1) == 530)
        #expect(alignment.dy(draggedBy: -100_000, from: 300, sourcePixelsPerPoint: 3, zoom: 1) == 1)
    }

    @Test func settingTheOffsetDirectlyIsAlsoClamped() throws {
        let session = twoFrameSession(dy: 300)
        var alignment = try #require(JoinAlignment(session: session, joinIndex: 0))
        alignment.setDy(999_999)
        #expect(alignment.dy == alignment.dyRange.upperBound)
    }

    // MARK: - Equivalence with the real compositor

    /// The test that keeps the duplicated layout maths honest. A real `Compositor` composite of the
    /// same two frames must place the join exactly where `JoinAlignment` says — checked two ways:
    /// the strip's height (a direct read-out of the placement) and the pixels either side of the
    /// boundary.
    @Test func theRealCompositorPlacesTheJoinWhereThisSaysItWill() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("align-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let source = makeSource(width: 240, height: 1400)
        let session = twoFrameSession(dy: 271)          // deliberately not the true offset
        for (i, keyframe) in session.keyframes.enumerated() {
            try KeyframeIO.writeRaw(
                crop(source, y: i * 300, height: 600),
                to: folder.appendingPathComponent(keyframe.filename)
            )
        }
        let alignment = try #require(JoinAlignment(session: session, joinIndex: 0))

        let image = try StitchAssembler.composite(session, in: folder)

        // The strip is: the upper frame's content, then the lower frame from `lowerSourceStart`
        // to its very bottom (content plus whatever bottom chrome it has).
        let expectedHeight = alignment.upperContentBottom
            + alignment.lowerPixelHeight - alignment.lowerSourceStart
        #expect(image.height == expectedHeight)

        // Height alone cannot catch a mirrored axis, so also check the pixels: the composite's
        // first row below the boundary must look far more like the lower frame's
        // `lowerSourceStart` row than like a row well away from it.
        let cs = StitchAssembler.colorSpace(for: session)
        let lower = try StitchAssembler.loadKeyframe(session.keyframes[1], in: folder, colorSpace: cs)
        let atBoundary = try rowDifference(image, row: alignment.upperContentBottom,
                                          lower, row: alignment.lowerSourceStart)
        let wellAway = try rowDifference(image, row: alignment.upperContentBottom,
                                        lower, row: alignment.lowerSourceStart + 40)
        #expect(atBoundary < wellAway / 2)
    }

    /// Mean absolute per-byte difference between one row of each image. Tolerant of colour-space
    /// and alpha handling, discriminating about which row was drawn.
    private func rowDifference(_ a: CGImage, row rowA: Int, _ b: CGImage, row rowB: Int) throws -> Double {
        func bytes(_ image: CGImage, _ row: Int) throws -> [UInt8] {
            let width = image.width
            let cs = CGColorSpaceCreateDeviceGray()
            let ctx = try #require(CGContext(
                data: nil, width: width, height: 1, bitsPerComponent: 8, bytesPerRow: width,
                space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue
            ))
            let crop = try #require(image.cropping(to: CGRect(x: 0, y: row, width: width, height: 1)))
            ctx.interpolationQuality = .none
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: 1))
            let data = try #require(ctx.data)
            return (0..<width).map { data.load(fromByteOffset: $0, as: UInt8.self) }
        }
        let left = try bytes(a, rowA), right = try bytes(b, rowB)
        let total = zip(left, right).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
        return total / Double(min(left.count, right.count))
    }
}
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t3.xcresult \
  -only-testing:SeamlyTests/JoinAlignmentTests test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/seamly-t3.xcresult
```

Expected: compile failure — no such type `JoinAlignment`.

- [ ] **Step 3: Implement it**

Create `Seamly/Seamly/Features/Repair/JoinAlignment.swift`:

```swift
import CoreGraphics
import Foundation
import StitchKit

/// The geometry of one join, and what a finger does to it.
///
/// This mirrors the placement rule in `Compositor.plan` — deliberately, and at a real cost. `plan`
/// is private and its layout type is internal, so the app cannot ask `StitchKit` where a join sits;
/// the only alternative to re-deriving it here is changing the pipeline. Duplicated layout maths
/// that drifts is how a preview starts promising something the exported image will not honour, so
/// `JoinAlignmentTests` asserts this against a real composite instead of trusting it.
///
/// Holds no images: this supplies the numbers, `RepairView` supplies the pixels.
///
/// `nonisolated` because this target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), and drag arithmetic has no business being pinned
/// to an actor.
nonisolated struct JoinAlignment: Equatable {
    /// One past the upper frame's last content row — where the strip stops using it.
    let upperContentBottom: Int
    /// The lower frame's first content row.
    let lowerContentTop: Int
    /// One past the lower frame's last content row.
    let lowerContentBottom: Int
    /// The lower frame's full height, including any bottom chrome — which the strip keeps, because
    /// the last frame's bottom bar is the finished image's bottom bar.
    let lowerPixelHeight: Int
    /// The offset being edited, in source pixels: the join's `Seam.provisionalDy`.
    private(set) var dy: Int

    /// Fails when the manifest does not actually describe this join — a missing keyframe either
    /// side, or no seam for the pair. Better than inventing a placement for a malformed manifest.
    init?(session: StitchSession, joinIndex: Int) {
        guard let upper = session.keyframes.first(where: { $0.index == joinIndex }),
              let lower = session.keyframes.first(where: { $0.index == joinIndex + 1 }),
              let seam = session.seams.first(where: { $0.fromIndex == joinIndex })
        else { return nil }

        let upperChrome = Self.effectiveInsets(session.resolvedChrome(for: upper), height: upper.pixelHeight)
        let lowerChrome = Self.effectiveInsets(session.resolvedChrome(for: lower), height: lower.pixelHeight)

        upperContentBottom = upper.pixelHeight - upperChrome.bottom
        lowerContentTop = lowerChrome.top
        lowerContentBottom = lower.pixelHeight - lowerChrome.bottom
        lowerPixelHeight = lower.pixelHeight
        dy = seam.provisionalDy
    }

    /// `Compositor` falls back to a zero crop when resolved insets are not plausible for the frame
    /// height, so this must too — otherwise the preview would crop rows the export keeps.
    private static func effectiveInsets(_ chrome: ResolvedChrome, height: Int) -> ChromeInsets {
        chrome.insets.isPlausible(forPixelHeight: height) ? chrome.insets : .zero
    }

    /// The lower frame's first drawn row — `Compositor.plan`'s `sourceStart`, clamp included.
    var lowerSourceStart: Int {
        min(max(upperContentBottom - dy, lowerContentTop), lowerContentBottom)
    }

    /// The offsets worth allowing: exactly the span over which `lowerSourceStart` still moves.
    /// Past either edge the compositor's own clamp pins the picture while the finger keeps going,
    /// which reads as a broken control, so the drag stops at the edge instead. No rubber-banding —
    /// a bounce would imply there is something past it.
    var dyRange: ClosedRange<Int> {
        // 1, not 0: a non-advancing join stacks two frames on the same rows, which is not a
        // placement any drag should be able to ask for.
        let lowest = max(1, upperContentBottom - lowerContentBottom)
        let highest = max(lowest, upperContentBottom - lowerContentTop)
        return lowest...highest
    }

    /// The offset for a drag of `translation` points that began with the join at `start`.
    ///
    /// `translation` is SwiftUI's cumulative gesture translation, positive downward, so this is
    /// computed fresh from the gesture's origin on every update rather than accumulated — there is
    /// no running total to drift, and a slow drag cannot judder.
    ///
    /// `sourcePixelsPerPoint` is the 1× ratio of source pixels to points across the frame's width;
    /// dividing by `zoom` is what makes magnification the precision mechanism.
    ///
    /// Dragging **down** raises `dy`, which starts repeating rows the upper frame already showed;
    /// dragging **up** lowers it and starts dropping rows. Lined up is where neither happens.
    func dy(draggedBy translation: CGFloat, from start: Int, sourcePixelsPerPoint: CGFloat, zoom: CGFloat) -> Int {
        let pixels = Double(translation) * Double(sourcePixelsPerPoint) / Double(max(zoom, 0.001))
        return Self.clamp(start + Int(pixels.rounded()), to: dyRange)
    }

    mutating func setDy(_ value: Int) {
        dy = Self.clamp(value, to: dyRange)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 4: Run the tests**

Same command as Step 2. Expected: 9 passed, 0 failed.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/Features/Repair/JoinAlignment.swift Seamly/SeamlyTests/JoinAlignmentTests.swift
```

Then commit with the `structured-commit` skill.

---

### Task 4: Teach `CaptureCondition` that some problems are lined up, not re-recorded

**Files:**
- Modify: `Seamly/Seamly/DesignSystem/CaptureCondition.swift`
- Test: `Seamly/SeamlyTests/CaptureConditionTests.swift`

**Interfaces:**
- Produces:
  - `Imperfection.canBeLinedUp: Bool` (a stored property, set per kind)
  - `CaptureCondition.offersLiningUp: Bool`
  - `CaptureCondition.liningUpActionTitle: String` (`"Line it up"`)

- [ ] **Step 1: Write the failing tests**

Append to `Seamly/SeamlyTests/CaptureConditionTests.swift`, inside the existing `CaptureConditionTests` struct:

```swift
    // MARK: - Which problems a drag can fix

    /// Not the inverse of `recommendsRecordingAgain`. Missing content needs a new recording;
    /// a misjoined image needs a drag; an assumed order needs neither.
    @Test(arguments: [
        (Imperfection.Kind.endedEarly, false),
        (Imperfection.Kind.gaps, false),
        (Imperfection.Kind.unresolvedBars, true),
        (Imperfection.Kind.flaggedJoins, true),
        (Imperfection.Kind.orderAssumed, false),
    ])
    func liningUpHelpsOnlyAlignmentProblems(kind: Imperfection.Kind, expected: Bool) throws {
        let facts: CaptureFacts = switch kind {
        case .endedEarly: CaptureFacts(isIncomplete: true)
        case .gaps: CaptureFacts(segmentBreaks: 1)
        case .unresolvedBars: CaptureFacts(unresolvedChrome: 1)
        case .flaggedJoins: CaptureFacts(flaggedSeams: 1)
        case .orderAssumed: CaptureFacts(orderAssumed: true)
        }
        guard case .imperfect(let primary, _) = CaptureCondition(ready: facts) else {
            Issue.record("expected imperfect for \(kind)"); return
        }
        #expect(primary.kind == kind)
        #expect(primary.canBeLinedUp == expected)
    }

    @Test func aCleanCaptureStillOffersLiningUpQuietly() {
        #expect(CaptureCondition(ready: CaptureFacts()).offersLiningUp)
    }

    /// The discriminating case, and the reason this reads every observation rather than only the
    /// primary: the loudest advice here is "record again", but the image on disk still has a join
    /// worth fixing.
    @Test func anImperfectionThatWantsARerecordDoesNotHideAFixableJoinBehindIt() throws {
        let condition = CaptureCondition(ready: CaptureFacts(flaggedSeams: 1, isIncomplete: true))
        guard case .imperfect(let primary, _) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.kind == .endedEarly)
        #expect(primary.canBeLinedUp == false)
        #expect(condition.recommendsRecordingAgain)
        #expect(condition.offersLiningUp)
    }

    @Test func anImperfectionNoDragCanFixDoesNotOfferLiningUp() {
        #expect(CaptureCondition(ready: CaptureFacts(orderAssumed: true)).offersLiningUp == false)
    }

    @Test func thereIsNothingToLineUpBeforeOrWithoutAnImage() {
        #expect(CaptureCondition.stitching.offersLiningUp == false)
        #expect(CaptureCondition.nothingToStitch.offersLiningUp == false)
        #expect(CaptureCondition.failed("broken").offersLiningUp == false)
    }
```

- [ ] **Step 2: Run and confirm failure**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t4.xcresult \
  -only-testing:SeamlyTests/CaptureConditionTests test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/seamly-t4.xcresult
```

Expected: compile failure — no member `canBeLinedUp`.

- [ ] **Step 3: Add the flag to `Imperfection`**

In `Seamly/Seamly/DesignSystem/CaptureCondition.swift`, after `recommendsRecordingAgain`:

```swift
    /// True when the fix for this observation is lining the join up by hand, rather than recording
    /// again.
    ///
    /// Deliberately **not** the inverse of `recommendsRecordingAgain`: an assumed order is neither
    /// (dragging one join cannot reorder a capture), and "some bars may repeat" is both — no new
    /// recording helps, and lining up genuinely does, because the rows hidden behind an undetected
    /// bar come back once the two halves are continuous. The band itself stays; removing it is not
    /// this gesture's job, and cannot be folded into it (see the spec's "Out of scope").
    let canBeLinedUp: Bool
```

Then give every case a value in the private `init?(kind:facts:)` — `.endedEarly` and `.gaps` and `.orderAssumed` get `canBeLinedUp: false`, `.unresolvedBars` and `.flaggedJoins` get `true`. For example, `.flaggedJoins` becomes:

```swift
        case .flaggedJoins:
            guard facts.flaggedSeams > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "A join may not line up",
                detail: Self.count(facts.flaggedSeams, "join", "joins") + " might be slightly off.",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: true
            )
```

- [ ] **Step 4: Add the condition-level members**

In the same file, beside `recommendsRecordingAgain`:

```swift
    /// Whether the result screen should offer the repair at all.
    ///
    /// Read over **every** observation, unlike `recommendsRecordingAgain`, which reads only the
    /// primary: a capture can have ended early *and* have a join worth fixing, and "record again"
    /// being the loudest advice does not make the image already on disk unfixable.
    ///
    /// A clean capture offers it too — quietly. This app's own history is that a green verdict has
    /// been confidently wrong, so flagged-only entry would leave a visibly bad stitch with no
    /// recourse but re-recording. Whether there is actually a join to drag is a question about the
    /// session, not about this verdict, and belongs to `RepairableJoins`.
    var offersLiningUp: Bool {
        switch self {
        case .clean: true
        case .imperfect(_, let all): all.contains(where: \.canBeLinedUp)
        case .stitching, .nothingToStitch, .failed: false
        }
    }

    /// The one label for the repair, wherever it appears. An imperfect capture shows it loudly and
    /// a clean one quietly, but the words are identical — so this stays the only place the string
    /// lives, which is the whole point of this type.
    static let liningUpActionTitle = "Line it up"
```

- [ ] **Step 5: Run the tests**

Same command as Step 2. Expected: 42-suite total rises; `CaptureConditionTests` all pass (the argument-based test counts as 5 cases).

- [ ] **Step 6: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/DesignSystem/CaptureCondition.swift Seamly/SeamlyTests/CaptureConditionTests.swift
```

Then commit with the `structured-commit` skill.

---

### Task 5: The repair screen

**Files:**
- Create: `Seamly/Seamly/Features/Repair/RepairView.swift`
- Modify: `Seamly/Seamly/Core/CaptureModel.swift` (add `joinFrames`)

**Interfaces:**
- Consumes: `JoinAlignment` (Task 3), `RepairableJoins.walkable(in:)` (Task 2), `CaptureCondition.liningUpActionTitle` (Task 4), `ZoomState`, `CaptureModel.update(_:)`, `CaptureModel.CaptureError.notFound`.
- Produces:
  - `CaptureModel.joinFrames(_ id: UUID, joinIndex: Int) async throws -> (upper: CGImage, lower: CGImage)`
  - `RepairView(captureID: UUID, model: CaptureModel, openingJoin: Int)`

This task has no unit test: it is a view. It is verified by a build, by `#Preview`, and by running the app and looking at it. The end-to-end gate is Task 7.

- [ ] **Step 1: Add `joinFrames` to `CaptureModel`**

In `Seamly/Seamly/Core/CaptureModel.swift`, after `fullComposite`:

```swift
    /// Load the two full-resolution keyframes either side of a join, off the main actor.
    ///
    /// Full resolution deliberately, and never the display proxy: the repair surface is where a
    /// user judges single-pixel alignment, so a downscaled image would have them lining up
    /// something the export does not draw. One pair at a time — never the whole set.
    func joinFrames(_ id: UUID, joinIndex: Int) async throws -> (upper: CGImage, lower: CGImage) {
        guard let capture = captures.first(where: { $0.id == id }) else { throw CaptureError.notFound }
        let session = capture.session, folder = capture.folder
        guard let upper = session.keyframes.first(where: { $0.index == joinIndex }),
              let lower = session.keyframes.first(where: { $0.index == joinIndex + 1 })
        else { throw CaptureError.notFound }
        let diag = self.diag
        let result: Result<(upper: CGImage, lower: CGImage), Error> = await Task.detached {
            do {
                let cs = StitchAssembler.colorSpace(for: session)
                return .success((
                    upper: try StitchAssembler.loadKeyframe(upper, in: folder, colorSpace: cs),
                    lower: try StitchAssembler.loadKeyframe(lower, in: folder, colorSpace: cs)
                ))
            } catch {
                return .failure(error)
            }
        }.value
        // Log the raw error and rethrow: `Diagnostics` is the only window into a device failure,
        // and the caller still has to tell the user what went wrong in their own language.
        if case .failure(let error) = result {
            diag.log("joinFrames: \(session.id.uuidString.prefix(8)) join \(joinIndex) FAILED: \(error) (\(error.localizedDescription))")
        }
        return try result.get()
    }
```

- [ ] **Step 2: Write `RepairView`**

Create `Seamly/Seamly/Features/Repair/RepairView.swift`:

```swift
import SwiftUI
import CoreGraphics
import StitchKit

/// Lining up one join, by dragging the lower half until the two halves meet.
///
/// The boundary is pinned to the middle of the screen and never moves; what moves is the lower
/// frame's content, tracking the finger one-to-one in displayed pixels. That is the entire
/// interaction. There is no offset field, no bar control, no per-join list, and nothing here says
/// "seam", "chrome" or "confidence" — the words the user reads all come from `CaptureCondition`.
///
/// Pinch is also the precision mechanism: at 1× a point is roughly three source pixels on this
/// hardware, so pixel-exact work needs magnification rather than a second, finer control. There is
/// deliberately **no panning** — one finger always means "line it up" — so at high zoom only the
/// middle of the frame's width is visible.
struct RepairView: View {
    let captureID: UUID
    let model: CaptureModel
    /// Where to start, from `RepairableJoins.opening(in:flaggedOnly:)`.
    let openingJoin: Int

    @Environment(\.dismiss) private var dismiss

    @State private var joins: [Int] = []
    @State private var position = 0
    @State private var frames: (upper: CGImage, lower: CGImage)?
    @State private var alignment: JoinAlignment?
    /// Offsets the user has changed, by join index. Empty means nothing to write.
    @State private var edited: [Int: Int] = [:]
    /// The offset this drag started from, so a cumulative translation maps to an absolute offset.
    @State private var dragStart: Int?
    @State private var zoom = ZoomState()
    @State private var loadError: String?
    @State private var busy = false

    private var session: StitchSession? {
        model.captures.first { $0.id == captureID }?.session
    }

    private var currentJoin: Int? {
        joins.indices.contains(position) ? joins[position] : nil
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(CaptureCondition.liningUpActionTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { commit() }.disabled(busy)
                    }
                }
                .safeAreaInset(edge: .bottom) { positionBar }
        }
        .task {
            guard let session else { return }
            joins = RepairableJoins.walkable(in: session)
            position = joins.firstIndex(of: openingJoin) ?? 0
        }
        .task(id: position) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            ContentUnavailableView {
                Label("Can't show this join", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            }
        } else if let frames, let alignment {
            GeometryReader { viewport in
                halves(in: viewport.size, frames: frames, alignment: alignment)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(in: viewport.size, frames: frames))
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { zoom.update(magnification: $0.magnification) }
                            .onEnded { _ in withAnimation(.snappy) { zoom.end() } }
                    )
                    .accessibilityIdentifier("repair-canvas")
                    .accessibilityLabel("The two halves of this join")
                    .accessibilityHint("Drag up or down to line them up. Pinch to zoom in.")
            }
            .background(.black)
            .ignoresSafeArea(edges: .horizontal)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The upper frame's tail above a pinned boundary, the lower frame's head below it. Each half
    /// is a clipped window onto a full-resolution frame, offset so the right source row lands on
    /// the boundary — so what the user sees is exactly the placement `JoinAlignment` describes and
    /// `Compositor` will draw.
    private func halves(in size: CGSize, frames: (upper: CGImage, lower: CGImage), alignment: JoinAlignment) -> some View {
        let scale = pointsPerSourcePixel(in: size, frames: frames)
        let boundary = size.height / 2
        return VStack(spacing: 0) {
            window(
                frames.upper,
                width: size.width * zoom.scale,
                offsetY: boundary - CGFloat(alignment.upperContentBottom) * scale,
                size: CGSize(width: size.width, height: boundary)
            )
            window(
                frames.lower,
                width: size.width * zoom.scale,
                offsetY: -CGFloat(alignment.lowerSourceStart) * scale,
                size: CGSize(width: size.width, height: size.height - boundary)
            )
        }
    }

    /// A clipped window onto one frame, offset so a chosen source row lands where it belongs.
    ///
    /// The upper window shows rows *above* `upperContentBottom`, which in the real strip come from
    /// the previous frame — identical content, since that is what overlap means. The one thing that
    /// would differ is this frame's own top bar, and the window cannot reach it: half a screen is
    /// at most a few hundred source pixels at 1×, while a frame is thousands tall, and zooming only
    /// narrows the window further.
    private func window(_ image: CGImage, width: CGFloat, offsetY: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: width, height: width * CGFloat(image.height) / CGFloat(max(image.width, 1)))
                .offset(y: offsetY)
        }
        .frame(width: size.width, height: max(size.height, 0), alignment: .topLeading)
        .clipped()
    }

    /// Displayed points per source pixel at the current zoom.
    private func pointsPerSourcePixel(in size: CGSize, frames: (upper: CGImage, lower: CGImage)) -> CGFloat {
        size.width * zoom.scale / CGFloat(max(frames.upper.width, 1))
    }

    private func dragGesture(in size: CGSize, frames: (upper: CGImage, lower: CGImage)) -> some Gesture {
        // The 1× ratio; `JoinAlignment` divides by the zoom itself.
        let sourcePixelsPerPoint = CGFloat(frames.upper.width) / max(size.width, 1)
        return DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard var alignment, let join = currentJoin else { return }
                let start = dragStart ?? alignment.dy
                dragStart = start
                let next = alignment.dy(
                    draggedBy: value.translation.height,
                    from: start,
                    sourcePixelsPerPoint: sourcePixelsPerPoint,
                    zoom: zoom.scale
                )
                alignment.setDy(next)
                self.alignment = alignment
                edited[join] = next
            }
            .onEnded { _ in dragStart = nil }
    }

    /// Where the user is, not a menu of places to go: chevrons and a count, so a join we never
    /// flagged is still reachable without building a picker.
    @ViewBuilder
    private var positionBar: some View {
        if joins.count > 1 {
            HStack(spacing: 24) {
                Button {
                    position -= 1
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(position == 0 || busy)
                .accessibilityLabel("Previous join")

                Text("\(position + 1) of \(joins.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    position += 1
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(position >= joins.count - 1 || busy)
                .accessibilityLabel("Next join")
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private func load() async {
        guard let session, let join = currentJoin else { return }
        loadError = nil
        zoom.reset()
        frames = nil
        var next = JoinAlignment(session: session, joinIndex: join)
        // Carry an unsaved edit across a move between joins, so paging away and back does not
        // silently discard the user's work.
        if let dy = edited[join] { next?.setDy(dy) }
        guard next != nil else {
            loadError = "This part of the capture is missing, so there's nothing to line up."
            return
        }
        do {
            let loaded = try await model.joinFrames(captureID, joinIndex: join)
            frames = loaded
            alignment = next
        } catch {
            // The model logged the raw error; this is the sentence a person can read.
            loadError = CaptureCondition.message(for: error)
        }
    }

    private func commit() {
        guard !edited.isEmpty, var session else { dismiss(); return }
        busy = true
        Task {
            defer { busy = false }
            for (join, dy) in edited {
                guard let index = session.seams.firstIndex(where: { $0.fromIndex == join }) else { continue }
                session.seams[index].provisionalDy = dy
                // The user has now looked at this join with their own eyes. Leaving it flagged
                // would put "a join may not line up" back on the result screen over a join they
                // just lined up themselves. This also drops the flag's other meaning, a nonzero
                // horizontal component — which `Compositor` never applies, so nothing is lost but
                // the badge.
                session.seams[index].isLowConfidence = false
            }
            await model.update(session)
            dismiss()
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`. Fix any Swift 6 isolation complaints by annotating the *pure* type, never the view.

- [ ] **Step 4: Run the full app suite**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t5.xcresult test 2>&1 | tail -5
xcrun xcresulttool get test-results summary --path /tmp/seamly-t5.xcresult
```

Expected: no regressions.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/Features/Repair/RepairView.swift Seamly/Seamly/Core/CaptureModel.swift
```

Then commit with the `structured-commit` skill.

---

### Task 6: Wire the two entries

**Files:**
- Modify: `Seamly/Seamly/DesignSystem/ConditionNotice.swift`
- Modify: `Seamly/Seamly/Features/Result/ResultView.swift`

**Interfaces:**
- Consumes: `CaptureCondition.offersLiningUp`, `CaptureCondition.liningUpActionTitle` (Task 4), `RepairableJoins.opening(in:flaggedOnly:)` (Task 2), `RepairView` (Task 5).
- Produces: `ConditionNotice(condition:onLineUp:)` — `onLineUp` defaults to `nil`.

- [ ] **Step 1: Give `ConditionNotice` the loud action**

In `Seamly/Seamly/DesignSystem/ConditionNotice.swift`, add the property and render it:

```swift
struct ConditionNotice: View {
    let condition: CaptureCondition
    /// Supplied when this capture has a join the user can line up. The notice is where the loud
    /// entry belongs: it is already the thing that told them something looks off, so the fix sits
    /// on the complaint rather than somewhere else on the screen.
    var onLineUp: (() -> Void)?
```

Then, at the end of the `VStack` inside `imperfect(primary:all:)`, after the `DisclosureGroup`:

```swift
            if let onLineUp {
                Button(CaptureCondition.liningUpActionTitle, action: onLineUp)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.subheadline)
            }
```

- [ ] **Step 2: Wire both entries in `ResultView`**

In `Seamly/Seamly/Features/Result/ResultView.swift`, add state and the target type:

```swift
    /// A join to open the repair on. A wrapper rather than a bare `Int` so `fullScreenCover(item:)`
    /// can identify it.
    private struct RepairTarget: Identifiable {
        let id: Int
    }

    @State private var repairTarget: RepairTarget?
```

Add the derivation:

```swift
    /// The join the repair should open on, or `nil` when this capture has nothing to line up.
    ///
    /// Two independent questions, deliberately kept apart: whether the *verdict* offers repair
    /// (`CaptureCondition.offersLiningUp`) and whether the *session* actually has a draggable join
    /// (`RepairableJoins`). A two-frame capture split by a segment break passes the first and fails
    /// the second, and opening a screen with nothing to drag would be worse than no entry at all.
    private var repairOpening: Int? {
        guard condition.offersLiningUp, let session = capture?.session else { return nil }
        let flaggedOnly = if case .imperfect = condition { true } else { false }
        return RepairableJoins.opening(in: session, flaggedOnly: flaggedOnly)
    }
```

Pass the loud action into the notice (in the `.clean, .imperfect` arm):

```swift
                    VStack(spacing: 0) {
                        ConditionNotice(
                            condition: condition,
                            onLineUp: repairOpening.map { join in { repairTarget = RepairTarget(id: join) } }
                        )
                        CaptureCanvas(proxy: proxy)
                    }
```

Add the quiet entry and the cover as modifiers on the `Group`, beside `.navigationTitle`:

```swift
        // The quiet entry. A clean capture gets the same words, in the toolbar rather than in a
        // notice — this app has shipped a confidently wrong "clean" verdict before, so a stitch we
        // judged fine still needs a way in. It stays out of the bottom bar, which already stacks
        // Save, the export row, and up to two more rows.
        .toolbar {
            if case .clean = condition, let join = repairOpening {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CaptureCondition.liningUpActionTitle) {
                        repairTarget = RepairTarget(id: join)
                    }
                    .font(.subheadline)
                }
            }
        }
        // Full screen rather than a push: a single-purpose surface with its own Cancel and Done,
        // and pushing it would sit a second back-chevron next to this screen's.
        .fullScreenCover(item: $repairTarget) { target in
            RepairView(captureID: captureID, model: model, openingJoin: target.id)
        }
```

- [ ] **Step 3: Build**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run the full app suite**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t6.xcresult test 2>&1 | tail -5
xcrun xcresulttool get test-results summary --path /tmp/seamly-t6.xcresult
```

Expected: no regressions.

- [ ] **Step 5: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/DesignSystem/ConditionNotice.swift Seamly/Seamly/Features/Result/ResultView.swift
```

Then commit with the `structured-commit` skill.

---

### Task 7: Seed a misaligned capture, and prove the whole path end to end

**Files:**
- Create: `Seamly/Seamly/Core/DebugSeed.swift`
- Create: `Seamly/SeamlyUITests/RepairUITests.swift`
- Modify: `Seamly/Seamly/SeamlyApp.swift`
- Modify: `Seamly/Seamly/Features/Home/HomeView.swift` (accessibility identifier on the recents thumbnail)

**Interfaces:**
- Consumes: everything above.
- Produces: `DebugSeed.seedIfRequested()` — a no-op unless the launch argument is present, and absent entirely from release builds.

- [ ] **Step 1: Write the debug seed**

Create `Seamly/Seamly/Core/DebugSeed.swift`:

```swift
#if DEBUG
import CoreGraphics
import Foundation
import StitchKit

/// Writes one deliberately misaligned capture into app storage, so a UI test can reach the repair
/// screen without driving the system photo picker.
///
/// **Debug builds only, and only when asked.** Spec 1 deferred UI-test seeding rather than adding
/// test-only hooks; this reverses that for the repair screen specifically, because the picker's
/// cells carry no distinguishing labels — a test that taps them is exactly the test that keeps
/// passing while the screen is broken, which this project has already shipped once (an invisible
/// record button survived 42 unit tests, 4 UI tests and eleven reviews).
///
/// The frames are synthesized rather than bundled: no binary asset, deterministic, and the stored
/// offset can be made wrong on purpose so there is genuinely something to fix.
enum DebugSeed {
    static let launchArgument = "-SeamlySeedMisalignedCapture"

    /// A fixed id, so repeated launches replace the seed instead of piling up captures.
    private static let id = UUID(uuidString: "5EED0000-0000-0000-0000-00000000C0DE")!

    private static let frameWidth = 300
    private static let frameHeight = 700
    /// What the frames were actually cropped at.
    private static let trueDy = 360
    /// What the manifest claims, which is what the user has to drag away. Far enough out to be
    /// obvious on screen, and far outside the ±16 px the old draw path would have quietly fixed.
    private static let storedDy = 300

    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        do {
            try seed()
        } catch {
            // A failed seed must be loud: the UI test that depends on it would otherwise fail
            // somewhere far away, looking like a bug in the repair screen.
            print("Seamly: DebugSeed FAILED: \(error)")
        }
    }

    private static func seed() throws {
        let store = SessionStore(containerURL: CaptureModel.appContainerURL())
        try? store.delete(id)   // best-effort: nothing to remove on a clean install
        let folder = try store.createFolder(for: id)

        let source = makeSource(width: frameWidth, height: frameHeight + trueDy)
        var session = StitchSession(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            colorSpaceName: source.colorSpace?.name as String?
        )
        for index in 0..<2 {
            let name = String(format: "kf-%04d.bgra", index)
            let crop = source.cropping(to: CGRect(
                x: 0, y: index * trueDy, width: frameWidth, height: frameHeight
            ))!
            try KeyframeIO.writeRaw(crop, to: folder.appendingPathComponent(name))
            session.keyframes.append(
                Keyframe(filename: name, pixelWidth: frameWidth, pixelHeight: frameHeight, index: index)
            )
        }
        // Wrong on purpose, and flagged — so the result screen shows the loud entry and the notice
        // has something to stop saying once the join is lined up.
        session.seams = [
            Seam(fromIndex: 0, provisionalDy: storedDy, confidence: 0.2, isLowConfidence: true)
        ]
        session.ensureChromeRecordsForKeyframes()
        // Deliberately *not* frozen: freezing happens at import, and this capture never goes
        // through one. That is what leaves the wrong offset in place for the test to drag away.
        try store.writeManifest(session)
    }

    /// A monotonic vertical ramp so vertical position is unambiguous, plus horizontal structure so
    /// a misalignment is visible to a human looking at the screen.
    private static func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let stripe = (y % 40 < 6) ? 90.0 : 0
                let v = 50.0 + Double(y) * (120.0 / Double(height)) + stripe
                    + 40 * sin(Double(x) * 0.3)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
#endif
```

- [ ] **Step 2: Call it, and label the recents thumbnail**

In `Seamly/Seamly/SeamlyApp.swift`:

```swift
@main
struct SeamlyApp: App {
    init() {
        #if DEBUG
        DebugSeed.seedIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

In `Seamly/Seamly/Features/Home/HomeView.swift`, on the recents `Button` inside `ForEach`:

```swift
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("recent-capture")
```

An identifier, not a behaviour hook: the thumbnail's only label is a localized date, which a test cannot match reliably.

- [ ] **Step 3: Write the UI test**

Create `Seamly/SeamlyUITests/RepairUITests.swift`:

```swift
import XCTest

/// The end-to-end gate for guided repair: a seeded, deliberately misaligned capture is opened, its
/// join is dragged, and the change is committed. The assertion is that the notice which said the
/// join might not line up is *gone* — which can only happen if the drag registered, the manifest
/// was rewritten, and the capture re-composited from it.
final class RepairUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiningUpAJoinClearsTheNotice() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // A seeded capture is not a new arrival, so nothing pushes to it — it appears in recents.
        let thumbnail = app.buttons["recent-capture"].firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 30), "the seeded capture never appeared")
        thumbnail.tap()

        let notice = app.staticTexts["A join may not line up"]
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "the seeded capture was not flagged")

        app.buttons["Line it up"].tap()

        let canvas = app.otherElements["repair-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "the repair screen never loaded")

        // Drag the lower half up. The seed stores an offset 60 px short of the truth, so this only
        // has to move it — the assertion is about the commit, not about pixel perfection.
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.2, thenDragTo: to)

        app.buttons["Done"].tap()

        XCTAssertTrue(
            notice.waitForNonExistence(timeout: 60),
            "the join was still flagged after being lined up — the edit did not reach the manifest"
        )
    }

    /// Same conditional dance as `SeamlyUITests`: onboarding shows only on a fresh install, and its
    /// button reads "Next" until the last page.
    @MainActor
    private func dismissOnboardingIfPresented(_ app: XCUIApplication) {
        let next = app.buttons["Next"]
        let getStarted = app.buttons["Get Started"]
        guard next.waitForExistence(timeout: 5) || getStarted.exists else { return }
        while next.exists { next.tap() }
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "onboarding never offered a way out")
        getStarted.tap()
    }
}
```

- [ ] **Step 4: Run the UI test**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-t7.xcresult \
  -only-testing:SeamlyUITests/RepairUITests test 2>&1 | tail -20
xcrun xcresulttool get test-results summary --path /tmp/seamly-t7.xcresult
```

Expected: 1 passed. If the app was previously installed on this simulator, `hasSeenOnboarding` may already be set — the helper handles both.

- [ ] **Step 5: Prove the test discriminates**

A UI test that cannot fail is worse than none. Temporarily make `RepairView.commit()` dismiss without writing:

```swift
    private func commit() { dismiss() }
```

Re-run Step 4 and confirm it **fails** on the final assertion. Then revert the change and confirm it passes again. Record both outcomes in the commit message.

- [ ] **Step 6: Run everything**

```bash
cd /Users/leo/Developer/Seamly.app
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath /tmp/seamly-final.xcresult test 2>&1 | tail -5
xcrun xcresulttool get test-results summary --path /tmp/seamly-final.xcresult
swift test --package-path Seamly/StitchKit 2>&1 | tail -5
```

Expected: `SeamlyTests` well above its 42 baseline with 0 failures; `SeamlyUITests` 5 passing; `StitchKit` **180 tests / 28 suites / 1 known issue, unchanged**. If the `StitchKit` numbers moved at all, something edited the package — stop and report.

- [ ] **Step 7: Run the app and look at it**

Not optional, and not replaceable by the tests above. This project has shipped a hero button that was invisible in dark mode past 42 unit tests, 4 UI tests, ten task reviews and a whole-branch review.

```bash
cd /Users/leo/Developer/Seamly.app
xcrun simctl boot "iPhone 17" 2>/dev/null; xcrun simctl bootstatus "iPhone 17" -b
APP=$(xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{d=$2} / FULL_PRODUCT_NAME/{n=$2} END{print d"/"n}')
xcrun simctl install "iPhone 17" "$APP"
xcrun simctl launch "iPhone 17" io.github.lilikazine.Seamly --args -SeamlySeedMisalignedCapture
```

Then drive it with `sim-use` (`describe-ui`, `tap`, `swipe`, `gesture pinch-out`, `screenshot`) and check, in **both** appearances (`xcrun simctl ui "iPhone 17" appearance dark` / `light`):

- The seeded stitch is visibly misaligned at the join before repair, and visibly aligned after.
- "Line it up" is legible in both appearances, in the notice and in the toolbar.
- Dragging moves the lower half and *only* the lower half, and the boundary stays put.
- Pinch magnifies about the boundary and the drag gets correspondingly finer.
- The chevrons and the "n of m" indicator do not appear for a single-join capture.
- **Double-tap the result screen's canvas with a real finger** and confirm it zooms back out — the one behaviour that could not be verified while writing the spec.

Attach screenshots to the commit message or the decision log.

- [ ] **Step 8: Write the decision log and update the spec's status**

Create `docs/logs/<today>-02-guided-repair.md` per the `structured-commit` template. Record the interaction decisions (pinned boundary, zoom as the precision mechanism, no panning), the entry-condition decision, the reversal on UI-test seeding, and anything the manual pass found that the tests did not.

Update `docs/superpowers/specs/2026-08-17-guided-repair-design.md`'s status line from "Approved (brainstorming)" to "Implemented", and strike the double-tap row in its verification table with the manual result.

- [ ] **Step 9: Commit**

```bash
cd /Users/leo/Developer/Seamly.app
git add Seamly/Seamly/Core/DebugSeed.swift Seamly/Seamly/SeamlyApp.swift \
        Seamly/Seamly/Features/Home/HomeView.swift Seamly/SeamlyUITests/RepairUITests.swift \
        docs/logs/ docs/superpowers/specs/2026-08-17-guided-repair-design.md
```

Then commit with the `structured-commit` skill.

---

## Also update the project's own documentation

Fold into Task 7's commit, or a follow-up commit if it grows:

- `CLAUDE.md` — the "Status" section says `EditView` and the seam controls were removed "pending a guided-repair spec" and that there is **no way to fix a bad stitch**. That stops being true with this work. Also worth recording under "Gotchas": `StitchAssembler.composite` no longer refines, and freezing must never move to the draw path.
- `README.md` — if it describes the result screen's actions, add the repair.
- `DECISIONS.md` — the frozen-geometry decision belongs there alongside the other load-bearing conventions, since a future reader who re-adds refinement to the draw path would silently break every repair.

## Where this deviates from the spec

Small, deliberate, and called out so a reviewer does not have to notice them:

- **`HomeView` gains an accessibility identifier** (`"recent-capture"`), which the spec's
  files-touched table does not list. A seeded capture is not a new arrival, so nothing auto-pushes
  to it and the UI test has to tap the recents thumbnail — whose only label is a localized date.
  An identifier, not a behaviour hook.
- **The debug seed is its own file** (`Core/DebugSeed.swift`) rather than code inside
  `SeamlyApp.swift`, so the whole test-only surface sits behind one `#if DEBUG` in one place.
- **The drag does not accumulate a running total.** The spec describes accumulating a `Double`
  across the gesture and rounding once; SwiftUI's `DragGesture` reports translation cumulatively
  from the gesture's origin, so `JoinAlignment` recomputes an absolute offset each update instead.
  Same goal — nothing to drift, no judder — with no state to get wrong.
- **The freeze is not keyed off `newArrivals` explicitly.** The spec's table describes it that way,
  but `importFromGroup`'s `resolveGeometry` block already runs only for a session just moved out of
  the App Group, so placing the freeze inside it *is* the new-arrival path. Nothing needs threading.

## Notes for whoever executes this

- **Task 1 is the load-bearing one.** If `freezingThenDrawingMatchesRefiningWhileDrawing` fails on real fixtures, the spec's chosen approach is wrong and the right move is to stop and report, not to loosen the assertion. The spec names the alternative that was rejected for being a `StitchKit` change (`Seam.userDy`), and reopening that is the user's call.
- **Do not add geometry computation to the draw path** — the invariant this whole plan rests on. `freezeGeometry` is called from imports only.
- **The two pure types are where the confidence lives.** If a behaviour is hard to test through `RepairView`, that is a sign it belongs in `JoinAlignment` or `RepairableJoins` instead.
- The real-fixture tests take tens of seconds each. That is the fixtures, not a hang. Use `--filter`-style `-only-testing:` while iterating — **with the trailing `()`**.
