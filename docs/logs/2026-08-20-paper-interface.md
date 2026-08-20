# 2026-08-20: The Paper interface

**Status:** Implemented

## Context

`design-system/` has been the design source of truth since it merged, and `CLAUDE.md`'s Status
section said so in the same breath as admitting that **the code had not moved yet**. This is
that move: 21 tasks rebuilding the SwiftUI shell against the design, spec'd in
`docs/superpowers/specs/2026-08-20-paper-interface-design.md` and planned in
`docs/superpowers/plans/2026-08-20-paper-interface.md`.

The engine is untouched. `StitchKit` gained exactly one additive public type (below) and no
behaviour change; `CaptureModel`, `StitchAssembler`, `MediaImporter`, `JoinAlignment`,
`RepairableJoins` and `Diagnostics` were kept as they were. What changed is every screen.

The shipped shape: Home opens on the most recent capture (return-home), Library lists them all
and grids them at regular width, Review is the capture at length, and repair is a **queue** that
walks the user through the capture's own problems one question at a time.

## Decisions

### 1. `Compositor.placement` — refusing a third copy of the layout rule

A margin marker sits at a fraction of the *composite's* height. That number is the cumulative
cursor inside `Compositor.plan`, which was private.

`JoinAlignment` had already hit this wall and answered it by re-deriving the segment walk in the
app, paying for the duplication with `JoinAlignmentTests` asserting against a real composite.
Doing that again would have put one layout rule in **three** places, with two of the copies
outside the module that owns it.

Instead `Compositor` publishes what it already computes:

```swift
public struct Placement: Sendable {
    public struct Span: Sendable, Equatable {
        public let keyframeIndex: Int?   // nil == a segment separator band
        public let destY: Int
        public let height: Int
    }
    public let spans: [Span]
    public let totalHeight: Int
    public func destY(forJoin joinIndex: Int) -> Int?        // nil across a break
    public func destY(forBreakAfter keyframeIndex: Int) -> Int?
}
```

The segment walk was extracted into one private `layoutSpans(_:dyByFrom:)` that **both** `plan`
and the new `placement(_:)` call, so there is no second copy inside `StitchKit` either.
`placement` needs no images — `plan` only ever used them to read `width`, which comes from
`keyframes.first?.pixelWidth` — so it is cheap enough to compute on the main actor whenever a
capture's session changes.

`PlacementTests` is the gate: `placement(s).totalHeight` must equal
`StitchAssembler.composite(s).height`, and every span boundary must match, on a synthetic
multi-segment session and on a `RealDevice` fixture. If those ever disagree, every mark in the
app is being drawn in the wrong place.

One incidental fix came with it: `offsets()` now merges with `uniquingKeysWith:` instead of
trapping on a duplicated seam.

### 2. One coordinate space, and the texture ceiling it retired

**This was built and proven before anything was allowed to stand on it**, because a mark in the
margin that does not line up with the mark on the sheet destroys the whole direction.

`CaptureGeometry` is the single pure function:

```swift
var contentHeight: CGFloat { sheetWidth * zoom * captureAspect }
func y(atPct: Double) -> CGFloat { CGFloat(atPct) * contentHeight - scrollY }
```

`zoom == 1` means "fill the sheet's width at natural aspect and scroll" — *not* "shrink 15 000 px
until it fits", at which size nothing is legible. The design kit's own arithmetic
(`atPct * zoom - top`) is correct for a mock where the sheet crops a small image and wrong for a
real 1:40 capture; this is the substitution reality required.

`CaptureView` is one `GeometryReader` over
`HStack { marginRail(34) · sheet · positionScale(16) }`. The sheet is a `ScrollView` whose
content is a bare `Color.clear` spacer of `contentHeight` — **no raster** — with the image and
the marks in an `.overlay` pinned to the *viewport* and offset by `−scrollY`. The image, the
seam marks on the sheet, the margin markers and the scale bracket therefore all resolve in the
same space from the same single `scrollY`. There is nothing for them to drift relative to.

**The bug this retires:** `CaptureCanvas` bound a 4096 px-tall proxy into scroll content up to
6× that, which exceeds the ~16 384 px GPU texture ceiling `CLAUDE.md` warns about. A
viewport-pinned overlay never renders a texture larger than the screen.

Two traps cost a fix round each and are worth naming, because both were silent:

