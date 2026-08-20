# Paper Interface Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Seamly's SwiftUI interface to `design-system/` — six screens on the design's tokens and components, with the engine untouched except for one additive read-only accessor.

**Architecture:** `StitchKit` gains `Compositor.placement`, a public read-only view of the layout the private `plan` already computes, so the app can ask where any join sits in the composite. On top of that the app grows one pure geometry function and one findings layer, then a `CaptureView` in which the image, the seam marks, the margin markers and the position scale are all drawn from a single `scrollY` in a single `GeometryReader` — which is what makes "findability lives in the margin" hold. Screens are replaced one at a time, with the old screen staying reachable until its replacement exists, so the suite is green at every commit.

**Tech Stack:** Swift 6 language mode, SwiftUI, iOS 26.0 deployment target, Swift Testing (`import Testing`) except `SeamlyUITests` (XCTest). First-party frameworks only.

**Spec:** `docs/superpowers/specs/2026-08-20-paper-interface-design.md` — read it before Task 1. The plan argues from the spec; both travel together.

## Global Constraints

Every task's requirements implicitly include all of these.

- **Swift 6 language mode** for the app, extension and `StitchKit`. Test targets are on `SWIFT_VERSION = 5.0` except `StitchKit`'s own.
- **The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.** Any pure type meant to be usable off the main actor must say `nonisolated`. SwiftUI views must **not**.
- **Swift Concurrency, never GCD.** `async`/`await`, `Task`, structured concurrency. Actors and `@MainActor`, never locks.
- **First-party frameworks only.** No third-party dependencies.
- **Never swallow an error, never show a raw one.** No bare `try?` that drops the error, no empty `catch {}`, no `?? someDefault` masking. User-visible text goes through `CaptureCondition.message(for:)`; the raw error goes to `Diagnostics`.
- **`SeamlyColor.sheet` is fixed white in BOTH themes.** Never replace it with a semantic background. A capture has its own brightness and must never be dimmed.
- **`SeamlyColor.markRec` is iOS system red** (`0xFF3B30`) for the live broadcast indicator. Never restyle.
- **Sheets are square** — `SeamlyRadius.sheet = 0`. Rounding is for controls only.
- **State is never colour alone.** Every mark carries its word.
- **Colour tokens are contrast-solved, not chosen by eye.** Every one clears 4.5:1 against its ground. Changing one means re-measuring it against `design-system/tokens/colors.css`.
- **Size classes, never pixel breakpoints.** `@Environment(\.horizontalSizeClass)` / `\.verticalSizeClass`, via `SeamlyLayout`. Do not port `--bp-regular: 700px` or `--vp-short: 500px`.
- **`.tracking()` never on body copy.** Display sizes and uppercase caps labels only — it is absolute points and does not scale with Dynamic Type.
- **Never port a CSS line-height number.** `line-height: 1.4` is a multiplier; `.lineSpacing()` is additive points. Use `seamlyLeading(_:for:)` from Task 2.
- **Numbers carry their unit, thin-space grouped, tabular.** `SeamlyNumber.px(_:)` / `.dimensions(width:height:)`. Never a comma separator.
- **Voice.** Never a bare warning — the em dash carries the pivot from problem to remedy. Never "screenshot" for the output, never "merge"/"blend"/"AI"/"smart"/"magic", never "seamlessly" as an adverb, no emoji, no exclamation marks.
- **Display proxies are capped at 4096 px tall** and a GPU texture tops out ~16 384 px/side. Never bind a full-resolution composite to an `Image`.
- **`freezeGeometry` must never move into the draw path.** `composite`, `fullComposite`, `writePDF` and anything `update(_:)` touches build `Compositor(refinementDelta: 0)`.
- **Target membership follows the folder.** The project uses Xcode synchronized folder groups; adding or deleting a source file needs no `.pbxproj` edit. A file under `Seamly/` is app-only; code both targets need belongs in `StitchKit`.

### Commands

