# Screenshot fixtures with a bar that isn't uniformly static

Five **real screenshots** taken with the iOS screenshot shortcut while scrolling a Google
Discover feed in **Chrome for iOS** (dark mode), at native resolution **1320×2868**.

`IMG_1850` … `IMG_1854` — **ascending filename order is scroll order, top→bottom.** Verified by
rendering the stitch (`swift run stitch-cli images <this dir>`): one continuous page, every seam
clean at full resolution.

## Ground truth

Measured on the **raw pixels**, worst case across all four consecutive pairs (not through
`VerticalProfile` — this is the independent yardstick the profile-space measurement is checked
against):

| rows        | px  | what |
|-------------|-----|------|
| 0…77        | 78  | status bar, identical in all five |
| 78…116      | 39  | clock and status icons — **differ between shots** |
| 117…371     | 255 | rest of the status bar + the omnibox, identical |
| 372…2633    | 2262 | the scrolling content |
| 2634…2828   | 195 | the bottom toolbar, identical |
| 2829…2843   | 15  | **differ between shots** (`IMG_1850`→`IMG_1851` only) |
| 2844…2867   | 24  | home indicator, identical |

So the true chrome is **372 px top / 234 px bottom**, and `BatchStitcher` measures 377 / 238 —
the extra ~5 px each is `sourcePixels`' deliberate outward rounding of one profile row.

## Recovered geometry

`BatchStitcher().plan(...)`:

| seam | dy (px) | confidence |
|------|---------|------------|
| 0→1  | 1425    | 0.777 |
| 1→2  | 932     | 0.974 |
| 2→3  | 1528    | 0.713 |
| 3→4  | 1412    | 0.647 |

One segment, no breaks, order `[0, 1, 2, 3, 4]`. Stitched output 1320×8171.

## Why this set is kept

Both bars contain a strip that changes between shots — screenshots are taken seconds apart, so
the clock and the status indicators simply aren't the same pixels. Every other fixture here was
captured fast enough (or cropped tightly enough) that its bars are static end to end, which let
`chromeBand` get away with scanning inward from each edge and halting at the first row that moved.
On this set that scan halts inside the status bar and reports **81 px / 27 px**, leaving the whole
browser toolbar inside every keyframe's strip — it is then stamped across the middle of the page
once per frame, while the manifest still reads as perfectly healthy (right order, one segment, no
breaks, high confidence).

That is the trap: this defect is invisible to every structural assertion and only shows up in the
pixels. See `docs/logs/2026-08-08-01-chrome-band-across-a-moving-status-bar.md` and
`DynamicChromeBandTests`, which asserts the band *and* counts toolbar occurrences in the composite.

Kept at native resolution, like `RealDevice/` and `Screenshots/`: a downscaled copy changes
`rowScale`, and the 39 px and 15 px moving strips are exactly the scale of detail that would not
survive it.
