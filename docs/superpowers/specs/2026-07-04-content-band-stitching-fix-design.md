# Design — Content-Band Stitching Fix

**Date:** 2026-07-04
**Branch:** `feat/broadcast-scroll-stitching` (continuation)
**Status:** Approved direction; ready for implementation planning.

## Problem

The shipped pipeline produces output that is *stacked screenshots*, not a stitched long
image: fixed navigation/tab bars repeat down the length, and scrolling content repeats at
each join. The core experience — recognizing overlap and merging — is effectively missing
on real app screens.

### Root cause (reproduced, not theorized)

`ChromeStitchReproTests` drives the **real** StitchKit pipeline (the exact sequence
`SampleHandler` uses) on synthetic frames that model a real screen: a fixed top chrome
band, a scrolling content region, and a fixed bottom chrome band. Two variants isolate the
failure:

| | Low-variance content (text-on-white) | High-variance content |
|---|---|---|
| Keyframes committed | **1** (whole scroll lost) | 3 |
| Seams | **0** | 2, `dy=243px` |
| Chrome detected | — | `top=76px` (true **24**), `bottom` swings **23→73** |
| Output ÷ expected height | **0.21×** | **0.48×** |

Both failures trace to **one** design flaw: *offset matching and chrome detection both run
on the full frame, and the static chrome corrupts both.*

- **Gap 1 — matching is chrome-biased.** `PositionTracker.process` matches full-frame
  profiles (`PositionTracker.swift:99`). Static, high-variance chrome (title text, tab
  icons) only aligns at `dy=0`, so on low-contrast content the best offset is pulled to
  zero, the tracker never advances, and the entire capture is lost. This happens **live in
  the extension**, so it must be fixed there.
- **Gap 2 — chrome handling is unreliable and mis-applied.** `ChromeDetector` runs on a
  single keyframe pair and is inaccurate/inconsistent (76 vs 24 px; 23→73). The
  `Compositor` then crops using only `refinedSeams.first`'s chrome, applied globally
  (`Compositor.swift:189-190`). Content is over-cropped (or, with real moderate-variance
  content, chrome+content are stacked).

### Prior art (research)

- Longshot's core matcher is **validated**: the column-sampling + MAD + predicted-offset
  technique in `baotlake/screenshot-splicing` and `wayscrollshot` is essentially
  `VerticalProfile` + `OffsetMatcher`. Keep the core; fix the wiring.
- **No drop-in solves auto chrome detection from pixels.** Tools that handle sticky headers
  cleanly (`Z7Lab/scrollshot`) use the **DOM** (hide `position:fixed` elements) — a signal
  unavailable from ReplayKit pixels. Pixel-only tools punt to user region selection.
- The principled technique (motion segmentation; patent US 8,411,738) identifies the
  scrolling region by **constant vertical motion across two or more frames** — i.e.
  *multi-frame consensus*, which is exactly why single-pair detection fails.

## Solution

Make the **scrolling content band a first-class, segment-stable concept**, detected via
**multi-frame consensus with an adaptive bootstrap**, and use it everywhere:

1. **Restrict offset matching to content-band rows** (chrome masked out) — fixes Gap 1.
2. **Detect one stable `ContentBand` per segment** by accumulating per-row static votes
   across frames — fixes Gap 2's inaccuracy/inconsistency.
3. **Crop chrome from the segment's locked band** in the compositor — fixes Gap 2's
   first-seam-only application.
4. **Manual override in the editor** — every mature tool provides a region fallback.

### Detection policy: locked band, adaptive bootstrap

- **Bootstrap (before lock):** from frame 2, exclude rows that are static vs the previous
  frame from the match, so matching is unbiased from the *first* scroll (kills the
  catastrophic startup stall with no fragile window).
- **Consensus + lock:** accumulate per-row "static across moving frames" votes; once a
  stable band emerges, **lock** it for the segment and drive steady-state matching and the
  compositor crop from the locked value (stable, testable, clean seams).
- **Change handling:** a sustained sharp change in the band (collapsing header settling,
  keyboard) → **segment break** (already supported) for the first cut; adaptive re-lock of
  the new steady state is a later enhancement, not required for this fix.

This spends adaptive's strength at startup and locked's strength in steady state, and
avoids adaptive's small-motion over-masking (the same confusion that produced 76 vs 24 px)
because the *lock* governs steady state, not a noisy per-frame mask.