- The overlay must be `.overlay(alignment: .topLeading)`. At the default `.center` every mark
  is displaced by half the difference between viewport and content height — which looks
  plausible on a short capture and absurd on a long one.
- `.clipped()` affects painting only. The repair canvas's accessibility and hit-test frame was
  the *union of two unclipped images*, so a drag aimed at the join landed nowhere. Fixed with
  `.accessibilityElement(children: .ignore)`, and it is the same class of bug as the
  `CaptureThumbnail` gotcha already in `CLAUDE.md`.

### 3. The repair ground goes from black to paper — a deliberate reversal

Guided repair drew its join on a **black** canvas, and that was a considered choice: black is
the honest ground for judging whether two halves line up, because it adds no light of its own.

This reverses it. The design puts a white sheet on a paper ground and holds that everywhere, and
a capture that dims at night is the single easiest way to break the direction by accident. The
compensation is that `SeamlyColor.sheet` is **fixed white in both themes** — the captured content
is never dimmed, in either appearance — and the queue opens hard at 6× so the join fills the
stage rather than floating in a field of ground colour.

`SeamlyColor.seamConfident` is fixed ink for the same reason: a mark drawn *on* captured content
cannot be theme-varying, because the content underneath it is not.

### 4. Repair is a queue, and the manual path is narrow

`docs/superpowers/specs/2026-08-17-guided-repair-design.md` rejected per-seam and per-bar
numeric controls and kept "seam", "chrome", "confidence", "offset" and "segment" off the screen
entirely. **That prohibition is reversed** — the design puts the pipeline's own words on screen
(`UNCERTAIN SEAM`, `dy +420 px`), and the capture enumerates its own problems rather than making
the user hunt a 15 000 px image.

What survives the reversal: the manual path is a narrow secondary affordance behind *Adjust
manually*, reached from the queue. It is **not** a return of `EditView`, which was a test harness
rather than a design.

Two engine facts were established while building it, both the hard way:

- A chrome crop on an interior keyframe is **height-invariant**. The compositor's overlap math
  cancels a modest crop exactly, so the composite's total height does not move until the crop is
  large enough to push `sourceStart` past its clamp. A test asserting "the height changed" has to
  cross that point deliberately.
- "No bars here" must answer **only the edge actually in doubt**. A finding's `edges` can name
  one edge while the other already carries a confident automatic measurement, and a blanket zero
  on both un-crops a bar the pipeline had measured correctly — the precise regression the feature
  exists to prevent.

### 5. The interactive swipe-back is gone

The design's `NavBar` is a custom view, not a `UINavigationBar`. Using it means the app no longer
gets UIKit's interactive pop gesture: **back is the button, and only the button.**

This is a real loss and was accepted with open eyes at design time rather than discovered. It is
recorded here so nobody "fixes" it later by reintroducing a system navigation bar, which would
take the design's typography, spacing and paper ground with it.

## What the visual pass found

A green suite has lied three times in this repo, so every screen was driven in both size classes,
both themes and both Dynamic Type extremes, and **looked at** — via a throwaway XCUITest harness
that walked the app and attached a screenshot per screen. The harness was deleted afterwards; it
was a capture device, not a gate.

It found five defects, none of which any assertion in this repo would have caught:

1. **"1 captures"** (Library) and **"1 frames"** (Review) — naive interpolation, correct for
   every value except the one a new user sees first. Both now go through
   `SeamlyNumber.counted(_:_:_:)`, which keeps the thin-space grouping too.
2. **`NavBar`'s back button had no accessibility label.** `backLabel` is empty on every compact
   screen, so VoiceOver got a bare SF Symbol and nothing to say. The design kit has the same
   gap because it is a web mock; supplying the spoken name is the port's job, not the mock's.
3. **First run was a dead end at `accessibility-extra-extra-extra-large`.** Step 2's card — the
   buzz explainer, the longest copy in the app — grew past the screen and pushed *Next* to
   y = 1 061 pt on an ~874 pt screen, beyond even VoiceOver's scroll-to-visible. The user who
   most needs that explanation was the one who could not get past it. The card area is now a
   `ScrollView` whose content carries `minHeight: proxy.size.height, alignment: .center`, so it
   still centres whenever it fits and the ordinary appearance is unchanged.
