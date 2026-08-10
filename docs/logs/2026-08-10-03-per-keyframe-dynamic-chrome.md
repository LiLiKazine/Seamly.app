# 2026-08-10-03: Per-keyframe dynamic chrome

**Status:** Implemented

## Symptom

`Screenshots3` always recovered the correct order, stayed one segment, and matched every seam, yet
Chrome's expanded toolbar from the first screenshot remained in the middle of the stitched page.
The toolbar collapses after that screenshot. The persisted crop belonged to the segment, so one
top/bottom pair could not represent both screen states.

This was a useful failure shape: arithmetic and topology were correct. Only ownership of the chrome
geometry was wrong.

## Options

| Approach | Advantages | Why it was rejected or chosen |
|---|---|---|
| Keep one crop per segment | Smallest code change | Reproduces the bug because chrome can change without a segment break |
| Store chrome per seam | Matches where residual evidence is observed | An interior keyframe belongs to two seams, so ownership is ambiguous |
| Key records by frame index | Easy to serialize | Reordering changes indices and can attach overrides to the wrong image |
| Add an old/new compatibility layer | Could read unreleased manifests | Adds permanent branching without released data to preserve |
| Store chrome per keyframe UUID | Stable ownership through reorder; supports independent overrides | Chosen |

## Decision

Replace the unreleased segment-wide schema with one strictly validated chrome record per stored
keyframe UUID, and make matching and composition consume each frame's resolved geometry.

## Rationale

Chrome state belongs to the captured viewport, not to scroll topology. UUID ownership survives
reorder and replanning, while separate automatic and user-override layers allow fresh measurements
without discarding edits. Because the app has not shipped, a clean schema cutover is safer and
smaller than maintaining compatibility code that has no real consumer.

## Model cutover

The app is unreleased, so the old manifest was replaced rather than supported alongside the new
one. `StitchSession` now requires `stitch-session.keyframe-chrome.v1` and owns `KeyframeChrome`
records keyed by stable `Keyframe.id`. Each record separates an automatic `ChromeMeasurement` from
an optional per-edge `ChromeOverride`. Resolution is override, then automatic, then zero crop; an
implausible combined crop resolves unlocked.

Planner UUIDs are temporary. `StitchAssembler` transfers automatic measurements by ordered slot to
the stored keyframe UUIDs, while preserving user overrides by stored identity. Duplicate and
dangling records are rejected at the harness boundary. `ContentBand` and `contentBands` were
deleted; there is no dual-write or legacy decoder.

## Detection

For a positive profile offset `dy`, later row `k` aligns to earlier row `dy + k`. The residual at
the beginning of that overlap observes the later frame's top edge; reversing it observes the
earlier frame's bottom edge. A direct chrome run needs eight high-residual rows, eight following
low-residual content rows, and the existing static-fraction floor. A two-observation cluster fills
an edge that cannot be seen directly.

The existing all-pair same-screen/translucent measurement remains a safe baseline. Per-seam
evidence may expand an individual edge beyond that baseline, which is what distinguishes the first
Screenshots3 toolbar. Evidence never crosses a segment break; an unmeasured singleton keeps an
explicit UUID record with no automatic layer.

Measured Screenshots3 chrome is:

| Frame | Top | Bottom |
|---|---:|---:|
| 0 | 193 px | 431 px |
| 1 | 202 px | 166 px |
| 2 | 193 px | 166 px |
| 3 | 193 px | 166 px |
| 4 | 193 px | 166 px |

Order remains `[0, 1, 2, 3, 4]`; offsets remain within the established raw-pixel tolerance; no
segment break is introduced.

## Matching and composition

`OffsetMatcher` now accepts a `RowMaskPair`, so each aligned row is checked against the mask of the
frame that owns it. This applies to weighted MAD and tile consensus without changing geometric
admissibility.

For each adjacent frame, `Compositor` calculates:

```text
previousContentBottom = previousHeight - previousBottom
currentContentBottom  = currentHeight - currentBottom
sourceStart = clamp(previousContentBottom - dy, currentTop...currentContentBottom)
```

It adds `sourceStart..<currentContentBottom`, keeps the first top chrome and final bottom chrome
once, and preserves a single-keyframe segment in full. Pixel-coded tests cover both directions of a
toolbar transition and assert every output row, catching gaps and duplicates rather than only
checking height.

## What Changed

- Added the per-keyframe chrome domain, resolver, persistence validation, and editor mutation APIs.
- Added asymmetric frame masks to weighted and tile-consensus matching.
- Added seam-residual measurement and per-keyframe composition, including stored-UUID remapping.
- Migrated the app, CLI, diagnostics, harness, documentation, and tests; deleted the segment-band
  production model and detector terminology.

## What Was Discovered

- Correct order, seams, and segment topology cannot prove correct chrome ownership; the rendered
  pixels were the only oracle that exposed the expanded toolbar in the page.
- A planner's UUIDs are temporary even when its ordered slots are correct, so automatic geometry
  must be remapped while overrides remain attached to stored identities.
- Strict domain decoding can precede a more specific harness topology diagnostic. The harness now
  preflights duplicate keyframe IDs so its existing error contract remains deterministic.
- The full real-video suite is intentionally expensive: the final run spent most of its time in
  tile-consensus matching and completed in 1274.115 seconds rather than being stalled.

## Verification

- Domain, matcher, compositor, and batch focused suites: 65 tests passed.
- Screenshots3 per-keyframe measurement oracle: passed after 104.319 s.
- Screenshots3 expanded-toolbar occurrence: hard assertion, expected zero.
- Dynamic chrome fixture suite: passed after 136.169 s.
- Raw-pixel chrome gate: passed after 108.009 s.
- Complete StitchKit package: 180 tests in 28 suites passed after 1274.115 s, with exactly the one
  pre-existing sparse fast-flick known issue.
- App integration: the app, broadcast extension, and editor built for the iPhone 17 simulator; all
  five `BatchAssemblyTests` passed, including stored-identity remapping through import.
- Visual verification: Screenshots3 rendered to 1320×9440 with the compact bottom bar once and no
  expanded toolbar in the page; Screenshots4 rendered to 1320×10063 with one top and one bottom
  browser bar. Both composites were inspected at full resolution with no visible seam break.
- Four-dimension Swift design review found no blockers. Remaining detector extraction, explicit
  absent-edge typing, and top-edge/boundary detector tests are non-blocking follow-ups.

## Commits

| Commit | Summary |
|---|---|
| This commit | Replace segment-wide chrome with the validated per-keyframe model and fix the collapsing-toolbar stitch |
