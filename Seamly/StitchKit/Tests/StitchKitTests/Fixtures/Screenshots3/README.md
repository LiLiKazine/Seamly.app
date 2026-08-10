# Screenshot fixtures with a large scroll step and a collapsing bottom bar

Five **real screenshots** taken with the iOS screenshot shortcut while scrolling a Chinese
consumer-subsidy article (`article.95516.com`) in **Chrome for iOS** (light mode, bottom omnibox),
at native resolution **1320×2868**.

`IMG_1863` … `IMG_1867` — **ascending filename order is scroll order, top→bottom.** Verified by
rendering the stitch (`swift run stitch-cli images <this dir>`): one continuous page, every seam
clean at full resolution.

Two things make this set different from `../Screenshots` and `../Screenshots2`, and both were
captured on purpose:

1. **The swipes are long.** Consecutive shots overlap 28–54% of the page, where the earlier sets
   sit around 60–70%.
2. **The bottom bar changes shape mid-capture.** `IMG_1863` carries Chrome's full bottom toolbar
   (omnibox plus the back / forward / new-tab / tabs / menu row); by `IMG_1864` it has collapsed to
   the bare URL pill and stays collapsed. So the bottom chrome is genuinely *not* the same pixels
   across the set — the first pair disagrees there and every later pair agrees.

## Ground truth

Measured on the **raw pixels** at full vertical resolution — not through `VerticalProfile`, which
is the independent yardstick the profile-space measurement is checked against. Rows are identical
(within 2 luma) across all five frames in exactly two runs:

| rows        | px   | what |
|-------------|------|------|
| 0…188       | 189  | status bar (the clock reads 13:27 in all five) |
| 189…2779    | 2591 | the scrolling content **plus the bottom bar**, which moves because it collapses |
| 2780…2867   | 88   | home indicator |

So the chrome that holds still across the whole set is **189 px top / 88 px bottom**, and
`BatchStitcher` measures 193 / 95 — the extra ~5 px each is `sourcePixels`' deliberate outward
rounding of one profile row.

The bottom bar is *not* in that band, and that is a **known defect**, not a rounding detail:
`IMG_1863`'s expanded toolbar occupies rows the other four frames don't, so the intersection across
pairs measures only the home indicator. The ~475 px of toolbar left in `IMG_1863`'s strip is stamped
through the middle of the finished page. See "Known issue" below.

Consecutive offsets, full-resolution mean-absolute-difference over content rows only:

| pair | dy (px) | content overlap | runner-up margin |
|------|---------|-----------------|------------------|
| 0→1  | 1873    | 27.7% | ×1.01 |
| 1→2  | 1863    | 28.1% | ×2.70 |
| 2→3  | 1635    | 36.9% | ×3.22 |
| 3→4  | 1201    | 53.6% | ×4.63 |

## Recovered geometry

`BatchStitcher().plan(...)`:

| seam | dy (px) | confidence |
|------|---------|------------|
| 0→1  | 1873    | 0.160 |
| 1→2  | 1864    | 0.562 |
| 2→3  | 1636    | 0.731 |
| 3→4  | 1201    | 0.992 |

One segment, no breaks, order `[0, 1, 2, 3, 4]`. Content band: `topChrome=193 bottomChrome=95`.
Stitched output 1320×9440.

Seam 0→1 stays flagged `isLowConfidence` at 0.160, and legitimately so: this page is a large flat
red banner, and even on raw pixels that pair's best alignment beats its runner-up by only ×1.01.
The offset is right; the evidence for it is genuinely weak.

## Why this set is kept

Seam 1→2 is a `dy` of 416 profile rows out of 640, and the masked matcher **could not measure it**:
its overlap floor was a fraction of the rows the mask left, and a masked match counts only rows
that are content at both ends of the shift, so the floor capped any masked match on this pair at
`dy ≈ 290`. The true offset was discarded before it could be scored, the masked match returned 183
at confidence 0.017, and — because `downwardMatch` keeps whichever variant is more confident — that
wrong answer beat a plain match that had found the offset correctly. The chain broke there, the set
stitched as two segments, and the second segment's frames kept their bars.

This is the same defect as `docs/logs/2026-08-08-02`, which moved the floor's reference from the
frame's rows to the countable rows and so raised the ceiling from `content − 160` to
`0.75 · content`. A ceiling proportional to the countable rows is still a ceiling; this set simply
scrolls further. It is fixed by making the *fractional* floor geometric — a property of `dy` — and
leaving only the absolute signal floor to the mask. See
`docs/logs/2026-08-09-03-geometric-overlap-floor.md` and `LargeScrollStepTests`.

Kept at native resolution, like every other real set here: a downscaled copy changes `rowScale` and
so the matcher's downsample, and the overlap fractions above are exactly what the defect keys on.

## Closed regression: the collapsing bar

Order, segmentation and every offset are correct, while the bottom bar has two different heights:
expanded in `IMG_1863`, collapsed in the rest. The old segment-owned crop could not describe both.
The manifest now stores automatic chrome per keyframe UUID, so the first frame resolves to roughly
`193/431` px top/bottom and the remaining frames to roughly `193/166` px.

Note the shape of it: the bar appears **once**, not once per keyframe, so the
"toolbar occurrences" probe that guards `Screenshots2` reports `1` for both the broken and the
correct output and cannot distinguish them. `LargeScrollStepTests` therefore asks the other question:
the expanded button row must appear **zero** times. That assertion is now a hard-green pixel oracle;
the order, seam offsets, and one-segment topology are pinned alongside it.