4. **`CueCard` elided its own caps label and title** — "BEFORE YO…", "Tap Reco…". Only `message`
   had `fixedSize`. A card that exists to teach something must not truncate the thing it teaches.
5. **`StatusNote` had a fixed height**, so at accessibility sizes it elided its own word —
   "1 fla…" — and a note whose whole point is to carry state *in words rather than in colour*
   had nothing left to carry it with. Now a minimum height plus padding: identical at default
   sizes, growing beyond them. Home's summary row became a `ViewThatFits` for the same reason;
   side by side while they fit, stacked when they do not.

Every fix is the brief's prescribed kind — letting text wrap and containers grow — and not one
shrinks a font or caps a text style.

Two things the pass *confirmed* rather than fixed. The load-bearing rule holds in shipped code:
the numbered ring in the margin and the flagged rule on the sheet land on the same line, because
both are placed from the same `CaptureGeometry`. And `SeamlyColor.sheet` really is theme-fixed —
the captured content measures (134.0, 133.6, 133.0) in light against (134.6, 134.2, 133.4) in
dark, a 0.2 % difference attributable to sub-pixel scroll, while the ground moves from
(236, 233, 227) to (26, 24, 21) and stays warm (R > G > B) in both.

One thing it found and deliberately did **not** change: at regular width Review offers *Export*
twice, once in the nav bar and once in the rail. The design kit's own `ReviewScreen.jsx` does
exactly this, so the port is faithful and the design wins. It does leave two identically
labelled buttons for VoiceOver, which is worth revisiting with the design rather than patching
around here.

### What this pass could NOT verify

**Landscape iPhone was not confirmed on screen.** `SeamlyLayout.isShort` is supposed to move the
position scale under the sheet, and six attempts failed to photograph it. Setting
`XCUIDevice.shared.orientation` rotates the screenshot buffer to 2622 × 1206 but the app's window
scene never resizes: every landscape screenshot shows portrait-shaped content rotated 90° with
the remaining 60 % of the frame solid black, unchanged 40 seconds after the rotation and
unchanged with `-parallel-testing-enabled NO`. That signature points at the simulator/XCUITest
interaction rather than at the app — nothing in the layout pins a portrait size, and the app
declares landscape support for iPhone — but it is *not* proof, and this log should not pretend
otherwise. **Rotate an iPhone by hand before trusting this path.**

By inspection the branch is at least self-consistent: `CaptureView` excludes the scale rail from
`sheetWidth` only when `!isShort` (line 85), draws the vertical scale only when `!isShort`
(line 96), and draws `shortScale()` when `isShort` (line 106) — so it cannot render both or
neither.

Two false passes are worth recording, because both looked green:

1. The first landscape run reported success and produced eleven **portrait** screenshots:
   an orientation set before `app.launch()` does not survive into the launched app.
2. The second survived an assertion added specifically to catch the first
   (`app.frame.width > app.frame.height`), because `TEST_RUNNER_SEAMLY_LANDSCAPE` never reached
   the runner, so the guard was skipped rather than failed. **A guard downstream of the same
   missing input as the thing it guards is not a guard.** The tell was not the exit code or the
   assertion but the screenshot *filenames* — they carried the `?? "shot"` default instead of the
   prefix passed by the same broken channel. Landscape is now its own test method selected with
   `-only-testing:`, which cannot fail to arrive.

## Consequences

- `ContentView`, `HomeView`, `ResultView`, `OutcomeViews`, `RepairView`, `ConditionNotice`,
  `CaptureCanvas`, `OnboardingView` and `PhotoImportButton` are deleted — 1 223 lines.
  `PickedMovie` survived its file and moved to `Features/Import/`.
- `CaptureCondition` keeps both halves, deliberately. `message(for:)` is load-bearing with nine
  live call sites and a hard rule in `CLAUDE.md`; the aggregate `Imperfection` layer is retained
  and tested even though the design replaced its prose with per-finding questions, because
  `endedEarly`, `orderAssumed` and `failed` have no per-finding equivalent. This is the spec's
  "accepted loss", not an oversight — see the spec's Findings section.
- `-SeamlyResetCaptures` joins `-SeamlySeedMisalignedCapture` as a `#if DEBUG` launch argument, so
  a UI test that needs an empty store asks for one instead of depending on class-name alphabetical
  ordering. The suite used to be green on a freshly erased simulator and red on a dirty one.
