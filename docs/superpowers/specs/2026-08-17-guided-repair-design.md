# Guided Repair — Design (Spec 2)

**Date:** 2026-08-17
**Status:** Approved (brainstorming) — ready for implementation plan.

## Summary

Give the user one way to fix a stitch that came out wrong: **take them to the join and let them
drag the two halves until they line up**, with live pixels under the finger.

Spec 1 shipped the one-shot shell and deliberately left no way to fix a bad stitch — only
re-record. That gap was raised and accepted on the condition that guided repair would follow
(`2026-08-10-one-shot-capture-shell-design.md`, "What is deleted"). This is that spec.

One interaction, one number per join, and no pipeline vocabulary anywhere: "seam", "chrome",
"confidence", "offset", "segment" never reach the screen. Nothing in `StitchKit` changes, and the
manifest schema does not change.

## The decision this rests on

Settled before this spec, and not reopened here:

| Decision | Choice |
|---|---|
| Repair model | **One guided repair, no vocabulary.** A single direct manipulation handles every misalignment. |
| Rejected | Per-seam and per-bar controls; a stepper form. `EditView` was deleted *because* a pixel-offset stepper contradicts this. |
| Repair surface | **A dedicated guided screen per join** — not the result canvas made editable. |
| Who is offered it | **Loudly when we flagged something, quietly when we did not.** |
| Geometry authority | **The manifest, frozen at import** — see "Making the drag survive" below. |

## Verified before designing on it (2026-08-17)

`CaptureCanvas`'s zoom fix shipped in Spec 1 without anyone ever pinching it — the session that
wrote it had no tap capability, and the follow-up was recorded as still owed
(`docs/logs/2026-08-11-02-final-review-fix-wave.md`, "Follow-ups"). Guided repair depends on it,
so it was driven for real on an iPhone 17 simulator against a live three-frame stitch:

| Behaviour | Result |
|---|---|
| Pinch to zoom | **Works** — content magnifies |
| Zoom accumulates across gestures | **Works** — a second pinch builds on the first, no snap back to 1× |
| Pan horizontally while zoomed | **Works** — content clipped off the right edge is reachable |
| Pan vertically while zoomed | **Works** — content below the viewport is reachable |
| Double-tap to zoom back out | **Inconclusive** — each `sim-use` invocation is a separate process, so two taps could not be landed inside the double-tap window. Not claimed broken; owed a real finger. |

So the layout-size fix (`viewport width × zoom` applied with `.frame`) and `ZoomState`'s
accumulation are both real. Repair can stand on them.

