# The Paper Interface — Design (Spec 3)

**Date:** 2026-08-20
**Status:** Approved, not yet implemented.

Rebuild Seamly's SwiftUI interface to `design-system/`. The design system is the source of
truth; where it disagrees with shipped UI, the design is the intent and the code is history
(`CLAUDE.md`, "Design"). `CLAUDE.md`'s Status section already records that the design governs
and that **the code has not moved yet**. This spec is that move.

## Summary

Six screens, rebuilt on the design's tokens and components:

| Screen | What it is |
|---|---|
| **Home** | The most recent capture, resolved, with its marks already visible. Return-home IA. |
| **Library** | Every capture. Ruled list at compact width, 3:5 grid at regular. |
| **Review** | The capture at length. Persistent findings rail at regular width. |
| **Repair queue** | One problem at a time, zoomed, one question, one wide affirmative answer. |
| **Sheets** | Export, Import, First run. |
| *(Diagnostics)* | Unchanged; moves behind Library's overflow. |

The engine does not change except for one additive, read-only accessor (§2). `StitchKit`,
`StitchAssembler`, `CaptureModel`, `MediaImporter`, `CaptureCondition`, `ZoomState`,
`RepairableJoins`, `JoinAlignment`, `Diagnostics` and `Exporter` are all kept.

## The concept this serves

> A capture knows its own weak points, and can walk you through them.

A Seamly capture is assembled from evidence the user produced by scrolling, so its
trustworthiness **varies along its length**. The engine makes a long screenshot; the product
makes one you can trust, by making its doubts legible and answerable.

**Direction: Paper.** The capture is a white sheet lying on a warm light desk. Square corners,
depth from rules rather than shadow.

**The load-bearing rule.** On a light ground a thin rule over white captured content is easy to
miss, so the mark on the sheet stays quiet and **findability lives in the margin**, where the
ground is always paper and contrast is guaranteed whatever was captured. Break that and the
direction stops working. §3 is the whole answer to it, and is built and proven before anything
else stands on it.

## Decisions settled before this spec

Not reopened here.

| Decision | Choice |
|---|---|
| Authority | The design governs. `2026-08-17-guided-repair-design.md`'s ban on per-seam controls and on pipeline vocabulary is **reversed**. |
| The manual path | A narrow secondary affordance reached from the queue. **Not** a return of `EditView`, which was a test harness rather than a design. |
| Colour | Contrast-solved, not chosen by eye. Every token clears 4.5:1 against its ground. Changing one means re-measuring it. |
| `SeamlyColor.sheet` | Fixed white in **both** themes. A capture has its own brightness and must never be dimmed. Not a semantic background. |
| Size classes | `horizontalSizeClass` / `verticalSizeClass`. The CSS breakpoints are a web stand-in and are **not** ported. |
| Type | Apple's pt ladder, identical on iPhone and iPad. Nothing hard-codes a body size. |

## Decisions taken for this spec

Asked and answered at design time:

| Question | Choice | Why |
|---|---|---|
| Where composite positions come from | **Expose from StitchKit** (§2) | `JoinAlignment` already re-derives `Compositor.plan`'s rule once and pays for it with a test. A second copy is worse than one additive accessor. |
| Bars-uncertain repair | **Implement it** (§6) | The manifest supports it (`setChromeOverride`). Without it the queue has a kind of finding it cannot answer, and the design's queue is partly decorative. |
| Gaps in the queue | **Acknowledge and advance** (§6) | The app cannot recapture a stretch. The gap keeps its number, its marker and its jump; it simply has no lever. |
| Diagnostics | **Library's nav-bar overflow** | Library is the "everything else" screen. Home and Review stay composed; it stays two taps away. |

---

## 1. Tokens