```bash
scripts/fetch-fixtures.sh                                  # once, on a fresh clone
swift test --package-path Seamly/StitchKit                 # StitchKit suite
swift test --package-path Seamly/StitchKit --filter PlacementTests
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

All paths are from the repo root. The Xcode project and the package live one level down in `Seamly/`.

### Every commit message ends with

```
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
```

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `Seamly/Seamly/DesignSystem/Tokens/SeamlyTokens.swift` | Every token. Diffs 1:1 against `design-system/tokens/*.css`. |
| `Seamly/Seamly/DesignSystem/CaptureGeometry.swift` | The one coordinate-space function. Pure, testable without a view. |
| `Seamly/Seamly/DesignSystem/CaptureFinding.swift` | `Finding`, `CaptureMark`, `CaptureFindings`, `CaptureMarks`. Per-item layer beside `CaptureCondition`. |
| `Seamly/Seamly/DesignSystem/CaptureView.swift` | The sheet, its margin rail and its position scale, in one coordinate space. |
| `Seamly/Seamly/DesignSystem/Components/Marks/SeamMark.swift` | The quiet rule on the sheet. |
| `Seamly/Seamly/DesignSystem/Components/Marks/MarginMarker.swift` | The numbered ring in the margin. Findability. |
| `Seamly/Seamly/DesignSystem/Components/Marks/PositionScale.swift` | Ruled edge scale; horizontal below `isShort`. |
| `Seamly/Seamly/DesignSystem/Components/Data/CaptureSheetView.swift` | White square sheet with lift, and the optional ribbon. |
| `Seamly/Seamly/DesignSystem/Components/Data/StatusNote.swift` | A wash behind ink, always carrying its word. |
| `Seamly/Seamly/DesignSystem/Components/Data/CaptureListRow.swift` | Compact library row. |
| `Seamly/Seamly/DesignSystem/Components/Data/CaptureGridCard.swift` | Regular library cell, fixed 3:5. |
| `Seamly/Seamly/DesignSystem/Components/Actions/SeamlyButton.swift` | Five variants, three sizes. |
| `Seamly/Seamly/DesignSystem/Components/Actions/IconButton.swift` | 44 pt target whatever the glyph. |
| `Seamly/Seamly/DesignSystem/Components/Navigation/NavBar.swift` | Paper nav bar with a mono subtitle and a `large` variant. |
| `Seamly/Seamly/DesignSystem/Components/Navigation/SheetChrome.swift` | Square-topped paper sheet header. |
| `Seamly/Seamly/DesignSystem/Components/Navigation/PageDots.swift` | First-run pagination. |
| `Seamly/Seamly/DesignSystem/Components/Feedback/EmptyState.swift` | Centred symbol, title, body. |
| `Seamly/Seamly/DesignSystem/Components/Feedback/ProgressNote.swift` | Determinate or genuinely indeterminate. |
| `Seamly/Seamly/DesignSystem/Components/Feedback/CueCard.swift` | The only place the buzz is taught. |
| `Seamly/Seamly/DesignSystem/Components/Capture/CaptureDock.swift` | The permanently docked capture affordance. |
| `Seamly/Seamly/DesignSystem/Components/Capture/ImportRow.swift` | A listed alternative source. |
| `Seamly/Seamly/DesignSystem/Components/Repair/QueuePrompt.swift` | One question, one wide affirmative answer. |
| `Seamly/Seamly/DesignSystem/Components/Repair/StepperRow.swift` | The advanced path, never the default. |
| `Seamly/Seamly/Features/Home/HomeScreen.swift` | Return-home. |
| `Seamly/Seamly/Features/Library/LibraryScreen.swift` | List at compact, grid at regular. |
| `Seamly/Seamly/Features/Result/ReviewScreen.swift` | The capture at length, plus the regular-width rail. |
| `Seamly/Seamly/Features/Repair/RepairQueueView.swift` | The queue. |
| `Seamly/Seamly/Features/Repair/RepairQueueModel.swift` | Pending answers and the commit, off the view. |
| `Seamly/Seamly/Features/Export/ExportSheet.swift` | Image vs document. |
| `Seamly/Seamly/Features/Import/ImportSheet.swift` | Two genuinely different kinds of progress. |
| `Seamly/Seamly/Features/Onboarding/FirstRunView.swift` | Three cue cards. |
| `Seamly/Seamly/AppShell.swift` | The `NavigationStack`, the `Route`, and every model-driven presentation. |

**Modified** — `Seamly/StitchKit/Sources/StitchKit/Compositor.swift` (adds `Placement`), `Seamly/Seamly/SeamlyApp.swift` (roots `AppShell`), `Seamly/Seamly/DesignSystem/CaptureCondition.swift` (unchanged logic; gains a doc note pointing at `CaptureFinding.swift`).

**Deleted, in Task 20** — `CaptureCanvas.swift`, `ConditionNotice.swift`, `HomeView.swift`, `ResultView.swift`, `OutcomeViews.swift`, `RepairView.swift`, `OnboardingView.swift`, `ContentView.swift`.

**Kept, untouched** — all of `StitchKit` except the additive accessor, `StitchAssembler`, `CaptureModel`, `MediaImporter`, `AppGroup+Observer`, `CaptureCondition`, `ZoomState`, `JoinAlignment`, `RepairableJoins`, `Exporter`, `DiagnosticsView`, `BroadcastPickerButton`, `PhotoImportButton`, `VideoImportButton`, `DebugSeed`.

---

## Task 1: `Compositor.placement`

Expose, read-only, the layout the private `plan` already computes — so the app can ask where a join sits without a second copy of the rule. The segment walk becomes one private function that both `plan` and `placement` call.

**Files:**
- Modify: `Seamly/StitchKit/Sources/StitchKit/Compositor.swift` (add `Placement`; replace the body of `plan` at lines 223–283 with a call into the shared walk)
- Test: `Seamly/StitchKit/Tests/StitchKitTests/PlacementTests.swift`

**Interfaces:**
- Consumes: `StitchSession`, `Seam`, `Keyframe`, `SegmentBreak` (existing public types).
- Produces:
  - `public struct Placement: Sendable, Equatable`
  - `public struct Placement.Span: Sendable, Equatable` with `keyframeIndex: Int?`, `srcY: Int`, `height: Int`, `destY: Int`, `segmentIndex: Int`, `segmentLocalY: Int`
  - `public let Placement.spans: [Span]`, `public let Placement.totalHeight: Int`, `public var Placement.segmentCount: Int`
  - `public func Placement.destY(forJoin joinIndex: Int) -> Int?`
  - `public func Placement.destY(forBreakAfter keyframeIndex: Int) -> Int?`
  - `public func Placement.firstSpan(forKeyframeIndex index: Int) -> Span?`
  - `public func Compositor.placement(_ session: StitchSession) -> Placement`

- [ ] **Step 1: Write the failing test**

Create `Seamly/StitchKit/Tests/StitchKitTests/PlacementTests.swift`:

```swift
import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// `Placement` is the public face of `Compositor.plan`'s layout. It exists so the app can
/// position a margin marker without re-deriving the rule a third time (`JoinAlignment` is the
/// second copy, and it is asserted against a real composite for exactly this reason). So the
/// gate here is the same one: the numbers must agree with real pixels, not with themselves.
struct PlacementTests {

    /// Per-pixel noise: distinct rows with real horizontal variance, so refinement has
    /// structure to lock onto. Buffer row 0 is the image's top row.
    private func noise(width: Int, height: Int, seed: Int = 5) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let bpr = ctx.bytesPerRow
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * height) { p in
            for r in 0..<height {
                for c in 0..<width {
                    let n = UInt64(bitPattern: Int64((r &* 73856093) ^ (c &* 19349663) ^ (seed &* 83492791)))
                    let v = UInt8((n >> 7) & 0xFF)
                    let i = r * bpr + c * 4
                    p[i] = v; p[i + 1] = v; p[i + 2] = v; p[i + 3] = 255
                }
            }
        }
        return ctx.makeImage()!
    }

    /// `count` frames of `height` rows, cropped from one tall source at `dy` intervals, with
    /// optional chrome and optional segment breaks. Returns the session and an image lookup.
    private func session(
        count: Int,
        width: Int = 120,
        height: Int = 300,
        dy: Int = 180,
        topChrome: Int = 0,
        bottomChrome: Int = 0,
        breaksAfter: [Int] = []
    ) -> (StitchSession, (Keyframe) throws -> CGImage) {
        let source = noise(width: width, height: height + dy * count)
        var images: [Int: CGImage] = [:]
        let keyframes: [Keyframe] = (0..<count).map { index in
            images[index] = source.cropping(
                to: CGRect(x: 0, y: index * dy, width: width, height: height)
            )!
            return Keyframe(filename: "kf-\(index).bgra", pixelWidth: width, pixelHeight: height, index: index)
        }
        var s = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: keyframes,
            seams: (0..<max(0, count - 1)).map { Seam(fromIndex: $0, provisionalDy: dy, confidence: 0.9) },
            segmentBreaks: breaksAfter.map { SegmentBreak(afterKeyframeIndex: $0, reason: .lostLock) }
        )
        s.keyframeChrome = keyframes.map {
            KeyframeChrome(
                keyframeID: $0.id,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: topChrome, bottom: bottomChrome),
                    confidence: 0.9
                )
            )
        }
        return (s, { kf in images[kf.index]! })
    }

    // MARK: - The gate: agreement with real pixels

    @Test func totalHeightMatchesTheCompositedImage() throws {
        let compositor = Compositor(refinementDelta: 0)
        for (count, breaks) in [(2, [Int]()), (4, []), (4, [1]), (5, [1, 3])] {
            let (s, images) = session(count: count, breaksAfter: breaks)
            let composite = try compositor.composite(s, images: images)
            #expect(
                compositor.placement(s).totalHeight == composite.height,
                "count=\(count) breaks=\(breaks)"
            )
        }
    }

    @Test func totalHeightMatchesWithChrome() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, images) = session(count: 4, topChrome: 24, bottomChrome: 18)
        let composite = try compositor.composite(s, images: images)
        #expect(compositor.placement(s).totalHeight == composite.height)
    }

    // MARK: - Spans

    @Test func spansAreContiguousAndCoverTheWholeHeight() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, _) = session(count: 5, breaksAfter: [2])
        let placement = compositor.placement(s)
        var cursor = 0
        for span in placement.spans {
            #expect(span.destY == cursor)
            #expect(span.height > 0)
            cursor += span.height
        }
        #expect(cursor == placement.totalHeight)
    }

    @Test func aSegmentBreakInsertsASeparatorSpan() throws {
        let compositor = Compositor(refinementDelta: 0, separatorHeight: 8)
        let (s, _) = session(count: 4, breaksAfter: [1])
        let placement = compositor.placement(s)
        let separators = placement.spans.filter { $0.keyframeIndex == nil }
        #expect(separators.count == 1)
        #expect(separators[0].height == 8)
        #expect(placement.segmentCount == 2)
        #expect(placement.destY(forBreakAfter: 1) == separators[0].destY)
        #expect(placement.destY(forBreakAfter: 0) == nil)
    }

    @Test func aJoinSitsWhereItsLowerFrameStarts() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, _) = session(count: 3, height: 300, dy: 180)
        let placement = compositor.placement(s)
        // Frame 0 contributes all 300 rows; frame 1 then starts at 300.
        #expect(placement.destY(forJoin: 0) == 300)
        #expect(placement.firstSpan(forKeyframeIndex: 1)?.destY == 300)
        // dy 180 into a 300-row frame: frame 1 contributes rows [120, 300) = 180 rows.
        #expect(placement.destY(forJoin: 1) == 480)
    }

    @Test func thereIsNoJoinAcrossASegmentBreak() throws {
        let compositor = Compositor(refinementDelta: 0)
        let (s, _) = session(count: 4, breaksAfter: [1])
        let placement = compositor.placement(s)
        #expect(placement.destY(forJoin: 1) == nil, "keyframe 2 opens a new segment, so there is no join here")
        #expect(placement.destY(forJoin: 0) != nil)
        #expect(placement.destY(forJoin: 2) != nil)
    }

    @Test func anEmptySessionPlacesNothing() {
        var s = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 1, orientation: .portrait)
        s.status = .complete
        let placement = Compositor(refinementDelta: 0).placement(s)
        #expect(placement.spans.isEmpty)
        #expect(placement.totalHeight == 0)
        #expect(placement.destY(forJoin: 0) == nil)
    }

    /// A duplicated seam is a malformed manifest, not a crash. The shared walk builds its
    /// offset lookup with `uniquingKeysWith:` rather than `uniqueKeysWithValues:`, which used
    /// to trap here.
    @Test func aDuplicatedSeamDoesNotTrap() {
        var (s, _) = session(count: 3)
        s.seams.append(Seam(fromIndex: 0, provisionalDy: 999, confidence: 0.1))
        let placement = Compositor(refinementDelta: 0).placement(s)
        #expect(placement.totalHeight > 0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --package-path Seamly/StitchKit --filter PlacementTests`
Expected: compile failure — `value of type 'Compositor' has no member 'placement'`.

- [ ] **Step 3: Add `Placement` to `Compositor.swift`**

Insert at **file scope**, after the closing brace of `struct Compositor` — not inside it. The app refers to this as `Placement`, not `Compositor.Placement`.

```swift
// MARK: - Placement

/// A read-only view of the composite's layout: where every source strip lands, without
/// drawing anything or loading a single image.
///
/// This exists so the app can answer "how far down the finished capture is this join?" —
/// which the margin markers and the position scale need — without re-deriving
/// `plan`'s rule. `JoinAlignment` is already a second copy of that rule, paid for with a test
/// against a real composite; a third copy is what this replaces. `plan` and `placement` both
/// call the same private walk, so there is nothing to drift.
public struct Placement: Sendable, Equatable {
    /// One laid-out strip: source rows `[srcY, srcY + height)` of the keyframe at
    /// `keyframeIndex`, drawn at `destY` in the composite. `keyframeIndex == nil` is a
    /// segment separator band, which comes from no keyframe at all.
    public struct Span: Sendable, Equatable {
        public let keyframeIndex: Int?
        public let srcY: Int
        public let height: Int
        public let destY: Int
        /// Which segment this strip belongs to. A separator carries the index of the segment
        /// it precedes.
        public let segmentIndex: Int
        /// Destination Y within the segment, for the PDF paginator.
        public let segmentLocalY: Int
    }

    public let spans: [Span]
    public let totalHeight: Int

    public init(spans: [Span]) {
        self.spans = spans
        self.totalHeight = spans.last.map { $0.destY + $0.height } ?? 0
    }

    public var segmentCount: Int {
        (spans.map(\.segmentIndex).max() ?? -1) + 1
    }

    /// The first strip contributed by a keyframe. A segment's last frame contributes a second
    /// strip for its bottom chrome; this is deliberately the first.
    public func firstSpan(forKeyframeIndex index: Int) -> Span? {
        spans.first { $0.keyframeIndex == index }
    }

    /// Where the join between `joinIndex` and `joinIndex + 1` sits — the row at which the
    /// lower frame starts contributing.
    ///
    /// `nil` when there is no such join: the pair does not exist, or a segment break sits
    /// between them, in which case nothing overlaps and there is nothing to line up.
    public func destY(forJoin joinIndex: Int) -> Int? {
        guard let i = spans.firstIndex(where: { $0.keyframeIndex == joinIndex + 1 }) else { return nil }
        guard i > spans.startIndex, spans[i - 1].keyframeIndex != nil else { return nil }
        return spans[i].destY
    }

    /// Where the separator band after `keyframeIndex` sits, or `nil` if no break follows it.
    public func destY(forBreakAfter keyframeIndex: Int) -> Int? {
        guard let i = spans.lastIndex(where: { $0.keyframeIndex == keyframeIndex }) else { return nil }
        let next = spans.index(after: i)
        guard next < spans.endIndex, spans[next].keyframeIndex == nil else { return nil }
        return spans[next].destY
    }
}
```

- [ ] **Step 4: Add the public accessor and the shared walk, and rewrite `plan` to use it**

Add to `Compositor` (public API section, after `writePDF`):

```swift
    /// Where every strip of this session's composite lands. Loads no images, so it is cheap
    /// enough to compute whenever a session changes.
    ///
    /// Uses the session's own stored offsets, which is correct for every app-side caller: the
    /// draw path is `refinementDelta: 0`, so the manifest is the authority and refinement is
    /// a no-op. See `StitchAssembler.freezeGeometry`.
    public func placement(_ session: StitchSession) -> Placement {
        Placement(spans: layoutSpans(session, dyByFrom: offsets(session.seams)))
    }
```

Add these two private members beside `plan`:

```swift
    /// Offset per join. `uniquingKeysWith:` rather than `uniqueKeysWithValues:` — a duplicated
    /// seam is a malformed manifest, and trapping on one is worse than laying it out with the
    /// first value we saw.
    private func offsets(_ seams: [Seam]) -> [Int: Int] {
        Dictionary(seams.map { ($0.fromIndex, $0.provisionalDy) }, uniquingKeysWith: { first, _ in first })
    }

    /// The single copy of the layout rule. `plan` decorates these into `Piece`s; `placement`
    /// publishes them as-is. Nothing else may re-derive it.
    private func layoutSpans(_ session: StitchSession, dyByFrom: [Int: Int]) -> [Placement.Span] {
        var spans: [Placement.Span] = []
        var cursor = 0

        for (s, seg) in splitIntoSegments(session).enumerated() {
            if s > 0 {
                spans.append(Placement.Span(
                    keyframeIndex: nil, srcY: 0, height: separatorHeight,
                    destY: cursor, segmentIndex: s, segmentLocalY: 0
                ))
                cursor += separatorHeight
            }
            var localY = 0

            func add(_ index: Int, _ srcY: Int, _ height: Int) {
                guard height > 0 else { return }
                spans.append(Placement.Span(
                    keyframeIndex: index, srcY: srcY, height: height,
                    destY: cursor, segmentIndex: s, segmentLocalY: localY
                ))
                cursor += height
                localY += height
            }

            if seg.count == 1 {
                add(seg[0].index, 0, seg[0].pixelHeight)
            } else {
                // Missing-seam fallback. A well-formed session has a seam for every consecutive
                // pair in a segment, so this only fires on a malformed/partial manifest — a
                // recoverable case where *some* placement is required. We substitute the median
                // of the segment's known positive offsets; zero/negative "offsets" are excluded
                // as non-advances, and if none remain, half the current frame's visible content
                // is a safe non-stacking default.
                let knownDys = seg.dropLast().compactMap { dyByFrom[$0.index] }.filter { $0 > 0 }

                let firstChrome = effectiveChromeInsets(session, for: seg[0], frameHeight: seg[0].pixelHeight)
                add(seg[0].index, 0, seg[0].pixelHeight - firstChrome.bottom)
                for j in 1..<seg.count {
                    let previous = seg[j - 1]
                    let current = seg[j]
                    let previousChrome = effectiveChromeInsets(session, for: previous, frameHeight: previous.pixelHeight)
                    let currentChrome = effectiveChromeInsets(session, for: current, frameHeight: current.pixelHeight)
                    let previousContentBottom = previous.pixelHeight - previousChrome.bottom
                    let currentContentBottom = current.pixelHeight - currentChrome.bottom
                    let currentContentHeight = max(0, currentContentBottom - currentChrome.top)
                    let fallbackDy = medianDy(knownDys) ?? max(1, currentContentHeight / 2)
                    let dy = dyByFrom[previous.index] ?? fallbackDy
                    let sourceStart = clamp(previousContentBottom - dy, to: currentChrome.top...currentContentBottom)
                    add(current.index, sourceStart, currentContentBottom - sourceStart)
                }
                let last = seg[seg.count - 1]
                let lastChrome = effectiveChromeInsets(session, for: last, frameHeight: last.pixelHeight)
                if lastChrome.bottom > 0 {
                    add(last.index, last.pixelHeight - lastChrome.bottom, lastChrome.bottom)
                }
            }
        }
        return spans
    }
```

Now replace the whole body of `plan` (its signature is unchanged) with:

```swift
    private func plan(_ session: StitchSession, refinedSeams: [Seam], images: (Keyframe) throws -> CGImage) throws -> Layout {
        let spans = layoutSpans(session, dyByFrom: offsets(refinedSeams))
        let width = try firstImage(session, images).width
        let byIndex = Dictionary(session.keyframes.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })

        var pieces: [Piece] = []
        var segments = Array(
            repeating: SegmentLayout(pieces: [], height: 0),
            count: (spans.map(\.segmentIndex).max() ?? -1) + 1
        )
        for span in spans {
            let piece = Piece(
                keyframe: span.keyframeIndex.flatMap { byIndex[$0] },
                srcY: span.srcY,
                height: span.height,
                destY: span.destY,
                segmentLocalY: span.segmentLocalY
            )
            pieces.append(piece)
            // A separator belongs to no segment — it sits between them, and the PDF paginator
            // must not page it as part of the segment that follows.
            guard span.keyframeIndex != nil else { continue }
            segments[span.segmentIndex].pieces.append(piece)
            segments[span.segmentIndex].height = span.segmentLocalY + span.height
        }

        return Layout(
            pieces: pieces,
            segments: segments,
            width: width,
            totalHeight: spans.last.map { $0.destY + $0.height } ?? 0
        )
    }
```

Delete the now-unused local `add`/`cursor`/`segPieces` machinery that was inside the old `plan`. Keep `medianDy`, `effectiveChromeInsets`, `clamp`, `splitIntoSegments` and `firstImage` exactly as they are.

- [ ] **Step 5: Run the new test**

Run: `swift test --package-path Seamly/StitchKit --filter PlacementTests`
Expected: PASS, all eight tests.

- [ ] **Step 6: Run the whole StitchKit suite**

Run: `swift test --package-path Seamly/StitchKit`
Expected: PASS. This is the real gate — `plan` feeds `composite`, `writePDF` and every real-frame tier, so a refactor of it either agrees with every existing pixel assertion or it is wrong. Expect several minutes; the real-frame tiers are inherently slow.

- [ ] **Step 7: Commit**

```bash
git add Seamly/StitchKit/Sources/StitchKit/Compositor.swift \
        Seamly/StitchKit/Tests/StitchKitTests/PlacementTests.swift
git commit -m "$(cat <<'EOF'
feat(stitchkit): publish the composite's layout as Placement

The app needs to know how far down a finished capture a join sits, to put
a margin marker there. That number is the cursor in Compositor.plan, which
is private — the wall JoinAlignment already hit and answered by re-deriving
the rule in the app plus a test against a real composite.

Rather than a third copy, extract the segment walk into one private
function and publish its output. plan now decorates those spans into
Pieces; placement returns them as-is, loading no images.

Also stops trapping on a duplicated seam: the offset lookup uses
uniquingKeysWith rather than uniqueKeysWithValues, so a malformed manifest
lays out with the first value seen instead of crashing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Tokens in the app target

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Tokens/SeamlyTokens.swift`
- Reference: `design-system/swiftui/SeamlyTokens.swift`, `design-system/tokens/*.css`, `design-system/swiftui/FEASIBILITY.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `SeamlyColor`, `SeamlyFont`, `SeamlySpace`, `SeamlyRadius`, `SeamlyMotion`, `SeamlyLayout`, `SeamlyNumber`; `View.seamlyCorners(_:)`, `.seamlySheetLift()`, `.seamlyProtectTop(_:)`, `.seamlyProtectBottom(_:)`, `.seamlyHitTarget()`, `.seamlyDisplayTracking()`, `.seamlyCapsTracking()`, `.seamlyLeading(_:for:)`; `Color.seamly(light:dark:)`, `Color.init(rgb:)`.

- [ ] **Step 1: Copy the port in, unmodified**

```bash
mkdir -p Seamly/Seamly/DesignSystem/Tokens
cp design-system/swiftui/SeamlyTokens.swift Seamly/Seamly/DesignSystem/Tokens/SeamlyTokens.swift
```

- [ ] **Step 2: Make it fit the app target**

Two mechanical edits across the file:

1. Drop `public` everywhere — this is app-internal now. (`public extension Color` → `extension Color`, `public enum SeamlyColor` → `nonisolated enum SeamlyColor`, and so on. The `public init`s inside `SeamlyLayout` and `Placement`-style structs become plain `init`.)
2. Add `nonisolated` to every type: `SeamlyColor`, `SeamlyFont`, `SeamlySpace`, `SeamlyRadius`, `SeamlyLayout`, `SeamlyNumber`. This target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; without it a token is only readable from the main actor, which defeats the point and makes them unusable from any pure type.

Leave every value alone. The colours are contrast-solved; the ladder is Apple's.

- [ ] **Step 3: Add the tokens the port is missing**

Append to `SeamlyColor` (values from `design-system/tokens/colors.css`):

```swift
    /// The wash behind a selected finding row and the position scale's viewport bracket.
    static let accentWash = Color.seamly(light: 0x33456B, dark: 0x93A6D4)
        .opacity(0.09)
```

That opacity differs by theme in the CSS (0.09 light, 0.14 dark) and `Color.opacity` cannot vary by trait, so express it the same way the rest of the file does:

```swift
    static let accentWash = Color.seamlyAlpha(light: (0x33456B, 0.09), dark: (0x93A6D4, 0.14))
```

with, beside `Color.seamly(light:dark:)`:

```swift
    /// Like `seamly(light:dark:)` but with a per-theme alpha, for the washes — whose opacity
    /// is itself part of the contrast solve and is not the same in both themes.
    static func seamlyAlpha(light: (UInt32, Double), dark: (UInt32, Double)) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let (rgb, alpha) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(rgb: rgb).withAlphaComponent(alpha)
        })
        #else
        return Color(rgb: light.0).opacity(light.1)
        #endif
    }
```

Then correct the four existing washes, which the port approximated with a single opacity:

```swift
    static let washOK    = Color.seamlyAlpha(light: (0x3E6B4F, 0.10), dark: (0x6FAE86, 0.14))
    static let washFlag  = Color.seamlyAlpha(light: (0x8A6219, 0.13), dark: (0xD9A544, 0.16))
    static let washGap   = Color.seamlyAlpha(light: (0xA6482A, 0.11), dark: (0xD9754E, 0.15))
    static let washError = Color.seamlyAlpha(light: (0xA3302B, 0.10), dark: (0xD9615A, 0.14))
```

And do the same for the rules, whose alphas also differ (`rule` 0.14 light / 0.16 dark, `ruleStrong` 0.30 / 0.32, `ruleFaint` 0.07 / 0.08). `seamConfident` is the exception and stays fixed:

```swift
    static let rule       = Color.seamlyAlpha(light: (0x1F1D1A, 0.14), dark: (0xF2EFE9, 0.16))
    static let ruleStrong = Color.seamlyAlpha(light: (0x1F1D1A, 0.30), dark: (0xF2EFE9, 0.32))
    static let ruleFaint  = Color.seamlyAlpha(light: (0x1F1D1A, 0.07), dark: (0xF2EFE9, 0.08))
    /// NOT theme-varying, unlike the rules above. This draws a join ON THE SHEET, and the
    /// sheet is fixed white in both themes — so the ink must not flip either. colors.css:46
    /// defines it once in `:root` with no dark override, deliberately.
    static let seamConfident = Color(rgb: 0x1F1D1A).opacity(0.10)
```

Add to `SeamlySpace`:

```swift
    /// How a join is drawn on the sheet. Deliberately thin — findability is the margin's job.
    static let seamWidth: CGFloat = 1
    static let seamWidthMark: CGFloat = 1.5
```

Add to `SeamlyRadius`: nothing — it is complete.

Add a new type:

```swift
// MARK: - Motion
//
// Restrained: the main object is a 15 000 px image someone is trying to read. Ported from
// design-system/tokens/motion.css; reduce-motion is handled by SwiftUI's own accessibility
// behaviour plus `SeamlyMotion.jump`'s single use site.

nonisolated enum SeamlyMotion {
    static let press = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.12)
    static let base = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)
    /// The pan that jumps to a mark — the one that matters.
    static let jump = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    static let stitching = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 1.1)
    static let disabledOpacity: Double = 0.38
}
```

Add to the `View` extension:

```swift
    /// CSS `line-height` is a MULTIPLIER; `.lineSpacing()` is additive leading in points.
    /// Porting the number directly is wrong at every size and worse as Dynamic Type scales,
    /// so compute the points from the style's own resolved size. See FEASIBILITY.md.
    func seamlyLeading(_ multiplier: CGFloat, for style: UIFont.TextStyle) -> some View {
        lineSpacing((multiplier - 1) * UIFont.preferredFont(forTextStyle: style).pointSize)
    }

    /// The bottom counterpart of `seamlyProtectTop`. A gradient, never a flat scrim — a
    /// capture can be any brightness and a scrim dims what the user is reading.
    func seamlyProtectBottom(_ height: CGFloat = 96) -> some View {
        overlay(alignment: .bottom) {
            LinearGradient(
                colors: [SeamlyColor.paper.opacity(0), SeamlyColor.paper.opacity(0.94)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }
```

- [ ] **Step 4: Build to verify it compiles under Swift 6**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. If a token is reported as main-actor-isolated at a use site, the `nonisolated` from Step 2 is missing on that type.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Tokens/SeamlyTokens.swift
git commit -m "$(cat <<'EOF'
feat(design): port the Paper tokens into the app target

Straight from design-system/swiftui/SeamlyTokens.swift, which already
typechecks under Swift 6, plus what the port did not carry: motion, the
seam widths, and the bottom protection gradient.

Two corrections to the port. The washes and rules have per-theme ALPHA in
the CSS, which Color.opacity cannot vary by trait, so they resolve through
a seamlyAlpha helper rather than a single averaged opacity — these values
are part of the contrast solve. And seamlyLeading computes additive points
from the text style's own resolved size, because CSS line-height is a
multiplier and porting the number is wrong at every size.

Every type is nonisolated: this target defaults new declarations to
MainActor, which would make a colour unreadable from any pure type.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: `CaptureGeometry` — the coordinate space

The load-bearing arithmetic, extracted so it is tested without a view. Everything drawn on or beside the sheet reads its position from here.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/CaptureGeometry.swift`
- Test: `Seamly/SeamlyTests/CaptureGeometryTests.swift`

**Interfaces:**
- Consumes: `CoreGraphics`.
- Produces: `nonisolated struct CaptureGeometry` with `init(sheetWidth:viewportHeight:captureSize:zoom:scrollY:)`, `var contentHeight: CGFloat`, `var maxScrollY: CGFloat`, `func y(atPct:) -> CGFloat`, `func isVisible(_:slack:) -> Bool`, `var viewportTopPct: Double`, `var viewportPct: Double`, `func scrollY(toShow:at:) -> CGFloat`, `func pct(forViewportY:) -> Double`.

- [ ] **Step 1: Write the failing test**

Create `Seamly/SeamlyTests/CaptureGeometryTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import Seamly

/// The one formula the whole Paper direction rests on. A margin marker and the rule on the
/// sheet must land on the same row, or "findability lives in the margin" stops being true —
/// so the arithmetic lives here, in one place, tested without a view.
struct CaptureGeometryTests {

    /// 400 pt wide, 800 pt tall viewport, onto a 1000 × 10 000 px capture (aspect 10).
    private func geometry(zoom: CGFloat = 1, scrollY: CGFloat = 0) -> CaptureGeometry {
        CaptureGeometry(
            sheetWidth: 400,
            viewportHeight: 800,
            captureSize: CGSize(width: 1000, height: 10_000),
            zoom: zoom,
            scrollY: scrollY
        )
    }

    @Test func oneTimesZoomFillsTheWidthAtNaturalAspect() {
        // NOT "shrink 10 000 px until it fits" — at that size nothing in it is legible.
        #expect(geometry().contentHeight == 4000)
        #expect(geometry(zoom: 3).contentHeight == 12_000)
    }

    @Test func aMarkSitsAtItsFractionOfTheContent() {
        #expect(geometry().y(atPct: 0) == 0)
        #expect(geometry().y(atPct: 0.5) == 2000)
        #expect(geometry().y(atPct: 1) == 4000)
    }

    @Test func scrollingMovesEveryMarkByTheSameAmount() {
        let g = geometry(scrollY: 500)
        #expect(g.y(atPct: 0) == -500)
        #expect(g.y(atPct: 0.5) == 1500)
    }

    @Test func zoomingScalesPositionAndScrollTogether() {
        let g = geometry(zoom: 3, scrollY: 600)
        #expect(g.y(atPct: 0.5) == 6000 - 600)
    }

    @Test func visibilityAllowsALittleSlackSoAMarkerFadesRatherThanPops() {
        let g = geometry(scrollY: 0)
        #expect(g.isVisible(0))
        #expect(g.isVisible(800))
        #expect(g.isVisible(-10))
        #expect(!g.isVisible(-40))
        #expect(!g.isVisible(900))
    }

    @Test func theViewportBracketDescribesWhereWeAreInTheWholeCapture() {
        let g = geometry(scrollY: 1000)
        #expect(abs(g.viewportTopPct - 0.25) < 1e-9)   // 1000 / 4000
        #expect(abs(g.viewportPct - 0.20) < 1e-9)      //  800 / 4000
    }

    @Test func jumpingPutsTheMarkWhereItWasAskedFor() {
        let g = geometry(zoom: 3)
        // atPct 0.5 is at 6000; put it 40% of the way down an 800 pt viewport.
        #expect(g.scrollY(toShow: 0.5, at: 0.4) == 6000 - 320)
    }

    @Test func jumpingNeverScrollsPastEitherEnd() {
        let g = geometry(zoom: 3)
        #expect(g.scrollY(toShow: 0, at: 0.4) == 0)
        #expect(g.scrollY(toShow: 1, at: 0.4) == g.maxScrollY)
        #expect(g.maxScrollY == 12_000 - 800)
    }

    @Test func scrubbingTheScaleReadsBackAsAFraction() {
        let g = geometry()
        #expect(abs(g.pct(forViewportY: 0) - 0) < 1e-9)
        #expect(abs(g.pct(forViewportY: 400) - 0.5) < 1e-9)
        #expect(abs(g.pct(forViewportY: 800) - 1) < 1e-9)
    }

    /// A capture shorter than the viewport, and a degenerate zero-width sheet, must not
    /// divide by zero or hand back a negative scroll extent.
    @Test func degenerateSizesStayFinite() {
        let tiny = CaptureGeometry(
            sheetWidth: 400, viewportHeight: 800,
            captureSize: CGSize(width: 1000, height: 100), zoom: 1, scrollY: 0
        )
        #expect(tiny.maxScrollY == 0)
        #expect(tiny.scrollY(toShow: 1, at: 0.4) == 0)

        let empty = CaptureGeometry(
            sheetWidth: 0, viewportHeight: 0,
            captureSize: .zero, zoom: 1, scrollY: 0
        )
        #expect(empty.contentHeight == 0)
        #expect(empty.viewportTopPct == 0)
        #expect(empty.viewportPct == 1)
        #expect(empty.pct(forViewportY: 10) == 0)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SeamlyTests/CaptureGeometryTests test
```
Expected: compile failure — `cannot find 'CaptureGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Seamly/Seamly/DesignSystem/CaptureGeometry.swift`:

```swift
import CoreGraphics

/// Where anything sits on, or beside, a capture on screen.
///
/// The Paper direction's one real weakness is that a thin rule over white captured content is
/// easy to miss, so findability moves to the margin — which only works if the margin marker and
/// the rule on the sheet land on the same row. That alignment is the whole point, so the
/// arithmetic is one function in one place rather than two similar expressions in two views.
///
/// On screen a mark is at `atPct * contentHeight - scrollY`. The kit writes this as
/// `atPct * zoom - top` in units of the sheet's own height, which is correct for a mock whose
/// sheet crops the image; a real 1:40 capture needs the capture's own height in the term.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`, and
/// coordinate arithmetic has no business being pinned to an actor.
nonisolated struct CaptureGeometry: Equatable {
    let sheetWidth: CGFloat
    let viewportHeight: CGFloat
    /// The whole capture, in source pixels.
    let captureSize: CGSize
    let zoom: CGFloat
    let scrollY: CGFloat

    init(sheetWidth: CGFloat, viewportHeight: CGFloat, captureSize: CGSize, zoom: CGFloat, scrollY: CGFloat) {
        self.sheetWidth = max(0, sheetWidth)
        self.viewportHeight = max(0, viewportHeight)
        self.captureSize = captureSize
        self.zoom = max(zoom, 0.001)
        self.scrollY = scrollY
    }

    /// `zoom == 1` means *fill the sheet's width at natural aspect and scroll down* — not
    /// *shrink 15 000 px until all of it fits*, at which size nothing in it is legible.
    var contentHeight: CGFloat {
        guard captureSize.width > 0 else { return 0 }
        return sheetWidth * zoom * (captureSize.height / captureSize.width)
    }

    var maxScrollY: CGFloat { max(0, contentHeight - viewportHeight) }

    /// The screen Y of a mark at `atPct` down the whole capture.
    func y(atPct: Double) -> CGFloat { CGFloat(atPct) * contentHeight - scrollY }

    /// Slack, so a marker leaving the viewport fades out one step past the edge rather than
    /// vanishing exactly at it.
    func isVisible(_ y: CGFloat, slack: CGFloat = 24) -> Bool {
        y >= -slack && y <= viewportHeight + slack
    }

    /// Where the viewport's top edge sits in the whole capture, for the position scale.
    var viewportTopPct: Double {
        guard contentHeight > 0 else { return 0 }
        return Double(scrollY / contentHeight)
    }

    /// How much of the whole capture the viewport covers.
    var viewportPct: Double {
        guard contentHeight > 0 else { return 1 }
        return Double(min(1, viewportHeight / contentHeight))
    }

    /// The scroll offset that puts `atPct` `fraction` of the way down the viewport, clamped so
    /// a jump never asks for a position past either end.
    func scrollY(toShow atPct: Double, at fraction: CGFloat) -> CGFloat {
        let target = CGFloat(atPct) * contentHeight - viewportHeight * fraction
        return min(max(0, target), maxScrollY)
    }

    /// The inverse, for scrubbing the position scale.
    func pct(forViewportY y: CGFloat) -> Double {
        guard viewportHeight > 0 else { return 0 }
        return Double(min(max(0, y / viewportHeight), 1))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SeamlyTests/CaptureGeometryTests test
```
Expected: PASS, all ten tests.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/CaptureGeometry.swift \
        Seamly/SeamlyTests/CaptureGeometryTests.swift
git commit -m "$(cat <<'EOF'
feat(design): add CaptureGeometry, the one coordinate space

Everything drawn on or beside a capture — the image, the rule on the
sheet, the numbered marker in the margin, the position scale's bracket —
reads its position from this one function, so they cannot drift apart.
That alignment is what lets a light ground carry signal in the margin.

The kit's atPct*zoom - top is correct for a mock whose sheet crops the
image. A real 1:40 capture needs the capture's own height in the term, so
zoom 1 means fill the sheet's width at natural aspect and scroll down.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Findings and marks

The per-item layer the design's queue and margin need. Lives beside `CaptureCondition`, which stays the only place pipeline facts become English — the design has licensed the pipeline's own words on screen, and this is where they are written.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/CaptureFinding.swift`
- Modify: `Seamly/Seamly/DesignSystem/CaptureCondition.swift` (doc note only)
- Test: `Seamly/SeamlyTests/CaptureFindingsTests.swift`

**Interfaces:**
- Consumes: `StitchKit.StitchSession`, `StitchKit.Placement`, `StitchKit.ChromeEdge` (Task 1).
- Produces:
  - `nonisolated struct Finding: Identifiable, Equatable` — `id: String`, `n: Int`, `kind: Kind`, `atPct: Double`, `target: Target`, `title: String`, `question: String`, `detail: String`, `dy: Int?`, `confidence: Double?`
  - `nonisolated enum Finding.Kind: Int, Comparable, CaseIterable` — `.gap`, `.bars`, `.seam`
  - `nonisolated enum Finding.Target: Equatable` — `.gap(afterKeyframeIndex: Int)`, `.chrome(keyframeID: UUID, edges: Set<ChromeEdge>)`, `.join(Int)`
  - `nonisolated struct CaptureMark: Identifiable, Equatable` — `id: String`, `kind: Kind` (`.confident`/`.flagged`/`.gap`), `atPct: Double`, `n: Int?`, `lostLabel: String?`
  - `nonisolated enum CaptureFindings { static func all(in:placement:) -> [Finding] }`
  - `nonisolated enum CaptureMarks { static func all(in:placement:findings:) -> [CaptureMark] }`

- [ ] **Step 1: Write the failing test**

Create `Seamly/SeamlyTests/CaptureFindingsTests.swift`:

```swift
import Testing
import Foundation
import StitchKit
@testable import Seamly

/// A capture enumerates its own problems, and the number a margin marker shows is the number
/// the queue uses. Both come from here, so the ordering and the numbering are asserted rather
/// than assumed.
struct CaptureFindingsTests {

    private func session(
        count: Int,
        height: Int = 300,
        dy: Int = 180,
        flagged: Set<Int> = [],
        breaksAfter: [Int] = [],
        chromeReviewed: Set<Int> = []
    ) -> StitchSession {
        let keyframes = (0..<count).map {
            Keyframe(filename: "kf-\($0).bgra", pixelWidth: 120, pixelHeight: height, index: $0)
        }
        var s = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            keyframes: keyframes,
            seams: (0..<max(0, count - 1)).map {
                Seam(fromIndex: $0, provisionalDy: dy, confidence: flagged.contains($0) ? 0.2 : 0.9,
                     isLowConfidence: flagged.contains($0))
            },
            segmentBreaks: breaksAfter.map { SegmentBreak(afterKeyframeIndex: $0, reason: .lostLock) }
        )
        // `chromeReviewed` names the frames whose bars are UNCERTAIN — they get a record with
        // no automatic measurement, which is what `chromeEdgesNeedingReview` keys off. Every
        // other frame gets a confident zero-inset measurement.
        s.keyframeChrome = keyframes.map { kf in
            chromeReviewed.contains(kf.index)
                ? KeyframeChrome(keyframeID: kf.id)
                : KeyframeChrome(keyframeID: kf.id,
                                 automatic: ChromeMeasurement(insets: .zero, confidence: 0.9))
        }
        return s
    }

    private func findings(_ s: StitchSession) -> [Finding] {
        CaptureFindings.all(in: s, placement: Compositor(refinementDelta: 0).placement(s))
    }

    // MARK: - What becomes a finding

    @Test func aCleanCaptureHasNoFindings() {
        #expect(findings(session(count: 4)).isEmpty)
    }

    @Test func aFlaggedSeamBecomesASeamFinding() throws {
        let all = findings(session(count: 4, flagged: [1]))
        #expect(all.count == 1)
        let f = try #require(all.first)
        #expect(f.kind == .seam)
        #expect(f.target == .join(1))
        #expect(f.question == "Does this line up?")
        #expect(f.dy == 180)
        #expect(f.confidence == 0.2)
    }

    @Test func aSegmentBreakBecomesAGapFinding() throws {
        let all = findings(session(count: 4, breaksAfter: [1]))
        #expect(all.count == 1)
        let f = try #require(all.first)
        #expect(f.kind == .gap)
        #expect(f.target == .gap(afterKeyframeIndex: 1))
        #expect(f.dy == nil, "nothing overlaps across a break, so there is no offset to state")
    }

    @Test func anUnmeasurableFrameBecomesABarsFinding() throws {
        let s = session(count: 3, chromeReviewed: [1])
        let all = findings(s)
        #expect(all.count == 1)
        let f = try #require(all.first)
        #expect(f.kind == .bars)
        #expect(f.question == "Where do the bars end?")
        guard case .chrome(let keyframeID, let edges) = f.target else {
            Issue.record("expected a chrome target, got \(f.target)")
            return
        }
        #expect(keyframeID == s.keyframes[1].id)
        #expect(edges == [.top, .bottom])
    }

    /// Nothing overlaps across a break, so `Compositor.plan` ignores that seam when laying the
    /// strip out — dragging it would move nothing. `RepairableJoins.walkable` excludes it for
    /// the same reason, and so must this.
    @Test func aFlaggedSeamAcrossABreakIsNotASeamFinding() {
        let all = findings(session(count: 4, flagged: [1], breaksAfter: [1]))
        #expect(all.filter { $0.kind == .seam }.isEmpty)
        #expect(all.filter { $0.kind == .gap }.count == 1)
    }

    // MARK: - Order and numbering

    @Test func findingsAreRankedByKindThenPosition() {
        let all = findings(session(count: 6, flagged: [0, 4], breaksAfter: [2], chromeReviewed: [3]))
        #expect(all.map(\.kind) == [.gap, .bars, .seam, .seam])
        #expect(all.map(\.n) == [1, 2, 3, 4])
        // Missing content outranks uncertain bars outranks an uncertain join — the same
        // ranking Imperfection.Kind already uses. Within a kind, top to bottom.
        let seams = all.filter { $0.kind == .seam }
        #expect(seams[0].atPct < seams[1].atPct)
    }

    @Test func numbersAreOneBasedAndContiguous() {
        let all = findings(session(count: 8, flagged: [1, 3, 5], breaksAfter: [6]))
        #expect(all.map(\.n) == Array(1...all.count))
    }

    @Test func everyFindingSitsInsideTheCapture() {
        for f in findings(session(count: 6, flagged: [0, 4], breaksAfter: [2], chromeReviewed: [3])) {
            #expect(f.atPct >= 0 && f.atPct <= 1, "\(f.title) at \(f.atPct)")
        }
    }

    @Test func idsAreStableAcrossRebuilds() {
        let s = session(count: 6, flagged: [0, 4], breaksAfter: [2], chromeReviewed: [3])
        #expect(findings(s).map(\.id) == findings(s).map(\.id))
    }

    // MARK: - Language

    /// The engine cannot know how much a break swallowed — that is what a break IS. Stating a
    /// pixel count would be inventing a number.
    @Test func aGapIsLabelledLostLockNotAPixelCount() throws {
        let s = session(count: 4, breaksAfter: [1])
        let marks = CaptureMarks.all(
            in: s,
            placement: Compositor(refinementDelta: 0).placement(s),
            findings: findings(s)
        )
        let gap = try #require(marks.first { $0.kind == .gap })
        #expect(gap.lostLabel == "lost lock")
    }

    @Test func frameNumbersReadOneBased() throws {
        let all = findings(session(count: 4, breaksAfter: [1]))
        #expect(try #require(all.first).title == "Gap after frame 2")
    }

    // MARK: - Marks

    @Test func everyJoinIsMarkedAndOnlyDoubtIsNumbered() {
        let s = session(count: 5, flagged: [2])
        let marks = CaptureMarks.all(
            in: s, placement: Compositor(refinementDelta: 0).placement(s), findings: findings(s)
        )
        #expect(marks.count == 4, "four joins in a five-frame capture")
        #expect(marks.filter { $0.kind == .confident }.count == 3)
        #expect(marks.filter { $0.n != nil }.count == 1, "a good capture must look like one image")
    }

    @Test func aMarksNumberIsItsFindingsNumber() throws {
        let s = session(count: 6, flagged: [4], breaksAfter: [2])
        let all = findings(s)
        let marks = CaptureMarks.all(in: s, placement: Compositor(refinementDelta: 0).placement(s), findings: all)
        for f in all {
            let mark = try #require(marks.first { $0.n == f.n })
            #expect(abs(mark.atPct - f.atPct) < 1e-9, "marker \(f.n) is not where finding \(f.n) is")
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SeamlyTests/CaptureFindingsTests test
```
Expected: compile failure — `cannot find 'CaptureFindings' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Seamly/Seamly/DesignSystem/CaptureFinding.swift`:

```swift
import Foundation
import StitchKit

/// One thing about a capture that is worth asking the user about, located in the finished
/// image and paired with its fix.
///
/// This is the per-item companion to `CaptureCondition`'s aggregate verdict, and it lives
/// beside it deliberately: `CaptureCondition` is the only place pipeline facts become English,
/// and that rule still holds. What changed is the vocabulary — the design puts the pipeline's
/// own words on screen ("seam", "bars", "gap"), reversing the ban in
/// `docs/superpowers/specs/2026-08-17-guided-repair-design.md`. So the strings here are
/// different from `Imperfection`'s, but they are written in the same file's spirit and in the
/// same one place.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`.
nonisolated struct Finding: Identifiable, Equatable {
    /// Declaration order **is** the ranking, most important first — the same order
    /// `Imperfection.Kind` already uses. Missing content outranks uncertain bars, which
    /// outranks a join that might be a pixel off.
    enum Kind: Int, Comparable, CaseIterable {
        case gap
        case bars
        case seam

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    /// What answering this finding actually changes.
    enum Target: Equatable {
        /// Nothing to change — the content was never captured.
        case gap(afterKeyframeIndex: Int)
        /// `StitchSession.setChromeOverride(_:for:keyframeID:)`.
        case chrome(keyframeID: UUID, edges: Set<ChromeEdge>)
        /// `Seam.provisionalDy` for the join between this index and the next.
        case join(Int)
    }

    /// Stable across rebuilds, so a `ForEach` and a queue position survive a re-derive.
    let id: String
    /// The number the margin marker shows and the queue counts by.
    let n: Int
    let kind: Kind
    /// Where this sits in the whole capture, 0…1.
    let atPct: Double
    let target: Target
    let title: String
    let question: String
    let detail: String
    /// The offset under the finger, for a seam. `nil` where there is no offset to state.
    let dy: Int?
    let confidence: Double?
}

/// A join drawn on the sheet. Every join gets one, confident ones included and unnumbered —
/// principle 1 says a good capture must look like one image, so only doubt draws attention.
nonisolated struct CaptureMark: Identifiable, Equatable {
    enum Kind { case confident, flagged, gap }

    let id: String
    let kind: Kind
    let atPct: Double
    /// Present only when this mark has a finding, and then it is that finding's number.
    let n: Int?
    /// A gap always says what was lost. `nil` for everything else.
    let lostLabel: String?
}

nonisolated enum CaptureFindings {

    /// Everything this capture wants to ask about, ranked and numbered.
    ///
    /// Numbering is by rank then position, which is why a capture's gaps are 1…k before its
    /// flagged joins — the queue walks the most important thing first, and the margin marker
    /// carries the same number so the two are never out of step.
    static func all(in session: StitchSession, placement: Placement) -> [Finding] {
        guard placement.totalHeight > 0 else { return [] }
        let height = Double(placement.totalHeight)

        struct Draft {
            let id: String
            let kind: Finding.Kind
            let atPct: Double
            let target: Finding.Target
            let title: String
            let question: String
            let detail: String
            let dy: Int?
            let confidence: Double?
        }

        var drafts: [Draft] = []

        // Gaps — content the scroll outran. Nothing overlaps across one, so there is no offset.
        for span in session.segmentBreaks.sorted(by: { $0.afterKeyframeIndex < $1.afterKeyframeIndex }) {
            guard let destY = placement.destY(forBreakAfter: span.afterKeyframeIndex) else { continue }
            drafts.append(Draft(
                id: "gap-\(span.afterKeyframeIndex)",
                kind: .gap,
                atPct: Double(destY) / height,
                target: .gap(afterKeyframeIndex: span.afterKeyframeIndex),
                title: "Gap after frame \(span.afterKeyframeIndex + 1)",
                question: "Nothing was captured here",
                detail: "You scrolled past this stretch too fast — recording that part again is the only way to get it.",
                dy: nil,
                confidence: nil
            ))
        }

        // Bars — an edge with neither a user value nor positive-confidence automatic evidence.
        // Resolution stays lossless, so the crop is zero and the app's bars may repeat.
        for keyframe in session.keyframes.sorted(by: { $0.index < $1.index }) {
            let edges = session.chromeEdgesNeedingReview(for: keyframe)
            guard !edges.isEmpty, let span = placement.firstSpan(forKeyframeIndex: keyframe.index) else { continue }
            drafts.append(Draft(
                id: "bars-\(keyframe.index)",
                kind: .bars,
                atPct: Double(span.destY) / height,
                target: .chrome(keyframeID: keyframe.id, edges: edges),
                title: "Bars uncertain — frame \(keyframe.index + 1)",
                question: "Where do the bars end?",
                detail: "Bars weren't detected confidently here — set the crop.",
                dy: nil,
                confidence: nil
            ))
        }

        // Seams the engine wasn't sure about. `destY(forJoin:)` is `nil` across a segment
        // break, which is the same exclusion `RepairableJoins.walkable` makes and for the same
        // reason: nothing overlaps there, so dragging it would move nothing.
        for seam in session.seams.filter(\.isLowConfidence).sorted(by: { $0.fromIndex < $1.fromIndex }) {
            guard let destY = placement.destY(forJoin: seam.fromIndex) else { continue }
            drafts.append(Draft(
                id: "seam-\(seam.fromIndex)",
                kind: .seam,
                atPct: Double(destY) / height,
                target: .join(seam.fromIndex),
                title: "Seam after frame \(seam.fromIndex + 1)",
                question: "Does this line up?",
                detail: "Drag the lower half until the two halves meet.",
                dy: seam.provisionalDy,
                confidence: seam.confidence
            ))
        }

        return drafts
            .sorted { a, b in a.kind == b.kind ? a.atPct < b.atPct : a.kind < b.kind }
            .enumerated()
            .map { index, d in
                Finding(
                    id: d.id, n: index + 1, kind: d.kind, atPct: d.atPct, target: d.target,
                    title: d.title, question: d.question, detail: d.detail,
                    dy: d.dy, confidence: d.confidence
                )
            }
    }
}

nonisolated enum CaptureMarks {

    /// Every join in the capture, with the numbered ones carrying their finding's number so
    /// the mark on the sheet and the row in the queue are the same thing.
    static func all(in session: StitchSession, placement: Placement, findings: [Finding]) -> [CaptureMark] {
        guard placement.totalHeight > 0 else { return [] }
        let height = Double(placement.totalHeight)
        let byTarget = Dictionary(findings.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })

        var marks: [CaptureMark] = []

        for seam in session.seams.sorted(by: { $0.fromIndex < $1.fromIndex }) {
            guard let destY = placement.destY(forJoin: seam.fromIndex) else { continue }
            let finding = byTarget[.join(seam.fromIndex)]
            marks.append(CaptureMark(
                id: "join-\(seam.fromIndex)",
                kind: finding == nil ? .confident : .flagged,
                atPct: Double(destY) / height,
                n: finding?.n,
                lostLabel: nil
            ))
        }

        for span in session.segmentBreaks.sorted(by: { $0.afterKeyframeIndex < $1.afterKeyframeIndex }) {
            guard let destY = placement.destY(forBreakAfter: span.afterKeyframeIndex) else { continue }
            marks.append(CaptureMark(
                id: "break-\(span.afterKeyframeIndex)",
                kind: .gap,
                atPct: Double(destY) / height,
                n: byTarget[.gap(afterKeyframeIndex: span.afterKeyframeIndex)]?.n,
                // The engine cannot know how much was never revealed — that is what a break
                // is. Naming a pixel count here would be inventing a number.
                lostLabel: "lost lock"
            ))
        }

        // A bars finding is about a whole frame rather than a join, so it gets a margin marker
        // (from `findings`) but no rule on the sheet — there is no line to draw.
        return marks.sorted { $0.atPct < $1.atPct }
    }
}

extension Finding.Target: Hashable {}
```

- [ ] **Step 4: Point `CaptureCondition` at its new neighbour**

In `Seamly/Seamly/DesignSystem/CaptureCondition.swift`, extend the doc comment on `enum CaptureCondition` with a final paragraph:

```swift
/// This type is the **aggregate** verdict — one line for the whole capture. `Finding` in
/// `CaptureFinding.swift` is the per-item companion the design's repair queue walks, and the
/// two split the vocabulary deliberately: this type's `Imperfection` wording predates the
/// design system and avoids pipeline words; `Finding`'s uses them, because the design puts
/// them on screen. Both live in this folder so there is still exactly one place where a
/// pipeline fact becomes English.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SeamlyTests/CaptureFindingsTests \
  -only-testing:SeamlyTests/CaptureConditionTests test
```
Expected: PASS. `CaptureConditionTests` is included to prove the doc-only change to that file broke nothing.

- [ ] **Step 6: Commit**

```bash
git add Seamly/Seamly/DesignSystem/CaptureFinding.swift \
        Seamly/Seamly/DesignSystem/CaptureCondition.swift \
        Seamly/SeamlyTests/CaptureFindingsTests.swift
git commit -m "$(cat <<'EOF'
feat(design): enumerate a capture's own problems as findings

A capture knows its weak points; this is where it lists them. Each finding
carries a number, a place in the finished image, a question, and what
answering it changes — the three inputs the margin marker, the position
scale and the repair queue all need.

Ranked gap > bars > seam, the ranking Imperfection.Kind already uses, then
by position, then numbered. So the number on a marker in the margin is the
number the queue counts by, which is the whole point of the pairing.

A gap says "lost lock", not a pixel count: the engine cannot know how much
a break swallowed, and naming a number would be inventing one. A flagged
seam across a break is not a finding at all — nothing overlaps there, the
same exclusion RepairableJoins.walkable makes.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: The marks — sheet, seam, margin marker, position scale

The four components that make the margin carry signal. Built before `CaptureView` so it has something to compose, and kept dumb: they take a position in points and draw. All the arithmetic is Task 3's.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Components/Data/CaptureSheetView.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Marks/SeamMark.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Marks/MarginMarker.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Marks/PositionScale.swift`

**Interfaces:**
- Consumes: `SeamlyColor`, `SeamlySpace`, `SeamlyRadius`, `SeamlyFont`, `SeamlyMotion` (Task 2); `CaptureMark` (Task 4).
- Produces:
  - `struct CaptureSheetView<Content: View>: View` — `init(ribbon: Bool = false, @ViewBuilder content: () -> Content)`
  - `struct SeamMark: View` — `init(kind: CaptureMark.Kind, lostLabel: String? = nil)`
  - `struct MarginMarker: View` — `init(n: Int, kind: CaptureMark.Kind, selected: Bool, action: @escaping () -> Void)`
  - `struct PositionScale: View` — `init(heightPx: Int, viewportTopPct: Double, viewportPct: Double, marks: [CaptureMark], orientation: Axis, onScrub: ((Double) -> Void)?)`

- [ ] **Step 1: Write `CaptureSheetView`**

Create `Seamly/Seamly/DesignSystem/Components/Data/CaptureSheetView.swift`:

```swift
import SwiftUI

/// A capture rendered as a SHEET: white, square-cornered, with its own edge and lift, sitting
/// on the paper ground.
///
/// Never bled to the screen edge — the edge is what tells you where the capture stops and the
/// app begins, which is the job a black canvas does in a dark system.
///
/// The white is `SeamlyColor.sheet`, which is fixed in BOTH themes and is not a semantic
/// background: a capture has its own brightness and must never be dimmed in dark mode.
struct CaptureSheetView<Content: View>: View {
    /// A thin strip down the right edge showing the whole capture squeezed, so length is
    /// legible without a misleading crop. Off inside `CaptureView`, which shows the capture
    /// itself; on for the library's thumbnails.
    var ribbon: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        Rectangle()
            .fill(SeamlyColor.sheet)
            .overlay { content() }
            .clipShape(Rectangle())
            .seamlySheetLift()
    }
}
```

- [ ] **Step 2: Write `SeamMark`**

Create `Seamly/Seamly/DesignSystem/Components/Marks/SeamMark.swift`:

```swift
import SwiftUI

/// How a join is drawn ON the sheet. Deliberately quiet: principle 1 says a good capture must
/// look like ONE IMAGE, so a confident join is nearly invisible and a flagged one is a thin
/// ruled line — not a glowing bar.
///
/// Findability is **not** this component's job. That belongs to `MarginMarker` and
/// `PositionScale`, which sit off the image where the ground is always paper and contrast is
/// guaranteed whatever was captured. That division is the whole reason a light ground works.
struct SeamMark: View {
    let kind: CaptureMark.Kind
    /// Required for a gap — always label what was lost.
    var lostLabel: String?

    private var color: Color {
        switch kind {
        case .confident: SeamlyColor.seamConfident
        case .flagged: SeamlyColor.seamFlag
        case .gap: SeamlyColor.seamGap
        }
    }

    private var width: CGFloat {
        kind == .confident ? SeamlySpace.seamWidth : SeamlySpace.seamWidthMark
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if kind == .gap {
                // Dashed, because nothing joins here — the two sides are not continuous.
                Rectangle()
                    .strokeBorder(style: StrokeStyle(lineWidth: width, dash: [5, 4]))
                    .foregroundStyle(color)
                    .frame(height: width)
            } else {
                Rectangle().fill(color).frame(height: width)
            }
            if let lostLabel {
                Text(lostLabel)
                    .font(SeamlyFont.mono)
                    .foregroundStyle(SeamlyColor.markGap)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(SeamlyColor.sheet)
                    .padding(.trailing, SeamlySpace.s3)
                    .offset(y: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3: Write `MarginMarker`**

Create `Seamly/Seamly/DesignSystem/Components/Marks/MarginMarker.swift`:

```swift
import SwiftUI

/// THE answer to the Paper direction's one real weakness.
///
/// On a light ground a thin rule over white captured content can be missed. So the signal does
/// not live on the image — it lives in the MARGIN, where the ground is always paper and
/// contrast is guaranteed regardless of what was captured. A numbered ring, a proof-reader's
/// mark: legible, countable, tappable, and tied to its row in the queue **by number**.
struct MarginMarker: View {
    let n: Int
    let kind: CaptureMark.Kind
    var selected: Bool = false
    let action: () -> Void

    private var color: Color {
        switch kind {
        case .gap: SeamlyColor.markGap
        case .confident: SeamlyColor.inkFaint
        case .flagged: SeamlyColor.markFlag
        }
    }

    var body: some View {
        Button(action: action) {
            Text("\(n)")
                .font(SeamlyFont.caps)
                .monospacedDigit()
                .foregroundStyle(selected ? SeamlyColor.sheet : color)
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(selected ? color : SeamlyColor.paper)
                }
                .overlay {
                    Circle().strokeBorder(color, lineWidth: 1.5)
                }
                // The ring is 24 pt but the target must not be, and the rail is only 34 pt
                // wide — so the target grows vertically, where there is room.
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .animation(SeamlyMotion.press, value: selected)
        .accessibilityLabel("Mark \(n)")
        .accessibilityIdentifier("margin-marker-\(n)")
    }
}
```

- [ ] **Step 4: Write `PositionScale`**

Create `Seamly/Seamly/DesignSystem/Components/Marks/PositionScale.swift`:

```swift
import SwiftUI

/// Principle 4: position is always answerable. The whole capture squeezed into a ruled scale,
/// with the viewport as a bracket and every mark as a tick.
///
/// **Ruled, not filled** — a document's edge scale rather than a video scrubber. Goes
/// horizontal on a short viewport (landscape iPhone), where a vertical scale would eat the
/// little height there is.
struct PositionScale: View {
    let heightPx: Int
    let viewportTopPct: Double
    let viewportPct: Double
    let marks: [CaptureMark]
    var orientation: Axis = .vertical
    var onScrub: ((Double) -> Void)?

    private func tone(_ kind: CaptureMark.Kind) -> Color {
        switch kind {
        case .flagged: SeamlyColor.markFlag
        case .gap: SeamlyColor.markGap
        case .confident: SeamlyColor.ruleStrong
        }
    }

    var body: some View {
        GeometryReader { geo in
            let along = orientation == .vertical ? geo.size.height : geo.size.width
            ZStack(alignment: .topLeading) {
                // Graduations every 10%, longer every 50% — so it reads as measurement.
                ForEach(0..<11, id: \.self) { i in
                    let length: CGFloat = i % 5 == 0 ? 8 : 4
                    Rectangle()
                        .fill(SeamlyColor.rule)
                        .frame(
                            width: orientation == .vertical ? length : 1,
                            height: orientation == .vertical ? 1 : length
                        )
                        .offset(
                            x: orientation == .vertical ? 0 : along * CGFloat(i) / 10,
                            y: orientation == .vertical ? along * CGFloat(i) / 10 : 0
                        )
                }
                ForEach(marks) { mark in
                    Rectangle()
                        .fill(tone(mark.kind))
                        .frame(
                            width: orientation == .vertical ? nil : 2,
                            height: orientation == .vertical ? 2 : nil
                        )
                        .frame(
                            maxWidth: orientation == .vertical ? .infinity : nil,
                            maxHeight: orientation == .vertical ? nil : .infinity
                        )
                        .offset(
                            x: orientation == .vertical ? 0 : along * CGFloat(mark.atPct),
                            y: orientation == .vertical ? along * CGFloat(mark.atPct) : 0
                        )
                }
                Rectangle()
                    .fill(SeamlyColor.accentWash)
                    .overlay { Rectangle().strokeBorder(SeamlyColor.accent, lineWidth: 1.5) }
                    .frame(
                        width: orientation == .vertical ? nil : max(2, along * CGFloat(viewportPct)),
                        height: orientation == .vertical ? max(2, along * CGFloat(viewportPct)) : nil
                    )
                    .frame(
                        maxWidth: orientation == .vertical ? .infinity : nil,
                        maxHeight: orientation == .vertical ? nil : .infinity
                    )
                    .offset(
                        x: orientation == .vertical ? 0 : along * CGFloat(viewportTopPct),
                        y: orientation == .vertical ? along * CGFloat(viewportTopPct) : 0
                    )
                    .animation(SeamlyMotion.jump, value: viewportTopPct)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(scrub(along: along))
        }
        .frame(
            width: orientation == .vertical ? SeamlySpace.scaleRail : nil,
            height: orientation == .vertical ? nil : SeamlySpace.scaleRail
        )
        .overlay(alignment: orientation == .vertical ? .leading : .top) {
            Rectangle()
                .fill(SeamlyColor.rule)
                .frame(
                    width: orientation == .vertical ? 1 : nil,
                    height: orientation == .vertical ? nil : 1
                )
        }
        .accessibilityElement()
        .accessibilityLabel("Position in capture")
        .accessibilityValue("\(Int((viewportTopPct * 100).rounded())) percent of \(SeamlyNumber.px(heightPx))")
    }

    private func scrub(along: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            guard let onScrub, along > 0 else { return }
            let raw = orientation == .vertical ? value.location.y : value.location.x
            onScrub(Double(min(max(0, raw / along), 1)))
        }
    }
}
```

- [ ] **Step 5: Build**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Data/CaptureSheetView.swift \
        Seamly/Seamly/DesignSystem/Components/Marks
git commit -m "$(cat <<'EOF'
feat(design): add the sheet and the three marks

SeamMark stays quiet on the sheet because a good capture must look like
one image. MarginMarker and PositionScale carry findability from off the
image, where the ground is always paper and contrast is guaranteed
whatever was captured. That division is what lets a light ground work.

The components take a position and draw; none of them computes one. The
arithmetic is CaptureGeometry's, in one place, so a marker and its rule
cannot land on different rows.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `CaptureView` — one coordinate space, proven

The load-bearing screen element. **Nothing else is built until this is looked at on a simulator and the margin marker is confirmed to sit on its rule.**

**Files:**
- Create: `Seamly/Seamly/DesignSystem/CaptureView.swift`

**Interfaces:**
- Consumes: `CaptureGeometry` (Task 3), `CaptureMark` (Task 4), `CaptureSheetView`/`SeamMark`/`MarginMarker`/`PositionScale` (Task 5), `ZoomState` (existing).
- Produces:
  - `struct CaptureJump: Equatable` — `init(atPct: Double, fraction: CGFloat = 0.4, token: Int)`
  - `enum CaptureSheetContent` — `.proxy(CGImage)`, `.join(upper: CGImage, lower: CGImage, alignment: JoinAlignment)` (the `.join` case is filled in by Task 11; declare both now with `.join` unhandled by a `switch` default only where noted)
  - `struct CaptureView: View` — `init(content:captureSize:marks:findings:zoom:selected:showScale:jump:onSelect:)`. **Two collections, not one:** `marks` drives the quiet rules on the sheet and the position scale's ticks; `findings` drives the numbered rings in the margin. They are different sets — a confident join is a mark with no finding, and a bars finding is a finding with no mark.

- [ ] **Step 1: Write `CaptureView` with the proxy content source**

Create `Seamly/Seamly/DesignSystem/CaptureView.swift`:

```swift
import SwiftUI
import CoreGraphics

/// A request to pan the capture so a mark is on screen. A token rather than just a position,
/// so asking for the same mark twice fires twice — a user tapping the marker they are already
/// looking at expects it to re-centre, not to do nothing.
struct CaptureJump: Equatable {
    let atPct: Double
    var fraction: CGFloat = 0.4
    let token: Int
}

/// What the sheet is showing.
enum CaptureSheetContent {
    /// The whole capture, downscaled. `StitchAssembler.makeProxy` caps it at 4096 px tall.
    case proxy(CGImage)
    /// The two full-resolution frames either side of one join, live under the finger.
    ///
    /// The proxy is only rebuilt after a commit, so a repair drag against it would move
    /// nothing visible. Filled in by Task 11.
    case join(upper: CGImage, lower: CGImage, alignment: JoinAlignment)
}

/// The sheet, its margin rail and its position scale — shared by Home, Review and the repair
/// queue, so all three agree about where a mark is.
///
/// **This is where the direction lives or dies.** A mark's position on screen is
/// `atPct * contentHeight - scrollY`, and the margin marker beside it must use the same number
/// or the margin stops carrying signal. So there is exactly one `GeometryReader`, exactly one
/// `scrollY`, and every element — the image, the rules on the sheet, the numbered markers, the
/// scale's bracket — is placed from them. There is nothing for them to drift relative to.
///
/// The scroll content is a bare `Color.clear` spacer, which carries no raster: a capture at 6×
/// is tens of thousands of points tall, and a texture that size exceeds the ~16 384 px GPU
/// ceiling. The image is drawn in an overlay pinned to the viewport and offset by `-scrollY`,
/// so nothing larger than the screen is ever rasterised. (`CaptureCanvas`, which this replaces,
/// did bind the whole proxy into the scroll content and had exactly that bug.)
struct CaptureView: View {
    let content: CaptureSheetContent
    /// The whole capture in source pixels — `Placement.totalHeight` and the keyframe width.
    let captureSize: CGSize
    /// Every join, drawn as a quiet rule ON the sheet. Confident ones included and unnumbered.
    var marks: [CaptureMark] = []
    /// Every doubt, drawn as a numbered ring IN the margin.
    ///
    /// Deliberately a separate collection from `marks`, because the two are not the same set.
    /// A confident join is a mark with no finding; a bars finding is a finding with no mark —
    /// it is about a whole frame rather than a join, so there is no line to draw on the sheet,
    /// but it must still be numbered and reachable in the margin. Driving the rail from `marks`
    /// would make every bars finding invisible and unanswerable.
    var findings: [Finding] = []
    var zoom: CGFloat = 1
    var selected: Int?
    var showScale: Bool = true
    var jump: CaptureJump?
    var onSelect: ((Int) -> Void)?

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    @State private var scrollY: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }

    var body: some View {
        VStack(spacing: SeamlySpace.s3) {
            HStack(spacing: SeamlySpace.s3) {
                GeometryReader { geo in
                    let sheetWidth = geo.size.width - SeamlySpace.marginRail - SeamlySpace.s3
                        - (showScale && !layout.isShort ? SeamlySpace.scaleRail + SeamlySpace.s3 : 0)
                    let g = CaptureGeometry(
                        sheetWidth: max(0, sheetWidth),
                        viewportHeight: geo.size.height,
                        captureSize: captureSize,
                        zoom: zoom,
                        scrollY: scrollY
                    )
                    HStack(spacing: SeamlySpace.s3) {
                        marginRail(g)
                        sheet(g)
                        if showScale && !layout.isShort { scale(g) }
                    }
                    .onChange(of: jump) { _, target in
                        guard let target else { return }
                        withAnimation(SeamlyMotion.jump) {
                            scrollPosition.scrollTo(y: g.scrollY(toShow: target.atPct, at: target.fraction))
                        }
                    }
                }
            }
            if showScale && layout.isShort { shortScale() }
        }
    }

    // MARK: - The margin — always paper, so contrast never depends on the capture

    @ViewBuilder
    private func marginRail(_ g: CaptureGeometry) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(findings) { finding in
                let y = g.y(atPct: finding.atPct)
                if g.isVisible(y) {
                    MarginMarker(
                        n: finding.n,
                        // A gap reads in its own tone; bars and seams are both "uncertain".
                        kind: finding.kind == .gap ? .gap : .flagged,
                        selected: selected == finding.n,
                        action: { onSelect?(finding.n) }
                    )
                    .offset(y: y - 12)
                }
            }
        }
        .frame(width: SeamlySpace.marginRail)
        .clipped()
    }

    // MARK: - The sheet

    @ViewBuilder
    private func sheet(_ g: CaptureGeometry) -> some View {
        CaptureSheetView {
            switch content {
            case .proxy(let image):
                proxySheet(image, g)
            case .join(let upper, let lower, let alignment):
                joinSheet(upper: upper, lower: lower, alignment: alignment, g: g)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func proxySheet(_ image: CGImage, _ g: CaptureGeometry) -> some View {
        ScrollView(.vertical) {
            // No raster: the extent exists so the scroll view has somewhere to go.
            Color.clear.frame(height: g.contentHeight)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            scrollY = y
        }
        // `.topLeading`, NOT the default `.center`: once the image's frame exceeds the
        // viewport — routine at any real zoom or content height — a centred overlay silently
        // shifts the marks off screen, and the margin stops agreeing with the sheet. Found by
        // eye during Task 6's visual gate; a green build cannot see it.
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                Color.clear
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: g.sheetWidth * zoom, height: g.contentHeight)
                    // Centred horizontally: there is deliberately no panning, so whichever
                    // slice is shown at zoom is the middle one, not the left edge.
                    .offset(x: -(g.sheetWidth * zoom - g.sheetWidth) / 2, y: -scrollY)
                ForEach(marks) { mark in
                    let y = g.y(atPct: mark.atPct)
                    if g.isVisible(y) {
                        SeamMark(kind: mark.kind, lostLabel: mark.lostLabel)
                            .offset(y: y)
                    }
                }
            }
            // The overlay must not eat the scroll gesture underneath it.
            .allowsHitTesting(false)
        }
        .clipped()
        .accessibilityLabel("Stitched capture")
        .accessibilityHint("Scroll to move through the capture. Pinch to zoom in.")
        .accessibilityIdentifier("capture-sheet")
    }

    // MARK: - The scale

    @ViewBuilder
    private func scale(_ g: CaptureGeometry) -> some View {
        PositionScale(
            heightPx: Int(captureSize.height),
            viewportTopPct: g.viewportTopPct,
            viewportPct: g.viewportPct,
            marks: marks,
            orientation: .vertical,
            onScrub: { pct in
                withAnimation(SeamlyMotion.jump) {
                    scrollPosition.scrollTo(y: g.scrollY(toShow: pct, at: 0.1))
                }
            }
        )
    }

    /// A short viewport (landscape iPhone) gets a horizontal scale below the sheet, because a
    /// vertical one would eat the little height there is.
    @ViewBuilder
    private func shortScale() -> some View {
        PositionScale(
            heightPx: Int(captureSize.height),
            viewportTopPct: 0,
            viewportPct: 1,
            marks: marks,
            orientation: .horizontal,
            onScrub: nil
        )
    }
}
```

The `.join` branch calls `joinSheet`, which the repair queue does not need until Task 11. For this task it is a stub that compiles and is obviously unfinished; Task 11 replaces it with the live pair:

```swift
    // Filled in by Task 11, when the repair queue needs a live pair under the finger.
    @ViewBuilder
    private func joinSheet(upper: CGImage, lower: CGImage, alignment: JoinAlignment, g: CaptureGeometry) -> some View {
        Color.clear
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Add a preview that exercises the alignment**

Append to `CaptureView.swift`:

```swift
#Preview("Marks line up with the margin") {
    // A tall striped proxy with marks at exact tenths, so a marker sitting off its rule is
    // visible by eye rather than only under a ruler.
    let width = 300, height = 6000
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // A CGBitmapContext has a BOTTOM-left origin, so a bar filled at `pct * height` renders
    // at `1 - pct` from the top once `Image(decorative:)` draws it top-down. Flip the context
    // so the fixture shares the orientation of the thing it is testing. This repo has shipped
    // the un-flipped version of this mistake before: an upside-down synthetic fixture cancelled
    // out a real sign error in VerticalProfile and hid it for three fix cycles (CLAUDE.md,
    // "A green suite here has lied three times"). `TestImages.make` in StitchKit flips for the
    // same reason.
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(gray: 0.72, alpha: 1)
    for band in stride(from: 0, to: height, by: 60) {
        ctx.fill(CGRect(x: 0, y: band, width: width, height: 22))
    }
    // A black bar exactly at each mark, so the rule and the marker have something to agree with.
    // Deliberately ASYMMETRIC. A symmetric set (0.2/0.5/0.8) is mirror-invariant, so every ring
    // would land on *a* bar even if the fixture and the geometry were both flipped — the preview
    // could not tell "correct" from "two errors cancelling".
    ctx.setFillColor(gray: 0.1, alpha: 1)
    for pct in [0.15, 0.5, 0.72] {
        ctx.fill(CGRect(x: 0, y: Int(Double(height) * pct), width: width, height: 3))
    }
    let image = ctx.makeImage()!

    return CaptureView(
        content: .proxy(image),
        captureSize: CGSize(width: width, height: height),
        marks: [
            CaptureMark(id: "a", kind: .flagged, atPct: 0.15, n: 1, lostLabel: nil),
            CaptureMark(id: "b", kind: .gap, atPct: 0.5, n: 2, lostLabel: "lost lock"),
            CaptureMark(id: "c", kind: .confident, atPct: 0.72, n: nil, lostLabel: nil),
        ],
        findings: [
            Finding(id: "a", n: 1, kind: .seam, atPct: 0.15, target: .join(0),
                    title: "Seam after frame 1", question: "Does this line up?",
                    detail: "", dy: 100, confidence: 0.3),
            Finding(id: "b", n: 2, kind: .gap, atPct: 0.5, target: .gap(afterKeyframeIndex: 1),
                    title: "Gap after frame 2", question: "Nothing was captured here",
                    detail: "", dy: nil, confidence: nil),
        ],
        selected: 1,
        onSelect: { _ in }
    )
    .padding(SeamlySpace.gutterCompact)
    .background(SeamlyColor.paper)
}
```

- [ ] **Step 4: Look at it — the gate for this whole plan**

Open `Seamly/Seamly.xcodeproj`, open `CaptureView.swift`, and run the preview on an iPhone 17 simulator. A green build proves none of this; the whole direction rests on what you see.

Confirm, by eye and then by scrolling:

1. The numbered ring at 15 % sits on the black bar at 15 %, not above or below it. Because the
   bar set is asymmetric, a ring landing on a bar means the orientation is genuinely right —
   not that two flips cancelled.
2. Scrolling moves the ring and its bar together — the ring never lags or leads.
3. At 50 % the dashed gap rule and its `lost lock` label are on the same row as marker 2.
4. Pinching (once Task 9 wires zoom in) or setting `zoom: 3` in the preview keeps all three aligned.
5. Marker 3 has no ring — a confident join draws no number, because only doubt draws attention.
6. Switch the preview to dark: the sheet stays white and the desk darkens.

If a marker and its rule disagree, **stop and fix `CaptureGeometry` or the overlay's offset**. Do not build a screen on top of it.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/CaptureView.swift
git commit -m "$(cat <<'EOF'
feat(design): add CaptureView, the shared capture surface

One GeometryReader, one scrollY. The image, the rules on the sheet, the
numbered markers in the margin and the position scale's bracket are all
placed from the same two numbers, so they cannot drift apart — which is
the condition on the margin carrying signal at all.

The scroll content is a bare Color.clear spacer and the image is drawn in
an overlay pinned to the viewport. So a 6x capture never rasterises more
than a screenful, where CaptureCanvas bound the whole proxy into scroll
content tens of thousands of points tall — past the GPU texture ceiling.

Verified by eye against a preview whose marks sit on drawn bars, in both
themes, before anything was built on top of it.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Base components — button, icon button, nav bar, status note, empty state

Everything the screens are assembled from. Dumb views, no model access.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Components/Actions/SeamlyButton.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Actions/IconButton.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Navigation/NavBar.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Data/StatusNote.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Feedback/EmptyState.swift`

**Interfaces:**
- Consumes: tokens (Task 2).
- Produces:
  - `struct SeamlyButton<Label: View>: View` — memberwise `init(variant:size:symbol:action:label:)`, plus the convenience `init(_ title: String, variant:size:symbol:action:)` used by every call site in this plan
  - `enum SeamlyButton.Variant` — `.filled`, `.tonal`, `.outline`, `.plain`, `.danger`
  - `enum SeamlyButton.Size` — `.small`, `.medium`, `.large`
  - `struct IconButton: View` — `init(symbol: String, label: String, count: Int? = nil, action:)`
  - `struct NavBar<Trailing: View>: View` — `init(title:subtitle:large:backLabel:onBack:@ViewBuilder trailing:)`
  - `struct StatusNote: View` — `init(kind:count:label:size:)`, all but `kind` defaulted
  - `enum StatusNote.Kind` — `.ready`, `.processing`, `.flagged`, `.gap`, `.bars`, `.incomplete`, `.orderAssumed`, `.failed`
  - `struct EmptyState<Actions: View>: View` — `init(symbol:title:message:@ViewBuilder actions:)`, plus `init(symbol:title:message:)` where `Actions == EmptyView`

- [ ] **Step 1: Write `SeamlyButton`**

Create `Seamly/Seamly/DesignSystem/Components/Actions/SeamlyButton.swift`:

```swift
import SwiftUI

/// PAPER buttons: filled is a solid ink-blue slab, tonal is a wash, plain is bare type. The
/// radius is small — this is a document, not a bubble.
struct SeamlyButton<Label: View>: View {
    enum Variant { case filled, tonal, outline, plain, danger }
    enum Size { case small, medium, large }

    var variant: Variant = .filled
    var size: Size = .medium
    var symbol: String?
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @Environment(\.isEnabled) private var isEnabled

    private var foreground: Color {
        switch variant {
        case .filled: SeamlyColor.inkInverse
        case .tonal, .plain: SeamlyColor.accent
        case .outline: SeamlyColor.ink
        case .danger: SeamlyColor.markError
        }
    }

    private var background: Color {
        switch variant {
        case .filled: SeamlyColor.accent
        case .tonal: SeamlyColor.accentWash
        case .danger: SeamlyColor.washError
        case .outline, .plain: .clear
        }
    }

    private var height: CGFloat {
        switch size {
        case .small: 36
        case .medium: SeamlySpace.hitMin
        case .large: 52
        }
    }

    private var font: Font {
        size == .small ? SeamlyFont.footnote : SeamlyFont.headline
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .small: 12
        case .medium: 18
        case .large: 22
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeamlySpace.s3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: size == .small ? 16 : 18))
                }
                label()
            }
            .font(font)
            .foregroundStyle(foreground)
            .frame(minWidth: SeamlySpace.hitMin)
            .frame(height: height)
            .padding(.horizontal, horizontalPadding)
            .background(background)
            .overlay {
                if variant == .outline {
                    RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                        .strokeBorder(SeamlyColor.ruleStrong, lineWidth: 1)
                }
            }
            .seamlyCorners(SeamlyRadius.sm)
            .opacity(isEnabled ? 1 : SeamlyMotion.disabledOpacity)
            // The design specifies a 36pt slab for `.small`, and that is what gets painted —
            // but a 36pt tap target is below the 44pt floor. So the target grows around the
            // slab rather than the slab growing to meet it: `minHeight` first, `contentShape`
            // after, so the whole 44pt box is tappable while only 36pt is drawn.
            .frame(minHeight: SeamlySpace.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension SeamlyButton where Label == Text {
    init(_ title: String, variant: Variant = .filled, size: Size = .medium,
         symbol: String? = nil, action: @escaping () -> Void) {
        self.init(variant: variant, size: size, symbol: symbol, action: action) { Text(title) }
    }
}
```

- [ ] **Step 2: Write `IconButton`**

Create `Seamly/Seamly/DesignSystem/Components/Actions/IconButton.swift`:

```swift
import SwiftUI

/// A 44 pt target always, even when the glyph is 20. `count` renders a numeral beside the
/// glyph rather than a bare dot — state is never colour alone.
struct IconButton: View {
    let symbol: String
    let label: String
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 20))
                if let count, count > 0 {
                    Text("\(count)").font(SeamlyFont.mono)
                }
            }
            .foregroundStyle(SeamlyColor.inkMuted)
            .padding(.horizontal, SeamlySpace.s3)
            .seamlyHitTarget()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 3: Write `NavBar`**

Create `Seamly/Seamly/DesignSystem/Components/Navigation/NavBar.swift`:

```swift
import SwiftUI

/// The Paper nav bar. A custom view rather than the system bar, because the design's bar
/// carries a mono tabular subtitle, a `large` variant, and a paper ground with a rule — none
/// of which a `UINavigationBar` expresses.
///
/// **Cost, accepted:** the screens using this hide the system bar, which disables the
/// interactive swipe-back gesture. Only two pushes exist (Home → Library → Review) and both
/// carry a visible back control. Recorded in the spec as a decision, not discovered later.
struct NavBar<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var large: Bool = false
    var backLabel: String = ""
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: large ? .bottom : .center, spacing: SeamlySpace.s4) {
            if let onBack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 20))
                        if !backLabel.isEmpty { Text(backLabel).font(SeamlyFont.body) }
                    }
                    .foregroundStyle(SeamlyColor.accent)
                    // BOTH dimensions: `backLabel` is empty on most screens, leaving a bare
                    // 20pt chevron whose intrinsic width is far under the 44pt floor. A height
                    // floor alone would have left it tall and thin.
                    .frame(minWidth: SeamlySpace.hitMin, minHeight: SeamlySpace.hitMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(backLabel.isEmpty ? "Back" : backLabel)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(large ? SeamlyFont.largeTitle : SeamlyFont.headline)
                    .foregroundStyle(SeamlyColor.ink)
                    .modifier(TitleTracking(large: large))
                if let subtitle {
                    Text(subtitle)
                        .font(SeamlyFont.mono)
                        .foregroundStyle(SeamlyColor.inkFaint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) { trailing() }
        }
        .padding(.horizontal, large ? SeamlySpace.gutterCompact : SeamlySpace.s4)
        .padding(.bottom, SeamlySpace.s4)
        .frame(maxWidth: .infinity)
        .background(SeamlyColor.paper)
        .overlay(alignment: .bottom) {
            if !large {
                Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
            }
        }
    }
}

extension NavBar where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, large: Bool = false,
         backLabel: String = "", onBack: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, large: large,
                  backLabel: backLabel, onBack: onBack) { EmptyView() }
    }
}

/// Tracking is absolute points and does not scale with Dynamic Type, so it is applied only at
/// display sizes — never to the subtitle or to body copy. See FEASIBILITY.md.
///
/// The CSS has `--tracking-title: -0.012em` for the compact title, and `em` scales with the
/// type. SwiftUI's `.tracking()` does not, so porting that number would be right at one size
/// and wrong at every other — worse the larger the user sets their type. The compact title is
/// `SeamlyFont.headline`, which grows with Dynamic Type, so it gets no tracking at all. Only
/// the `large` variant, a capped display size, keeps it.
private struct TitleTracking: ViewModifier {
    let large: Bool
    func body(content: Content) -> some View {
        large ? AnyView(content.seamlyDisplayTracking()) : AnyView(content)
    }
}
```

- [ ] **Step 4: Write `StatusNote`**

Create `Seamly/Seamly/DesignSystem/Components/Data/StatusNote.swift`:

```swift
import SwiftUI

/// State is NEVER colour alone: every note carries its word. A wash behind ink — no coloured
/// left-border card, no bare dot.
struct StatusNote: View {
    enum Kind { case ready, processing, flagged, gap, bars, incomplete, orderAssumed, failed }
    enum Size { case small, medium }

    let kind: Kind
    var count: Int?
    /// Overrides the default word entirely, for the one-off lines the screens need.
    var label: String?
    var size: Size = .medium

    private var word: String {
        switch kind {
        case .ready: "Ready"
        case .processing: "Stitching…"
        case .flagged: "flagged"
        case .gap: "gap"
        case .bars: "bars uncertain"
        case .incomplete: "Incomplete"
        case .orderAssumed: "Order assumed"
        case .failed: "Couldn't stitch"
        }
    }

    private var symbol: String {
        switch kind {
        case .ready: "checkmark"
        case .processing: "list.bullet"
        case .flagged: "flag"
        case .gap: "scissors"
        case .bars: "rectangle.dashed"
        case .incomplete: "exclamationmark.circle"
        case .orderAssumed: "arrow.up.arrow.down"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var tone: Color? {
        switch kind {
        case .ready: SeamlyColor.markOK
        case .flagged, .bars: SeamlyColor.markFlag
        case .gap: SeamlyColor.markGap
        case .incomplete, .failed: SeamlyColor.markError
        case .processing, .orderAssumed: nil
        }
    }

    private var wash: Color {
        switch kind {
        case .ready: SeamlyColor.washOK
        case .flagged, .bars: SeamlyColor.washFlag
        case .gap: SeamlyColor.washGap
        case .incomplete, .failed: SeamlyColor.washError
        case .processing, .orderAssumed: .clear
        }
    }

    private var text: String {
        if let label { return label }
        if let count { return "\(count) \(word)" }
        return word
    }

    var body: some View {
        let small = size == .small
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: small ? 11 : 13, weight: .medium))
            Text(text).monospacedDigit()
        }
        .font(small ? SeamlyFont.caps : SeamlyFont.caption)
        .foregroundStyle(tone ?? SeamlyColor.inkMuted)
        .padding(.horizontal, small ? 7 : 9)
        .frame(height: small ? 20 : 24)
        .background(wash)
        .seamlyCorners(SeamlyRadius.xs)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}
```

- [ ] **Step 5: Write `EmptyState`**

Create `Seamly/Seamly/DesignSystem/Components/Feedback/EmptyState.swift`:

```swift
import SwiftUI

struct EmptyState<Actions: View>: View {
    var symbol: String = "photo"
    let title: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: SeamlySpace.s4) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(SeamlyColor.inkFaint)
            Text(title)
                .font(SeamlyFont.title3)
                .foregroundStyle(SeamlyColor.ink)
                .seamlyDisplayTracking()
            if let message {
                Text(message)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    // No ch-to-pt guess: the column caps the measure, per FEASIBILITY.md.
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            actions()
        }
        .frame(maxWidth: SeamlySpace.columnMax)
        .padding(.vertical, SeamlySpace.s10)
        .padding(.horizontal, SeamlySpace.gutterCompact)
    }
}

extension EmptyState where Actions == EmptyView {
    init(symbol: String = "photo", title: String, message: String? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
```

- [ ] **Step 6: Build**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Actions \
        Seamly/Seamly/DesignSystem/Components/Navigation/NavBar.swift \
        Seamly/Seamly/DesignSystem/Components/Data/StatusNote.swift \
        Seamly/Seamly/DesignSystem/Components/Feedback/EmptyState.swift
git commit -m "$(cat <<'EOF'
feat(design): add the base components

Button, IconButton, NavBar, StatusNote, EmptyState. Square-ish controls
on a paper ground, a rule instead of a shadow, and every status carrying
its word — state is never colour alone.

NavBar is custom rather than the system bar: a mono tabular subtitle, a
large variant, and a paper ground are not things a UINavigationBar
expresses. That costs the interactive swipe-back on the two pushes in the
app, which the spec accepts and records.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `CaptureDock` and `ImportRow`

The capture affordance is permanently present, never a toolbar icon. That is the return-home IA showing up as a component.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Components/Capture/CaptureDock.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Capture/ImportRow.swift`

**Interfaces:**
- Consumes: tokens (Task 2), `BroadcastPickerButton` (existing).
- Produces:
  - `struct CaptureDock: View` — `init(recording: Bool = false, onVideo: @escaping () -> Void, onPhotos: @escaping () -> Void)`
  - `struct ImportRow: View` — `init(symbol:title:detail:action:)`

- [ ] **Step 1: Write `CaptureDock`**

Create `Seamly/Seamly/DesignSystem/Components/Capture/CaptureDock.swift`:

```swift
import SwiftUI

/// Return-home IA: the capture affordance is PERMANENTLY present, never a toolbar icon.
/// Docked at the bottom, in thumb reach, with the two import paths flanking it so the hero is
/// unmistakable but the alternatives cost one tap.
///
/// The centre is `BroadcastPickerButton` rather than a `Button`, because
/// `RPSystemBroadcastPickerView` has no SwiftUI equivalent and is the project's one sanctioned
/// UIKit exception. It draws a fixed **black** glyph in both appearances and does not adapt, so
/// the accent slab behind it carries the contrast on its own, exactly as `HomeView`'s disc did.
///
/// Width is capped: a 1024 pt-wide capture button on iPad is absurd.
struct CaptureDock: View {
    var recording: Bool = false
    let onVideo: () -> Void
    let onPhotos: () -> Void

    var body: some View {
        HStack(spacing: SeamlySpace.s4) {
            side(symbol: "film", label: "From a screen recording", action: onVideo)
            ZStack {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .fill(recording ? SeamlyColor.markRec : SeamlyColor.accent)
                HStack(spacing: SeamlySpace.s3) {
                    Image(systemName: "record.circle").font(.system(size: 20, weight: .light))
                    Text(recording ? "Recording" : "Record").font(SeamlyFont.headline)
                }
                .foregroundStyle(SeamlyColor.inkInverse)
                .allowsHitTesting(false)
                // The picker sits on top, transparent, and takes the tap. Reaching into its
                // private subviews to restyle or auto-tap it is the fragility we refuse.
                // Must fill the slab. `RPSystemBroadcastPickerView` reports a small intrinsic
                // size, and a ZStack child without its own flexible frame is laid out at that
                // size and centred — which would leave the hero button tappable only in a
                // circle at its middle, with dead zones either side. The other call site in
                // this app sizes it explicitly for the same reason.
                BroadcastPickerButton()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(0.02)
                    .accessibilityLabel(recording ? "Recording" : "Record")
                    .accessibilityIdentifier("record-button")
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            side(symbol: "photo.on.rectangle", label: "From screenshots", action: onPhotos)
        }
        .frame(maxWidth: SeamlySpace.columnMax)
        .frame(maxWidth: .infinity)
    }

    private func side(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(SeamlyColor.ink)
                .frame(width: 52, height: 52)
                .background(SeamlyColor.paperRaised)
                .overlay {
                    RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                        .strokeBorder(SeamlyColor.rule, lineWidth: 1)
                }
                .seamlyCorners(SeamlyRadius.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 2: Write `ImportRow`**

Create `Seamly/Seamly/DesignSystem/Components/Capture/ImportRow.swift`:

```swift
import SwiftUI

/// A listed alternative source, or a listed export destination. Ruled, not carded — a document
/// lists things on rules.
struct ImportRow: View {
    let symbol: String
    let title: String
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SeamlySpace.s4) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(SeamlyColor.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(SeamlyFont.body).foregroundStyle(SeamlyColor.ink)
                    if let detail {
                        Text(detail).font(SeamlyFont.caption).foregroundStyle(SeamlyColor.inkFaint)
                    }
                }
                Spacer(minLength: SeamlySpace.s4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(SeamlyColor.inkFaint)
            }
            .frame(minHeight: 56)
            .padding(.vertical, SeamlySpace.s3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Capture
git commit -m "$(cat <<'EOF'
feat(design): add CaptureDock and ImportRow

The capture affordance is permanently docked, never a toolbar icon —
return-home showing up as a component. The two import paths flank it, so
the hero is unmistakable and the alternatives cost one tap.

The centre keeps BroadcastPickerButton, the project's one sanctioned UIKit
exception, laid transparently over an accent slab: the system picker draws
a fixed black glyph in both appearances, so the slab has to carry the
contrast itself.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: The shell and Home — return home

The IA change. Home stops being a launcher and becomes the most recent capture, because the app's commonest launch context is *"I just stopped a broadcast — what did I get?"*

`ResultView` and `RepairView` stay alive and reachable behind `Route.review` until Tasks 10 and 14 replace them, so the suite is green at this commit.

**Files:**
- Create: `Seamly/Seamly/Core/Capture+Design.swift`
- Create: `Seamly/Seamly/AppShell.swift`
- Create: `Seamly/Seamly/Features/Home/HomeScreen.swift`
- Modify: `Seamly/Seamly/SeamlyApp.swift`
- Modify: `Seamly/SeamlyUITests/SeamlyUITests.swift` (`testHomeShowsRecordFirst`)
- Modify: `Seamly/SeamlyUITests/RepairUITests.swift` (navigation only)

**Interfaces:**
- Consumes: `CaptureModel`, `Capture` (existing); `Placement` (Task 1); `CaptureFindings`/`CaptureMarks` (Task 4); `CaptureView` (Task 6); `NavBar`/`StatusNote`/`SeamlyButton`/`IconButton`/`EmptyState` (Task 7); `CaptureDock` (Task 8).
- Produces:
  - `extension Capture` — `var placement: Placement`, `var pixelSize: CGSize`, `var findings: [Finding]`, `var displayMarks: [CaptureMark]`, `var condition: CaptureCondition`, `var title: String`
  - `enum Route: Hashable` — `.library`, `.review(UUID)`
  - `struct AppShell: View`
  - `struct HomeScreen: View` — `init(model:onLibrary:onReview:onRepair:onHelp:onVideo:onPhotos:)`

- [ ] **Step 1: Write the capture-to-design bridge**

Create `Seamly/Seamly/Core/Capture+Design.swift`:

```swift
import CoreGraphics
import Foundation
import StitchKit

/// What a stored capture looks like to the interface.
///
/// Everything here is derived, never stored: `Placement` loads no images and a re-derive costs
/// a walk over the manifest, so there is nothing to invalidate and nothing to go stale after a
/// repair. `refinementDelta: 0` matches `StitchAssembler.composite` — the manifest is the
/// authority and the draw path never re-searches.
extension Capture {
    var placement: Placement {
        Compositor(refinementDelta: 0).placement(session)
    }

    /// The finished composite in source pixels — the width of a keyframe by the placed height.
    var pixelSize: CGSize {
        CGSize(
            width: session.keyframes.first?.pixelWidth ?? 0,
            height: placement.totalHeight
        )
    }

    var findings: [Finding] {
        CaptureFindings.all(in: session, placement: placement)
    }

    var displayMarks: [CaptureMark] {
        let p = placement
        return CaptureMarks.all(
            in: session,
            placement: p,
            findings: CaptureFindings.all(in: session, placement: p)
        )
    }

    /// The aggregate verdict, from the phase and the facts. The single caller-side rule for
    /// which `CaptureCondition` case applies, so no screen invents its own.
    var condition: CaptureCondition {
        switch phase {
        case .processing: .stitching
        case .failed(let message): .failed(message)
        case .ready: CaptureCondition(ready: CaptureFacts(session))
        }
    }

    /// "Today" / "Yesterday" / "16 August" — a capture is named by when it was made.
    var title: String {
        let calendar = Calendar.current
        let date = session.createdAt
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.wide))
    }
}
```

- [ ] **Step 2: Write `HomeScreen`**

Create `Seamly/Seamly/Features/Home/HomeScreen.swift`:

```swift
import SwiftUI
import StitchKit

/// RETURN HOME. The app is backgrounded while the user scrolls another app, so the most common
/// launch context is *"I just stopped a broadcast — what did I get?"* This screen answers that
/// before anything else: the newest capture, resolved, with its marks already visible and one
/// way into fixing them.
///
/// Tapping a margin marker here opens the repair queue at that finding, which deliberately
/// differs from Review, where the same tap only jumps. Home is a glance and the marker is the
/// way in; Review is where you are already looking, and a screen change there would throw away
/// the place you had.
struct HomeScreen: View {
    let model: CaptureModel
    var onLibrary: () -> Void
    var onReview: (UUID) -> Void
    var onRepair: (UUID, Int) -> Void
    var onHelp: () -> Void
    var onVideo: () -> Void
    var onPhotos: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @State private var jumpToken = 0

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }
    private var capture: Capture? { model.captures.first }

    var body: some View {
        VStack(spacing: 0) {
            if let capture {
                header(capture)
                stage(capture)
                statusRow(capture)
            } else {
                NavBar(title: "Seamly", subtitle: "Capture beyond the screen", large: true) {
                    IconButton(symbol: "questionmark.circle", label: "How it works", action: onHelp)
                }
                Spacer(minLength: 0)
                EmptyState(
                    symbol: "plus.viewfinder",
                    title: "Nothing captured yet",
                    message: "Record your screen while you scroll another app, and Seamly stitches everything you reveal into one image."
                )
                Spacer(minLength: 0)
            }
            CaptureDock(onVideo: onVideo, onPhotos: onPhotos)
                .padding(.horizontal, layout.gutter)
                .padding(.top, SeamlySpace.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ capture: Capture) -> some View {
        NavBar(title: "Seamly") {
            IconButton(symbol: "list.bullet", label: "Library", action: onLibrary)
            IconButton(symbol: "questionmark.circle", label: "How it works", action: onHelp)
        }
        HStack(alignment: .firstTextBaseline, spacing: SeamlySpace.s4) {
            Text(capture.title)
                .font(SeamlyFont.largeTitle)
                .foregroundStyle(SeamlyColor.ink)
                .seamlyDisplayTracking()
            Spacer(minLength: SeamlySpace.s4)
            if capture.phase == .ready {
                Text(SeamlyNumber.dimensions(
                    width: Int(capture.pixelSize.width),
                    height: Int(capture.pixelSize.height)
                ))
                .font(SeamlyFont.mono)
                .foregroundStyle(SeamlyColor.inkFaint)
            }
        }
        .padding(.horizontal, layout.gutter)
    }

    // MARK: - The capture, or what happened instead of one

    @ViewBuilder
    private func stage(_ capture: Capture) -> some View {
        Group {
            switch capture.phase {
            case .ready:
                if let proxy = capture.proxy {
                    CaptureView(
                        content: .proxy(proxy),
                        captureSize: capture.pixelSize,
                        marks: capture.displayMarks,
                        findings: capture.findings,
                        onSelect: { n in onRepair(capture.id, n) }
                    )
                } else {
                    // Stored, resolved, but the proxy is gone — deleted out from under us.
                    EmptyState(
                        symbol: "photo.badge.exclamationmark",
                        title: "Capture removed",
                        message: "This capture is no longer on the device."
                    )
                }
            case .processing:
                ProgressNote(label: "Stitching…", value: model.importProgress)
                    .frame(maxWidth: SeamlySpace.columnMax)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                // The design is silent here. Never a raw error: `message` already came through
                // `CaptureCondition.message(for:)`, and the raw one is in Diagnostics. There is
                // no separate "Record again" button because the dock is already on screen
                // directly below with Record as its hero — a second one would be the same
                // action twice.
                VStack(spacing: SeamlySpace.s5) {
                    StatusNote(kind: .failed)
                    Text(message)
                        .font(SeamlyFont.footnote)
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: SeamlySpace.columnMax)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, layout.gutter)
        .padding(.vertical, SeamlySpace.s5)
        .frame(maxWidth: layout.isRegular ? 720 : .infinity)
        .frame(maxWidth: .infinity)
    }

    // MARK: - What this capture wants to say

    @ViewBuilder
    private func statusRow(_ capture: Capture) -> some View {
        let findings = capture.phase == .ready ? capture.findings : []
        let flagged = findings.filter { $0.kind == .seam || $0.kind == .bars }.count
        let gaps = findings.filter { $0.kind == .gap }.count

        HStack(spacing: SeamlySpace.s4) {
            HStack(spacing: SeamlySpace.s3) {
                if capture.session.status == .recording { StatusNote(kind: .incomplete) }
                if capture.session.orderAssumed { StatusNote(kind: .orderAssumed) }
                if flagged > 0 { StatusNote(kind: .flagged, count: flagged) }
                if gaps > 0 { StatusNote(kind: .gap, count: gaps) }
                if capture.phase == .ready, findings.isEmpty {
                    StatusNote(kind: .ready, label: "Every seam matched confidently")
                }
            }
            Spacer(minLength: SeamlySpace.s4)
            if capture.phase == .ready, capture.proxy != nil {
                SeamlyButton(
                    findings.isEmpty ? "Open" : "Review them",
                    variant: .plain,
                    symbol: findings.isEmpty ? nil : "arrow.right"
                ) {
                    onReview(capture.id)
                }
                .accessibilityIdentifier("review-capture")
            }
        }
        .padding(.horizontal, layout.gutter)
        .frame(minHeight: SeamlySpace.hitMin)
    }
}
```

Home's processing state needs `ProgressNote`, and the import sheet in Task 17 needs the same component, so it is written here in full rather than twice:

Create `Seamly/Seamly/DesignSystem/Components/Feedback/ProgressNote.swift`:

```swift
import SwiftUI

/// Determinate for reading a video, where a real percentage exists. Indeterminate for
/// stitching, which genuinely has none — the work is data-dependent and finishes when the
/// seams are found. **Never fake progress.**
struct ProgressNote: View {
    let label: String
    /// `nil` means indeterminate, and the copy beside it must say so in words.
    var value: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    var body: some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(SeamlyFont.footnote).foregroundStyle(SeamlyColor.ink)
                Spacer()
                if let value {
                    Text("\(Int((value * 100).rounded()))%")
                        .font(SeamlyFont.mono)
                        .foregroundStyle(SeamlyColor.inkMuted)
                }
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(SeamlyColor.paperSunk).frame(height: 3)
                GeometryReader { geo in
                    if let value {
                        Rectangle()
                            .fill(SeamlyColor.accent)
                            .frame(width: geo.size.width * CGFloat(value))
                            .animation(SeamlyMotion.base, value: value)
                    } else if reduceMotion {
                        // No sweep to run, so draw nothing rather than parking a bar at some
                        // arbitrary fill — a still bar at 38% reads as "38% done", which is
                        // the exact lie this component exists to avoid. The label carries it.
                        Color.clear
                    } else {
                        // A genuine SWEEP, not a fill. Stitching has no percentage — the work
                        // is data-dependent and finishes when the seams are found — so the bar
                        // must show activity without implying an amount. `--dur-stitching`
                        // exists in the token set for exactly this.
                        Rectangle()
                            .fill(SeamlyColor.accent)
                            .frame(width: geo.size.width * 0.38)
                            .offset(x: sweeping ? geo.size.width : -geo.size.width * 0.38)
                            .animation(
                                SeamlyMotion.stitching.repeatForever(autoreverses: false),
                                value: sweeping
                            )
                            .onAppear { sweeping = true }
                    }
                }
                .frame(height: 3)
                .clipped()
            }
        }
        .padding(.horizontal, SeamlySpace.s5)
        .padding(.vertical, SeamlySpace.s4)
        .background(SeamlyColor.paperRaised)
        .overlay {
            RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                .strokeBorder(SeamlyColor.rule, lineWidth: 1)
        }
        .seamlyCorners(SeamlyRadius.sm)
    }
}
```

- [ ] **Step 3: Write `AppShell`**

Create `Seamly/Seamly/AppShell.swift`:

```swift
import SwiftUI
import StitchKit

/// Where the app goes. Home is the root, because the app opens on the most recent capture.
enum Route: Hashable {
    case library
    case review(UUID)
}

/// The one place the model is owned, the navigation stack lives, and every model-driven
/// presentation is decided. Screens take closures and know nothing about routing.
struct AppShell: View {
    @State private var model = CaptureModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var path: [Route] = []
    @State private var showFirstRun = false
    @State private var showDiagnostics = false
    @State private var showNothingToStitch = false

    /// A join to open the repair on. A wrapper rather than a bare `Int` so
    /// `fullScreenCover(item:)` can identify it.
    struct RepairTarget: Identifiable, Hashable {
        let captureID: UUID
        let findingNumber: Int
        var id: String { "\(captureID)-\(findingNumber)" }
    }

    @State private var repairTarget: RepairTarget?

    var body: some View {
        NavigationStack(path: $path) {
            HomeScreen(
                model: model,
                onLibrary: { path.append(.library) },
                onReview: { path.append(.review($0)) },
                onRepair: { repairTarget = RepairTarget(captureID: $0, findingNumber: $1) },
                onHelp: { showFirstRun = true },
                onVideo: {},
                onPhotos: {}
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(route).toolbar(.hidden, for: .navigationBar)
            }
        }
        .task {
            if !hasSeenOnboarding { showFirstRun = true; hasSeenOnboarding = true }
            AppGroup.startBroadcastFinishObserver()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seamlyBroadcastFinished)) { _ in
            Task { await model.refresh() }
        }
        // A new arrival — including a failed one, per DECISIONS.md [B4] — pops to Home rather
        // than pushing. Under return-home, Home IS the answer to "what did I get?"; pushing a
        // screen over it would bury the thing the user came back for.
        .onChange(of: model.pendingResult) { _, id in
            guard id != nil else { return }
            path.removeAll()
            model.consumePendingResult()
        }
        // React to the flag being *set*, not to it changing: `lastPickupWasEmpty` is an event,
        // and consuming it immediately is what lets a second consecutive empty pickup set it
        // `true` again and fire this a second time.
        .onChange(of: model.lastPickupWasEmpty) { _, empty in
            guard empty else { return }
            showNothingToStitch = true
            model.consumeLastPickupWasEmpty()
        }
        .sheet(isPresented: $showFirstRun) { OnboardingView() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showNothingToStitch) {
            nothingToStitch.presentationDetents([.medium])
        }
        .fullScreenCover(item: $repairTarget) { target in
            // Replaced by RepairQueueView in Task 13. Until then the shipped repair screen
            // stays reachable, so nothing regresses between commits.
            legacyRepair(target)
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { model.importError != nil },
                set: { if !$0 { model.clearImportError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .library:
            // Replaced by LibraryScreen in Task 15.
            EmptyState(symbol: "list.bullet", title: "Library")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SeamlyColor.paper)
        case .review(let id):
            // Replaced by ReviewScreen in Task 10.
            ResultView(captureID: id, model: model, onRecordAgain: { path.removeAll() })
                .toolbar(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var nothingToStitch: some View {
        EmptyState(
            symbol: "arrow.up.and.down",
            title: "Nothing to stitch",
            message: "This recording didn't scroll, so there was nothing to join together. Start the recording, switch to the app you want, then scroll down steadily."
        ) {
            SeamlyButton("Record again") { showNothingToStitch = false }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    @ViewBuilder
    private func legacyRepair(_ target: RepairTarget) -> some View {
        if let capture = model.captures.first(where: { $0.id == target.captureID }),
           let finding = capture.findings.first(where: { $0.n == target.findingNumber }),
           case .join(let joinIndex) = finding.target {
            RepairView(captureID: target.captureID, model: model, openingJoin: joinIndex)
        } else if let capture = model.captures.first(where: { $0.id == target.captureID }),
                  let opening = RepairableJoins.opening(in: capture.session, flaggedOnly: true) {
            RepairView(captureID: target.captureID, model: model, openingJoin: opening)
        } else {
            EmptyState(symbol: "checkmark.seal", title: CaptureCondition.nothingToLineUpMessage) {
                SeamlyButton("Close") { repairTarget = nil }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SeamlyColor.paper)
        }
    }
}
```

Home's `onVideo` / `onPhotos` are empty closures for now — Task 17 wires the import sheet. The dock's Record button already works, because `BroadcastPickerButton` presents the system picker itself.

- [ ] **Step 4: Root the shell**

In `Seamly/Seamly/SeamlyApp.swift`, replace `ContentView()` with `AppShell()`:

```swift
    var body: some Scene {
        WindowGroup {
            AppShell()
        }
    }
```

Leave `ContentView.swift` and `HomeView.swift` on disk — deleting them is Task 20, after nothing references them.

- [ ] **Step 5: Update the two UI tests that assert the old Home**

In `Seamly/SeamlyUITests/SeamlyUITests.swift`, replace the body of `testHomeShowsRecordFirst`:

```swift
    /// Verifies the empty-home state: the dock is present with all three ways in, and the
    /// empty state is capture-first. This never seeds a capture, so it only exercises the
    /// no-captures branch.
    @MainActor
    func testHomeShowsRecordFirst() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresented(app)

        // Home is *behind* the onboarding sheet, so its elements exist even while the sheet is
        // covering them — these assertions are only worth something because they also check the
        // elements can be reached.
        let headline = app.staticTexts["Nothing captured yet"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertTrue(headline.isHittable, "home is covered — onboarding was not dismissed")
        XCTAssertTrue(app.buttons["Record"].isHittable, "the dock's hero is missing")
        XCTAssertTrue(app.buttons["From a screen recording"].isHittable)
        XCTAssertTrue(app.buttons["From screenshots"].isHittable)
    }
```

In `Seamly/SeamlyUITests/RepairUITests.swift`, replace the two navigation lines (the `thumbnail` lookup and its `tap()`) with:

```swift
        // Return-home: a seeded capture is the newest one, so Home is already showing it —
        // there is no recents strip to tap any more. Fully rewritten in Task 19 once the
        // repair queue replaces this screen; for now it just reaches the same place.
        let review = app.buttons["review-capture"]
        XCTAssertTrue(review.waitForExistence(timeout: 30), "the seeded capture never appeared")
        review.tap()
```

- [ ] **Step 6: Run the whole app test suite**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS, including `RepairUITests.testLiningUpAJoinClearsTheNotice` — the shipped repair path is untouched, only how it is reached has changed.

- [ ] **Step 7: Look at Home on the simulator**

Launch with the seed so there is a real capture to look at:

```bash
xcrun simctl launch booted io.github.lilikazine.Seamly -SeamlySeedMisalignedCapture
```

Confirm: Home opens on the capture, not a launcher; the dock is docked; the flagged join has a numbered ring in the margin sitting on its rule; the dimensions line reads with thin-space grouping (`300 × 1 060 px`, not `300 × 1,060 px`); and the empty state appears with no captures.

- [ ] **Step 8: Commit**

```bash
git add Seamly/Seamly/Core/Capture+Design.swift \
        Seamly/Seamly/AppShell.swift \
        Seamly/Seamly/Features/Home/HomeScreen.swift \
        Seamly/Seamly/DesignSystem/Components/Feedback/ProgressNote.swift \
        Seamly/Seamly/SeamlyApp.swift \
        Seamly/SeamlyUITests/SeamlyUITests.swift \
        Seamly/SeamlyUITests/RepairUITests.swift
git commit -m "$(cat <<'EOF'
feat(home): open on the most recent capture

Home stops being a launcher. The app is backgrounded while the user
scrolls another app, so its commonest launch context is "I just stopped a
broadcast — what did I get?" — and this answers that before anything else,
with the capture's own marks already visible and one tap into fixing them.

A new arrival now pops to Home rather than pushing a result screen, for
the same reason. It still fires on failure, per DECISIONS.md [B4]; the
failed state is drawn in the capture slot, never as a raw error.

The old result and repair screens stay reachable behind Route.review until
their replacements land, so this commit regresses nothing.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Review — the one screen where iPad changes the design

Compact: the capture owns the column; findings sit under it and tapping a margin marker jumps, never transitions. Regular: a persistent rail beside the capture, so the list stays visible while panning 15 000 px and stepping between problems costs nothing. **Two designs, not one layout reflowed.**

**Files:**
- Create: `Seamly/Seamly/Features/Result/ReviewScreen.swift`
- Modify: `Seamly/Seamly/AppShell.swift` (`destination(_:)` — `.review` now builds `ReviewScreen`)

**Interfaces:**
- Consumes: `Capture+Design` (Task 9), `CaptureView`/`CaptureJump` (Task 6), `NavBar`/`StatusNote`/`SeamlyButton`/`IconButton`/`EmptyState` (Task 7).
- Produces: `struct ReviewScreen: View` — `init(captureID:model:onBack:onRepair:onExport:)`

- [ ] **Step 1: Write `ReviewScreen`**

Create `Seamly/Seamly/Features/Result/ReviewScreen.swift`:

```swift
import SwiftUI
import StitchKit

/// The capture at length, and the one screen where regular width is a different design rather
/// than a bigger one.
struct ReviewScreen: View {
    let captureID: UUID
    let model: CaptureModel
    var onBack: () -> Void
    var onRepair: (Int) -> Void
    var onExport: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    @State private var selected: Int?
    /// `ZoomState`, not a bare `CGFloat`. `MagnifyGesture.magnification` is cumulative from the
    /// START of the current gesture, so multiplying it into an already-updated scale on every
    /// tick compounds superlinearly and slams into the clamp instead of tracking the finger.
    /// `ZoomState` exists in this codebase precisely to bank the committed scale separately —
    /// see its doc comment, which records the bug it was written for.
    @State private var zoom = ZoomState()
    @State private var jump: CaptureJump?
    @State private var jumpToken = 0

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }
    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    var body: some View {
        Group {
            if let capture, let proxy = capture.proxy, capture.phase == .ready {
                if layout.isRegular {
                    regular(capture, proxy)
                } else {
                    compact(capture, proxy)
                }
            } else {
                // Deleted out from under this screen, or still stitching. Either way there is
                // nothing to review; Home is where the state of a capture is reported.
                VStack(spacing: 0) {
                    NavBar(title: "Review", backLabel: "Home", onBack: onBack)
                    EmptyState(
                        symbol: "photo.badge.exclamationmark",
                        title: "Nothing to show yet",
                        message: "This capture isn't ready. Go back and Seamly will tell you where it got to."
                    )
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    // MARK: - Shared pieces

    private func head(_ capture: Capture) -> some View {
        NavBar(
            title: capture.title,
            subtitle: SeamlyNumber.dimensions(
                width: Int(capture.pixelSize.width),
                height: Int(capture.pixelSize.height)
            ) + " · \(capture.session.keyframes.count) frames",
            backLabel: layout.isRegular ? "Library" : "",
            onBack: onBack
        ) {
            if let first = capture.findings.first {
                IconButton(symbol: "slider.horizontal.3", label: "Repair") { onRepair(first.n) }
            }
            IconButton(symbol: "square.and.arrow.up", label: "Export", action: onExport)
        }
    }

    private func stage(_ capture: Capture, _ proxy: CGImage) -> some View {
        CaptureView(
            content: .proxy(proxy),
            captureSize: capture.pixelSize,
            marks: capture.displayMarks,
            findings: capture.findings,
            zoom: zoom.scale,
            selected: selected,
            jump: jump,
            onSelect: { jumpTo($0, in: capture) }
        )
        .padding(.horizontal, layout.gutter)
        .padding(.top, SeamlySpace.s4)
        .padding(.bottom, SeamlySpace.s5)
        .gesture(
            MagnifyGesture()
                .onChanged { zoom.update(magnification: $0.magnification) }
                .onEnded { _ in withAnimation(SeamlyMotion.base) { zoom.end() } }
        )
    }

    /// Select, zoom in, and pan the mark to 40 % down. Never a screen transition — the user is
    /// already looking at this capture, and pushing would throw away the place they had.
    private func jumpTo(_ n: Int, in capture: Capture) {
        guard let finding = capture.findings.first(where: { $0.n == n }) else { return }
        selected = n
        zoom.set(3)
        jumpToken += 1
        jump = CaptureJump(atPct: finding.atPct, token: jumpToken)
    }

    // MARK: - Compact

    private func compact(_ capture: Capture, _ proxy: CGImage) -> some View {
        VStack(spacing: 0) {
            head(capture)
            stage(capture, proxy)
            HStack(spacing: SeamlySpace.s4) {
                summary(capture)
                Spacer(minLength: SeamlySpace.s4)
                if let first = capture.findings.first {
                    SeamlyButton("Review them", symbol: "arrow.right") { onRepair(first.n) }
                        .accessibilityIdentifier("open-repair")
                }
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .frame(minHeight: 52)
        }
    }

    // MARK: - Regular

    private func regular(_ capture: Capture, _ proxy: CGImage) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                head(capture)
                stage(capture, proxy)
            }
            rail(capture)
                .frame(width: SeamlySpace.sidebarWidth)
                .background(SeamlyColor.paperRaised)
                .overlay(alignment: .leading) {
                    Rectangle().fill(SeamlyColor.rule).frame(width: 1)
                }
        }
    }

    private func rail(_ capture: Capture) -> some View {
        let findings = capture.findings
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(findings.isEmpty ? "Nothing to fix" : "\(findings.count) to look at")
                    .font(SeamlyFont.title3)
                    .foregroundStyle(SeamlyColor.ink)
                    .seamlyDisplayTracking()
                Text(findings.isEmpty
                     ? "Every seam matched confidently."
                     : "Select one to jump there.")
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SeamlySpace.s5)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s4)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(findings) { finding in
                        FindingLine(finding: finding, selected: selected == finding.n) {
                            jumpTo(finding.n, in: capture)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: SeamlySpace.s4) {
                SeamlyButton("Repair", variant: .outline) {
                    findings.first.map { onRepair($0.n) }
                }
                .disabled(findings.isEmpty)
                .frame(maxWidth: .infinity)
                SeamlyButton("Export", symbol: "square.and.arrow.up", action: onExport)
                    .frame(maxWidth: .infinity)
            }
            .padding(SeamlySpace.s5)
            .overlay(alignment: .top) {
                Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summary(_ capture: Capture) -> some View {
        let findings = capture.findings
        let flagged = findings.filter { $0.kind == .seam || $0.kind == .bars }.count
        let gaps = findings.filter { $0.kind == .gap }.count
        HStack(spacing: SeamlySpace.s3) {
            if flagged > 0 { StatusNote(kind: .flagged, count: flagged) }
            if gaps > 0 { StatusNote(kind: .gap, count: gaps) }
            if findings.isEmpty { StatusNote(kind: .ready, label: "Every seam matched confidently") }
        }
    }
}

/// One row in the regular-width rail. Its number is the number on the margin marker, which is
/// the number the repair queue counts by.
private struct FindingLine: View {
    let finding: Finding
    let selected: Bool
    let action: () -> Void

    private var color: Color {
        switch finding.kind {
        case .gap: SeamlyColor.markGap
        case .bars, .seam: SeamlyColor.markFlag
        }
    }

    /// Numbers carry their unit and don't reflow. `dy` is the offset under the finger;
    /// a gap has none, because nothing overlaps across a break.
    private var measurement: String {
        var parts: [String] = []
        if let dy = finding.dy {
            // Through `SeamlyNumber`, not hand-formatted: a real scroll step runs to four
            // figures, and an ungrouped "dy +1420 px" beside a grouped "884 × 15 402 px" is
            // exactly the inconsistency the thin-space rule exists to prevent.
            parts.append("dy \(dy > 0 ? "+" : "")" + SeamlyNumber.px(dy))
        } else if finding.kind == .gap {
            parts.append("never revealed")
        }
        if let confidence = finding.confidence {
            parts.append("conf \(String(format: "%.2f", confidence))")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: SeamlySpace.s4) {
                Text("\(finding.n)")
                    .font(SeamlyFont.caps)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .overlay { Circle().strokeBorder(color, lineWidth: 1.5) }
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(finding.title)
                        .font(SeamlyFont.subheadline)
                        .foregroundStyle(SeamlyColor.ink)
                        .multilineTextAlignment(.leading)
                    if !measurement.isEmpty {
                        Text(measurement)
                            .font(SeamlyFont.mono)
                            .monospacedDigit()
                            .foregroundStyle(SeamlyColor.inkFaint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(SeamlySpace.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? SeamlyColor.accentWash : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
        .accessibilityIdentifier("finding-\(finding.n)")
    }
}
```

- [ ] **Step 2: Route to it**

In `AppShell.swift`, replace the `.review` branch of `destination(_:)`:

```swift
        case .review(let id):
            ReviewScreen(
                captureID: id,
                model: model,
                onBack: { path.removeLast() },
                onRepair: { repairTarget = RepairTarget(captureID: id, findingNumber: $0) },
                onExport: {}
            )
```

`onExport` is empty until Task 16 wires the export sheet. `ResultView` now has no caller; it stays on disk until Task 20.

- [ ] **Step 3: Build and run the app tests**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS — except `RepairUITests.testLiningUpAJoinClearsTheNotice`, which asserts on `ResultView`'s notice text and its "Line it up" button, neither of which exists on `ReviewScreen`.

Update that test's middle section to drive the new screen:

```swift
        let repair = app.buttons["open-repair"]
        XCTAssertTrue(repair.waitForExistence(timeout: 30), "the seeded capture was not flagged")
        repair.tap()
```

and replace the two `notice` assertions with a count assertion that survives the queue landing in Task 13:

```swift
        // The seeded capture has exactly one flagged join. Once it is answered, Review has
        // nothing left to offer a repair for, so the entry disappears.
        XCTAssertTrue(
            repair.waitForNonExistence(timeout: 60),
            "the join was still flagged after being lined up — the edit did not reach the manifest"
        )
```

Keep the existing hittability-gated re-assertion, retargeted from `Save to Photos` to the capture sheet:

```swift
        let sheet = app.descendants(matching: .any).matching(identifier: "capture-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "Review never came back")
        XCTAssertTrue(waitUntilHittable(sheet, timeout: 30),
                      "the capture never became interactive again — the re-composite did not finish")
        XCTAssertFalse(repair.exists,
                       "the join is still flagged now that Review is back and interactive")
```

Re-run the suite. Expected: PASS.

- [ ] **Step 4: Look at both size classes**

Run the app on an iPhone 17 simulator and on an iPad Pro 13-inch simulator, with `-SeamlySeedMisalignedCapture`.

Confirm:
1. iPhone: the capture owns the column, the summary and "Review them" sit beneath it, and tapping the margin marker zooms and pans **without a screen change**.
2. iPad: the rail is present and stays visible while the capture pans; a rail row and the margin marker with the same number select together.
3. On both, the jump lands the mark about 40 % down rather than at the very top.
4. Rotate the iPhone to landscape: the position scale moves below the sheet rather than eating the height.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/Features/Result/ReviewScreen.swift \
        Seamly/Seamly/AppShell.swift \
        Seamly/SeamlyUITests/RepairUITests.swift
git commit -m "$(cat <<'EOF'
feat(review): the capture at length, with a rail at regular width

Two designs rather than one layout reflowed. Compact gives the capture the
column and puts the findings under it; regular adds a persistent rail, so
the list stays visible while panning 15 000 px and stepping between
problems costs nothing.

A marker tap here jumps rather than transitioning — the user is already
looking at this capture, and pushing a screen would throw away the place
they had. Home's marker tap does open the queue, deliberately: Home is a
glance and the marker is the way in.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: `CaptureView`'s live join

A repair drag against the proxy would move nothing visible — the proxy is only rebuilt after a commit. So a seam finding draws the two full-resolution frames either side of the join, windowed exactly as the shipped `RepairView` does.

**Files:**
- Modify: `Seamly/Seamly/DesignSystem/CaptureView.swift` (replace the `joinSheet` placeholder)

**Interfaces:**
- Consumes: `JoinAlignment` (existing), `CaptureGeometry` (Task 3).
- Produces: `CaptureView` gains `var onDrag: ((CGFloat, CGFloat) -> Void)?` — called with `(translationInPoints, sourcePixelsPerPoint)` on every drag update, so the caller owns the offset and this view stays about drawing.

- [ ] **Step 1: Replace the placeholder**

In `CaptureView.swift`, add the property beside `onSelect`:

```swift
    /// Called on every update of a drag over a `.join` sheet, with the gesture's cumulative
    /// translation in points and the frame's 1× source-pixels-per-point ratio. The caller
    /// applies it through `JoinAlignment.dy(draggedBy:from:sourcePixelsPerPoint:zoom:)` —
    /// this view draws, it does not decide geometry.
    var onDrag: ((CGFloat, CGFloat) -> Void)?
```

and replace `joinSheet` with:

```swift
    /// The upper frame's tail above a pinned boundary, the lower frame's head below it. Each
    /// half is a clipped window onto a full-resolution frame, offset so the right source row
    /// lands on the boundary — so what the user sees is exactly the placement `JoinAlignment`
    /// describes and `Compositor` will draw.
    ///
    /// There is deliberately **no panning**: one finger always means "line it up". At high zoom
    /// only the middle of the frame's width is visible, which is why both windows align `.top`
    /// and not `.topLeading`.
    @ViewBuilder
    private func joinSheet(upper: CGImage, lower: CGImage, alignment: JoinAlignment, g: CaptureGeometry) -> some View {
        // Displayed points per source pixel at the current zoom.
        let scale = g.sheetWidth * zoom / CGFloat(max(upper.width, 1))
        let boundary = g.viewportHeight / 2
        // The 1× ratio; `JoinAlignment` divides by the zoom itself.
        let sourcePixelsPerPoint = CGFloat(upper.width) / max(g.sheetWidth, 1)

        VStack(spacing: 0) {
            joinWindow(
                upper,
                width: g.sheetWidth * zoom,
                offsetY: boundary - CGFloat(alignment.upperContentBottom) * scale,
                size: CGSize(width: g.sheetWidth, height: boundary)
            )
            joinWindow(
                lower,
                width: g.sheetWidth * zoom,
                offsetY: -CGFloat(alignment.lowerSourceStart) * scale,
                size: CGSize(width: g.sheetWidth, height: max(0, g.viewportHeight - boundary))
            )
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1).onChanged { value in
                onDrag?(value.translation.height, sourcePixelsPerPoint)
            }
        )
        .accessibilityIdentifier("repair-canvas")
        .accessibilityLabel("The two halves of this join")
        .accessibilityHint("Drag up or down to line them up. Pinch to zoom in.")
    }

    private func joinWindow(_ image: CGImage, width: CGFloat, offsetY: CGFloat, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            Image(decorative: image, scale: 1)
                // `Compositor` draws with `.none`, so this must too. Zoom is this surface's
                // only precision mechanism, and smoothing is precisely what it must not do: at
                // 6× a source row is six points tall, and interpolation would blend it with its
                // neighbours into a gradient the exported image will not contain. The user
                // would be dragging against rows that exist nowhere but this preview.
                .interpolation(.none)
                .resizable()
                .frame(width: width, height: width * CGFloat(image.height) / CGFloat(max(image.width, 1)))
                .offset(y: offsetY)
        }
        // `.top`, not `.topLeading`: the image is `zoom`× wider than this frame once zoomed in,
        // so whichever edge this aligns to is the only slice the user can see. `.top` centres
        // the zoomed slice horizontally while leaving the vertical placement — which `offsetY`
        // computes exactly — alone.
        .frame(width: size.width, height: max(size.height, 0), alignment: .top)
        .clipped()
    }
```

- [ ] **Step 2: Build**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run `JoinAlignmentTests` to confirm the geometry contract still holds**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SeamlyTests/JoinAlignmentTests test
```
Expected: PASS. Nothing in `JoinAlignment` changed; this proves the drawing above is still reading the same numbers the exported image will honour.

- [ ] **Step 4: Commit**

```bash
git add Seamly/Seamly/DesignSystem/CaptureView.swift
git commit -m "$(cat <<'EOF'
feat(design): draw a live join in the capture sheet

The display proxy is only rebuilt after a commit, so a repair drag against
it would move nothing visible. A seam finding therefore draws the two
full-resolution frames either side of the join, windowed exactly as the
shipped repair screen does — interpolation off, because zoom is the only
precision mechanism and smoothing would have the user lining up rows the
export does not contain.

The margin rail and the position scale still describe the whole capture,
so the surround is unchanged and only the pixels differ. CaptureView takes
the drag and hands its translation out; it draws, it does not decide
geometry — JoinAlignment still owns that.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: `QueuePrompt` and `StepperRow`

The repair model made concrete: one question at a time, and a wide affirmative answer because most flagged seams turn out fine and the common case should be one tap. The steppers exist — behind *Adjust manually*, where they belong. A spell-checker, not a dictionary.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Components/Repair/QueuePrompt.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Repair/StepperRow.swift`

**Interfaces:**
- Consumes: tokens (Task 2), `SeamlyButton` (Task 7), `Finding.Kind` (Task 4).
- Produces:
  - `struct QueuePrompt<Manual: View>: View` — `init(index:total:kind:question:detail:value:affirmative:onNudge:onAccept:onSkipAll:@ViewBuilder manual:)`
  - `struct StepperRow: View` — `init(label:value:unit:step:range:hint:onChange:)`

- [ ] **Step 1: Write `QueuePrompt`**

Create `Seamly/Seamly/DesignSystem/Components/Repair/QueuePrompt.swift`:

```swift
import SwiftUI

/// One question at a time, zoomed to the problem, answerable in a tap. The user never hunts
/// through a 15 000 px image, and never scans a form for the control that matters.
///
/// The affirmative answer is the WIDE, primary one — most flagged seams are actually fine.
///
/// `onNudge` is optional and the chevrons disappear without it. A gap has no lever: the content
/// was never captured, so there is nothing to nudge, and offering a control that does nothing
/// would be worse than offering none. `affirmative` is the word on the primary button, which
/// changes with the kind for the same reason ("Looks right" is a claim a gap cannot make).
struct QueuePrompt<Manual: View>: View {
    let index: Int
    let total: Int
    let kind: Finding.Kind
    let question: String
    var detail: String?
    /// The offset under the finger, shown in mono so it does not reflow as it steps.
    var value: Int?
    var affirmative: String = "Looks right"
    var onNudge: ((Int) -> Void)?
    let onAccept: () -> Void
    let onSkipAll: () -> Void
    @ViewBuilder var manual: () -> Manual

    private var kindWord: String {
        switch kind {
        case .gap: "Gap"
        case .bars: "Bars uncertain"
        case .seam: "Uncertain seam"
        }
    }

    private var kindColor: Color {
        kind == .gap ? SeamlyColor.markGap : SeamlyColor.markFlag
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s5) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindWord.uppercased())
                    .font(SeamlyFont.caps)
                    .seamlyCapsTracking()
                    .foregroundStyle(kindColor)
                Spacer()
                Text("\(index) of \(total)")
                    .font(SeamlyFont.mono)
                    .monospacedDigit()
                    .foregroundStyle(SeamlyColor.inkFaint)
            }

            manual()

            VStack(alignment: .leading, spacing: SeamlySpace.s1) {
                Text(question)
                    .font(SeamlyFont.title3)
                    .foregroundStyle(SeamlyColor.ink)
                    .seamlyDisplayTracking()
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(SeamlyFont.footnote)
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: SeamlySpace.s3) {
                if let onNudge {
                    nudge(symbol: "chevron.up", label: "Nudge up") { onNudge(-1) }
                }
                SeamlyButton(affirmative, size: .large, action: onAccept)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("queue-accept")
                if let onNudge {
                    nudge(symbol: "chevron.down", label: "Nudge down") { onNudge(1) }
                }
            }
            .frame(height: 52)

            HStack {
                if let value {
                    Text("dy \(value > 0 ? "+" : "")\(value) px")
                        .font(SeamlyFont.mono)
                        .monospacedDigit()
                        .foregroundStyle(SeamlyColor.inkMuted)
                }
                Spacer()
                Button("Skip all", action: onSkipAll)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.top, SeamlySpace.s5)
        .padding(.bottom, SeamlySpace.s7)
        .frame(maxWidth: .infinity)
        .background(SeamlyColor.paperRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(SeamlyColor.rule).frame(height: 1)
        }
    }

    private func nudge(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(SeamlyColor.ink)
                .frame(width: 52)
                .frame(maxHeight: .infinity)
                .background(SeamlyColor.paperSunk)
                .overlay {
                    RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                        .strokeBorder(SeamlyColor.rule, lineWidth: 1)
                }
                .seamlyCorners(SeamlyRadius.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension QueuePrompt where Manual == EmptyView {
    init(index: Int, total: Int, kind: Finding.Kind, question: String, detail: String? = nil,
         value: Int? = nil, affirmative: String = "Looks right",
         onNudge: ((Int) -> Void)? = nil,
         onAccept: @escaping () -> Void, onSkipAll: @escaping () -> Void) {
        self.init(index: index, total: total, kind: kind, question: question, detail: detail,
                  value: value, affirmative: affirmative, onNudge: onNudge,
                  onAccept: onAccept, onSkipAll: onSkipAll) { EmptyView() }
    }
}
```

- [ ] **Step 2: Write `StepperRow`**

Create `Seamly/Seamly/DesignSystem/Components/Repair/StepperRow.swift`:

```swift
import SwiftUI

/// The ADVANCED path, never the default. Available behind *Adjust manually* for people who want
/// the number; the queue is what everyone else uses.
///
/// Tabular figures so the row does not reflow as the value steps.
struct StepperRow: View {
    let label: String
    let value: Int
    var unit: String = "px"
    var step: Int = 1
    var range: ClosedRange<Int>
    var hint: String?
    let onChange: (Int) -> Void

    private func set(_ direction: Int) {
        let next = value + direction * step
        onChange(min(max(range.lowerBound, next), range.upperBound))
    }

    var body: some View {
        HStack(spacing: SeamlySpace.s4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(SeamlyFont.body).foregroundStyle(SeamlyColor.ink)
                if let hint {
                    Text(hint).font(SeamlyFont.caption).foregroundStyle(SeamlyColor.inkFaint)
                }
            }
            Spacer(minLength: SeamlySpace.s4)
            Text("\(value) \(unit)")
                .font(SeamlyFont.mono)
                .monospacedDigit()
                .foregroundStyle(SeamlyColor.inkMuted)
                .frame(minWidth: 68, alignment: .trailing)
            HStack(spacing: 0) {
                stepButton("minus", label: "Decrease \(label)") { set(-1) }
                    .disabled(value <= range.lowerBound)
                Rectangle().fill(SeamlyColor.rule).frame(width: 1)
                stepButton("plus", label: "Increase \(label)") { set(1) }
                    .disabled(value >= range.upperBound)
            }
            .frame(height: 34)
            .background(SeamlyColor.paperSunk)
            .overlay {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .strokeBorder(SeamlyColor.rule, lineWidth: 1)
            }
            .seamlyCorners(SeamlyRadius.sm)
        }
        .frame(minHeight: SeamlySpace.hitMin)
        .padding(.vertical, SeamlySpace.s3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(SeamlyColor.accent)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Repair
git commit -m "$(cat <<'EOF'
feat(design): add QueuePrompt and StepperRow

One question, one wide affirmative answer, because most flagged seams turn
out fine and the common case must be one tap. The steppers exist behind
Adjust manually — the advanced path, never the default.

The nudge chevrons and the primary's word are both parameters: a gap has
no lever, since the content was never captured, and offering a control
that does nothing would be worse than offering none.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: The repair queue — seam findings

The queue itself, answering the kind the app can already fix. Bars and gaps arrive in Task 14.

**Files:**
- Create: `Seamly/Seamly/Features/Repair/RepairQueueModel.swift`
- Create: `Seamly/Seamly/Features/Repair/RepairQueueView.swift`
- Modify: `Seamly/Seamly/DesignSystem/CaptureView.swift` (`onDrag` gains the drag's start offset)
- Modify: `Seamly/Seamly/AppShell.swift` (`legacyRepair` becomes `RepairQueueView`)

**Interfaces:**
- Consumes: `CaptureModel`, `JoinAlignment`, `ZoomState` (existing); `Finding` (Task 4); `CaptureView` (Tasks 6, 11); `QueuePrompt`/`StepperRow` (Task 12).
- Produces:
  - `@MainActor @Observable final class RepairQueueModel` — `init(captureID:model:startAt:)`, `var findings: [Finding]`, `var position: Int`, `var current: Finding?`, `var frames: (upper: CGImage, lower: CGImage)?`, `var alignment: JoinAlignment?`, `var loadError: String?`, `var saveError: String?`, `var busy: Bool`, `var answeredCount: Int`, `var hasPendingEdits: Bool`, `func load() async`, `func drag(translation:sourcePixelsPerPoint:from:zoom:)`, `func setDy(_:)`, `func nudge(_:)`, `func answer() async -> Bool`, `func commit() async -> Bool`, `func clearSaveError()`
  - `struct RepairQueueView: View` — `init(captureID:model:startAt:onClose:)`
- Amends Task 11: `CaptureView.onDrag` is `((CGFloat, CGFloat, Int) -> Void)?` — `(translation, sourcePixelsPerPoint, startDy)`.

- [ ] **Step 1: Give the drag its baseline**

In `CaptureView.swift`, change the `onDrag` declaration and the gesture in `joinSheet`:

```swift
    /// Called on every update of a drag over a `.join` sheet, with the gesture's cumulative
    /// translation in points, the frame's 1× source-pixels-per-point ratio, and the offset the
    /// gesture *started* from. The caller applies it through
    /// `JoinAlignment.dy(draggedBy:from:sourcePixelsPerPoint:zoom:)`.
    var onDrag: ((CGFloat, CGFloat, Int) -> Void)?

    /// The offset a fresh drag begins from. `@GestureState`, not `@State`: SwiftUI resets it
    /// automatically whenever the gesture ends *or is cancelled or interrupted*, which a plain
    /// var cleared in `onEnded` cannot promise — and a stale baseline would make the next drag
    /// jump by the previous drag's translation.
    var currentDy: Int?
    // `= nil` explicitly: a property wrapper without an initial value joins the
    // memberwise init, and every call site would then have to pass it.
    @GestureState private var dragStart: Int? = nil
```

and in `joinSheet`:

```swift
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($dragStart) { _, state, _ in
                    // Captures the offset this drag began from, once, the first time this
                    // fires for a fresh gesture.
                    if state == nil { state = currentDy }
                }
                .onChanged { value in
                    onDrag?(value.translation.height, sourcePixelsPerPoint, dragStart ?? currentDy ?? 0)
                }
        )
```

- [ ] **Step 2: Write `RepairQueueModel`**

Create `Seamly/Seamly/Features/Repair/RepairQueueModel.swift`:

```swift
import CoreGraphics
import Foundation
import Observation
import StitchKit

/// The queue's state: which finding is on screen, what the user has answered but not yet saved,
/// and the one write at the end.
///
/// Off the view because the commit is the delicate part. An edit that did not survive to disk
/// must never be reported as saved — `DECISIONS.md [B4]` is that class of bug on the import
/// path, and `CaptureModel.update(_:)` throws precisely so this can surface it.
@MainActor
@Observable
final class RepairQueueModel {
    let captureID: UUID
    private let model: CaptureModel

    private(set) var findings: [Finding] = []
    var position: Int = 0
    private(set) var answered: Set<Int> = []

    private(set) var frames: (upper: CGImage, lower: CGImage)?
    private(set) var alignment: JoinAlignment?
    private(set) var loadError: String?
    /// Separate from `loadError`: a save failure must not blank out the canvas the user was
    /// just looking at and might retry against.
    private(set) var saveError: String?
    private(set) var busy = false

    /// Answers held until the queue finishes. Committed once, because a chrome change moves
    /// every position below it and a per-answer commit would re-composite — seconds on a long
    /// capture — between two questions.
    private var editedDy: [Int: Int] = [:]
    private var editedChrome: [UUID: ChromeInsets] = [:]

    /// Bumped at the top of every `load()`; a load only commits its result if this still
    /// matches when its `await` returns. `CaptureModel.joinFrames` reads through an independent
    /// `Task.detached`, which does not observe a `.task(id:)` cancellation, so a slow load can
    /// resolve after a faster later one. Tokens rather than finding numbers: paging away and
    /// back is a legitimate way to reach the same finding twice, and the first visit's stale
    /// load must not overwrite what the second visit (and a drag on top of it) produced.
    private var loadToken = 0

    init(captureID: UUID, model: CaptureModel, startAt: Int) {
        self.captureID = captureID
        self.model = model
        let findings = model.captures.first { $0.id == captureID }?.findings ?? []
        self.findings = findings
        self.position = findings.firstIndex { $0.n == startAt } ?? 0
    }

    var current: Finding? { findings.indices.contains(position) ? findings[position] : nil }
    var answeredCount: Int { answered.count }
    var hasPendingEdits: Bool { !editedDy.isEmpty || !editedChrome.isEmpty }

    private var session: StitchSession? {
        model.captures.first { $0.id == captureID }?.session
    }

    // MARK: - Loading

    /// The single load path. Every exit sets either `loadError` or the pair of `frames` and
    /// `alignment` — it never leaves the screen on a spinner with nothing in flight to end it.
    func load() async {
        loadToken += 1
        let token = loadToken
        loadError = nil
        frames = nil
        alignment = nil

        guard let session else {
            loadError = CaptureCondition.message(for: CaptureModel.CaptureError.notFound)
            return
        }
        guard let finding = current else {
            loadError = CaptureCondition.nothingToLineUpMessage
            return
        }
        // Only a seam has frames to load. Bars and gaps answer against the proxy (Task 14).
        guard case .join(let joinIndex) = finding.target else { return }

        var next = JoinAlignment(session: session, joinIndex: joinIndex)
        // Carry an unsaved edit across a move between findings, so paging away and back does
        // not silently discard the user's work.
        if let dy = editedDy[joinIndex] { next?.setDy(dy) }
        guard let resolved = next else {
            loadError = CaptureCondition.joinNotDescribedMessage
            return
        }
        do {
            let loaded = try await model.joinFrames(captureID, joinIndex: joinIndex)
            guard token == loadToken else { return }
            frames = loaded
            alignment = resolved
        } catch {
            guard token == loadToken else { return }
            // The model logged the raw error; this is the sentence a person can read.
            loadError = CaptureCondition.message(for: error)
        }
    }

    // MARK: - Answering a seam

    func drag(translation: CGFloat, sourcePixelsPerPoint: CGFloat, from start: Int, zoom: CGFloat) {
        guard var alignment, case .join(let joinIndex)? = current?.target else { return }
        let next = alignment.dy(
            draggedBy: translation, from: start,
            sourcePixelsPerPoint: sourcePixelsPerPoint, zoom: zoom
        )
        alignment.setDy(next)
        self.alignment = alignment
        editedDy[joinIndex] = next
    }

    func setDy(_ value: Int) {
        guard var alignment, case .join(let joinIndex)? = current?.target else { return }
        alignment.setDy(value)
        self.alignment = alignment
        editedDy[joinIndex] = alignment.dy
    }

    /// Two source pixels per press: one is imperceptible at 1×, and the queue's chevrons are a
    /// coarse correction — the stepper behind *Adjust manually* is where single pixels live.
    func nudge(_ direction: Int) {
        guard let alignment else { return }
        setDy(alignment.dy + direction * 2)
    }

    // MARK: - Advancing and committing

    /// Mark the current finding answered and move on. Returns `true` when the queue is done and
    /// the caller should close.
    func answer() async -> Bool {
        if let n = current?.n { answered.insert(n) }
        if position + 1 < findings.count {
            position += 1
            return false
        }
        return await commit()
    }

    /// Write every held answer, once. Returns `true` when the caller may close — either the
    /// write succeeded or there was nothing to write.
    func commit() async -> Bool {
        guard hasPendingEdits else { return true }
        guard var session else {
            // The capture disappeared out from under this screen while edits were pending.
            // This drop is not silent: it reads like any other failed save.
            saveError = CaptureCondition.message(for: CaptureModel.CaptureError.notFound)
            return false
        }
        busy = true
        defer { busy = false }

        for (joinIndex, dy) in editedDy {
            guard let i = session.seams.firstIndex(where: { $0.fromIndex == joinIndex }) else {
                // Unreachable: `editedDy` is only set where a `JoinAlignment` exists, and its
                // init requires the seam. Skipping this one edit is the least-bad response to
                // manifest data we did not expect — better than discarding the whole batch.
                continue
            }
            session.seams[i].provisionalDy = dy
            // The user has now looked at this join with their own eyes. Leaving it flagged
            // would re-raise a finding over a join they just answered.
            session.seams[i].isLowConfidence = false
        }
        for (keyframeID, insets) in editedChrome {
            session.setChromeOverride(insets.top, for: .top, keyframeID: keyframeID)
            session.setChromeOverride(insets.bottom, for: .bottom, keyframeID: keyframeID)
        }

        do {
            try await model.update(session)
            editedDy.removeAll()
            editedChrome.removeAll()
            return true
        } catch {
            // The model logged the raw error; this is the sentence a person can read. The
            // edits stay held so the user can try again — they must never be led to believe a
            // repair saved when it did not.
            saveError = CaptureCondition.message(for: error)
            return false
        }
    }

    func clearSaveError() { saveError = nil }

    /// Record a chrome answer. Used by Task 14.
    func setChrome(_ insets: ChromeInsets, keyframeID: UUID) {
        editedChrome[keyframeID] = insets
    }

    func chrome(for keyframeID: UUID) -> ChromeInsets? { editedChrome[keyframeID] }
}
```

- [ ] **Step 3: Write `RepairQueueView`**

Create `Seamly/Seamly/Features/Repair/RepairQueueView.swift`:

```swift
import SwiftUI
import StitchKit

/// Repair as a QUEUE. The user never hunts a 15 000 px image: each problem is presented zoomed,
/// with one question and a wide affirmative answer, because most flagged seams turn out fine
/// and the common case must be one tap.
///
/// The ground is **paper**, not the black canvas the previous repair screen used. That was a
/// considered choice for judging alignment and this reverses it deliberately: the design puts a
/// white sheet on a paper ground, and the sheet is white in both themes, so the content itself
/// is never dimmed.
struct RepairQueueView: View {
    let captureID: UUID
    let model: CaptureModel
    let onClose: () -> Void

    @State private var queue: RepairQueueModel
    @State private var zoom = ZoomState()
    @State private var showManual = false

    init(captureID: UUID, model: CaptureModel, startAt: Int, onClose: @escaping () -> Void) {
        self.captureID = captureID
        self.model = model
        self.onClose = onClose
        _queue = State(initialValue: RepairQueueModel(captureID: captureID, model: model, startAt: startAt))
    }

    private var capture: Capture? { model.captures.first { $0.id == captureID } }
    /// The stage shows one join, but the margin still describes the WHOLE capture — so the
    /// marker the user tapped stays visible beside the pixels it points at.
    private var captureSize: CGSize { capture?.pixelSize ?? .zero }
    private var marks: [CaptureMark] { capture?.displayMarks ?? [] }
    private var findings: [Finding] { queue.findings }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "Repair",
                subtitle: "\(queue.answeredCount) of \(queue.findings.count) answered"
            ) {
                IconButton(symbol: "xmark", label: "Close") {
                    Task { if await queue.commit() { onClose() } }
                }
            }

            if let finding = queue.current {
                stage(finding)
                prompt(finding)
            } else {
                EmptyState(
                    symbol: "checkmark.seal",
                    title: "Nothing to fix",
                    message: "Every seam matched confidently."
                )
                .frame(maxHeight: .infinity)
                SeamlyButton("Close", action: onClose)
                    .padding(SeamlySpace.gutterCompact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
        .overlay { saving }
        .task(id: queue.position) {
            showManual = false
            zoom.reset()
            await queue.load()
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(
                get: { queue.saveError != nil },
                set: { if !$0 { queue.clearSaveError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(queue.saveError ?? "")
        }
    }

    // MARK: - The problem, zoomed

    @ViewBuilder
    private func stage(_ finding: Finding) -> some View {
        Group {
            if let message = queue.loadError {
                EmptyState(symbol: "exclamationmark.triangle", title: "Can't show this", message: message)
            } else if let frames = queue.frames, let alignment = queue.alignment {
                CaptureView(
                    content: .join(upper: frames.upper, lower: frames.lower, alignment: alignment),
                    captureSize: captureSize,
                    marks: marks,
                    // The queue opens hard at 6x; pinch multiplies from there.
                    zoom: 6 * zoom.scale,
                    selected: finding.n,
                    showScale: false,
                    onDrag: { translation, ratio, start in
                        queue.drag(
                            translation: translation,
                            sourcePixelsPerPoint: ratio,
                            from: start,
                            zoom: zoom.scale
                        )
                    },
                    currentDy: alignment.dy
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { zoom.update(magnification: $0.magnification) }
                        .onEnded { _ in withAnimation(SeamlyMotion.base) { zoom.end() } }
                )
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.top, SeamlySpace.s3)
        .padding(.bottom, SeamlySpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - The question

    @ViewBuilder
    private func prompt(_ finding: Finding) -> some View {
        QueuePrompt(
            index: queue.position + 1,
            total: queue.findings.count,
            kind: finding.kind,
            question: finding.question,
            detail: finding.detail,
            value: queue.alignment?.dy,
            onNudge: { queue.nudge($0) },
            onAccept: { Task { if await queue.answer() { onClose() } } },
            onSkipAll: { Task { if await queue.commit() { onClose() } } }
        ) {
            manualPath(finding)
        }
    }

    @ViewBuilder
    private func manualPath(_ finding: Finding) -> some View {
        if !showManual {
            Button("Adjust manually") { showManual = true }
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.accent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let alignment = queue.alignment {
            VStack(spacing: 0) {
                StepperRow(
                    label: "Offset",
                    value: alignment.dy,
                    step: 1,
                    range: alignment.dyRange,
                    hint: "Source pixels between the two halves"
                ) { queue.setDy($0) }
            }
            .padding(.horizontal, SeamlySpace.s4)
            .background(SeamlyColor.paper)
            .overlay {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .strokeBorder(SeamlyColor.rule, lineWidth: 1)
            }
            .seamlyCorners(SeamlyRadius.sm)
        }
    }

    // MARK: - Committing

    /// Committing awaits `CaptureModel.update(_:)`, which persists the manifest *and*
    /// re-composites at full resolution plus a proxy — seconds on a long capture. Without this
    /// the screen is simply frozen: every control is disabled and the stage still has frames,
    /// so the loading branch cannot stand in.
    @ViewBuilder
    private var saving: some View {
        if queue.busy {
            ZStack {
                // Dims rather than replaces: the user keeps sight of the join they just lined
                // up, and the dimming is itself the signal that it is no longer live.
                SeamlyColor.ink.opacity(0.4)
                ProgressView().controlSize(.large)
            }
            .ignoresSafeArea()
            .accessibilityIdentifier("repair-saving")
            .accessibilityLabel("Saving")
        }
    }
}
```

- [ ] **Step 4: Route to it**

In `AppShell.swift`, replace `legacyRepair(target)` in the `fullScreenCover` with:

```swift
            RepairQueueView(
                captureID: target.captureID,
                model: model,
                startAt: target.findingNumber,
                onClose: { repairTarget = nil }
            )
```

and delete the `legacyRepair` function. `RepairView` now has no caller; it stays on disk until Task 20.

- [ ] **Step 5: Build and run the app tests**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS, `RepairUITests` included — Task 10 already retargeted it at `open-repair` and the capture sheet, and the drag it performs lands on `repair-canvas` inside the queue's stage exactly as it did on the old screen.

- [ ] **Step 6: Drive it by hand**

Launch with `-SeamlySeedMisalignedCapture`. From Home, tap the numbered ring in the margin. Confirm:

1. The queue opens on that finding, zoomed hard to the join, on a **paper** ground with a white sheet — not black.
2. Dragging moves the lower half live, one-to-one, and the `dy` readout under the button steps with it without reflowing.
3. Pinching magnifies and the drag becomes finer — zoom is the precision mechanism.
4. *Adjust manually* reveals the offset stepper, and stepping it moves the same pixels.
5. "Looks right" on the last finding saves — the dimming overlay appears — and returns to Home with the flag gone.
6. Closing with ✕ after a drag also saves, rather than discarding it silently.

- [ ] **Step 7: Commit**

```bash
git add Seamly/Seamly/Features/Repair/RepairQueueModel.swift \
        Seamly/Seamly/Features/Repair/RepairQueueView.swift \
        Seamly/Seamly/DesignSystem/CaptureView.swift \
        Seamly/Seamly/AppShell.swift
git commit -m "$(cat <<'EOF'
feat(repair): walk the capture's problems as a queue

One question at a time, zoomed to the problem, with a wide affirmative
answer — most flagged seams turn out fine, so the common case is one tap.
The steppers move behind Adjust manually, where the design puts them.

Answers are held and committed once, because a commit re-composites and
doing that between two questions would cost seconds. The commit keeps the
shipped screen's discipline: an edit that did not reach disk is never
reported as saved, and the held edits survive a failure so Done can be
retried.

The ground is paper now, not black. That reverses a considered decision;
the sheet stays white in both themes, so the pixels being judged are not
dimmed either way.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: The queue answers bars and gaps

The queue can now answer every kind of finding it enumerates. A bars answer writes a chrome override; a gap has no lever and says so.

**Files:**
- Modify: `Seamly/Seamly/Features/Repair/RepairQueueView.swift`
- Modify: `Seamly/Seamly/Features/Repair/RepairQueueModel.swift`
- Test: `Seamly/SeamlyTests/RepairQueueModelTests.swift`

**Interfaces:**
- Consumes: `StitchSession.setChromeOverride(_:for:keyframeID:)`, `StitchSession.chromeValueForEditing(_:keyframeID:)`, `ChromeInsets.maxCombinedCropFraction` (existing public API).
- Produces: `RepairQueueModel` gains `func chromeValue(_ edge: ChromeEdge, for finding: Finding) -> Int`, `func setChrome(_ value: Int, edge: ChromeEdge, for finding: Finding)`, `func acceptNoBars(for finding: Finding)`, `var chromeRange: ClosedRange<Int>` (computed per finding via `chromeRange(for:)`), `var jumpTarget: CaptureJump?`.

- [ ] **Step 1: Write the failing test**

Create `Seamly/SeamlyTests/RepairQueueModelTests.swift`:

```swift
import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// The queue holds answers and writes them once. What matters is that every kind of answer
/// reaches the manifest, and that an answered finding stops being a finding — otherwise the
/// queue would re-raise a question the user just answered.
@MainActor
struct RepairQueueModelTests {

    /// A real capture on disk, so `CaptureModel` can load, assemble and re-assemble it.
    private func makeCapture(chromeUncertainOn: Set<Int> = [], flagged: Set<Int> = []) async throws -> (CaptureModel, UUID) {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let store = SessionStore(containerURL: container)

        let id = UUID()
        let folder = try store.createFolder(for: id)
        let width = 120, height = 300, dy = 180, count = 3
        let source = ramp(width: width, height: height + dy * count)

        var session = StitchSession(
            id: id, createdAt: Date(timeIntervalSince1970: 0), status: .complete,
            deviceScale: 1, orientation: .portrait,
            colorSpaceName: source.colorSpace?.name as String?
        )
        for index in 0..<count {
            let name = String(format: "kf-%04d.bgra", index)
            let crop = source.cropping(to: CGRect(x: 0, y: index * dy, width: width, height: height))!
            try KeyframeIO.writeRaw(crop, to: folder.appendingPathComponent(name))
            session.keyframes.append(
                Keyframe(filename: name, pixelWidth: width, pixelHeight: height, index: index)
            )
        }
        session.seams = (0..<(count - 1)).map {
            Seam(fromIndex: $0, provisionalDy: dy,
                 confidence: flagged.contains($0) ? 0.2 : 0.9,
                 isLowConfidence: flagged.contains($0))
        }
        session.keyframeChrome = session.keyframes.map { kf in
            chromeUncertainOn.contains(kf.index)
                ? KeyframeChrome(keyframeID: kf.id)
                : KeyframeChrome(keyframeID: kf.id,
                                 automatic: ChromeMeasurement(insets: .zero, confidence: 0.9))
        }
        try store.writeManifest(session)

        let model = CaptureModel(appContainer: container, groupContainer: nil)
        await model.refresh()
        return (model, id)
    }

    private func ramp(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 40.0 + Double(y) * (150.0 / Double(height)) + 40 * sin(Double(x) * 0.4)
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

    @Test func answeringNoBarsClearsTheFinding() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .bars })

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.acceptNoBars(for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id })
        #expect(after.findings.filter { $0.kind == .bars }.isEmpty,
                "an answered finding must stop being a finding, or the queue re-asks it")
    }

    @Test func aBarsAnswerReachesTheManifest() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .bars })
        guard case .chrome(let keyframeID, _) = finding.target else {
            Issue.record("expected a chrome target")
            return
        }

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.setChrome(44, edge: .top, for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id })
        #expect(after.session.chromeValueForEditing(.top, keyframeID: keyframeID) == 44)
        #expect(after.session.hasChromeOverride(.top, keyframeID: keyframeID))
    }

    /// Chrome moves every position below it, so the composite must actually change height.
    @Test func aBarsAnswerChangesTheCompositesHeight() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let before = try #require(model.captures.first { $0.id == id }).pixelSize.height
        let finding = try #require(model.captures.first { $0.id == id }?.findings.first { $0.kind == .bars })

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.setChrome(40, edge: .bottom, for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id }).pixelSize.height
        #expect(after != before)
    }

    /// A queue the user walked without changing anything must close cleanly. Committing
    /// nothing is a success, not a failure — otherwise "Skip all" would raise a save error.
    @Test func committingNothingSucceeds() async throws {
        let (model, id) = try await makeCapture()
        let queue = RepairQueueModel(captureID: id, model: model, startAt: 1)
        #expect(!queue.hasPendingEdits)
        #expect(await queue.commit())
    }

    @Test func answeringTheLastFindingCommitsAndFinishes() async throws {
        let (model, id) = try await makeCapture(flagged: [0])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .seam })

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        await queue.load()
        queue.setDy(150)
        #expect(await queue.answer(), "the last answer commits and tells the caller to close")

        let after = try #require(model.captures.first { $0.id == id })
        let seam = try #require(after.session.seams.first { $0.fromIndex == 0 })
        #expect(seam.provisionalDy == 150)
        #expect(!seam.isLowConfidence, "a join the user has looked at must stop being flagged")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:SeamlyTests/RepairQueueModelTests test
```
Expected: compile failure — `value of type 'RepairQueueModel' has no member 'acceptNoBars'`.

- [ ] **Step 3: Add the chrome answers to `RepairQueueModel`**

Replace the two placeholder chrome members at the bottom of `RepairQueueModel` with:

```swift
    // MARK: - Answering bars

    /// The crop currently in force for one edge, including any answer held but not yet written.
    func chromeValue(_ edge: ChromeEdge, for finding: Finding) -> Int {
        guard case .chrome(let keyframeID, _) = finding.target else { return 0 }
        if let held = editedChrome[keyframeID] {
            return edge == .top ? held.top : held.bottom
        }
        return session?.chromeValueForEditing(edge, keyframeID: keyframeID) ?? 0
    }

    /// The compositor refuses a combined crop past half the frame, and
    /// `setChromeOverride` clamps to it — so the control must stop there too, rather than
    /// letting a stepper run on while the picture stops moving.
    func chromeRange(for finding: Finding) -> ClosedRange<Int> {
        guard case .chrome(let keyframeID, _) = finding.target,
              let keyframe = session?.keyframes.first(where: { $0.id == keyframeID })
        else { return 0...0 }
        let limit = Int(Double(keyframe.pixelHeight) * ChromeInsets.maxCombinedCropFraction)
        return 0...max(0, limit)
    }

    func setChrome(_ value: Int, edge: ChromeEdge, for finding: Finding) {
        guard case .chrome(let keyframeID, _) = finding.target else { return }
        var insets = editedChrome[keyframeID] ?? ChromeInsets(
            top: session?.chromeValueForEditing(.top, keyframeID: keyframeID) ?? 0,
            bottom: session?.chromeValueForEditing(.bottom, keyframeID: keyframeID) ?? 0
        )
        switch edge {
        case .top: insets.top = value
        case .bottom: insets.bottom = value
        }
        editedChrome[keyframeID] = insets
    }

    /// "No bars here" — the affirmative answer for a bars finding.
    ///
    /// Writes an explicit **zero** override rather than leaving the edge alone. Resolution is
    /// already lossless at zero, so nothing about the picture changes; what changes is that the
    /// edge now has a *user* value, which is what stops `chromeEdgesNeedingReview` returning it
    /// and stops the queue asking again. An unanswered edge and an edge answered "none" resolve
    /// to the same crop and must not read as the same state.
    func acceptNoBars(for finding: Finding) {
        guard case .chrome(let keyframeID, _) = finding.target else { return }
        editedChrome[keyframeID] = ChromeInsets(top: 0, bottom: 0)
    }
```

Delete the old `setChrome(_:keyframeID:)` and `chrome(for:)` stubs from Task 13.

- [ ] **Step 4: Let the queue's stage show a proxy for bars and gaps**

In `RepairQueueView`, replace `stage(_:)`:

```swift
    /// A seam is judged against the live frame pair, because the proxy would not move under
    /// the finger. Bars and gaps are judged against the capture itself, jumped to the frame or
    /// the break in question — there is nothing to drag, and what the user needs to see is the
    /// picture as it stands.
    @ViewBuilder
    private func stage(_ finding: Finding) -> some View {
        Group {
            if let message = queue.loadError {
                EmptyState(symbol: "exclamationmark.triangle", title: "Can't show this", message: message)
            } else if finding.kind == .seam {
                if let frames = queue.frames, let alignment = queue.alignment {
                    CaptureView(
                        content: .join(upper: frames.upper, lower: frames.lower, alignment: alignment),
                        captureSize: captureSize,
                        marks: marks,
                        findings: findings,
                        zoom: 6 * zoom.scale,
                        selected: finding.n,
                        showScale: false,
                        onDrag: { translation, ratio, start in
                            queue.drag(translation: translation, sourcePixelsPerPoint: ratio,
                                       from: start, zoom: zoom.scale)
                        },
                        currentDy: alignment.dy
                    )
                    .simultaneousGesture(magnify)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let proxy = capture?.proxy {
                CaptureView(
                    content: .proxy(proxy),
                    captureSize: captureSize,
                    marks: marks,
                    findings: findings,
                    zoom: 3 * zoom.scale,
                    selected: finding.n,
                    showScale: false,
                    jump: CaptureJump(atPct: finding.atPct, fraction: 0.25, token: queue.position)
                )
                .simultaneousGesture(magnify)
            } else {
                EmptyState(
                    symbol: "photo.badge.exclamationmark",
                    title: "Can't show this",
                    message: "This capture is no longer on the device."
                )
            }
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.top, SeamlySpace.s3)
        .padding(.bottom, SeamlySpace.s5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { zoom.update(magnification: $0.magnification) }
            .onEnded { _ in withAnimation(SeamlyMotion.base) { zoom.end() } }
    }
```

- [ ] **Step 5: Give each kind its own answer**

Replace `prompt(_:)` and `manualPath(_:)`:

```swift
    @ViewBuilder
    private func prompt(_ finding: Finding) -> some View {
        QueuePrompt(
            index: queue.position + 1,
            total: queue.findings.count,
            kind: finding.kind,
            question: finding.question,
            detail: finding.detail,
            // Only a seam has an offset to state. A gap has nothing overlapping; a bars answer
            // is a crop, and the steppers show it.
            value: finding.kind == .seam ? queue.alignment?.dy : nil,
            affirmative: affirmative(finding),
            // A gap has no lever — the content was never captured, so a nudge would move
            // nothing. Offering a control that does nothing is worse than offering none.
            onNudge: finding.kind == .seam ? { queue.nudge($0) } : nil,
            onAccept: { accept(finding) },
            onSkipAll: { Task { if await queue.commit() { onClose() } } }
        ) {
            manualPath(finding)
        }
    }

    private func affirmative(_ finding: Finding) -> String {
        switch finding.kind {
        case .seam: "Looks right"
        case .bars: "No bars here"
        case .gap: "Got it"
        }
    }

    private func accept(_ finding: Finding) {
        // "No bars here" is itself the answer, and must be recorded as one: an edge nobody has
        // answered and an edge answered "none" crop identically but are not the same state.
        if finding.kind == .bars { queue.acceptNoBars(for: finding) }
        Task { if await queue.answer() { onClose() } }
    }

    @ViewBuilder
    private func manualPath(_ finding: Finding) -> some View {
        // A gap cannot be adjusted at all — there is no number behind it.
        if finding.kind == .gap {
            EmptyView()
        } else if !showManual {
            Button("Adjust manually") { showManual = true }
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.accent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                switch finding.kind {
                case .seam:
                    if let alignment = queue.alignment {
                        StepperRow(
                            label: "Offset",
                            value: alignment.dy,
                            step: 1,
                            range: alignment.dyRange,
                            hint: "Source pixels between the two halves"
                        ) { queue.setDy($0) }
                    }
                case .bars:
                    StepperRow(
                        label: "Top bar",
                        value: queue.chromeValue(.top, for: finding),
                        step: 5,
                        range: queue.chromeRange(for: finding),
                        hint: "Repeated chrome cropped from this frame"
                    ) { queue.setChrome($0, edge: .top, for: finding) }
                    StepperRow(
                        label: "Bottom bar",
                        value: queue.chromeValue(.bottom, for: finding),
                        step: 5,
                        range: queue.chromeRange(for: finding)
                    ) { queue.setChrome($0, edge: .bottom, for: finding) }
                case .gap:
                    EmptyView()
                }
            }
            .padding(.horizontal, SeamlySpace.s4)
            .background(SeamlyColor.paper)
            .overlay {
                RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                    .strokeBorder(SeamlyColor.rule, lineWidth: 1)
            }
            .seamlyCorners(SeamlyRadius.sm)
        }
    }
```

- [ ] **Step 6: Run the tests**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS, all suites.

- [ ] **Step 7: Commit**

```bash
git add Seamly/Seamly/Features/Repair \
        Seamly/SeamlyTests/RepairQueueModelTests.swift
git commit -m "$(cat <<'EOF'
feat(repair): answer bars and gaps in the queue too

The queue can now answer every kind of finding it enumerates, so none of
its questions is decorative.

A bars answer writes a chrome override — including "No bars here", which
writes an explicit zero. Resolution was already lossless at zero, so the
picture does not change; what changes is that the edge now has a user
value, which is what stops the queue asking again. An unanswered edge and
an edge answered "none" crop identically and are not the same state.

A gap gets the same frame and the same jump but no lever: the content was
never captured, so a nudge would move nothing, and a control that does
nothing is worse than no control.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Library

Compact: a ruled list. Regular: a grid of uniform 3:5 cells — never square, and never sized by capture length; length is told by the ribbon and the number. The dock stays, because the capture affordance is permanently present.

**Files:**
- Modify: `Seamly/Seamly/DesignSystem/Components/Data/CaptureSheetView.swift` (implement the ribbon)
- Create: `Seamly/Seamly/DesignSystem/Components/Data/CaptureThumbnail.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Data/CaptureListRow.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Data/CaptureGridCard.swift`
- Create: `Seamly/Seamly/Features/Library/LibraryScreen.swift`
- Modify: `Seamly/Seamly/AppShell.swift` (`.library` destination)

**Interfaces:**
- Consumes: `Capture+Design` (Task 9), `CaptureSheetView` (Task 5), `StatusNote`/`NavBar`/`IconButton`/`EmptyState` (Task 7), `CaptureDock`/`ImportRow` (Task 8).
- Produces:
  - `struct CaptureThumbnail: View` — `init(proxy: CGImage?, marks: [CaptureMark], ribbon: Bool)`
  - `struct CaptureListRow: View` — `init(capture:onOpen:onDelete:)`
  - `struct CaptureGridCard: View` — `init(capture:onOpen:onDelete:)`
  - `struct LibraryScreen: View` — `init(model:onOpen:onBack:onVideo:onPhotos:onDiagnostics:)`

- [ ] **Step 1: Implement the ribbon**

Replace `CaptureSheetView`'s body in `Components/Data/CaptureSheetView.swift`:

```swift
struct CaptureSheetView<Content: View>: View {
    /// A thin strip down the right edge showing the whole capture squeezed, so length is
    /// legible without a misleading crop. Off inside `CaptureView`, which shows the capture
    /// itself; on for the library, where the crop is top-anchored and short.
    var ribbon: Bool = false
    /// Drawn as ticks on the ribbon, so a library thumbnail still says where its doubt is.
    var ribbonMarks: [CaptureMark] = []
    /// The whole capture, squeezed to fill the ribbon.
    var ribbonImage: CGImage?
    @ViewBuilder var content: () -> Content

    var body: some View {
        Rectangle()
            .fill(SeamlyColor.sheet)
            .overlay {
                HStack(spacing: 0) {
                    content()
                    if ribbon {
                        ZStack(alignment: .topLeading) {
                            if let ribbonImage {
                                Image(decorative: ribbonImage, scale: 1)
                                    .resizable()
                                    .opacity(0.85)
                            } else {
                                SeamlyColor.paperSunk
                            }
                            GeometryReader { geo in
                                ForEach(ribbonMarks.filter { $0.kind != .confident }) { mark in
                                    Rectangle()
                                        .fill(mark.kind == .gap ? SeamlyColor.markGap : SeamlyColor.markFlag)
                                        .frame(height: 2)
                                        .offset(y: geo.size.height * CGFloat(mark.atPct))
                                }
                            }
                        }
                        .frame(width: 10)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(SeamlyColor.rule).frame(width: 1)
                        }
                    }
                }
            }
            .clipShape(Rectangle())
            .seamlySheetLift()
    }
}
```

- [ ] **Step 2: Write `CaptureThumbnail`**

Create `Seamly/Seamly/DesignSystem/Components/Data/CaptureThumbnail.swift`:

```swift
import SwiftUI
import CoreGraphics

/// A capture as a small plate: white sheet, square corners, a **top-anchored** crop, and the
/// ribbon down its right edge.
///
/// Principle 3: the crop is top-anchored. The middle of a 1:40 image is an unrecognisable slice
/// that reads as "not stitched".
struct CaptureThumbnail: View {
    let proxy: CGImage?
    var marks: [CaptureMark] = []
    var ribbon: Bool = true

    var body: some View {
        CaptureSheetView(ribbon: ribbon, ribbonMarks: marks, ribbonImage: proxy) {
            if let proxy {
                GeometryReader { geo in
                    Image(decorative: proxy, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, alignment: .top)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .clipped()
                }
            } else {
                SeamlyColor.paperSunk
            }
        }
        // `.clipped()` above only affects painting: without this the hit-test and
        // accessibility frame follow the aspect-filled image's own unclipped render size,
        // which for a capture many screens tall is wildly bigger than the box. This bit
        // HomeView's recents thumbnail — see docs/logs/2026-08-18-02-guided-repair.md.
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 3: Write `CaptureListRow` and `CaptureGridCard`**

Create `Seamly/Seamly/DesignSystem/Components/Data/CaptureListRow.swift`:

```swift
import SwiftUI

/// Compact-width library row. Ruled, not carded — a document lists things on rules.
struct CaptureListRow: View {
    let capture: Capture
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: SeamlySpace.s4) {
                CaptureThumbnail(proxy: capture.proxy, marks: capture.displayMarks)
                    .frame(width: 46, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                    Text(SeamlyNumber.dimensions(
                        width: Int(capture.pixelSize.width),
                        height: Int(capture.pixelSize.height)
                    ))
                    .font(SeamlyFont.mono)
                    .monospacedDigit()
                    .foregroundStyle(SeamlyColor.inkFaint)
                    CaptureStatusNotes(capture: capture, size: .small)
                }
                Spacer(minLength: SeamlySpace.s4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16))
                    .foregroundStyle(SeamlyColor.inkFaint)
            }
            .padding(.vertical, SeamlySpace.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-row")
        .overlay(alignment: .bottom) {
            Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// The badges a capture wears wherever it is listed. One implementation, so the same state can
/// never read two different ways in two different places.
struct CaptureStatusNotes: View {
    let capture: Capture
    var size: StatusNote.Size = .small

    var body: some View {
        let findings = capture.phase == .ready ? capture.findings : []
        let flagged = findings.filter { $0.kind == .seam || $0.kind == .bars }.count
        let gaps = findings.filter { $0.kind == .gap }.count
        HStack(spacing: SeamlySpace.s2) {
            if case .failed = capture.phase { StatusNote(kind: .failed, size: size) }
            if capture.phase == .processing { StatusNote(kind: .processing, size: size) }
            if capture.session.status == .recording { StatusNote(kind: .incomplete, size: size) }
            if flagged > 0 { StatusNote(kind: .flagged, count: flagged, size: size) }
            if gaps > 0 { StatusNote(kind: .gap, count: gaps, size: size) }
        }
    }
}
```

Create `Seamly/Seamly/DesignSystem/Components/Data/CaptureGridCard.swift`:

```swift
import SwiftUI

/// Regular-width library cell. A square grid cell is wrong for a 1:40 image, so every card is a
/// fixed 3:5 window on the START of the capture, uniform whatever the length — length is told
/// by the ribbon and the number, never by cell size.
///
/// The caption sits BELOW the sheet, on paper: a plate with a caption, not text burned over the
/// image.
struct CaptureGridCard: View {
    let capture: Capture
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: SeamlySpace.s3) {
                CaptureThumbnail(proxy: capture.proxy, marks: capture.displayMarks)
                    .aspectRatio(3.0 / 5.0, contentMode: .fit)
                VStack(alignment: .leading, spacing: 3) {
                    Text(capture.title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                    Text(SeamlyNumber.px(Int(capture.pixelSize.height)))
                        .font(SeamlyFont.mono)
                        .monospacedDigit()
                        .foregroundStyle(SeamlyColor.inkFaint)
                    CaptureStatusNotes(capture: capture)
                        .padding(.top, 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-card")
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
```

- [ ] **Step 4: Write `LibraryScreen`**

Create `Seamly/Seamly/Features/Library/LibraryScreen.swift`:

```swift
import SwiftUI

/// Every capture. Compact is a ruled list; regular is a grid of uniform 3:5 cells. The dock
/// stays, because the capture affordance is permanently present.
struct LibraryScreen: View {
    let model: CaptureModel
    var onOpen: (UUID) -> Void
    var onBack: () -> Void
    var onVideo: () -> Void
    var onPhotos: () -> Void
    var onDiagnostics: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    private var layout: SeamlyLayout { SeamlyLayout(horizontal: hSize, vertical: vSize) }

    var body: some View {
        VStack(spacing: 0) {
            NavBar(
                title: "Library",
                subtitle: "\(model.captures.count) captures",
                large: true,
                onBack: onBack
            ) {
                // Diagnostics is a developer surface, not a feature. It stays reachable
                // because the extension cannot draw UI and its container is not reliably
                // pullable over USB, so this log is the only window into a failed capture on a
                // device — but it lives behind an overflow, on the screen that already holds
                // everything else.
                Menu {
                    Button("Diagnostics", systemImage: "stethoscope", action: onDiagnostics)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .seamlyHitTarget()
                }
                .accessibilityLabel("More")
            }

            if model.captures.isEmpty {
                EmptyState(
                    symbol: "tray",
                    title: "No captures yet",
                    message: "Anything you record or import shows up here."
                )
                .frame(maxHeight: .infinity)
            } else if layout.isRegular {
                grid
            } else {
                list
            }

            CaptureDock(onVideo: onVideo, onPhotos: onPhotos)
                .padding(.horizontal, layout.gutter)
                .padding(.top, SeamlySpace.s5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }

    private var list: some View {
        List {
            ForEach(model.captures) { capture in
                CaptureListRow(
                    capture: capture,
                    onOpen: { onOpen(capture.id) },
                    onDelete: { model.delete(capture.id) }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
                .listRowSeparator(.hidden)
                .listRowBackground(SeamlyColor.paper)
            }
            Section {
                ImportRow(symbol: "film", title: "From Video",
                          detail: "Stitch an existing screen recording", action: onVideo)
                ImportRow(symbol: "photo.on.rectangle", title: "From Photos",
                          detail: "Pick overlapping screenshots", action: onPhotos)
            } header: {
                Text("Or start from something you already have".uppercased())
                    .font(SeamlyFont.caps)
                    .seamlyCapsTracking()
                    .foregroundStyle(SeamlyColor.inkFaint)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: layout.gutter, bottom: 0, trailing: layout.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(SeamlyColor.paper)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(SeamlyColor.paper)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190), spacing: SeamlySpace.s7)],
                spacing: SeamlySpace.s7
            ) {
                ForEach(model.captures) { capture in
                    CaptureGridCard(
                        capture: capture,
                        onOpen: { onOpen(capture.id) },
                        onDelete: { model.delete(capture.id) }
                    )
                }
            }
            .padding(.horizontal, layout.gutter)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s8)
        }
    }
}
```

- [ ] **Step 5: Route to it**

In `AppShell.swift`, replace the `.library` branch of `destination(_:)`:

```swift
        case .library:
            LibraryScreen(
                model: model,
                onOpen: { path.append(.review($0)) },
                onBack: { path.removeLast() },
                onVideo: {},
                onPhotos: {},
                onDiagnostics: { showDiagnostics = true }
            )
```

- [ ] **Step 6: Build, test, and look at both size classes**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS.

Then run on an iPhone 17 and an iPad Pro 13-inch simulator with `-SeamlySeedMisalignedCapture`. Confirm:

1. iPhone: a ruled list, with the two import rows beneath under a caps header. Swipe a row left to delete.
2. iPad: uniform 3:5 cards, all the same height regardless of capture length. Long-press for Delete.
3. Every thumbnail is cropped from the **top**, not the middle.
4. Tapping a thumbnail opens that capture, and the tap lands where the thumbnail is drawn — not below it.
5. The overflow menu reaches Diagnostics.

- [ ] **Step 7: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Data \
        Seamly/Seamly/Features/Library/LibraryScreen.swift \
        Seamly/Seamly/AppShell.swift
git commit -m "$(cat <<'EOF'
feat(library): list every capture, and grid them on iPad

Ruled list at compact width, uniform 3:5 cards at regular. Never square
and never sized by capture length — a 1:40 image in a square cell is an
unrecognisable slice, so length is told by the ribbon and the number while
the crop stays top-anchored.

Every fixed-box thumbnail carries contentShape alongside clipped: clipped
only affects painting, and without it the hit-test follows the
aspect-filled image's unclipped size, which for a capture many screens
tall lands the tap well below the picture. That bug shipped once already.

Diagnostics moves behind the overflow here — a developer surface, but the
only window into a failed capture on a device.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Export

Grouped as image vs document, because that is the decision the user is actually making. Dimensions stated up front — numbers carry their unit.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Components/Navigation/SheetChrome.swift`
- Create: `Seamly/Seamly/Features/Export/ExportSheet.swift`
- Modify: `Seamly/Seamly/AppShell.swift` (present it), `Seamly/Seamly/Features/Result/ReviewScreen.swift` (`onExport`)

**Interfaces:**
- Consumes: `Exporter`, `CaptureModel.fullComposite(_:)`, `CaptureModel.exportPDF(_:)` (existing); `ImportRow` (Task 8).
- Produces:
  - `struct SheetChrome<Leading: View, Trailing: View, Content: View>: View` — `init(title:@ViewBuilder leading:@ViewBuilder trailing:@ViewBuilder content:)`
  - `struct ExportSheet: View` — `init(captureID:model:onClose:)`

- [ ] **Step 1: Write `SheetChrome`**

Create `Seamly/Seamly/DesignSystem/Components/Navigation/SheetChrome.swift`:

```swift
import SwiftUI

/// Paper sheets slide up as paper: a square top edge with a rule, not a big rounded glass card.
/// The radius stays small so it reads as a sheet, not a bubble.
struct SheetChrome<Leading: View, Trailing: View, Content: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SeamlySpace.s4) {
                HStack { leading() }.frame(maxWidth: .infinity, alignment: .leading)
                Text(title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                HStack { trailing() }.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .padding(.vertical, SeamlySpace.s4)
            .frame(minHeight: 56)
            .overlay(alignment: .bottom) {
                Rectangle().fill(SeamlyColor.ruleFaint).frame(height: 1)
            }
            ScrollView { content() }
        }
        .background(SeamlyColor.paper)
        .presentationDragIndicator(.visible)
    }
}
```

- [ ] **Step 2: Write `ExportSheet`**

Create `Seamly/Seamly/Features/Export/ExportSheet.swift`:

```swift
import SwiftUI
import CoreGraphics

/// Where a finished capture goes. Grouped image vs document, because that is the decision the
/// user is actually making.
///
/// Nothing is prepared until it is asked for, and the sheet is built fresh on every
/// presentation — so a file rendered from the geometry as it was cannot outlive a repair. The
/// old result screen cached PNG and PDF URLs for the screen's lifetime and had to discard them
/// explicitly on every return from repair, because two of its four export paths would
/// otherwise have handed out pre-repair bytes.
struct ExportSheet: View {
    let captureID: UUID
    let model: CaptureModel
    let onClose: () -> Void

    @State private var busy = false
    @State private var status: String?
    @State private var shareItem: ShareItem?

    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    var body: some View {
        SheetChrome(title: "Export") {
            EmptyView()
        } trailing: {
            SeamlyButton("Done", variant: .plain, size: .small, action: onClose)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if let capture {
                    HStack(spacing: SeamlySpace.s3) {
                        Text(SeamlyNumber.dimensions(
                            width: Int(capture.pixelSize.width),
                            height: Int(capture.pixelSize.height)
                        ))
                        .monospacedDigit()
                        if !capture.findings.isEmpty {
                            Text("· \(capture.findings.count) unanswered").monospacedDigit()
                        }
                    }
                    .font(SeamlyFont.mono)
                    .foregroundStyle(SeamlyColor.inkFaint)
                    .padding(.bottom, SeamlySpace.s5)
                }

                caps("Image")
                ImportRow(symbol: "photo", title: "Save to Photos",
                          detail: "Full resolution PNG", action: saveToPhotos)
                ImportRow(symbol: "square.and.arrow.up", title: "Share PNG",
                          detail: "Composited on demand", action: sharePNG)
                ImportRow(symbol: "doc.on.doc", title: "Copy to Clipboard", action: copy)

                caps("Document").padding(.top, SeamlySpace.s7)
                ImportRow(symbol: "doc.richtext", title: "Export PDF",
                          detail: "Paginated for very long captures", action: sharePDF)

                if busy {
                    ProgressView()
                        .padding(.top, SeamlySpace.s6)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .padding(.top, SeamlySpace.s5)
            .padding(.bottom, SeamlySpace.s8)
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .alert(
            "Export",
            isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(status ?? "")
        }
        .disabled(busy)
    }

    private func caps(_ text: String) -> some View {
        Text(text.uppercased())
            .font(SeamlyFont.caps)
            .seamlyCapsTracking()
            .foregroundStyle(SeamlyColor.inkFaint)
            .padding(.bottom, SeamlySpace.s3)
    }

    // MARK: - Actions

    private func saveToPhotos() {
        run {
            let image = try await model.fullComposite(captureID)
            try await Exporter.saveToPhotos(image)
            status = "Saved to Photos."
        }
    }

    private func sharePNG() {
        run {
            let image = try await model.fullComposite(captureID)
            shareItem = ShareItem(url: try Exporter.pngURL(image, name: "Seamly-\(captureID.uuidString)"))
        }
    }

    private func sharePDF() {
        run { shareItem = ShareItem(url: try await model.exportPDF(captureID)) }
    }

    private func copy() {
        run {
            let image = try await model.fullComposite(captureID)
            Exporter.copyToPasteboard(image)
            status = "Copied."
        }
    }

    /// Shared tail: every export path surfaces what actually went wrong, in plain language —
    /// never a generic "something failed", and never a bridged Swift enum description. The
    /// model logs the raw error to `Diagnostics`.
    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await body() }
            catch { status = CaptureCondition.message(for: error) }
        }
    }
}
```

`ShareLink` cannot serve here: it needs its item at construction time, and these files are composited on demand. So add, at the bottom of the same file, with `import UIKit` at the top:

```swift
/// `UIActivityViewController` has no SwiftUI equivalent that can be presented *from* a sheet
/// with a prepared file — `ShareLink` needs its item at construction time, and these files are
/// composited on demand. This is the same class of exception as `BroadcastPickerButton`.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
```

- [ ] **Step 3: Present it**

In `AppShell.swift`, add state and the presentation:

```swift
    @State private var exportTarget: UUID?
```

```swift
        .sheet(item: Binding(
            get: { exportTarget.map { IdentifiedUUID(id: $0) } },
            set: { exportTarget = $0?.id }
        )) { target in
            ExportSheet(captureID: target.id, model: model, onClose: { exportTarget = nil })
                .presentationDetents([.medium, .large])
        }
```

with, at file scope in `AppShell.swift`:

```swift
/// `sheet(item:)` needs an `Identifiable`, and a bare `UUID` is not one.
private struct IdentifiedUUID: Identifiable { let id: UUID }
```

and in `destination(_:)`'s `.review` branch, replace the empty closure:

```swift
                onExport: { exportTarget = id }
```

- [ ] **Step 4: Build, test, and drive it**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS.

Then by hand, with `-SeamlySeedMisalignedCapture`: open Review, tap Export, and confirm Save to Photos writes (granting the permission prompt), Copy reports "Copied.", and Share PNG and Export PDF both raise the system share sheet with a real file.

Then: export a PNG, go back, repair the join, and export again — the second PNG must contain the repaired geometry. Nothing is cached across the sheet's lifetime, so this should hold by construction; confirm it does.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Navigation/SheetChrome.swift \
        Seamly/Seamly/Features/Export/ExportSheet.swift \
        Seamly/Seamly/AppShell.swift \
        Seamly/Seamly/Features/Result/ReviewScreen.swift
git commit -m "$(cat <<'EOF'
feat(export): group export as image versus document

That is the decision the user is actually making, so it is the grouping
the sheet uses. Dimensions and any unanswered findings are stated up
front, thin-space grouped and tabular.

Nothing is prepared until it is asked for and the sheet is rebuilt on
every presentation, so a file rendered from the geometry as it was cannot
outlive a repair. The old screen cached PNG and PDF URLs for its lifetime
and had to discard them explicitly on every return from the repair cover,
because two of its four paths would otherwise hand out pre-repair bytes.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 17: Import

The one flow with two genuinely different kinds of progress — and the first surface to present the distinction `CaptureModel` was built for.

**Files:**
- Create: `Seamly/Seamly/Features/Import/ImportSheet.swift`
- Modify: `Seamly/Seamly/AppShell.swift` (wire `onVideo` / `onPhotos` on Home and Library)

**Interfaces:**
- Consumes: `CaptureModel.importProgress`, `.isAssemblingNewArrival`, `.importError`, `.clearImportError()`, `.importVideo(_:)`, `.importPhotos(_:)` (existing); `PickedMovie` (existing); `ProgressNote` (Task 9), `SheetChrome` (Task 16).
- Produces: `struct ImportSheet: View` — `init(source: Source, model:onClose:onOpen:)`, `enum ImportSheet.Source { case video, photos }`

- [ ] **Step 1: Write `ImportSheet`**

Create `Seamly/Seamly/Features/Import/ImportSheet.swift`:

```swift
import SwiftUI
import PhotosUI
import CoreGraphics
import ImageIO

/// Picking a source and watching it come in.
///
/// **The two phases are deliberately different.** Reading a recording has a real percentage.
/// Stitching does not — the work is data-dependent and finishes when the seams are found — so
/// it runs indeterminate and says so in words. A bar there would be a lie about how far along
/// the work is, which is why `ProgressNote` takes an optional value at all.
struct ImportSheet: View {
    enum Source { case video, photos }

    let source: Source
    let model: CaptureModel
    let onClose: () -> Void

    @State private var videoSelection: PhotosPickerItem?
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var pickError: String?
    @State private var started = false

    private var isVideo: Bool { source == .video }
    private var reading: Double? { model.importProgress }
    private var stitching: Bool { model.isAssemblingNewArrival }
    private var working: Bool { reading != nil || stitching }

    var body: some View {
        SheetChrome(title: isVideo ? "From Video" : "From Photos") {
            if working { SeamlyButton("Cancel", variant: .plain, size: .small, action: onClose) }
        } trailing: {
            if !working && started { SeamlyButton("Done", variant: .plain, size: .small, action: onClose) }
        } content: {
            VStack(alignment: .leading, spacing: SeamlySpace.s5) {
                if let message = model.importError ?? pickError {
                    failure(message)
                } else if working {
                    progress
                } else if started {
                    finished
                } else {
                    picker
                }
            }
            .padding(.horizontal, SeamlySpace.gutterCompact)
            .padding(.top, SeamlySpace.s6)
            .padding(.bottom, SeamlySpace.s8)
        }
        .onChange(of: videoSelection) { _, item in
            guard let item else { return }
            Task { await loadVideo(item) }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await loadPhotos(items) }
        }
    }

    // MARK: - States

    private var picker: some View {
        Group {
            if isVideo {
                PhotosPicker(selection: $videoSelection, matching: .videos) {
                    importLabel(symbol: "film", title: "Choose a screen recording",
                                detail: "Only the frames that moved are kept")
                }
            } else {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 20, matching: .images) {
                    importLabel(symbol: "photo.on.rectangle", title: "Choose overlapping screenshots",
                                detail: "Pick at least two")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s5) {
            ProgressNote(label: reading != nil ? "Reading video…" : "Stitching…", value: reading)
            Text(reading != nil
                 ? "Decoding the recording into keyframes. Only frames that moved are kept."
                 : "Matching each frame against the last. This has no percentage — it finishes when the seams are found.")
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var finished: some View {
        HStack(spacing: SeamlySpace.s3) {
            Image(systemName: "checkmark").foregroundStyle(SeamlyColor.markOK)
            Text("Stitched.").font(SeamlyFont.body).foregroundStyle(SeamlyColor.ink)
        }
    }

    /// Non-accusatory, and it asks rather than blames. The message already came through
    /// `CaptureCondition.message(for:)`; the raw error is in `Diagnostics`.
    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: SeamlySpace.s5) {
            Text(message)
                .font(SeamlyFont.footnote)
                .foregroundStyle(SeamlyColor.markError)
                .fixedSize(horizontal: false, vertical: true)
                .padding(SeamlySpace.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SeamlyColor.washError)
                .seamlyCorners(SeamlyRadius.xs)
            HStack(spacing: SeamlySpace.s4) {
                SeamlyButton("Cancel", variant: .outline, action: onClose)
                    .frame(maxWidth: .infinity)
                SeamlyButton("Try again") {
                    model.clearImportError()
                    pickError = nil
                    started = false
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func importLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: SeamlySpace.s4) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(SeamlyColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                Text(detail).font(SeamlyFont.caption).foregroundStyle(SeamlyColor.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    // MARK: - Picking

    private func loadVideo(_ item: PhotosPickerItem) async {
        pickError = nil
        // Clear up front, not on the success branch: `PhotosPickerItem` is `Equatable` and
        // `.onChange` only fires on a *change*, so a selection still standing when we return
        // makes re-picking the same video a no-op and the row looks dead.
        videoSelection = nil
        started = true
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                pickError = "That video couldn't be read."
                return
            }
            await model.importVideo(movie.url)
        } catch {
            pickError = CaptureCondition.message(for: error)
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        pickError = nil
        photoSelection = []
        started = true
        var images: [CGImage] = []
        for (i, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    pickError = "Couldn't read photo \(i + 1)."
                    return
                }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    pickError = "Photo \(i + 1) isn't a decodable image."
                    return
                }
                images.append(image)
            } catch {
                pickError = CaptureCondition.message(for: error)
                return
            }
        }
        guard images.count >= 2 else {
            pickError = "Pick at least two overlapping screenshots."
            return
        }
        await model.importPhotos(images)
    }
}
```

- [ ] **Step 2: Present it**

In `AppShell.swift`, add:

```swift
    @State private var importSource: ImportSheet.Source?
```

Make `ImportSheet.Source` `Identifiable` by adding to `ImportSheet.swift`:

```swift
extension ImportSheet.Source: Identifiable {
    var id: String { self == .video ? "video" : "photos" }
}
```

Present it:

```swift
        .sheet(item: $importSource) { source in
            ImportSheet(source: source, model: model, onClose: { importSource = nil })
                .presentationDetents([.medium])
                .interactiveDismissDisabled(model.importProgress != nil || model.isAssemblingNewArrival)
        }
```

and wire the dock on both screens: `onVideo: { importSource = .video }`, `onPhotos: { importSource = .photos }` in the `HomeScreen(...)` and `LibraryScreen(...)` calls.

Finally, dismiss the sheet when the import lands — the new capture becomes Home's capture, and leaving a sheet over it would bury the answer:

```swift
        .onChange(of: model.pendingResult) { _, id in
            guard id != nil else { return }
            importSource = nil
            path.removeAll()
            model.consumePendingResult()
        }
```

(replacing the existing `onChange(of: model.pendingResult)` body from Task 9.)

The alert on `model.importError` in `AppShell` now double-reports: the sheet shows the same message inline. Remove the `.alert("Import failed", ...)` block from `AppShell` — the sheet is where an import failure belongs, and `CaptureCondition` is still the only place the words come from.

- [ ] **Step 3: Build and test**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS.

- [ ] **Step 4: Drive an import by hand**

On a simulator with a screen recording in Photos, tap the dock's film button and pick it. Confirm:

1. Reading shows a **determinate** bar with a percentage.
2. Stitching shows an **indeterminate** one, with copy that says in words that there is no percentage.
3. When it lands, the sheet closes and Home is showing the new capture.
4. Picking a non-scrolling recording surfaces the "Nothing to stitch" sheet rather than an error.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/Features/Import/ImportSheet.swift \
        Seamly/Seamly/AppShell.swift
git commit -m "$(cat <<'EOF'
feat(import): show the two phases as the different things they are

Reading a recording has a real percentage and gets a determinate bar.
Stitching has none — the work is data-dependent and finishes when the
seams are found — so it runs indeterminate and says so in words. A bar
there would be a lie, which is why ProgressNote's value is optional.

This is the first surface to present a distinction CaptureModel has
carried since video import shipped. The import error moves out of a
top-level alert and into the sheet, where the failure actually happened,
still worded by CaptureCondition and still logged raw to Diagnostics.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 18: First run

Nothing may be drawn during a broadcast — a banner would be recorded into the capture. The app owns four seconds before and the moment after, which is the entire reason `CueCard` exists.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/Components/Feedback/CueCard.swift`
- Create: `Seamly/Seamly/DesignSystem/Components/Navigation/PageDots.swift`
- Create: `Seamly/Seamly/Features/Onboarding/FirstRunView.swift`
- Modify: `Seamly/Seamly/AppShell.swift` (present `FirstRunView` instead of `OnboardingView`)
- Modify: `Seamly/SeamlyUITests/SeamlyUITests.swift`, `Seamly/SeamlyUITests/RepairUITests.swift` (the dismissal helper)

**Interfaces:**
- Consumes: tokens (Task 2), `SeamlyButton` (Task 7).
- Produces:
  - `struct CueCard: View` — `init(symbol:when:title:message:)`, `enum CueCard.When { case before, after }`
  - `struct PageDots: View` — `init(count:index:)`
  - `struct FirstRunView: View` — `init(onDone:)`

- [ ] **Step 1: Write `CueCard` and `PageDots`**

Create `Seamly/Seamly/DesignSystem/Components/Feedback/CueCard.swift`:

```swift
import SwiftUI

/// The app's UI during a broadcast is a VIBRATION — nothing may be drawn on screen or it lands
/// in the capture. So the meaning of the buzz has to be taught before the session and explained
/// after it. This component is the only place that happens, which is why it exists at all.
struct CueCard: View {
    enum When { case before, after }

    var symbol: String = "hand.draw"
    var when: When = .before
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: SeamlySpace.s5) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(SeamlyColor.accent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text((when == .before ? "Before you start" : "What that buzz meant").uppercased())
                    .font(SeamlyFont.caps)
                    .seamlyCapsTracking()
                    .foregroundStyle(SeamlyColor.inkFaint)
                Text(title).font(SeamlyFont.headline).foregroundStyle(SeamlyColor.ink)
                Text(message)
                    .font(SeamlyFont.footnote)
                    .foregroundStyle(SeamlyColor.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(SeamlySpace.s5)
        .background(SeamlyColor.paperRaised)
        .overlay {
            RoundedRectangle(cornerRadius: SeamlyRadius.sm, style: .continuous)
                .strokeBorder(SeamlyColor.rule, lineWidth: 1)
        }
        .seamlyCorners(SeamlyRadius.sm)
    }
}
```

Create `Seamly/Seamly/DesignSystem/Components/Navigation/PageDots.swift`:

```swift
import SwiftUI

struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? SeamlyColor.accent : SeamlyColor.ruleStrong)
                    .frame(width: i == index ? 18 : 6, height: 6)
                    .animation(SeamlyMotion.base, value: index)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(index + 1) of \(count)")
    }
}
```

- [ ] **Step 2: Write `FirstRunView`**

Create `Seamly/Seamly/Features/Onboarding/FirstRunView.swift`:

```swift
import SwiftUI

/// The only place the buzz can be taught. Nothing may be drawn during a broadcast, so its
/// meaning has to land before the session starts.
struct FirstRunView: View {
    let onDone: () -> Void

    @State private var page = 0

    private struct Step {
        let symbol: String
        let title: String
        let message: String
    }

    private let steps = [
        Step(symbol: "record.circle",
             title: "Tap Record, pick Seamly",
             message: "Seamly records your screen while you scroll another app. Pick Seamly in the sheet and wait for the countdown."),
        Step(symbol: "hand.draw",
             title: "A buzz means slow down",
             message: "Switch to the app you want and scroll at a steady pace. If you feel a buzz you are outrunning the frame rate — ease up, or scroll back a little."),
        Step(symbol: "checkmark.seal",
             title: "Stop and come back",
             message: "Stop from the red indicator, then return. Your capture is waiting, already stitched, with anything uncertain marked."),
    ]

    private var isLast: Bool { page == steps.count - 1 }

    var body: some View {
        VStack(spacing: SeamlySpace.s7) {
            VStack(spacing: SeamlySpace.s7) {
                CueCard(
                    symbol: steps[page].symbol,
                    title: steps[page].title,
                    message: steps[page].message
                )
                if page == 1 {
                    Text("Seamly cannot show you anything while it records — a banner would be captured along with everything else. The buzz is the only signal it can send.")
                        .font(SeamlyFont.footnote)
                        .foregroundStyle(SeamlyColor.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
            .frame(maxWidth: SeamlySpace.columnMax)

            PageDots(count: steps.count, index: page)

            SeamlyButton(isLast ? "Get Started" : "Next", size: .large) {
                if isLast { onDone() } else { withAnimation(SeamlyMotion.base) { page += 1 } }
            }
            .frame(maxWidth: SeamlySpace.columnMax)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, SeamlySpace.gutterCompact)
        .padding(.vertical, SeamlySpace.s7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeamlyColor.paper)
    }
}
```

- [ ] **Step 3: Present it**

In `AppShell.swift`, replace `OnboardingView()` with:

```swift
        .sheet(isPresented: $showFirstRun) {
            FirstRunView(onDone: { showFirstRun = false })
                .interactiveDismissDisabled(false)
        }
```

- [ ] **Step 4: Update the UI tests' dismissal helper**

`FirstRunView`'s last button reads "Get Started", same as before, and the others read "Next" — so both helpers still work unchanged. Verify by running the suite rather than by reading:

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS. If a helper times out, the button titles diverged — align `FirstRunView`'s to "Next" / "Get Started" rather than changing the tests, since three call sites depend on them.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/Components/Feedback/CueCard.swift \
        Seamly/Seamly/DesignSystem/Components/Navigation/PageDots.swift \
        Seamly/Seamly/Features/Onboarding/FirstRunView.swift \
        Seamly/Seamly/AppShell.swift
git commit -m "$(cat <<'EOF'
feat(onboarding): teach the buzz on three cue cards

Nothing may be drawn during a broadcast — a banner would be recorded into
the capture — so the buzz is the only signal the app can send, and its
meaning has to land before the session starts. That is the entire reason
CueCard exists, and step two says so in as many words.

Three steps rather than four: the old second and third both described
scrolling steadily, and the buzz is the part that needs the room.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 19: Rewrite the UI tests for the new surfaces

The end-to-end gate. `RepairUITests` has been patched twice to keep it green through the rebuild; this is where it is written for the screens that actually exist.

**Files:**
- Modify: `Seamly/SeamlyUITests/RepairUITests.swift`
- Modify: `Seamly/SeamlyUITests/SeamlyUITests.swift`

- [ ] **Step 1: Rewrite `RepairUITests`**

Replace the body of `testLiningUpAJoinClearsTheNotice`, renaming it:

```swift
    /// The end-to-end gate for the repair queue: a seeded, deliberately misaligned capture is
    /// opened from Home's margin marker, its join is dragged, and the answer is committed. The
    /// assertion is that the finding is *gone* — which can only happen if the drag registered,
    /// the manifest was rewritten, and the capture re-composited from it.
    @MainActor
    func testAnsweringAJoinClearsTheFinding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Return-home: the seeded capture IS Home, so its margin marker is on screen. Its
        // number is 1 — the seed has exactly one finding, a flagged join.
        let marker = app.descendants(matching: .any).matching(identifier: "margin-marker-1").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 30), "the seeded capture never appeared, or was not flagged")
        marker.tap()

        let canvas = app.descendants(matching: .any).matching(identifier: "repair-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "the repair queue never loaded the join")

        // Drag the lower half up. The seed stores an offset 60 px past the truth (420 vs a
        // true 360), and dragging up *lowers* dy, so this converges rather than moving further
        // away. The assertion below is about the commit reaching disk, not pixel perfection.
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.2, thenDragTo: to)

        app.buttons["queue-accept"].tap()

        // The marker disappearing proves almost nothing on its own: while the queue's cover is
        // up, Home is not in the accessibility tree at all, so the marker is already absent the
        // moment it was tapped. The hittability gate below does the real work — it waits until
        // Home is genuinely back and interactive (which needs a .ready capture with a proxy),
        // and only then asserts the marker is gone, i.e. that the condition recomputed clean
        // from what was actually written.
        let sheet = app.descendants(matching: .any).matching(identifier: "capture-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 60), "Home never came back")
        XCTAssertTrue(
            waitUntilHittable(sheet, timeout: 60),
            "the capture never became interactive again — the post-commit re-composite did not finish"
        )
        XCTAssertFalse(
            marker.exists,
            "the join is still flagged now that Home is back and interactive — the answer did not reach the manifest"
        )
    }
```

Keep `waitUntilHittable` and `dismissOnboardingIfPresented` exactly as they are.

- [ ] **Step 2: Add a queue-walk test**

Add to `RepairUITests`:

```swift
    /// The queue's shape, not its arithmetic: it opens on the finding that was tapped, counts
    /// its answers, and the manual path is reachable but not the default.
    @MainActor
    func testTheQueueOffersTheManualPathBehindAdjustManually() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        let marker = app.descendants(matching: .any).matching(identifier: "margin-marker-1").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 30))
        marker.tap()

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 20),
                      "the queue never showed its position")
        XCTAssertTrue(app.buttons["queue-accept"].isHittable,
                      "the affirmative answer must be the wide, primary one")
        XCTAssertFalse(app.buttons["Increase Offset"].exists,
                       "the steppers are the advanced path, not the default")

        app.buttons["Adjust manually"].tap()
        XCTAssertTrue(app.buttons["Increase Offset"].waitForExistence(timeout: 5))
    }
```

- [ ] **Step 3: Add a library test**

Add to `SeamlyUITests`:

```swift
    /// Library is reachable from Home and lists the capture Home is showing.
    @MainActor
    func testLibraryListsTheCapture() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        let library = app.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 30), "Home never offered Library")
        library.tap()

        let row = app.descendants(matching: .any).matching(identifier: "library-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the capture is not listed")
        XCTAssertTrue(app.buttons["Record"].isHittable, "the dock must stay on Library")
    }
```

- [ ] **Step 4: Run the whole suite**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Seamly/SeamlyUITests
git commit -m "$(cat <<'EOF'
test(ui): drive the repair queue and the library end to end

The repair gate now opens the queue from Home's margin marker, which is
the design's own entry, and asserts the finding is gone once Home is back
and interactive. The hittability gate is kept and is still the part doing
the work: while the queue's cover is up Home is not in the accessibility
tree, so the marker's absence proves nothing on its own.

Adds a queue-shape test — the affirmative is primary, the steppers are
behind Adjust manually — and a library test that the dock stays docked.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 20: Delete the old shell

Nothing references these any more. They go last so every commit before this one was independently runnable.

**Files:**
- Delete: `Seamly/Seamly/ContentView.swift`, `Seamly/Seamly/DesignSystem/CaptureCanvas.swift`, `Seamly/Seamly/DesignSystem/ConditionNotice.swift`, `Seamly/Seamly/Features/Home/HomeView.swift`, `Seamly/Seamly/Features/Result/ResultView.swift`, `Seamly/Seamly/Features/Result/OutcomeViews.swift`, `Seamly/Seamly/Features/Repair/RepairView.swift`, `Seamly/Seamly/Features/Onboarding/OnboardingView.swift`, `Seamly/Seamly/Features/Capture/PhotoImportButton.swift`, `Seamly/Seamly/Features/Capture/VideoImportButton.swift`

- [ ] **Step 1: Confirm nothing references them**

Run:
```bash
cd /Users/lili/Developer/Seamly
for name in ContentView CaptureCanvas ConditionNotice HomeView ResultView ProcessingView \
            NothingToStitchView CaptureFailureView RepairView OnboardingView \
            PhotoImportButton VideoImportButton; do
  echo "--- $name"
  grep -rn "\b$name\b" Seamly/Seamly Seamly/SeamlyTests Seamly/SeamlyUITests \
    --include='*.swift' | grep -v "Features/Result/OutcomeViews.swift\|Features/Result/ResultView.swift\|Features/Repair/RepairView.swift\|Features/Home/HomeView.swift\|Features/Onboarding/OnboardingView.swift\|DesignSystem/CaptureCanvas.swift\|DesignSystem/ConditionNotice.swift\|ContentView.swift\|PhotoImportButton.swift\|VideoImportButton.swift"
done
```
Expected: no output under any name. Any hit is a live reference — resolve it before deleting.

`PickedMovie` lives in `VideoImportButton.swift` and **is** still used, by `ImportSheet`. Move it first:

```bash
git mv Seamly/Seamly/Features/Capture/VideoImportButton.swift \
       Seamly/Seamly/Features/Import/PickedMovie.swift
```

then delete the `VideoImportButton` struct from that file, leaving only `PickedMovie` and its `import` lines.

- [ ] **Step 2: Delete**

```bash
git rm Seamly/Seamly/ContentView.swift \
       Seamly/Seamly/DesignSystem/CaptureCanvas.swift \
       Seamly/Seamly/DesignSystem/ConditionNotice.swift \
       Seamly/Seamly/Features/Home/HomeView.swift \
       Seamly/Seamly/Features/Result/ResultView.swift \
       Seamly/Seamly/Features/Result/OutcomeViews.swift \
       Seamly/Seamly/Features/Repair/RepairView.swift \
       Seamly/Seamly/Features/Onboarding/OnboardingView.swift \
       Seamly/Seamly/Features/Capture/PhotoImportButton.swift
```

No `.pbxproj` edit is needed: the project uses synchronized folder groups.

- [ ] **Step 3: Build and run everything**

Run:
```bash
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
swift test --package-path Seamly/StitchKit
```
Expected: PASS on both.

- [ ] **Step 4: Commit**

```bash
git add -A Seamly/Seamly Seamly/SeamlyTests Seamly/SeamlyUITests
git commit -m "$(cat <<'EOF'
refactor: delete the one-shot shell

Every screen it held has a replacement built to the design system, and
nothing has referenced these since Task 19. They went last so that each
commit before this one was independently runnable.

PickedMovie moves out of VideoImportButton rather than dying with it —
ImportSheet still needs it to copy a recording out of the Photos sandbox
for AVAssetReader.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 21: The pass a green build cannot do

A green suite here has lied three times. The design has two size classes and two themes, and nothing so far has proven any of them.

**Files:** whichever the pass turns up. Expect small fixes in the component files.

- [ ] **Step 1: Capture every screen in all four combinations**

For each of `iPhone 17` and `iPad Pro 13-inch (M4)`, and each of Light and Dark:

```bash
xcrun simctl boot "iPhone 17"
xcrun simctl ui booted appearance dark      # and: light
xcrun simctl launch booted io.github.lilikazine.Seamly -SeamlySeedMisalignedCapture
xcrun simctl io booted screenshot /tmp/seamly-<device>-<theme>-<screen>.png
```

Screens: Home (with a capture and empty), Library, Review, the repair queue, the export sheet, the import sheet, first run.

- [ ] **Step 2: Check each against the direction**

For every screenshot, confirm:

1. **The sheet is white in dark mode.** If a capture is dimmed at night, `SeamlyColor.sheet` has been made semantic — the single easiest thing to break by accident.
2. **The ground is warm paper**, not iOS grey, and it darkens to a night desk rather than inverting.
3. **Sheets have square corners.** Rounding is for controls only.
4. **Depth is a rule and a lifted edge** — no large blurs, no glass.
5. **Every status carries its word**, never colour alone.
6. **Every number is thin-space grouped and tabular** — `884 × 15 402 px`, never a comma.
7. **The margin marker sits on its rule** at every zoom, in both size classes.
8. **Nothing is `.tracking()`ed except display sizes and caps labels.**

- [ ] **Step 3: Run the Dynamic Type extremes**

```bash
xcrun simctl ui booted content_size extra-small
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
```

Confirm on each screen: nothing clips, nothing truncates a word mid-glyph, the dock's three controls stay reachable, and the queue's affirmative button stays wider than its nudge chevrons. Body copy must **grow**; the caps labels and mono measurements may stay put.

Fix by letting text wrap and containers grow — never by shrinking a font or capping a text style.

- [ ] **Step 4: Rotate**

On iPhone, rotate each screen to landscape. Confirm the position scale moves below the sheet (`SeamlyLayout.isShort`) rather than eating the height, and that the queue's prompt does not push the capture off screen.

- [ ] **Step 5: Check contrast on anything that was changed**

If any colour was adjusted during this pass, re-measure it against its ground rather than eyeballing it. Every token clears 4.5:1; `design-system/tokens/colors.css` records the intended values and `design-system/guidelines/palette.card.html` records the reasoning.

- [ ] **Step 6: Commit the fixes**

```bash
git add -A Seamly/Seamly
git commit -m "$(cat <<'EOF'
fix(design): the pass a green build cannot do

Every screen driven in both size classes, both themes, and both Dynamic
Type extremes, and looked at. A green suite here has lied three times, and
none of the four combinations was proven by anything before this.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: Reconcile the documentation**

`CLAUDE.md`'s Status section says the design governs and **the code has not moved yet**. It has now. Update that section, and the "Key locations" list, to describe what ships:

- Home is the most recent capture, Library lists them, Review is the capture at length with a rail at regular width, and repair is a queue.
- `Features/` gains `Library/` and `Import/`; `DesignSystem/` gains `Tokens/`, `Components/`, `CaptureGeometry`, `CaptureView`, `CaptureFinding`.
- `CaptureCanvas`, `ConditionNotice`, `EditView`-era views and `RepairView` are gone.
- The gotcha about `.frame(w,h).clipped()` needing `.contentShape(Rectangle())` still applies, now to `CaptureThumbnail`.

Add a decision log at `docs/logs/2026-08-20-paper-interface.md` recording, at minimum: the `Compositor.placement` extraction and why a third copy of the layout rule was refused; the viewport-pinned overlay and the texture-ceiling bug it retired; the repair ground going from black to paper; and the loss of the interactive swipe-back with the custom nav bar.

```bash
git add CLAUDE.md docs/logs/2026-08-20-paper-interface.md
git commit -m "$(cat <<'EOF'
docs: reconcile CLAUDE.md with the shipped Paper interface

Status said the design governs and the code had not moved. It has.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```
