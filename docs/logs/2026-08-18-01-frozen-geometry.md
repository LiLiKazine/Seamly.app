# 2026-08-18-01: Freeze seam offsets into the manifest

**Status:** Implemented

## Context

Guided repair (`docs/superpowers/specs/2026-08-17-guided-repair-design.md`) lets a user drag a
join until it lines up, then persist that offset into `Seam.provisionalDy`. But
`StitchAssembler.composite` built `Compositor(refinementDelta: 16)`, and `Compositor.composite`
calls `refineSeams` on **every draw** (`Compositor.swift:102`), re-searching ±16 px around
whatever offset is stored and overwriting it whenever the local match scores well enough. Writing
a user's hand-aligned value into the manifest would therefore hand the final say straight back to
the matcher the next time anything drew that capture — the one join the user just corrected by
hand could silently move again, by up to 16 px, which is often more than a line of body text.

This task moves that ±16 px refinement out of the draw path and into import, so the manifest
becomes the authority on geometry and every later repair task has something stable to write into.

## Options

The spec's "Making the drag survive" section considered three approaches:

| Approach | Verdict |
|---|---|
| **A. Freeze the offsets in the manifest at import; composite with `refinementDelta: 0`** | **Chosen.** |
| B. Persist the user's `dy` as-is, keep `refinementDelta: 16`, let refinement "polish" it on every draw | Rejected — this re-runs the matcher exactly where the matcher already failed (that's why the user had to drag it), and abandons the promise that the pixels under the finger are the pixels that get exported. |
| C. Add `Seam.userDy: Int?`, mirroring the existing `ChromeOverride` pattern for chrome | The cleanest semantics — an explicit user layer over the automatic one — but it is a `StitchKit` source change plus a manifest schema bump, and `StitchKit` is a finished core that is off-limits for this plan (180 tests / 28 suites / 1 known issue, must not move). |

## Decision

`StitchAssembler.freezeGeometry(_:in:compositor:)` runs `Compositor(refinementDelta: 16)
.refineSeams` once and copies only the resulting `provisionalDy` onto the stored seams;
`confidence`, `isLowConfidence`, and `provisionalDx` pass through untouched. `composite` and
`writePDF` now default to `Compositor(refinementDelta: 0)`, at which `refineVertical`'s search
range collapses to `lo == hi == provisional` (`Compositor.swift:354`), so the stored `dy` comes
back exactly as written — refinement becomes a geometry no-op on the draw path without a single
`StitchKit` line changing. `freezeGeometry` is called once, at both import call sites
(`MediaImporter.write`, and `CaptureModel.importFromGroup`'s new-arrival branch), immediately
after `resolveGeometry`.

## Rationale

Approach A was the only one that didn't require reopening `StitchKit`, and it turns "the manifest
is the authority" from an aspiration into something actually true: today's output is
`refine(stored)`; the new path is `composite(freeze(stored))` with refinement disabled — the same
function over the same inputs, so the result is identical by construction, not merely by
intention. `freezingThenDrawingMatchesRefiningWhileDrawing` holds that claim honest against real
device screenshots (see "What Was Discovered").

**`assemble` must never call `freezeGeometry`, and this is not a minor caveat — it is the one trap
in the whole approach.** `assemble` is also what `CaptureModel.update(_:)` calls after a future
repair, and what every relaunch calls for a capture that loads with no cached proxy. If freezing
ran there, it would re-search ±16 px around *the user's own value* and move it — silently undoing
the repair the very next time the app is opened, which is exactly the failure this task exists to
prevent.

It is tempting to wave this off with "freezing is idempotent, so calling it twice is harmless."
That argument is false, for two independent reasons: (1) the search window recentres on whatever
value is currently stored, so a second pass searches a *different* ±16 px window than the first
and can converge on a different local minimum; and (2) the user's value is by definition not the
matcher's argmin in the first place — that mismatch is *why* they had to drag it — so re-running
the matcher against it is not a no-op, it is a second opinion the user has already overruled once.
Freezing only belongs beside `resolveGeometry`, at import, exactly once per capture's lifetime.

**Accepted consequence for captures already on disk.** A dev capture imported before this change
carries coarse, unfrozen offsets. It will now composite directly from those offsets instead of
being refined on the way to the screen, which can be a slightly coarser stitch until the capture
is re-imported. The manifest format is still `keyframeChromePreRelease` and nothing has shipped,
so this is scoped to local dev captures. Detecting "this manifest was never frozen" heuristically
was considered and rejected: it would be a guess standing in for the schema field this plan does
not get to add.

## What Changed

- `Seamly/Seamly/Core/StitchAssembler.swift` — new `freezeGeometry(_:in:compositor:)`, placed
  after `resolveGeometry`; `composite` and `writePDF` now default to `Compositor(refinementDelta:
  0)` instead of `16`.
- `Seamly/Seamly/Core/MediaImporter.swift` — `write` now calls `freezeGeometry` on the
  `resolveGeometry` output before writing the manifest.
- `Seamly/Seamly/Core/CaptureModel.swift` — `importFromGroup`'s new-arrival branch does the same;
  a resolve/freeze failure still falls back to keeping the extension's manifest (unchanged
  non-fatal behaviour, just re-worded to mention both steps).
- `Seamly/SeamlyTests/FrozenGeometryTests.swift` — four new tests: a stored offset is corrected to
  the pixel-exact value and persisted; the draw path uses the stored offset verbatim (no
  re-refinement); freezing-then-drawing is byte-identical to today's refine-while-drawing on real
  fixture pixels; and `MediaImporter.write` leaves a frozen manifest on disk.

## What Was Discovered

- **The real-fixture equivalence held byte-for-byte.** `freezingThenDrawingMatchesRefiningWhileDrawing`
  compares `Compositor(refinementDelta: 16).composite(coarse, ...)` (today's path) against
  `Compositor(refinementDelta: 0).composite(freezeGeometry(coarse, ...), ...)` (the new path) on
  the three full-resolution `Screenshots/IMG_1757-1759.PNG` fixtures, and the output images are
  pixel-identical. This is the hard-stop test named in the task brief — it did not trip, so
  approach A is validated on real pixels, not just synthetic ones. This mattered specifically
  because this repo's synthetic fixtures have hidden a real sign-flip bug here before
  (`CLAUDE.md`, "A green suite here has lied three times").
- `Seam.isLowConfidence` defaults to `false` in `Seam.init`, which is what makes
  `freezingCorrectsAStoredOffsetToThePixelExactValue`'s `#expect(frozen.seams[0].isLowConfidence
  == false)` a meaningful assertion rather than a tautology — the test's synthetic seam is
  constructed with the default, and `freezeGeometry` is what has to *not* touch it, since
  `refineSeams` itself does compute and would otherwise overwrite `isLowConfidence` based on the
  refined match's own confidence.
- The two real-fixture tests (`freezingThenDrawingMatchesRefiningWhileDrawing`,
  `importingThroughMediaImporterLeavesAFrozenManifest`) each take on the order of a minute per run
  under the Swift Testing parallel test runner (up to ~110s observed for the latter) — consistent
  with compositing three 1320×2868 frames twice per test, not a regression or a hang.