`design-system/swiftui/SeamlyTokens.swift` ports into `Seamly/Seamly/DesignSystem/Tokens/`,
with `nonisolated` on `SeamlyColor`, `SeamlyFont`, `SeamlySpace`, `SeamlyRadius`,
`SeamlyLayout` and `SeamlyNumber` (this target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
MainActor`), and `public` dropped.

**Colours stay in code, not an asset catalog.** FEASIBILITY suggests a catalog for production;
the trade here runs the other way. One Swift file diffs 1:1 against `tokens/colors.css`, so
re-solving a token for contrast is a one-line change a reviewer can check against the CSS. A
catalog would scatter the same values across plist blobs.

### The three things that do not port

Each is a mistake FEASIBILITY names, and each gets a helper so the mistake is unavailable:

- **Line height.** CSS `1.4` is a multiplier; `.lineSpacing()` is additive points. A helper
  `seamlyLeading(_ multiplier: CGFloat, for style: UIFont.TextStyle)` computes
  `(multiplier − 1) × UIFont.preferredFont(forTextStyle: style).pointSize`, so it stays correct
  as Dynamic Type scales. **Never port the number.**
- **Tracking.** `.tracking()` is absolute points and does not scale. Confined to
  `seamlyDisplayTracking()` and `seamlyCapsTracking()`, applied to largeTitle, title3 and caps
  only. **Never on body copy.**
- **`--measure: 38ch`.** There is no `ch` unit and no honest point conversion. Explainer copy
  uses `.fixedSize(horizontal: false, vertical: true)` inside a column already capped at
  `SeamlySpace.columnMax`, and the column does the work. **No magic number.**

### Tokens the port is missing

Added, from `tokens/*.css`: `accentWash`, `protectBottom`, `seamWidth` (1) / `seamWidthMark`
(1.5), `liftCard`, `liftModal`, `insetWell`, `disabledOpacity` (0.38), and motion —
`durPress` 120 ms, `durBase` 220 ms, `durJump` 420 ms, `durStitching` 1100 ms, with
`easeStandard` = `timingCurve(0.32, 0.72, 0, 1)` and `easeOut` = `timingCurve(0.22, 1, 0.36, 1)`.

`durJump` at `easeOut` is the one that matters: it is the pan that jumps to a mark.

### Icons

No `Icon` component is ported. The kit inlines SVG paths only because the web has no SF Pro
symbols; every name it uses is a real SF Symbol. On iOS this is `Image(systemName:)`.

---

## 2. `Compositor.placement` — positions, from one place

A margin marker sits at a fraction of the **composite's** height. That number is the cumulative
cursor in `Compositor.plan`, which is private.

`JoinAlignment` already faced this and chose to re-derive the rule in the app, paying for it
with `JoinAlignmentTests` asserting against a real composite. Doing that a second time would
put the layout rule in three places. Instead, additively, in `StitchKit`:

```swift
public struct Placement: Sendable {
    /// One laid-out strip. `keyframeIndex == nil` is a segment separator band.
    public struct Span: Sendable, Equatable {
        public let keyframeIndex: Int?
        public let destY: Int
        public let height: Int
    }
    public let spans: [Span]
    public let totalHeight: Int

    /// Where the lower frame of a join starts in the composite.
    public func destY(forJoin joinIndex: Int) -> Int?
    /// Where the separator band after a keyframe starts.
    public func destY(forBreakAfter keyframeIndex: Int) -> Int?
}

extension Compositor {
    public func placement(_ session: StitchSession) -> Placement
}
```

`plan` needs `images` only to read `width`; `placement` takes it from
`keyframes.first?.pixelWidth`. The segment walk is extracted into one private function that
both `plan` and `placement` call, so there is no second copy to drift. No images are loaded,
so this is cheap enough to compute on the main actor when a capture's session changes.

**Gate:** `PlacementTests` asserts `placement(s).totalHeight == StitchAssembler.composite(s).height`
and that every span boundary matches, on a synthetic multi-segment session and on a
`RealDevice` fixture. If those disagree the accessor is wrong and everything downstream of it
is drawing marks in the wrong place.

This does not change behaviour, the manifest schema, or any existing call.

---

## 3. The coordinate space

**This is the load-bearing part, and it is built and proven before anything else stands on it.**

The kit positions a mark at `atPct * zoom - top`, in units of the sheet's own height. That is
correct for a mock where the sheet crops the image; it is not the arithmetic a real 1:40
capture needs. The real rule, in one pure function:

```swift
nonisolated struct CaptureGeometry: Equatable {
    let sheetWidth: CGFloat
    let viewportHeight: CGFloat
    let captureAspect: CGFloat      // captureHeight / captureWidth
    let zoom: CGFloat
    let scrollY: CGFloat

    /// zoom == 1 means "fill the sheet's width at natural aspect and scroll down" —
    /// not "shrink 15 000 px until it fits", at which size nothing is legible.
    var contentHeight: CGFloat { sheetWidth * zoom * captureAspect }

    func y(atPct: Double) -> CGFloat { CGFloat(atPct) * contentHeight - scrollY }
    func isVisible(_ y: CGFloat, slack: CGFloat = 24) -> Bool
    var viewportTopPct: Double
    var viewportPct: Double
    /// The scrollY that puts `atPct` `fraction` of the way down the viewport.
    func scrollY(toShow atPct: Double, at fraction: CGFloat) -> CGFloat
}
```

### Why nothing can drift

`CaptureView` is a `GeometryReader` over
`HStack(spacing: s3) { marginRail(34) · sheet · positionScale(16) }`.

The sheet is a `ScrollView` whose **content is a bare `Color.clear` spacer** of
`contentHeight` — no raster, so a 40 000 pt extent costs nothing. The image and the `SeamMark`s
live in an `.overlay` pinned to the *viewport*, offset by `−scrollY`.

So the image, the seam marks on the sheet, the margin markers and the scale bracket are all
drawn in the same outer `GeometryReader` space, from the same single `scrollY`. There is one
term and one space; there is nothing for them to drift *relative to*.

`scrollY` comes from `.onScrollGeometryChange(for: CGFloat.self)`. Jump-to-mark is a
`ScrollPosition` `scrollTo(y:)` inside `withAnimation(SeamlyMotion.jump)`.

### A bug this retires

`CaptureCanvas` today binds a 4096 px-tall proxy into scroll content up to 6× that, which
exceeds the ~16 384 px GPU texture ceiling `CLAUDE.md` warns about. The viewport-pinned overlay
never renders a texture larger than the screen.

### Two content sources

```swift
enum CaptureSheetContent {
    case proxy(CGImage)
    case join(upper: CGImage, lower: CGImage, alignment: JoinAlignment)
}
```

The proxy is only rebuilt after a commit, so a repair drag against it would move nothing
visible. A seam finding therefore draws the **live full-resolution pair**, windowed exactly as
`RepairView.halves` does today — `.interpolation(.none)` included, for the reason its doc
comment gives: at 6× a source row is six points tall, and smoothing would have the user
dragging against rows the export does not contain. Everything else — the margin rail, the
scale, the marks describing the whole capture — is shared.

This is a detail the static kit could not have known. It is the design's `CaptureView`, with
the one substitution the interaction actually requires.

### Short viewports

`SeamlyLayout.isShort` (landscape iPhone) moves the position scale horizontal, under the sheet.

---

## 4. Findings

`CaptureCondition.swift` gains a per-item layer. Same file, deliberately: it remains the only
place pipeline facts become English, and the design has licensed the pipeline's own words on
screen.

```swift
nonisolated struct Finding: Identifiable, Equatable {
    /// Declaration order is the ranking. Mirrors `Imperfection.Kind`: missing content
    /// outranks uncertain bars outranks an uncertain join.
    enum Kind: Int, Comparable { case gap, bars, seam }

    enum Target: Equatable {
        case join(Int)
        case gap(afterKeyframeIndex: Int)
        case chrome(keyframeID: UUID, edges: Set<ChromeEdge>)
    }

    let n: Int                  // the number the margin marker shows
    let kind: Kind
    let atPct: Double
    let target: Target
    let title: String           // "Gap after frame 4"
    let question: String        // "Does this line up?"
    let detail: String
    let dy: Int?                // nil for a gap
    let confidence: Double?
}

nonisolated enum CaptureFindings {
    static func all(in session: StitchSession, placement: Placement) -> [Finding]
}

nonisolated enum CaptureMarks {
    /// Every join, confident ones included and unnumbered — a good capture must look
    /// like one image, and only doubt draws attention.
    static func all(in session: StitchSession, placement: Placement) -> [Mark]
}
```

**Sources.** `gap` ← each `SegmentBreak`. `seam` ← each `Seam` where `isLowConfidence`.
`bars` ← each keyframe with a non-empty `chromeEdgesNeedingReview`.

**Numbering.** Sorted by kind rank, then by `atPct`, then numbered 1…n. This is why the kit's
own sample data numbers gaps 1–3 before flagged 4–5, and it reuses `Imperfection.Kind`'s
existing ranking rather than inventing a second, contradictory one.

**A gap's label is "lost lock", not "N px lost".** The engine cannot know how much was never
revealed — that is what a break *is*. The kit's data says the same thing. Stating a pixel count
here would be inventing a number, which the voice rules forbid twice over.

`CaptureFacts`, `Imperfection` and `CaptureCondition` are untouched and keep
`CaptureConditionTests`. They still own `offersLiningUp`, `recommendsRecordingAgain`,
`message(for:)`, and the wording for `endedEarly`, `orderAssumed` and `failed` — none of which
has a per-finding equivalent.

**Accepted loss:** some `Imperfection` headlines stop appearing on screen. The design replaced
aggregate prose ("2 joins might be slightly off") with per-finding questions ("Does this line
up?"). That is the design winning, as settled.

---

## 5. Information architecture

`NavigationStack(path:)` over `enum Route { case library, review(UUID) }`. **Home is the root.**

### Home — return home

The app is backgrounded while the user scrolls another app, so its most common launch context
is *"I just stopped a broadcast — what did I get?"* Home answers that before anything else.

NavBar("Seamly", trailing: Library · How it works) · title + `884 × 15 402 px` in mono ·
`CaptureView` of the newest capture with marks live · a status row of `StatusNote`s and
"Review them →" · `CaptureDock`, permanently present.

Tapping a margin marker on Home opens the queue at that finding — the kit's `onRepair(n)`.
This deliberately differs from Review, where the same tap *jumps* rather than transitioning
(§5, Review): Home is a glance and the marker is the way in; Review is where you are already
looking, and a screen change there would throw away the place you had.

Empty: `EmptyState("Nothing captured yet")` with the dock still docked, so the empty state is
capture-first for free.

### `pendingResult` under return-home

`CaptureModel.pendingResult` currently pushes a result screen. Under return-home it **pops to
Home**, because Home now *is* the answer. It still fires on failure, per `DECISIONS.md [B4]` —
a capture that fails silently is the bug that shipped once already. `consumePendingResult()`
is still called immediately, for the reason its doc comment gives.

### Library

Large NavBar("Library", "N captures", back, trailing: Capture · overflow → **Diagnostics**).

- Compact: `CaptureListRow`s, ruled not carded, plus the two `ImportRow`s under "Or start from
  something you already have".
- Regular: `LazyVGrid(.adaptive(minimum: 190))` of 3:5 `CaptureGridCard`s. Never square, never
  sized by capture length — length is told by the ribbon and the number.

Dock stays. Delete via `.swipeActions` on a row and `.contextMenu` on a card.

### Review

- Compact: capture owns the column; findings summary and actions sit beneath it. Tapping a
  margin marker jumps — never a screen transition.
- Regular: a persistent 340 pt `paperRaised` rail — "N to look at", the finding lines, and a
  Repair / Export footer — so the list stays visible while panning 15 000 px.

`jump(n)` is one function for both marker taps and rail taps: select, zoom to 3, and
`scrollY(toShow: atPct, at: 0.4)` under `SeamlyMotion.jump`.

---

## 6. The repair queue

A full-screen cover. NavBar("Repair", "k of N answered", trailing ✕) · `CaptureView` zoomed to
the finding with `showScale: false` · `QueuePrompt`.

The user never hunts a 15 000 px image. Most flagged seams turn out fine, so the affirmative
answer is the wide primary button and the common case is one tap.

### Three answer shapes

| Kind | Question | Answer |
|---|---|---|
| **seam** | "Does this line up?" | Nudge ± · wide **Looks right** · `dy` readout. *Adjust manually* reveals the offset `StepperRow`. Drag on the sheet is the primary gesture. |
| **bars** | "Where do the bars end?" | *Adjust manually* reveals Top bar / Bottom bar `StepperRow`s writing `setChromeOverride`. |
| **gap** | "Recapture this stretch?" → answered as **Got it** | No nudges (`value == nil`), no lever. Keeps its number, marker and jump. |

"Skip all" exits the queue without committing further answers.

### Seam findings

`JoinAlignment`, `ZoomState`, `RepairableJoins` and today's drag arithmetic all survive intact.
What changes is the surround, not the interaction. On commit, a seam's `provisionalDy` is
written and `isLowConfidence` cleared — the user has now looked at it with their own eyes, and
leaving it flagged would re-raise a finding over a join they just answered.

### Bars findings

New function. `session.setChromeOverride(value, for: edge, keyframeID:)` already clamps against
the combined-crop ceiling the compositor enforces.

**A chrome change moves every position below it**, because `Compositor.plan` places each frame
from the previous frame's content bottom.

The queue holds every pending answer in memory and commits **once**, when it finishes or when
it is closed with answers outstanding, through `CaptureModel.update(_:)` — the same path
`RepairView.commit()` uses today, with the same failure handling: log the raw error, show
`CaptureCondition.message(for:)`, stay on screen so Done can be retried, never dismiss as
though a repair saved when it did not. `Placement` and the findings are re-derived from the
committed manifest afterwards.

So **within one queue session, findings below a pending chrome answer sit at slightly stale
positions.** This is accepted rather than corrected: a margin marker is a locator, not a
measurement, and the alternative — re-deriving mid-session — would renumber the queue under
the user while they are walking it, which is worse than a marker being a few percent off. It
also avoids a full re-composite (seconds on a long capture) between two questions.

### The ground becomes paper

Today's repair canvas is deliberately black — a neutral, non-reflective surround for judging
alignment. The design puts a white sheet on a paper ground, and the sheet is white in both
themes, so the content itself is never dimmed. **The design wins.** This is a real reversal of
a considered decision and is recorded as one, not left to look like an oversight.

The consequence: `RepairView`'s `.toolbarColorScheme(.dark, for: .navigationBar)` and its
forced `.environment(\.colorScheme, .dark)` go away with the black ground. The custom NavBar
(§7) draws on paper and needs neither.

---

## 7. Navigation chrome

The design's `NavBar` carries a mono tabular subtitle, a `large` variant, and a paper ground
with a rule. A system navigation bar cannot express that. So the system bar is hidden and
`NavBar` is a custom view.

**Cost:** hiding the system bar disables the interactive swipe-back gesture. Only two pushes
exist (Home → Library → Review) and both screens carry a visible back control. Accepted, and
recorded here so it is a decision rather than a regression someone finds later.

Over a capture, chrome sits on the **protection gradient**, never a flat scrim — a proxy can be
any brightness and a scrim dims what the user is reading (`seamlyProtectTop`).

---

## 8. Sheets

**Export.** Dimensions line (`884 × 15 402 px`, plus "N unanswered" when findings remain),
then Image — Save to Photos · Share PNG · Copy to Clipboard — and Document — Export PDF.
Grouped that way because image-vs-document is the decision the user is actually making. Straight
onto the existing `Exporter`, `model.fullComposite` and `model.exportPDF`; no export behaviour
changes.

**Import.** The one flow with two genuinely different kinds of progress, and the first surface
to present the distinction `CaptureModel` was built for:

- *reading* — `model.importProgress`, a real percentage, determinate `ProgressNote`.
- *stitching* — `model.isAssemblingNewArrival`, **no percentage exists**; the work is
  data-dependent and finishes when the seams are found. Indeterminate, and it says so in words.
  A bar here would be a lie.

Errors come from `model.importError` (already `CaptureCondition.message(for:)`-mapped), read
non-accusatorially, with Cancel / Try again.

**First run.** Three `CueCard` steps + `PageDots` + Button, replacing `OnboardingView`'s
four-step `TabView`. Step 2 carries the buzz explainer: nothing may be drawn during a broadcast
— a banner would be captured along with everything else — so the buzz is the only signal the
app can send, and its meaning has to land before the session starts.

---

## 9. States the design does not cover

Named explicitly, with the default taken:

| State | Decision |
|---|---|
| **Failed capture** | The capture slot shows `StatusNote(kind: .failed)` over an empty sheet, with `CaptureCondition.message(for:)`'s sentence and *Record again*. Never a raw error. |
| **Nothing to stitch** | `EmptyState` inside a `Sheet`, same `lastPickupWasEmpty` trigger and same `consumeLastPickupWasEmpty()` discipline. |
| **Processing** | The capture slot shows a `ProgressNote`. The Import sheet covers the import path. |
| **Permissions** | Unchanged. Photos add-only at export (`Exporter.ExportError.photosDenied`); the broadcast picker is the system's. |
| **Pre-flight countdown** | None is ours — ReplayKit owns it. First run step 1 names it; the app adds nothing. |
| **Diagnostics** | Unchanged view, behind Library's overflow. It stays because the extension cannot draw UI and its container is not reliably pullable over USB. |

---

## 10. File plan

**New**

```
DesignSystem/Tokens/SeamlyTokens.swift
DesignSystem/CaptureGeometry.swift
DesignSystem/CaptureView.swift
DesignSystem/Components/Actions/{SeamlyButton,IconButton}.swift
DesignSystem/Components/Capture/{CaptureDock,ImportRow}.swift
DesignSystem/Components/Data/{CaptureSheetView,CaptureListRow,CaptureGridCard,StatusNote}.swift
DesignSystem/Components/Marks/{SeamMark,MarginMarker,PositionScale}.swift
DesignSystem/Components/Repair/{QueuePrompt,StepperRow}.swift
DesignSystem/Components/Feedback/{CueCard,EmptyState,ProgressNote}.swift
DesignSystem/Components/Navigation/{NavBar,SheetChrome,PageDots}.swift
Features/Home/HomeScreen.swift
Features/Library/LibraryScreen.swift
Features/Result/ReviewScreen.swift
Features/Repair/RepairQueueView.swift
Features/Export/ExportSheet.swift
Features/Import/ImportSheet.swift
Features/Onboarding/FirstRunView.swift
```

**Modified** — `CaptureCondition.swift` (adds `Finding`, `CaptureFindings`, `CaptureMarks`),
`SeamlyApp.swift` (root shell), `StitchKit/Compositor.swift` (adds `Placement`).

**Deleted, at the end** — `CaptureCanvas.swift`, `ConditionNotice.swift`, `HomeView.swift`,
`ResultView.swift`, `OutcomeViews.swift`, `RepairView.swift`, `OnboardingView.swift`,
`ContentView.swift`.

Target membership follows the folder — the project uses synchronized folder groups, so no
`.pbxproj` edit is needed for any of this.

---

## 11. Testing

**New**

- `PlacementTests` (StitchKit, Swift Testing) — `totalHeight` and every span boundary against a
  real composite, on a synthetic multi-segment session and a `RealDevice` fixture. This is the
  gate on §2; if it fails, every mark on screen is in the wrong place.
- `CaptureGeometryTests` — `y(atPct:)`, visibility, `viewportTopPct`, `scrollY(toShow:at:)`.
  Pure, so the load-bearing arithmetic is tested without a view.
- `CaptureFindingsTests` — kinds, ordering, numbering, and that a bars finding names the right
  keyframe and edges. Table-driven over hand-built sessions.

**Kept unchanged** — `CaptureConditionTests`, `JoinAlignmentTests`, `RepairableJoinsTests`,
`ZoomStateTests`, `CaptureModelRegressionTests`, and every import/assembly suite.

**Rewritten**

- `RepairUITests` — drives the queue end to end off `-SeamlySeedMisalignedCapture`: the seeded
  capture appears on Home with a flagged marker, the queue opens on it, the drag registers,
  *Looks right* commits, and the finding count clears once Home is interactive again. The
  existing test's hittability-gated re-assertion is kept — it is the part doing the real work,
  for the reason its comment gives.
- `SeamlyUITests.testHomeShowsRecordFirst` — moves to the dock and the empty state.

**Visual.** A green suite here has lied three times. The design has two size classes and two
themes and a green build proves none of them, so each screen is captured on the simulator in
compact and regular, light and night desk, and looked at. `stitch-cli` is unaffected.

---

## 12. Order of work

Hardest first, so the risky part fails early.

1. `Compositor.placement` + `PlacementTests`.
2. Tokens into the app target; compile gate under Swift 6.
3. `CaptureGeometry`, `CaptureFindings`, `CaptureMarks` + their tests.
4. Marks components + `CaptureView`, both content sources — **proven on the simulator before
   anything else is built on it.**
5. Review, both size classes.
6. Repair queue: three answer shapes, chrome writes, commit path.
7. Home.
8. Library.
9. Export / Import / First run.
10. Component polish, UI tests, dark theme and Dynamic Type pass. Delete the old views.

## Out of scope

- Partial recapture of a gap. The app has no such capability; §6 says so on screen.
- Trim (`topTrim` / `bottomTrim`). The manifest carries it and nothing in the design surfaces
  it. Unchanged, unexposed.
- Any change to stitching, matching, chrome detection, order recovery or export encoding.
- The `withKnownIssue` dense live-frame oracle. Untouched — it needs a real capture, not a UI.
