# 2026-07-25-01: Translucent chrome defeats static-row band detection

**Status:** Implemented. Covers every path that produces a finished stitch. The unfixed
incremental-consensus case is `PositionTracker`-only, which has no production callers — see
"What Was Discovered".

## Context

Running a real iPhone 17 Pro Max screen recording of the YouTube feed (iOS 26, 8.4s, 1320×2868)
through the "From Video" pipeline produced a stitch that passed every structural gate the suite
has — 0 decode failures, monotonic order `[0..5]`, no segment breaks, seam confidences 0.756–0.936,
all five offsets pixel-exact against a full-width brute-force search — and was still visibly wrong.
The translucent bottom tab bar was baked into the output **six times**, once per keyframe, hiding
the content beneath each copy (a video title row, an "Explore more" button, most of two thumbnails).

`contentBands` reported `top=188 bottom=0`. `BatchStitcher.chromeBand` classifies a row as chrome
only when both its mean and its variance hold within `chromeTolerance` (0.02) across *every*
adjacent pair. A translucent bar is a blur material: as bright thumbnails scroll behind it, its row
means shift by up to **0.051** (2.5× tolerance) while its variances stay within **0.0007**. The mean
term rejects it, the band collapses to zero, and nothing gets cropped.

This was already known in the abstract —
`RealFrameStitchTests.stitchesRealScreenshotWithTranslucentChrome` documents it as
"pixel-only translucent detection is unsolved (see 2026-07-05-01)" — but with a synthetic fixture
and no discriminator. iOS 26 makes it the common case rather than an edge case: system bars are
translucent by default.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Loosen `meanTolerance` | One-line change | No safe value exists: the bar's mean shift (0.051) overlaps real content's. Measured 0.06/0.10 both land on the correct band here, but only because *this* content happens to differ elsewhere — it removes the discriminator rather than fixing it |
| Consensus voting instead of unanimity (mirror `consensusBand`'s `staticFraction`) | Reuses an existing, proven idea | Doesn't work: only 2 of 5 pairs read the bottom rows as static (0.4), below the 0.7 threshold. Unanimity isn't the problem; the *measure* is |
| Drop the mean term, keep variance only | Detected the band correctly (54 rows, stable across a 3.3× threshold range) | Variance alone can't distinguish a flat *content* band at the frame edge from flat chrome — it discards real signal |
| Mean-centered signature comparison alone | Isolates the right property; measured gap on `youtube-*` is ~8× (chrome ≤ 0.057, first content row ≥ 0.449), identical at full and half resolution | **Insufficient on its own** — see the follow-up below. Content whose horizontal pattern repeats identically row to row scores *exactly* 0, so it reads as chrome |
| **Centered signature + a bounded brightness shift (chosen)** | Requires both halves of the physical signature: shape preserved *and* brightness moved only as far as a blur material plausibly tints. Separates both failure directions | Two constants instead of one; needs a guard for single-sample rows |

## Decision

Add `structureTolerance` to `ContentBandDetector` and an `allowingTranslucency:` parameter on its
`isStatic`, which accepts a row whose mean-centered signature is unchanged even when its mean
moved. **Only `BatchStitcher.chromeBand` passes `true`.** Separately, convert the static-row count
to source pixels by rounding *outward* one profile row instead of to nearest.

## Rationale

The centered-signature measure is the only option that separates the two cases on a physical
property rather than a tuned threshold: a blur material's brightness tracks its backdrop while its
own structure (icons, labels) stays put. The measured margin is ~8× and resolution-independent
(signatures are always 64 columns), so `0.15` sits in the gap with ~2.7× headroom above chrome and
~3× below content rather than hugging either edge.

Scoping it to the batch path is not a compromise but the correct blast radius, and it is
*sufficient*: `StitchAssembler.resolveGeometry` re-derives geometry with `BatchStitcher` at import
for **every** source (broadcast included, `LibraryModel.swift:200`) and overwrites `contentBands`.
Stronger still — the shipping capture path never computes a content band in the first place (see
"What Was Discovered"), so there is no second implementation left holding the old behaviour.

`chromeBand` now calls `ContentBandDetector.isStatic` rather than inlining its own copy of the
comparison. The duplication was the mechanism of this bug: two implementations of "is this row
static" that could drift, and did.

## What Changed

- `Sources/StitchKit/ContentBandDetector.swift` — added `structureTolerance` (default 0.15) and
  `centeredDifference`; `isStatic` gains `allowingTranslucency:` (default `false`, so every existing
  caller is byte-for-byte unchanged) and is no longer `private`.
- `Sources/StitchKit/BatchStitcher.swift` — `chromeBand` delegates to `ContentBandDetector.isStatic`
  with `allowingTranslucency: true`; new `sourcePixels(_:rowScale:)` rounds the band outward.
- `Tests/StitchKitTests/TranslucentChromeTests.swift` — new suite: the discriminator in isolation,
  the single-column guard, plus two fixture tests (band detected; no residual bar at seams).
- `Tests/StitchKitTests/Fixtures/RealDevice/youtube-00..05.png` — new fixture (6 half-res keyframes,
  4.7MB) + README section with the measured deltas.
- `Tests/StitchKitTests/RealFrameStitchTests.swift` — reframed the known-issue comment: the gap is
  now specifically capture-time, and why it can't be closed the same way.
- `Sources/stitch-cli/` + `Package.swift` — new `stitch-cli` executable (`video` / `images` modes).

## What Was Discovered

- **Follow-up (same day): the shape test alone over-cropped, and the fixtures couldn't see it.**
  Pointing `ChromeStitchReproTests` at the shipped path (see 2026-07-25-02) immediately collapsed it:
  output 272px against 1244px expected, because `chromeBand` measured bottom chrome as **240px when
  the truth is 20px**. Cause: that fixture's `lowVarDoc` gives every row the *same* horizontal
  pattern (`c % 7 == 0`) and varies only per-row brightness — so its centered difference is
  **exactly 0.0000** while its mean shifts by **0.486–0.773**. Identical shape, different brightness
  is the translucency signature, so real content was cropped as chrome.

  This was a genuine production regression, not a test artifact: before the change the mean test
  correctly rejected those rows. It was invisible because these suites did not exercise `chromeBand`
  at all — the only fixture that did was `youtube-*`, which happens not to contain such content.
  Fixed by requiring **both** halves of the signature: `translucencyMeanCeiling` (0.20) bounds the
  brightness shift, since a blur material tints toward its backdrop but cannot swing 0.5. The bar
  measures ≤ 0.051 and that content ≥ 0.486, so the ceiling sits ~4× above one and ~2.4× below the
  other. After it: `ChromeStitchRepro` bands land at 25/21 against a truth of 24/20 (output ratio
  0.99), and the `youtube-*` band is unchanged at 247px.

  Lesson worth keeping: "the intersection across all pairs protects against over-cropping" was
  wrong, and one real fixture was not enough to establish it. The adversarial low-signal synthetic
  fixture caught what the realistic one could not.
- **A legacy capture tier is still acting as the project's regression oracle.** Verifying the
  paragraph above turned up something broader: `PositionTracker` (240 lines) and `FrameSelector`
  have **no production callers** — `PositionTracker` appears outside its own file only in doc
  comments and 5 test files, and `FrameSelector` not even in a doc comment. The shipping path is
  `SampleHandler` → `ScrollCaptureDriver` → `KeyframeSelector`, and `KeyframeSelector` touches
  `ContentBandDetector` only via `staticMask` — so **live capture never computes a content band at
  all**. `ContentBandDetector`'s whole consensus half (`observe`, `lockedBand`,
  `bandChangedSharply`, and the `motionThreshold` / `minMovingFrames` / `staticFraction` /
  `jumpThreshold` parameters, plus 5 of its 7 tests) is reachable only from `PositionTracker`.

  This matters beyond dead code: `RealFrameStitchTests` and `ChromeStitchReproTests` both label
  their `buildSession` helper a "Faithful mirror of SampleHandler's capture → session pipeline",
  and that claim is now **false** — those are the real-device oracles, and they validate a pipeline
  the app no longer ships. It explains why the translucent-chrome `withKnownIssue` could not be
  promoted by this fix. Not addressed here (deleting a tracker plus rewriting four test suites onto
  the shipped path is well outside a cropping fix); flagged for a decision.
