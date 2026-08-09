# Screenshot fixtures with a very large scroll step

Five **real screenshots** taken with the iOS screenshot shortcut while scrolling a Google Discover
feed in **Chrome for iOS** (dark mode), at native resolution **1320×2868** — the same app and the
same bars as `../Screenshots2`, scrolled much harder.

`IMG_1870` … `IMG_1874` — **ascending filename order is scroll order, top→bottom.** Verified by
rendering the stitch (`swift run stitch-cli images <this dir>`): one continuous page, every seam
clean at full resolution.

## Ground truth

Measured on the **raw pixels** at full vertical resolution — not through `VerticalProfile`, which
is the independent yardstick the profile-space measurement is checked against.

| rows        | px   | what |
|-------------|------|------|
| 0…77        | 78   | status bar, identical in all five |
| 78…117      | 40   | clock and status icons — **differ between shots** |
| 118…371     | 254  | rest of the status bar + the omnibox, identical |
| 372…2633    | 2262 | the scrolling content |
| 2634…2867   | 234  | the bottom toolbar and home indicator, identical |

So the true chrome is **372 px top / 234 px bottom** — the same bars `../Screenshots2` measures,
which is the cross-check that this set differs from it only in how far each swipe went.

Consecutive offsets, full-resolution mean-absolute-difference over content rows only:

| pair | dy (px) | content overlap | MAD at the match |
|------|---------|-----------------|------------------|
| 0→1  | 1666    | 26.3% | 0.54 |
| 1→2  | **2159** | **4.6%** | 0.70 |
| 2→3  | 1835    | 18.9% | 0.59 |
| 3→4  | 1543    | 31.8% | 0.50 |

Every one of those is a near-pixel-perfect alignment (MAD under 1 on a 0…255 scale). Pair 1→2 is
the extreme: the swipe advanced 2159 px of a 2262 px viewport, leaving **103 rows** — 4.6% of the
page — in common. It is included deliberately as the hardest honest case in the repo, and it is
still a *correct* capture: the overlap is small but real, and the alignment is unambiguous.

> Measuring that pair needs care. A search that requires a minimum overlap to score a candidate
> will stop before reaching 2159 px and report the best offset *below* its own cutoff — which is
> how this README first recorded 2142 px, and, in profile space, the same shape of mistake the
> matcher was making. Any yardstick applied here has to be checked for its own floor.

## Recovered geometry

`BatchStitcher().plan(...)`:

| seam | dy (px) | confidence |
|------|---------|------------|
| 0→1  | 1667    | 0.884 |
| 1→2  | 2151    | 0.613 |
| 2→3  | 1837    | 0.753 |
| 3→4  | 1542    | 0.871 |

One segment, no breaks, order `[0, 1, 2, 3, 4]`. Content band: `topChrome=377 bottomChrome=238`
(the extra ~5 px each is `sourcePixels`' deliberate outward rounding of one profile row).

## Why this set is kept

It pins two defects at once, and neither is visible in a manifest.

**The masked overlap floor capped how far a match could measure.** Three of the four pairs here
have a true `dy` past the ceiling the floor imposed on a masked match — 372, 409 and 482 profile
rows against ceilings of 346, 348 and 322 — so the masked matcher discarded the correct offset
before scoring it and returned the best surviving one. Because `downwardMatch` keeps whichever
variant is *more confident*, and masking usually scores better, those wrong answers then overrode
plain matches that had found the offset correctly. Pair 0→1 is the clearest case: its overlap is
pixel-identical (MAD 0.54, a ×58 margin over the next alignment) and it scored **0.003**. The set
recovered as `[2, 3, 4, 0, 1]` with a spurious `dy=238` seam joining `IMG_1874` to `IMG_1870`.

**A segment holding one frame got no content band.** `buildPlan` measures a band from the *pairs*
inside a segment, and a lone frame has none, so `chromeBand` answered `.unlocked` — the frame was
composited with its status bar and browser toolbar intact, stamped through the middle of the page.
The broken recovery above put `IMG_1871` alone in the second segment, which is how it surfaced.

See `docs/logs/2026-08-09-03-geometric-overlap-floor.md` and `LargeScrollStepTests`.

Kept at native resolution, like every other real set here: a downscaled copy changes `rowScale` and
so the matcher's downsample, and the 40 px moving strip in the status bar is exactly the scale of
detail that would not survive it.
