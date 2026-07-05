# 2026-07-05-01: Real-geometry matcher fix — why auto-detection never worked on device

**Status:** Implemented (matcher core verified end-to-end on real pixels; translucent-chrome detection still open)

Follow-up to [2026-07-04-01](2026-07-04-01-broadcast-scroll-stitching.md), whose content-band
fix went green on synthetic fixtures but did **not** work on real screens.

## Context

After the content-band stitching fix merged, the app still produced stacked screenshots on
real app screens — fixed bars repeating, content repeating, no merge — and the content band
was "never detected confidently." The prior fix's acceptance test (`ChromeStitchReproTests`)
was green, so the failure was invisible to CI.

## Root cause (reproduced, not theorized)

The bug was **geometry-dependent** and hidden by the test fixtures' geometry. The profiler
downscales each frame to 64 px wide with aspect-locked height, so
**`rowScale = sourceWidth / 64`**:

- Test fixtures (80–264 px wide): `rowScale ≈ 1.25` — essentially 1:1.
- A real iPhone frame (~1179–1206 px wide): `rowScale ≈ 18` — 18× coarser.

Every threshold in the matcher was implicitly tuned at 1:1 and collapsed at 18:1. The
content-band **detector was correct all along** — fed correct offsets it locks the true band;
the failure was one layer down in `OffsetMatcher`:

1. `minimumOverlap = 8` (absurdly small): at real geometry the matcher returned the search
   **boundary (±2400 px)** because 8 cherry-picked rows average a lower error than the true
   offset's ~600.
2. The score is a per-row average with **no overlap term**, so a partial-overlap offset ties
   the true full-overlap one — winning outright, or posing as a near-equal confidence
   runner-up.
3. Confidence used a fixed `peakExclusion = 2`: at coarse geometry the correlation valley is
   several rows wide, so the runner-up sat *inside* the valley → a correct, unambiguous match
   reported **confidence 0.23** (< the 0.3 lost-lock threshold).
4. Vertical over-downscale: a 60 px scroll spanned ~3 profile rows — below resolution.

Downstream: garbage/low-confidence offsets → the tracker false-broke every 2–3 frames → the
detector never survived the 3 moving pairs it needs → band locked `0/0` **marked
high-confidence** → compositor never cropped chrome (bars repeat) and content was lost. Exactly
the field report, including "not detected confidently."

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Tune thresholds only | Minimal diff | Doesn't address the missing overlap term or the confidence metric; brittle |
| Replace matcher with Vision registration | First-party | Rejected in 2026-07-04-01 (chrome-biased, not pixel-exact, untestable); core is validated |
| **Make the matcher geometry-robust + finer profile (chosen)** | Fixes the actual defects; keeps the validated MAD core | Four coordinated changes across two files |

## Decision

Fix `OffsetMatcher` to be overlap-aware and geometry-robust, and give the coarse profile
enough vertical resolution to resolve normal scrolls.

## What changed

- `OffsetMatcher.minimumOverlapFraction` (0.25): overlap floor as a fraction of the frame,
  rejecting the tiny-overlap boundary offsets. Kept below the ~30 % overlap a legitimate fast
  scroll still reaches (the safety-cue threshold), so real scrolls aren't rejected.
- `OffsetMatcher.overlapPenalty` (1.0): scales the score by `1 + penalty·(1 − overlapFraction)`
  so a fuller-overlap alignment is genuinely cheaper — fixes both the wrong pick and the
  confidence runner-up pollution.
- `OffsetMatcher` confidence: replaced the fixed `peakExclusion` window with a
  **prominence-based valley** (`valleyProminence`). The winning offset's valley is walked out
  to a half-prominence level and the runner-up is the best score *outside* it — high confidence
  for a single smooth valley, low for genuine periodic repeats.
- `VerticalProfile.maxRows` (640): decouples profile height from width so `rowScale ≈ 3–4 px/row`
  on a real device instead of ~18. The pixel-exact `forcingHeight` path is unchanged.
- Tests: `RealGeometryStitchTests` (matcher recovers a normal scroll at real geometry — failed
  before, returning ±2000 px) and `RealFrameStitchTests` + `Fixtures/wikipedia.png` (real
  1206×2622 screenshot windowed through the full pipeline).

## What was discovered

- **Synthetic pipeline tests are an unreliable oracle at coarse geometry.** An end-to-end test
  on synthetic content swung between 9.8× (stacking) and 0.39× (collapse) with trivial changes
  to the fixture's luma-block size or downscale filter — it was measuring fixture matching
  quirks, not the code. Block content created a *comb* of near-minima (one tread wide); smooth
  value-noise let *distant* offsets self-align; fine blocks *aliased* under nearest-neighbor
  downscale. Per the systematic-debugging discipline, this is the 3+-fixes-thrashing signal to
  stop tuning and change the oracle.
- **The real-pixel oracle passed cleanly:** windowing a real Safari/Wikipedia screenshot
  through the exact `SampleHandler` pipeline gives output ratio **1.00** (2619 vs 2622 px),
  band locks confidently (~259/209 vs a nominal 210/260 split), **0 segment breaks**, 12 frames
  → 2 keyframes. The matcher fixes work on real content; the synthetic failures were artifacts.
- **Failed experiment — area-averaging the coarse downscale (`.high`).** Reverted. It fixed the
  local aliasing but its interaction with synthetic content flipped results to under-capture;
  with real content the default nearest-neighbor downscale stitches fine, so the change was
  unjustified. Left as a candidate if device testing shows phase noise.
- **Translucent chrome — reproduced, now a tracked known gap.** Added
  `stitchesRealScreenshotWithTranslucentChrome`: the real content is composited under a blurred,
  semi-transparent bar so the chrome band's pixels change every frame. Result: the band **can't
  lock** (`0/0`, low-confidence) and chrome/segment repetition inflates the output to ~1.64×.
  This is the design's stated fallback (surface-don't-mask): content is **not lost** and the
  segment is flagged low-confidence for the editor override — but automatic cropping doesn't
  happen. Encoded as `withKnownIssue` (hard-asserting only the must-hold contract: content not
  lost, capture not shattered) so CI stays green and auto-flags if translucent detection is later
  solved. Pixel-only translucent detection is genuinely unsolved (DOM-based tools hide
  `position:fixed`; that signal is unavailable from ReplayKit pixels) — a distinct future effort.
- **Ultimate confirmation** is still a real capture through the ReplayKit broadcast on device.
