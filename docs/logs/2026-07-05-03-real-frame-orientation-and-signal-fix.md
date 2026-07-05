# 2026-07-05-03: The real reason on-device stitching was broken — profile orientation + a degenerate match signal

**Status:** Implemented (matcher + compositor fixes proven on real device frames; full
end-to-end stitch pending a dense live-frame capture)

Follow-up to [2026-07-05-02](2026-07-05-02-on-device-stitching-state.md), which recorded
that the pipeline still shattered real captures despite two prior green-on-synthetic fixes.

## Context

Three fix cycles all went green on synthetic / static-screenshot fixtures while the device
stayed broken. The missing ingredient every prior log named was **an oracle built from real
broadcast frames**. This time we got one: the actual failing captures were pulled straight
off the device with `xcrun devicectl device copy from --domain-type appDataContainer
--source "Library/Application Support"` (the full-container copy aborts on a locked
`Library/SplashBoard` file; the subpath copy works). Two real sessions (884×1918 raw BGRA
keyframes + `manifest.json`):

- **Baidu feed in Safari** — a clean 7-frame *downward* scroll. Device manifest: **0 seams,
  6 segment breaks** → total shatter.
- **WeChat** — recording started before the app opened: home screen, app-launch animation,
  then the chat list. Device manifest: a garbage `dy=2124` (> frame height = zero overlap)
  committed as a seam, then breaks.

## Root cause (reproduced on the real pixels, not theorized)

Two coupled defects, both invisible to the synthetic fixtures:

1. **Profile orientation was inverted.** `VerticalProfile.renderGray` flipped the frame
   (`translateBy`/`scaleBy(-1)`), producing a **bottom-up** profile for a real (top-down)
   frame. So a real *downward* scroll matched as a **negative** (backward) offset; the
   extension writes `max(0, dy)` seams and the tracker only appends on forward motion, so
   every real forward scroll was skipped → lost lock → shatter. The synthetic fixtures were
   themselves built upside-down (`TestImages.make` relied on `makeImage`'s flip; other
   builders used `dst = height-1-r`), so *two* flips cancelled and synthetic tests passed
   while real frames — correctly oriented — inverted. The one "real screenshot" test
   (`wikipedia.png`) also missed it because it windowed content with **bottom-referenced**
   `CGImage.cropping`, running its scroll the opposite way from a real capture.

2. **The match signal was degenerate.** `OffsetMatcher` compared a per-row **mean+variance**
   only. Real feed content (rows of similar brightness) makes a downward scroll score no
   better than its mirror, so incidental factors (the flip's sampling phase, gamma) decided
   the winner. A full-resolution pixel MAD picks the true offset with a decisive ~4× margin;
   the mean-only profile threw that margin away.

3. **A latent compositor bug** the orientation fix exposed: `Compositor.drawStrip` placed
   strips with a top-left mental model in a bottom-left context, **vertically block-reversing
   multi-piece segments**. A single full-frame keyframe filled the context so it looked right
   (why single-frame and symmetric-fixture tests passed), but every real multi-keyframe
   stitch came out segment-reversed — exactly the field report "the scrolled-to-top frame
   rendered *below* the scrolled-down frame (inverted order)."

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Tune matcher thresholds again | Small diff | Fourth cycle of tuning a degenerate signal; doesn't fix orientation |
| Flip real frames on entry, keep everything else | Localized | Compositor also consumes real frames; two code paths, fragile |
| Vision `VNTranslationalImageRegistrationRequest` | First-party | Rejected before (chrome-biased, not pixel-exact); doesn't address orientation |
| **Correct orientation + match on per-row signatures (chosen)** | Fixes both real defects; keeps the validated MAD core; decisive on real content | Wide test-fixture re-orientation (the whole synthetic suite assumed the old flip) |

## Decision

Make `VerticalProfile` produce genuinely **top-down** profiles (no flip) carrying a **per-row
luminance signature**, and have `OffsetMatcher` score a variance-weighted **2-D MAD** over
those signatures. Re-orient the synthetic test fixtures to match real top-down frames, and
fix the compositor's strip placement.

## What changed

- `FrameProfile`: carries `rows: [[Float]]` (per-row signature) plus derived `means`/
  `variances`; a back-compat `init(means:variances:…)` synthesizes 1-column rows so array-built
  matcher tests are unchanged (2-D MAD reduces to mean-MAD).
- `OffsetMatcher`: `weightedMAD` now uses `rowDifference` (variance-weighted 2-D MAD).
  `overlapPenalty` default `1.0 → 0.8` (the `1.0` knife-edge failed a legitimate ~44%-scroll
  pair; `0.6–0.9` all recover it and still reject boundary offsets).
- `VerticalProfile`: renders sRGB **RGBA**, computes BT.601 luma per row, **no flip**.
- `Compositor`: `drawStrip` maps source→output rows in the bottom-left context correctly (fixes
  the block-reversal); `columnMeans`/`applyTrim` corrected to top-referenced crops.
- Tests: re-oriented `TestImages` (upright `make`, top-referenced `crop`), `RealGeometry`,
  `RealFrameStitch`, `ChromeStitchRepro`, `CompositorTests` to the top-down model; added
  `RealDeviceStitchTests` + `Fixtures/RealDevice/` (the real-frame oracle, full resolution).

## What was discovered

- **The matcher fix is proven on real pixels:** with the bootstrap chrome mask, 5 of 6 Baidu
  pairs recover the correct offset within tolerance and **all 6 recover the correct downward
  direction** (the sign fix). The 6th (kf04→05) is a ~44%-of-frame fast scroll where a
  higher-overlap partial alignment competes; it recovers direction but underestimates
  magnitude — fast-flick / safety-cue territory.
- **A false green, caught by looking:** an earlier attempt bundled the fixtures at *half*
  resolution. That changed `rowScale` (1.5 vs the device's 3.0) and the downsample, so the
  half-res oracle passed while compositing the **full-res** frames end-to-end still produced
  stacked, duplicated segments. Only rendering the real output and inspecting it caught this —
  the exact meta-lesson. Fixtures are now full resolution.
- **Sparse keyframes can't validate the full stitch.** These fixtures are the committed
  keyframes of the *broken* capture, so their frame-to-frame gaps are huge (kf00→01 ≈ 1165 px,
  ~60% of a frame). On such gaps the correct match reads low-confidence (feed periodicity) and
  the segment breaks — arguably correct (fast scroll → segment). A normal-speed **live**
  capture yields dense frames that stitch. So `cleanDownwardScrollStitchesIntoOneSegment` is a
  documented `withKnownIssue` pending a dense live-frame oracle; the strong, faithful assertion
  is the matcher recovering correct downward offsets on real frames.
- **Grayscale was a red herring.** An intermediate hypothesis blamed `DeviceGray` gamma; a
  controlled {flip}×{grayscale} test showed grayscale does not affect the match sign — the flip
  does. (We still switched to explicit BT.601 luma as it's simpler and predictable.)

## Follow-up

- Add an extension **frame-trace** debug mode so a live capture records every processed frame
  (not just keyframes) → build the dense-frame oracle and promote the `withKnownIssue`.
- Handle the WeChat "recording started before the app" case (pre-app frames should segment off,
  not corrupt tracking).
- On-device verification of a fresh capture (the user's part).