Incidental finding that shaped the entry condition: a three-screenshot import came back
**`.clean`**, with no `ConditionNotice` at all. If repair were reachable only from a flagged
capture, a visibly-wrong-but-unflagged stitch would still have no recourse — and this repo's
history is explicit that a green verdict has been confidently wrong before (`CLAUDE.md`, "A green
suite here has lied three times").

## Goals

- One interaction that fixes a misaligned join, reachable in one tap from the result screen.
- The pixels under the finger are the pixels that get exported. No re-guessing after the user has
  spoken.
- `CaptureModel.update(_:)` finally gets the caller it was kept for.
- No `StitchKit` edit, no manifest schema change, no movement in its 180 tests / 28 suites / 1
  known issue.

## Non-goals

- Removing a bar band that sits mid-strip. Reasoned below; it is unsound, not merely unwanted.
- Anything for `gaps`, `endedEarly`, or `orderAssumed` — those are not alignment problems.
- Horizontal alignment. `Compositor` measures `dx` and never applies it.
- Panning inside the repair screen, and any per-join list, picker, or numeric readout.

## The surface

### Entry

`Imperfection` gains one flag beside `recommendsRecordingAgain` (`CaptureCondition.swift:65`):
whether the fix is *alignment*. The two are not inverses.

| Kind | Re-record helps | Lining up helps |
|---|---|---|
| `endedEarly` | yes | no |
| `gaps` | yes | no |
| `unresolvedBars` | no | partly — restores continuity around the band |
| `flaggedJoins` | no | **yes** |
| `orderAssumed` | no | no |

- **Loud** — condition is `.imperfect` and **any** imperfection is alignment-fixable:
  `ConditionNotice` carries the action. Its existing headline already reads "A join may not line
  up", so the button reads **"Line it up"**.

  Note the deliberate asymmetry with `recommendsRecordingAgain`, which reads the **primary**
  imperfection only (`CaptureCondition.swift:91`). A capture can have ended early *and* have a
  fixable join; "record again" being the loudest advice does not make the image already on disk
  unfixable. So the action attaches to the notice as a whole rather than to a row, and it is
  offered whenever any observation is alignment-fixable.
- **Quiet** — condition is `.clean`: the same words as a nav-bar trailing item on `ResultView`.
  One string, so `CaptureCondition` remains the only place this copy lives; only prominence
  differs. It deliberately stays out of the bottom bar, which already stacks Save, the export row,
  and up to two more rows.

Presented as a **full-screen cover**, not a push: it is a single-purpose surface with its own
Cancel/Done, and pushing it would sit a second back-chevron beside the result's.

```
┌──────────────────────────────┐
│ Cancel      Line it up   Done│
├──────────────────────────────┤
│   ▒▒▒ upper frame's tail ▒▒▒ │
│   ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │
│ ──────────────────────────── │ ← boundary, vertically centred
│   ░░░ lower frame's head ░░░ │ ⇕ one finger; the lower half
│   ░░░░░░░░░░░░░░░░░░░░░░░░░░ │   tracks it exactly
├──────────────────────────────┤
│        ‹   3 of 8   ›        │
└──────────────────────────────┘
```

### Which join it opens on

The least-confident seam — `Seam.confidence` ascending, ties broken by index. Among the flagged
seams for the loud entry; among all of them for the quiet one, **and for a loud entry where no seam
is flagged at all**, which is reachable: `unresolvedBars` is alignment-fixable and is counted from
chrome records, not from seam confidence, so a capture can offer repair with every seam unflagged.
Ranking all of them covers that without a second rule.

The chevrons walk every join in the capture in index order, so a bad join we never flagged is
still reachable. The indicator is a **position, not a menu**: no list, no picker, nothing that
reads as per-seam controls.

**Joins spanning a segment break are excluded.** Nothing overlaps across a break
(`StitchSession.hasSegmentBreak(after:)`), so there is nothing to line up, and `Compositor.plan`
ignores any seam that crosses one.

That makes an empty set reachable — two keyframes with a break between them have no walkable join —
so **both entries are hidden when the walkable set is empty**, rather than opening a screen with
nothing to drag. A capture in that state is `gaps`, and re-recording is already what it offers.

**Rejected: a workflow that walks the flagged joins and calls itself done.** "Next problem" until
all flagged joins are visited, then "Done", is a state machine whose only output is a slightly
better-timed button label. The notice already says how many joins look off.

### What the finger does

One finger, vertical: the lower half's content tracks it 1:1 in displayed pixels. Pinch zooms
1×–6× about the boundary (`ZoomState`, unchanged).

**Zoom is also the precision mechanism.** At 1× on this device a point is ~3.3 source pixels
(1320 px across 402 pt), so ~3.3× is where one point becomes one pixel and 6× is finer than
anyone needs. No fine-adjust control, no rate-reduced dragging, and no number on screen.

**Deliberately absent: panning.** The boundary stays centred and the view never scrolls, so one
finger always means exactly one thing. The cost is that at high zoom only the middle of the
frame's width is visible. If real use shows that is too narrow, two-finger pan is the additive
fix — better than shipping an overloaded gesture on a guess.

## Making the drag survive

`StitchAssembler.composite` builds `Compositor(refinementDelta: 16)`
(`StitchAssembler.swift:97`), and `Compositor.composite` calls `refineSeams` on **every** draw
(`Compositor.swift:102`), re-searching ±16 px around each stored offset and replacing it whenever
the local match scores ≥ `refinementConfidence`. Writing the user's value into
`Seam.provisionalDy` therefore hands the final say back to the matcher on the one join the user
just corrected by hand, and it can move it by up to 16 px. Body-text line pitch is often under
16 px, so it can snap back a whole line.

| Approach | Verdict |
|---|---|
| Freeze the offsets in the manifest; composite with `refinementDelta: 0` | **Chosen.** |
| Persist the user's `dy`, keep delta 16 and let refinement "polish" it | Rejected — re-runs the matcher exactly where the matcher already failed, and abandons the promise that the pixels under the finger are the pixels you get. |
| Add `Seam.userDy: Int?`, mirroring `ChromeOverride` | Cleanest semantics; rejected because it is a `StitchKit` change plus a manifest schema bump, both off-limits. |

### How the freeze works

- New app-side `StitchAssembler.freezeGeometry(_:in:)` runs `Compositor(refinementDelta: 16)
  .refineSeams` and copies **only** `provisionalDy` onto the stored seams. `confidence`,
  `isLowConfidence` and `provisionalDx` pass through untouched, so no existing user-facing copy
  shifts as a side effect of this change.
- `StitchAssembler.composite` and `writePDF` default to `Compositor(refinementDelta: 0)`. At
  delta 0 the search range in `refineVertical` collapses to `lo == hi == provisional`
  (`Compositor.swift:354`), so `dy` returns untouched — refinement becomes a no-op on geometry
  without `StitchKit` changing a line.

### Freezing belongs to import, not to drawing

**`assemble` must never freeze.** This is the one trap in the whole approach, and it is not
obvious: `assemble` is also what `update(_:)` calls after a repair, and what every relaunch calls
for captures that load with no proxy. A freeze there would re-search ±16 px around *the user's own
value* and move it — silently undoing the repair the next time the app is opened, which is
precisely what this approach exists to prevent.

It is tempting to argue the freeze is idempotent and therefore harmless to repeat. It is not: the
search window recenters on the new value, so a second pass can find a different minimum in the
shifted window. And the user's value is *by definition* not the matcher's argmin — that is why they
had to drag it.

So the freeze runs **exactly once per capture, at import, next to where geometry is already
derived** — the completion of `resolveGeometry`'s job, not a step in the draw path:

| Path | Freeze |
|---|---|
| App Group pickup | once per session in `GroupImportOutcome.newArrivals`, after `resolveGeometry` |
| Photos / video import | once, on the id `runImport` returns, after `MediaImporter.write` |
| Launch / foreground re-assembly | never — composites the stored, already-frozen manifest |
| Post-repair re-assembly (`update(_:)`) | never — this is what keeps the repair |

No persisted marker is needed, and none is possible without a schema change. The distinction is
already in the model: `newArrivals` exists precisely to separate "geometry was just derived for
this" from "this was already in app storage", and it is the same distinction `pendingResult` keys
off (`CaptureModel.swift:236`).

**Why this is safe rather than merely convenient.** Today's output is `refine(stored)`; the new
path is `composite(freeze(stored))` with refinement disabled — the same function over the same
inputs, so the result is identical by construction. A fixture-level equivalence test holds that
claim honest (below). If it ever fails, this approach is wrong, not inconvenient.

**What it buys beyond repair:**

- The composite becomes a pure function of the manifest — which non-destructive editing already
  claims, but is not true while every draw silently re-derives geometry.
- Exports stop re-refining. `fullComposite` and `exportPDF` each redo the full pass today, on
  every tap.

Refinement cost per capture drops from once per draw to once per lifetime.

**Accepted consequence for captures already on disk.** A dev capture imported before this change
has coarse, unfrozen offsets, and would now composite from them directly instead of being refined
on the way to the screen — a slightly coarser stitch until it is re-imported. The manifest format
is `keyframeChromePreRelease` and nothing has shipped, so this affects local dev captures only.
Detecting "never frozen" heuristically is rejected: it would be a guess standing in for the schema
field this spec does not get to add.

**If the freeze throws** (unreadable keyframes) the import keeps the unfrozen manifest and logs to
`Diagnostics`, matching how a failed `resolveGeometry` is already handled
(`CaptureModel.swift:309`). The subsequent composite will fail on the same unreadable keyframes and
surface through the existing `.failed` path.

## The pure core

`JoinAlignment` — a `nonisolated` value type holding no images, owning all the arithmetic.
`nonisolated` for the reason `CaptureFacts` and `ZoomState` already are: this target sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

- `lowerSourceStart = clamp(upperContentBottom - dy, lowerChromeTop...lowerContentBottom)`,
  mirroring `Compositor.plan` (`Compositor.swift:270`), clamp included.
- Drag: `dy' = dy + Δpoints × sourcePixelsPerPoint / zoom`, where `sourcePixelsPerPoint` is the
  **1× ratio** `keyframe.pixelWidth / viewportWidthInPoints` (the frames are rendered at full
  resolution and fitted to the viewport width, as `CaptureCanvas` does with the proxy).
  Accumulated as a `Double` across the gesture and rounded once, so a slow drag does not judder.
- Sign: dragging **down** raises `dy`, which slides the lower content down and begins duplicating
  rows; dragging **up** lowers it and begins dropping rows. The user drags until neither happens.
- `dy` clamps to `max(1, upperContentBottom - lowerContentBottom) ... upperContentBottom -
  lowerChromeTop` — exactly the range over which `sourceStart` still moves. Outside it the
  compositor's own clamp would freeze the picture while the finger kept going, a dead zone that
  reads as a broken control. It stops at a hard edge; no rubber-banding, because a bounce implies
  something lies past it.

### The one real cost, and how it is paid

This is a **second copy** of `Compositor.plan`'s placement rule. `plan` is private and `Layout` is
internal, so the app cannot ask for it without changing `StitchKit`. Duplicated layout math that
drifts is how a preview starts lying — the failure mode this project has already paid for twice
(`CLAUDE.md`, "A green suite here has lied three times").

So it is pinned by an equivalence test, not by hope: the boundary `JoinAlignment` computes must be
the source row a real `Compositor` draws there, on real fixture pixels. The duplication is
acceptable *because* it is asserted.

## Committing

1. Write `provisionalDy` for each edited join.
2. Clear `isLowConfidence` on those joins only. The user has now looked at that join with their own
   eyes; leaving the warning up after a successful repair is the app disagreeing with them. That
   flag also carries "nonzero `dx`", which this discards — `Compositor` never applies `dx`, so
   nothing is lost but the badge.
3. `await model.update(session)` (`CaptureModel.swift:473`) — the persist-and-reassemble path kept
   without a caller through Spec 1, used exactly as its comment promised. It re-composites at
   `announce: false`, so nothing re-pushes.

The capture goes `.processing` during the re-composite, and `ResultView` already renders
`ProcessingView` for that phase — the few seconds need no new state. Editing nothing writes
nothing. Cancel discards.

Recomputing `CaptureCondition` after the write is what makes the repair visible: the flag is gone,
so the notice goes with it.

## Data flow

```
ResultView
  ├─ .imperfect + alignment-fixable ──▶ ConditionNotice action  ┐
  └─ .clean ─────────────────────────▶ nav-bar item            ├──▶ RepairView (fullScreenCover)
                                                                ┘        │
                          loads the two keyframes at full res            │ drag → JoinAlignment.dy
                          (KeyframeIO via StitchAssembler)               │
                                                                         ▼
                                             Done ──▶ CaptureModel.update(session)
                                                          │
                                        writeManifest ────┤
                                                          └── assemble(announce: false)
                                                                  └─ composite (delta 0, no freeze)
                                                                          │
                                                          ResultView re-derives CaptureCondition

import (once per capture, elsewhere):
  resolveGeometry / MediaImporter.write ──▶ freezeGeometry (delta 16) ──▶ writeManifest
```

The repair survives a relaunch because of what is *absent* from the first path: nothing after the
commit ever re-derives geometry, and `freezeGeometry` copies only `provisionalDy`, so the cleared
`isLowConfidence` stays cleared too.

## Error handling

Per `CLAUDE.md`: nothing swallowed, nothing masked, and no raw error on screen.

- Loading the two keyframes can throw (`KeyframeIO.IOError`). The repair screen is not opened
  empty: the failure surfaces through `CaptureCondition.message(for:)` on the result screen, with
  the raw error to `Diagnostics`.
- `freezeGeometry` failing means the keyframes cannot be read. The import keeps the unfrozen
  manifest and logs the raw error, exactly as a failed `resolveGeometry` already does rather than
  losing the capture; the assemble that follows fails on the same unreadable keyframes and surfaces
  through the existing `Phase.failed` path with a translated message. Nothing is swallowed, and the
  failure is not papered over by quietly reinstating delta 16 for that capture.
- `update(_:)` already logs a failed manifest write while keeping the in-memory edit.

## Testing

**`StitchKit` is not touched** — no source edit, no schema change, so 180 / 28 / 1 cannot move.
Everything lands in `Seamly/Seamly/` and the two app test targets.

`SeamlyTests` (Swift Testing), extending existing suites:

- `JoinAlignment` arithmetic: drag sign, zoom scaling, both clamp edges, `sourceStart` against
  `plan`'s rule. Pure — no images, no disk.
- **Freeze equivalence**, on real fixture sessions: `composite(stored, delta 16)` must equal
  `composite(freeze(stored), delta 0)` pixel-for-pixel. The entire safety argument above.
- **Preview equivalence**: the boundary `JoinAlignment` computes must be the source row a real
  `Compositor` composite puts there. Observed in pixels, not by reading internals — composite a
  two-keyframe session and require the output row at the boundary to equal the lower keyframe's row
  `lowerSourceStart`, for a stored `dy` and for an edited one.
- `canBeLinedUp` per `Imperfection.Kind`, table-driven beside the existing condition tests.

Counts get read from `xcrun xcresulttool get test-results summary`, never from "TEST SUCCEEDED",
and every `-only-testing:` filter carries the trailing `()` — without it xcodebuild matches zero
tests and still reports success, which hid a deterministically broken test on main for weeks.

### UI-test seeding: build it, rather than inherit the gap

Spec 1 left UI tests covering only the empty home, deferring seeding rather than adding test-only
hooks. For repair that trade flips. Driving the system photo picker was the one fragile step when
this flow was driven by hand: its cells carry no distinguishing labels, so a test that taps them is
exactly the test that keeps passing while the screen is broken — the dark-mode record button, again.

So: a `#if DEBUG` launch argument that **synthesizes** two keyframes at launch and writes a
manifest with a deliberately wrong `dy`. No bundled binary asset, deterministic, and it gives the
repair screen something genuinely misaligned to fix. The honest cost is one debug-only entry point
into app storage, present in no release build.

One UI test: launch seeded → result → "Line it up" → drag → Done → notice gone.

### And a real finger on it

Run the app and look at it, light and dark, at 1× and zoomed — including the double-tap that could
not be conclusively driven above. Forty-two green tests, four UI tests, ten task reviews and a
whole-branch review already missed an invisible record button once.

## Out of scope, with reasons

**A bar band mid-strip is not removed by the drag.** Aligning restores content continuity *around*
the band — a real improvement, since the rows hidden behind that bar come back — but the band is
the upper frame's own bottom bar, and only a chrome edit deletes it. Folding that into the same
gesture means deriving a bottom-chrome override from the drag, and that is **unsound at the common
end of the range**: `ChromeInsets.maxCombinedCropFraction` is 0.5 (`ChromeDomain.swift:20`), and on
a careful, small scroll step the derived override exceeds that ceiling, so
`StitchSession.setChromeOverride` clamps it (`StitchSession.swift:295`) and the composite silently
duplicates content instead of cutting the band. A gesture that quietly does the wrong thing for
careful users is worse than a gesture that does not claim to.

**No reset control.** Cancel covers a drag in progress. After Done the edit is still
non-destructive — re-entering repair and dragging again is the fix — so "put it back" would be a
third path to the same place.

**No numbers, no vocabulary, no per-join list.** Stated again because every one of them is a
plausible-looking addition that would contradict the governing decision.

## Files touched

| File | Change |
|---|---|
| `DesignSystem/CaptureCondition.swift` | alignment-fixable flag on `Imperfection`; the action's copy |
| `DesignSystem/ConditionNotice.swift` | the loud entry action |
| `Features/Result/ResultView.swift` | quiet nav-bar entry; `fullScreenCover` |
| `Features/Repair/RepairView.swift` | new — the guided screen |
| `Features/Repair/JoinAlignment.swift` | new — the pure arithmetic |
| `Core/StitchAssembler.swift` | `freezeGeometry`; `refinementDelta: 0` defaults |
| `Core/CaptureModel.swift` | freeze new arrivals at import only; `assemble` unchanged |
| `SeamlyApp.swift` | `#if DEBUG` seeding argument |
| `SeamlyTests/`, `SeamlyUITests/` | the suites above |

## Follow-ups this leaves open

- Two-finger horizontal pan in the repair screen, if real use shows the centred column is too
  narrow at high zoom.
- The bar band itself. It needs its own decision about where a chrome edit lives without becoming
  the per-bar control this model rejects — not a quiet extension of this gesture.
- A permanently-failing capture is still re-composited on every foreground (Spec 1 follow-up,
  unchanged here, and now one refine cheaper per attempt).
