# 2026-08-18-02: Seed a misaligned capture, and prove guided repair end to end

**Status:** Implemented

## Context

Tasks 1-6 built guided repair (`docs/superpowers/specs/2026-08-17-guided-repair-design.md`):
`JoinAlignment`, `RepairableJoins`, `RepairView`, the loud/quiet entries on `ResultView`, and
frozen geometry (`2026-08-18-01-frozen-geometry.md`). None of it had ever been driven through the
real UI. Reaching `RepairView` needs a capture on disk, and the app's only import paths are the
system photo picker and a video picker — neither of which a UI test can drive reliably (the
picker's cells carry no distinguishing labels, which is exactly the kind of gap that let an
invisible record button ship past 42 unit tests, 4 UI tests, and eleven reviews).

This task closes that gap: a `#if DEBUG` launch-argument seed that synthesizes a deliberately
misaligned two-keyframe capture straight into app storage, a UI test that drives the whole loud
path end to end, and a manual pass with real touch input.

## Options — the seed's chrome records

The brief's first draft called `session.ensureChromeRecordsForKeyframes()`, which leaves
`automatic == nil` on every edge. That looked harmless (chrome isn't the thing under test) but is
not: `CaptureFacts.unresolvedChrome` counts keyframes with any edge needing review, and
`Imperfection.Kind` ranks `unresolvedBars` (rank 2) above `flaggedJoins` (rank 3) —
`CaptureCondition.init(ready:)` picks the first (lowest-rank) imperfection as primary. With both
edges unresolved, the notice would read "Some bars may repeat", not "A join may not line up", and
the real headline would sit unseen inside a collapsed "1 more" disclosure. A UI test asserting on
the wrong string is worse than none — it fails somewhere that reads like a `RepairView` bug when
the actual defect is in the seed.

| Approach | Verdict |
|---|---|
| `ensureChromeRecordsForKeyframes()`, `automatic == nil` | Rejected — wrong primary imperfection. |
| **Explicit zero-inset, positive-confidence `ChromeMeasurement` per keyframe** | **Chosen.** |

Each `KeyframeChrome` record gets `automatic: ChromeMeasurement(insets: .zero, confidence: 0.9)`,
so `chromeEdgesNeedingReview` returns empty for both edges, `unresolvedChrome == 0`, and
`flaggedJoins` is the only (and therefore primary) imperfection.

## Options — the seed's offset and drag direction

The brief seeded `storedDy = 300` against a synthesized `trueDy = 360`, with the UI test dragging
**upward**. `JoinAlignment.dy(draggedBy:...)` computes `dy' = start + Δy_points ×
sourcePixelsPerPoint / zoom`; a real finger dragging up on screen reports a *negative*
`translation.height`, which *lowers* `dy`. Starting from 300 (already 60 below the true 360) and
dragging up would move further from the truth, while the brief's own comment claimed convergence —
the two facts contradict each other.

| Approach | Verdict |
|---|---|
| `storedDy = 300`, drag up (brief's draft) | Rejected — moves *away* from the true 360. |
| **`storedDy = 420`, drag up** | **Chosen** — 60 px past the truth, converges under an upward drag. |

At `storedDy = 420` the seeded preview duplicates roughly 60 rows at the join (confirmed visually,
see below); dragging up by the UI test's ~105 pt (at ~0.75 source px/pt on this hardware) lands
near 342 — close enough that the committed join no longer reads as flagged, without claiming pixel
perfection.

## Options — isolation for the debug entry point

`DebugSeed.seedIfRequested()` calls `CaptureModel.appContainerURL()`, a `@MainActor`-declared
static function. The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so in principle
every new declaration in the target (including this debug-only file) is already `@MainActor` by
default. Rather than depend on that default holding for a debug-only file that could plausibly be
extracted or reused elsewhere later, `seedIfRequested()` and the private `seed()` helper are marked
`@MainActor` explicitly, naming the actual requirement instead of an inferred one.
`CaptureModel.appContainerURL()` itself is untouched — nothing here makes it `nonisolated` to
satisfy a debug-only hook, which would have been the wrong fix (loosening a real type's isolation
to serve a test aid).

## Decision

- `Seamly/Seamly/Core/DebugSeed.swift` (new, `#if DEBUG`-only): writes one deliberately misaligned
  two-keyframe capture directly into app storage — a `SessionStore` write, not an App Group import
  — so it never goes through `resolveGeometry`/`freezeGeometry`. That is what leaves the seeded
  `provisionalDy = 420` in place for the test (and a human) to drag away, exactly like a capture
  that has never been re-imported.
- `Seamly/Seamly/SeamlyApp.swift`: `init()` calls `DebugSeed.seedIfRequested()` under `#if DEBUG`.
- `Seamly/Seamly/Features/Home/HomeView.swift`: the recents `Button` gets
  `.accessibilityIdentifier("recent-capture")` — an identifier, not a behaviour hook, since the
  thumbnail's only label is a localized date a test cannot match reliably.
- `Seamly/SeamlyUITests/RepairUITests.swift` (new): launches with `-SeamlySeedMisalignedCapture`,
  taps the seeded recent, asserts the loud notice, opens repair, drags up, commits, and asserts the
  notice is gone — and *stays* gone once the capture is provably back to `.ready` (see below).

### The UI-test seeding reversal

Spec 1 (`2026-08-10-one-shot-capture-shell-design.md`) deliberately deferred UI-test seeding rather
than add test-only hooks to app storage. This task reverses that, narrowly, for guided repair: the
picker-driven paths (Photos, video) have no way to land a UI test reliably, but a bad stitch
reaching `RepairView` needs something on disk. The seed is the "reverse" — narrow, `#if
DEBUG`-gated, and an explicit launch argument, not a general test-fixture mechanism. If the seed
fails, it prints loudly (`Seamly: DebugSeed FAILED: ...`) rather than leaving the UI test to fail
somewhere in `RepairView` that looks like a screen bug.

### Correction 4 — proving the assertion means what it claims

`notice.waitForNonExistence(timeout:)` alone is satisfied the instant the capture flips to
`.processing`: `ResultView`'s `.stitching` case renders `ProcessingView`, which has no
`ConditionNotice` at all. That proves nothing about whether the write that triggered the flip was
correct — a commit that transitioned to `.processing` without truly persisting the fix (or without
writing anything, if some unrelated path re-triggered assembly) would make the notice disappear
*transiently*, then reappear once the capture settles back to `.ready` with its still-flagged
condition, and a test that stops watching the instant the notice first vanishes would report a
false pass.

The test instead waits for `"Save to Photos"` to become **hittable** again (which only happens
once `assemble` finishes and the capture is `.ready` with a proxy) and *then* asserts the notice is
still absent. That can only hold if the capture actually came back `.ready` with a condition that
recomputed clean.

### Discrimination, both directions

Per the checklist: `RepairView.commit()` was temporarily reduced to `{ dismiss() }` (skipping the
write entirely) and the suite re-run.

| Commit body | Result |
|---|---|
| Real (`commit()` writes edits, calls `model.update`) | **Pass** (see Verification below) |
| `{ dismiss() }` | **Fail** — `"the join was still flagged after being lined up — the edit did not reach the manifest"` |

Then reverted and re-run to confirm the pass again. A UI test that cannot fail is worse than none.

## What Was Discovered

**The recents thumbnail's tap target didn't match its own visible bounds — found by the UI test
failing for a reason that had nothing to do with `RepairView`.** The first automated run of
`RepairUITests` failed on `"the seeded capture was not flagged"`: the thumbnail never actually
navigated anywhere. Manual investigation (`sim-use`) showed `HomeView`'s recents `Button` reporting
an accessibility/hit-test frame of `72×269` pt against its own explicit `.frame(width: 72, height:
96)`. `.clipped()` only affects *painting*; without an explicit `.contentShape(Rectangle())`, both
the hit-test region and the accessibility frame follow the aspect-filled `Image`'s own unclipped
render size — here, a 300×~1120 px proxy scaled to 72 pt wide renders 72×268.8 pt tall before
clipping. `XCUIElement.tap()` (and `sim-use tap`) both target the *center* of the reported frame,
which for this button sits at y ≈ 746 — 38 pt below the button's real, visually-clipped bottom edge
at y ≈ 708. The tap landed on nothing.

This is not a Task-7 regression: `thumbnail(_:)` is untouched code from Spec 1, and the bug is
latent in *any* capture whose proxy is far more portrait than the 72:96 target box — which is every
real stitched capture (they're all "many screens tall, ~72 pt wide" once thumbnailed), not just
this synthetic seed. It went unnoticed because nothing had ever driven a tap at the thumbnail's
*reported* geometry before; a human tapping by eye targets the visible 96 pt box, which is well
inside both the true and the inflated hit region, so it always "worked" by accident. Fixed with one
line — `.contentShape(Rectangle())` after `.clipShape(...)` in `thumbnail(_:)` — which pins the hit
test and accessibility frame to the same 72×96 box the pixels are actually clipped to. Verified
before and after with `sim-use`: the reported frame changed from `72×269` to exactly `72×96`, and a
tap at its center then navigated correctly.

**The repair screen's nav-bar title is illegible in light mode.** Not one of the lettered manual
checks, and not fixed here — found while capturing screenshots for check E. `RepairView`'s canvas
sits on `.background(.black)` with only `.ignoresSafeArea(edges: .horizontal)` (vertical safe area
is intentionally respected, per the code comment about not covering the nav bar). On this iOS 26
simulator, the navigation bar still renders as a translucent overlay above that black content: the
`Cancel`/`Done` toolbar buttons pick up an automatic dark legibility pill and stay readable in
*both* appearances, but the plain center `.navigationTitle("Line it up")` text does not get the
same treatment. In **dark mode** the system's white title text is legible against the black canvas
underneath (confirmed, screenshot). In **light mode** the title renders in the system's default
black and is completely invisible against the same black canvas — confirmed by cropping the exact
title region: solid black, zero contrast, in a build where the accessibility tree still reports the
"Line it up" heading present and correctly labelled. This is functionally the inverse of the
project's dark-mode record-button precedent (`DECISIONS.md`), just triggered by the opposite
appearance and a different screen. **Left unresolved** — root-causing and fixing iOS 26's
translucent-bar-over-black-content interaction is a design call (does the repair screen want an
opaque nav bar? a different title treatment?) outside this task's scope, and is called out as a
concern in the task report rather than patched blind.

**Pinch does not drag the join.** The one question this task was most worried about. Tested with a
genuine, perfectly-symmetric two-finger `sim-use multi-touch` gesture centred exactly on the
boundary (each finger moves 100 pt outward from a fixed centroid — a pinch with, by construction,
zero net pan). Rather than trying to eyeball whether the alignment shifted, the test exploited
`RepairView.commit()`'s own structure: it only writes anything if `edited` is non-empty, and
`edited[join]` is only set from `dragGesture(...).onChanged`. So: perform the pinch, immediately
tap Done, and check whether the notice cleared. It did **not** — the pinch alone left `edited`
empty, `commit()` took its `dismiss()`-only early exit, and the join was still flagged after
returning to `ResultView`. `DragGesture` and `MagnifyGesture` compete under
`.simultaneousGesture`, but SwiftUI's/UIKit's gesture arbitration is correctly keeping the
single-finger pan from also interpreting a concurrent two-finger touch. "One finger means one
thing" holds.

**The double-tap-to-zoom-out check, previously inconclusive, is now conclusively verified.** The
spec's own verification table recorded this as "Inconclusive — each `sim-use` invocation is a
separate process, so two taps could not be landed inside the double-tap window." `sim-use ios
batch` (one HID session, ordered steps, no process-per-step overhead) closes that gap: two `touch
--down --up` steps at the same point in one batch landed inside the recognizer's window. Before:
~4 stripe-bands visible (zoomed in ~2-3×). After: ~9-10 bands visible, matching the original 1×
density. Confirmed working.

## Verification

- `RepairUITests/testLiningUpAJoinClearsTheNotice()`: **1 passed, 0 failed** (fresh
  `-resultBundlePath`, `xcrun xcresulttool get test-results summary`).
- Discrimination: **fails** on `RepairView.commit() { dismiss() }` with the expected failure text;
  **passes** once reverted.
- Full app suite (`SeamlyTests` + `SeamlyUITests`, fresh bundle): **72 passed / 0 failed** (up from
  the stated 71-passed baseline — the +1 is the new `RepairUITests` test). `StitchKit` untouched
  (no file under `Seamly/StitchKit/` was edited).
- Manual pass answers (A-J) are in the task report; screenshots under the task's scratchpad
  directory (`task7-*.png`).

## What Changed

- `Seamly/Seamly/Core/DebugSeed.swift` — new, `#if DEBUG`-gated seed.
- `Seamly/Seamly/SeamlyApp.swift` — calls `DebugSeed.seedIfRequested()` from `init()` under `#if
  DEBUG`.
- `Seamly/Seamly/Features/Home/HomeView.swift` — `.accessibilityIdentifier("recent-capture")` on
  the recents button; `.contentShape(Rectangle())` on `thumbnail(_:)` fixing the hit-test/a11y
  frame bug described above.
- `Seamly/SeamlyUITests/RepairUITests.swift` — new end-to-end UI test.
- `CLAUDE.md`, `README.md`, `DECISIONS.md` — status and documentation updates reflecting that
  guided repair now exists and ships.