- **Enabling the structural test on the incremental consensus path breaks it.** `observe` /
  `bandChangedSharply` count contiguously inward and lock only when two successive candidates
  agree. A scrolling vertical *gradient* is a near-uniform brightness shift with its horizontal
  shape intact — indistinguishable from translucency by this measure — so the band creeps into
  content by a different amount each pair and never locks. This regressed `ChromeStitchReproTests`
  and `stitchesRealScreenshotScroll` from a correct band to `0/0, isLowConfidence`. Reverted;
  closing the live gap needs a gradient-vs-translucency discriminator, not this one.
- **Widening `staticMask` costs overlap edges.** The mask feeds `OffsetMatcher`; masking the bar's
  54 rows out of the match cost pair 3-4 its edge and split the capture into two segments.
  `downwardMatch` picks between the masked and unmasked match on confidence alone ("the mask helps
  some real pairs and flips the sign on others"), so that interaction needs its own measurement pass.
- **A second, independent defect was masked by the first.** With `bottomChrome == 0` the band's
  *quantization* never mattered. Once detection worked, a ~5px sliver of the bar's dark top edge
  remained in every strip — the band is measured on 4.48px profile rows and was rounded to nearest
  (54 rows → 241px, cutting at y=2627 when the bar starts at ~2622). The hard cut baked that sliver
  in as a thin dark line at every seam. Sweeping the value shows a cliff: cb ≤ 241 → seam
  discontinuity 0.33–0.36; cb ≥ 246 → ≤ 0.008. Rounding outward gives 247.
- **Synthetic fixtures for this are easy to get wrong, in a silent direction.** Three attempts at
  "content" rows accidentally reproduced the translucency signature and made the test vacuous:
  `(c + seed) * k % m` shifts by a *constant* (cancels under mean-centering); two independent
  random rows share a mean *and* variance (static under any of these tests); and low-amplitude
  texture shrinks the centered difference below tolerance regardless of correlation. Content must
  differ in mean *and* carry wide-amplitude texture. The real fixture is the load-bearing test.
- **The single-column guard is load-bearing, not defensive.** The mean-only `FrameProfile`
  initializer gives each row one sample, which centers to `[0]` in both frames — so without the
  `count > 1` guard every row with a steady variance reads as chrome. Verified by removing it:
  `ContentBandDetectorTests.staticMaskExcludesChromeAndKeepsContent` fails with `mask → nil`.
- **`Compositor` output height is independent of `bottomChrome`** (`h + Σdy` either way) — the band
  shifts *which* strip is sampled (`h - chromeBottom - dy`), not its size. An unchanged height is
  therefore not evidence that a band change had no effect.
- Pre-existing, unrelated to this change: `plan(_:)` order recovery still breaks this fixture after
  slot 1 while `plan(_:assumingOrder:)` does not — the deferred direction-mis-scoring issue from
  2026-07-23-01, reproduced on a second real capture.
