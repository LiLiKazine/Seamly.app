# 2026-07-25-04: Refuse an implausible ContentBand instead of clamping it

**Status:** Implemented

## Context

Nothing validated a `ContentBand`. `Compositor.plan` clamped whatever it was handed:

```swift
let band = max(1, h - chromeTop - chromeBottom)
let dy   = min(max(rawDy, 1), band)
```

If `topChrome + bottomChrome` approached the frame height, `band` degraded to `1`, every
seam was clamped to a 1px advance, and the composite collapsed to roughly one frame tall —
with no throw, no log, and no user-visible signal. Filed as issue #7 after an over-detected
band (bottom chrome measured 240px against a true 20px) produced 272px where 1244px was
expected, while the manifest still read as entirely healthy.

While working the issue backlog, `SeamlyTests/BatchAssemblyTests.importReordersScrambledKeyframesAndStitches`
turned out to be failing on `main` — undocumented, not a `withKnownIssue`. Probing it gave
the exact same signature, and made it a live in-repo reproduction of #7:

```
height=362  expected=640
order=[kf-top, kf-mid, kf-bot]   breaks=[]   orderAssumed=false
seams=[(0, dy=140, conf=1.0, lowConf=false), (1, dy=140, conf=1.0, lowConf=false)]
bands=[(topChrome: 361, bottomChrome: 0, isLowConfidence: false)]
```

Order recovery perfect, both seams pixel-exact at full confidence — and a **361px top chrome
band on a 360px frame**, flagged as confident. Exactly the failure mode #7 describes: a
detectable measurement failure converted into a plausible-looking wrong image.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep clamping (status quo) | No change | The bug: silently collapses the stitch, masks every future chrome-detection regression |
| Throw `CompositorError` on an implausible band | Loudest possible signal; impossible to ignore | A capture already on disk with a bad band becomes undisplayable. Content disappearing is the worse failure, and the project's stated stance is that repeated chrome beats lost content |
| Tune the detector so it stops over-detecting | Fixes the root measurement | Not achievable here — see "What Was Discovered". The detector has no way to know it is wrong, and `translucencyMeanCeiling`'s own doc records why the shape test alone can't be tightened safely |
| **Refuse the band, degrade to `.unlocked` (chosen)** | Reuses vocabulary the codebase already models: whole frame is content, chrome repeats, segment flagged `isLowConfidence`, editor override available. Surfaces through `Capture.lowConfidenceBandCount`, which already exists | Doesn't repair the underlying measurement — a capture that hits this crops no chrome at all |

## Decision

Treat a band occupying more than `ContentBand.maxChromeFraction` (50%) of the frame as a
measurement failure and degrade to `.unlocked`, at both the measurement site
(`BatchStitcher.chromeBand`) and the compositing site (`Compositor.plan`).

## Rationale

`.unlocked` already means precisely "no confident band — whole frame is content, flagged for
the editor". An implausible measurement *is* an absence of a confident band, so this needs no
new concept and inherits the existing UI surfacing for free.

The ceiling is deliberately loose. It cannot distinguish a slightly-wrong band from a right
one — nothing here knows the true answer — so it is set only to catch measurements that
cannot be chrome at all. Real chrome measures 2–8% per edge on the `youtube-*`, baidu, and
wikipedia fixtures; 50% leaves enormous headroom.

Guarding at **both** sites is intentional and they are not redundant. `BatchStitcher` stops a
bad band from ever being written to a manifest. `Compositor` covers what `BatchStitcher`
cannot vet: manifests persisted before this check existed, and bands the editor's override can
produce.

## What Changed

- `ContentBand.swift` — added `maxChromeFraction` and `isPlausible(forFrameHeight:)`, one
  definition shared by both call sites.
- `BatchStitcher.chromeBand` — returns `.unlocked` when the measured band exceeds the ceiling.
  Checked in profile rows (the space it was measured in) so `sourcePixels`' outward rounding
  cannot slip a rejected band back under.
- `Compositor.plan` — validates the segment's band against the frame height and substitutes
  `.unlocked` rather than clamping. Hoisted `let h` above the band decision.
- `CompositorTests` — three tests: an absurd band no longer collapses the stitch; a
  large-but-credible band (33%) is still cropped; unit coverage of the plausibility boundary.
- `BatchStitcherTests` — a test driving the exact frames that produced the 361-on-360 band.

## What Was Discovered

- **The synthetic fixture defeats the translucency test, and that is not fixable by tuning.**
  The generator is `60 + y·(120/H) + 50·sin(0.35x) + 25·sin(0.2y + 0.15x)`. Comparing row *i*
  of two frames 140px apart: the vertical ramp shifts the mean by ~0.10 luminance, which
  clears `meanTolerance` (0.02) but lands **under** `translucencyMeanCeiling` (0.20); the
  dominant `50·sin(0.35x)` term is identical in every row of every frame, so the mean-centered
  signature difference stays under `structureTolerance`; and variance is dominated by that same
  shared term, so it matches too. All three gates pass on **every** row → the whole frame reads
  as translucent chrome. This is the exact hazard `translucencyMeanCeiling`'s doc comment warns
  about ("content whose horizontal pattern repeats identically row to row"), just with a mean
  shift small enough to slip under the ceiling rather than far above it.
- **A guard was the right layer precisely because the detector can't self-diagnose.** Raising
  `translucencyMeanCeiling` would break real translucent-bar detection, which the `youtube-*`
  measurements pin at ≤0.051; lowering `structureTolerance` would clip the top of real bars.
  There is no setting that distinguishes this content from a real bar on shape and brightness
  alone. What *is* unambiguous is the conclusion — "every row is chrome" — so that is what gets
  rejected.
- **`topChrome` could exceed the frame height.** 361 > 360, because `sourcePixels` rounds
  outward by a row and nothing bounded the result. Worth noting even though the guard now
  makes it unreachable.
- **Verified no effect on real captures.** The stitched `youtube-*` output is **byte-identical**
  (sha256 `6618d56b…`) before and after. Real-fixture bands unchanged: `ChromeStitchReproTests`
  top=25/bottom=21 ratio 0.99, `RealFrameStitchTests` top=238/bottom=262 ratio 1.00, Baidu
  `kf=7 seams=3 breaks=3 out=9927`.
- **The app test now passes**, and `swift test` went 80 → 84 tests with the same 3 known
  issues. Both known issues are #2's direction mis-scoring and are untouched by this.
- Rejected throwing after re-reading #7's own framing: "chrome repeats" is a far better
  failure than "content disappears". Throwing would have inverted that for any capture whose
  manifest already carries a bad band.