## Components

1. **`ContentBand` (new model, StitchKit)** — `{ topChrome: Int, bottomChrome: Int }` in
   source pixels, per segment. The scrolling content is rows `[topChrome, height −
   bottomChrome)`.

2. **`ContentBandDetector` (evolve `ChromeDetector`)** — accumulates per-row static votes
   over moving frames; exposes (a) an adaptive per-pair static mask for bootstrap, (b) a
   locked `ContentBand` once consensus is confident, (c) a "band changed sharply" signal
   for segment breaks. Multi-frame, not single-pair.

3. **`OffsetMatcher` / `PositionTracker`** — accept a restricted row range / mask so chrome
   rows are excluded from the weighted MAD. Bootstrap uses the adaptive mask; post-lock uses
   the locked band. The tracker owns the detector lifecycle per segment.

4. **`Compositor`** — crop using the segment's locked `ContentBand` (not
   `refinedSeams.first`); keep pixel-exact refinement within the content band. The
   missing-seam fallback must not draw full frames.

5. **Manifest / contract (`StitchSession`)** — store one `ContentBand` per segment (segments
   already exist via `SegmentBreak`). Deprecate/remove per-seam `chromeTopPixels`/
   `chromeBottomPixels`. Decode defaults so older manifests still load
   (`StitchSession.init(from:)` pattern).

6. **`EditView`** — expose the detected top/bottom chrome as user-adjustable, re-compositing
   non-destructively (mirrors the existing global trim).

## Data flow

```
extension: frame → VerticalProfile → ContentBandDetector (bootstrap mask / lock)
                 → OffsetMatcher(content rows only) → PositionTracker → FrameSelector
                 → keyframes + seams + per-segment ContentBand → manifest (App Group)
app:       manifest + keyframes → Compositor(crop by segment ContentBand, refine within band)
                 → long image; EditView can adjust the band and re-composite
```

## Error handling

Follows the project rule (never swallow silently). Detection failure is *surfaced, not
masked*: if no confident band locks for a segment, treat `topChrome = bottomChrome = 0`
(whole frame is content — safe, chrome merely repeats rather than content being lost),
flag the segment `isLowConfidence`, and rely on the editor override. No `try?`/`?? default`
that hides a real failure.

## Testing (TDD)

- **Acceptance:** `ChromeStitchReproTests` (already RED) must go GREEN — output height ≈
  unique content (±10%) for both high- and low-variance content. Extend with assertions
  that chrome appears once (top and bottom) and a unique content marker appears once.
- **Unit:**
  - `ContentBandDetector`: synthetic frames with known chrome → band ≈ `{24,20}`; robust to
    a noisy single pair; consensus stabilizes over frames.
  - `PositionTracker`: low-variance content no longer stalls (advances from frame 1 via
    bootstrap); locked band restricts matching.
  - `Compositor`: multi-keyframe (>2) with a locked band crops chrome once; missing-seam
    fallback does not stack full frames.
  - Collapsing-header sequence → segment break or re-lock.
- **Regression:** existing 55 StitchKit tests stay green; app + extension `xcodebuild`
  green.

## Implementation slices (sequential, each TDD-green)

1. **Row-range/mask in `OffsetMatcher`** — restrict the weighted MAD to a row range; unit
   tests. (pure)
2. **`ContentBandDetector`** — consensus lock + adaptive bootstrap mask + change signal;
   unit tests. (pure)
3. **Wire into `PositionTracker`** — detector lifecycle per segment; bootstrap then locked
   matching; low-variance no-stall test. (pure)
4. **Manifest contract** — per-segment `ContentBand`; graceful decode; update
   `SampleHandler` to detect/lock and write it.
5. **`Compositor`** — crop by segment band; fix missing-seam fallback; multi-keyframe tests;
   `ChromeStitchReproTests` GREEN.
6. **`EditView`** — manual band adjustment, non-destructive re-composite.

## Out of scope

- Replacing the MAD matcher with Vision `VNTranslationalImageRegistrationRequest` (core is
  validated; not needed for this fix).
- Horizontal scrolling / horizontal chrome (side bars).
- Driving the scroll automatically (Longshot is capture-only, user scrolls).
