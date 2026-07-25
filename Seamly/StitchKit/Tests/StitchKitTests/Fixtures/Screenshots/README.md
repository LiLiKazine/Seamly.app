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
| 2→3  | 1416    | **0.368** |
| 3→4  | 1533    | 0.867 |
| 4→5  | 1537    | 0.822 |

One segment, no breaks. Content band: `topChrome=242 bottomChrome=238`.

## Why this set is kept

Seam 2→3's **0.368** is the point. It sits under the 0.4 floor that `buildPlan` stamps as
`isLowConfidence`, on a chain that is otherwise complete and correctly ordered — a combination no
synthetic fixture here produces, and one the app got wrong: `StitchAssembler` read that flag as
"the recovered order can't be trusted" and fell back to the user's pick order, silently discarding
a correct order on every import. See `docs/logs/2026-07-25-08-photo-pick-order-trust.md`.

So this directory pins two things at once, and both matter:

- `ScreenshotOrderRecoveryTests` — recovery on this set is exact and **permutation-invariant**.
- `SeamlyTests/PhotoPickOrderTests` — the app must not throw that order away. It loads three of
  these by source-relative path rather than duplicating the PNGs into the app test bundle.

Kept at native resolution, like `RealDevice/`: a downscaled copy changes `rowScale` and the
matcher's downsample, and 0.368 is precisely the kind of number that would not survive it. If a
future matcher change lifts that seam above 0.4, `aCompleteChainStillCarriesALowConfidenceSeam`
fails loudly — the fixture has stopped exercising the trap and something else must.
