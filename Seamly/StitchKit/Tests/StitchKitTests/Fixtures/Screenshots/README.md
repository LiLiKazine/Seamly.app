# Photos-app screenshot fixtures

Six **real screenshots** taken with the iOS screenshot shortcut (not ReplayKit) while scrolling
a Google Discover feed in Safari, at native resolution **1320×2868**. This is the "From Photos"
import shape: a handful of overlapping full-frame captures with large gaps between them, rather
than the dense, closely-spaced keyframes in `RealDevice/`.

`IMG_1757` … `IMG_1762` — **ascending filename order is scroll order, top→bottom.** Verified by
rendering the stitch (`swift run stitch-cli images <this dir>`): it reads as one continuous page,
every seam clean.

## Recovered geometry

`BatchStitcher().plan(...)` on all six, in any input permutation:

| seam | dy (px) | confidence |
|------|---------|------------|
| 0→1  | 1326    | 0.727 |
| 1→2  | 1636    | 0.613 |
| 2→3  | 1416    | **~0.726** |
| 3→4  | 1533    | 0.867 |
| 4→5  | 1537    | 0.822 |

One segment, no breaks. Content band: `topChrome=242 bottomChrome=238`.

## Why this set is kept

Seam 2→3 historically scored **0.368**, below the shipping 0.4 flag threshold, on a chain that was
otherwise complete and correctly ordered. That exposed an app policy bug: `StitchAssembler` read
the seam flag as "the recovered order can't be trusted" and fell back to pick order. After the
masked-overlap-floor fix the same seam and offset score about **0.726**. The regression tests inject
a 0.8 flag threshold so the original condition remains non-vacuous without recording 0.368 as a
current measurement. See `docs/logs/2026-07-25-08-photo-pick-order-trust.md`.

So this directory pins two things at once, and both matter:

- `ScreenshotOrderRecoveryTests` — recovery on this set is exact and **permutation-invariant**.
- `SeamlyTests/PhotoPickOrderTests` — the app must not throw that order away. It loads three of
  these by source-relative path rather than duplicating the PNGs into the app test bundle.

Kept at native resolution, like `RealDevice/`: a downscaled copy changes `rowScale` and the
matcher's downsample. `aCompleteChainStillCarriesALowConfidenceSeam` uses the real pixels with an
injected 0.8 threshold and fails loudly if the fixture stops exercising the policy trap.
