# 2026-08-08-01: The chrome band has to survive a moving status bar

**Status:** Implemented

## Context

A new fixture set — `Fixtures/Screenshots2`, five real Chrome-for-iOS screenshots of a Google
Discover feed at 1320×2868 — stitched into an image with the browser's bottom toolbar stamped
**four times** through the middle of the page.

Nothing structural reported a problem. Order recovery was exact (`[0, 1, 2, 3, 4]`, monotonic),
one segment, no breaks, seam confidences 0.65–0.97. This is the failure mode `CLAUDE.md` warns
about in as many words: a stitch can clear every gate and still be plainly wrong, and only
rendering it shows that. What the CLI did report, if you were looking, was the band:

```
band[0] topChrome=81 bottomChrome=27
```

Measured on the raw pixels across all four consecutive pairs — an independent yardstick, not the
profile the detector uses — the true chrome is **372 px top / 234 px bottom**:

| rows | px | what |
|------|-----|------|
| 0…77 | 78 | status bar, identical in all five |
| 78…116 | 39 | clock and status icons — **differ between shots** |
| 117…371 | 255 | rest of the status bar + the omnibox, identical |
| 372…2633 | 2262 | the scrolling content |
| 2634…2828 | 195 | the bottom toolbar, identical |
| 2829…2843 | 15 | **differ** (`IMG_1850`→`IMG_1851` only) |
| 2844…2867 | 24 | home indicator, identical |

`BatchStitcher.chromeBand` counted static rows *inward from each edge* and stopped at the first
row that moved. At the top it stopped inside the status bar, at row 78 of 372. At the bottom the
15 px strip above the home indicator stopped it at 24 px of 234.

The root cause is not a tolerance. **A bar is not uniformly static.** Screenshots are taken
seconds apart, so a clock, a signal indicator, a battery percentage simply are not the same
pixels. Every fixture in the repo up to now was captured fast enough (broadcast keyframes,
video frames) or was lucky enough that its bars held still end to end, so an inward scan was
never tested against the ordinary case.

With `bottomChrome = 27` the compositor's strips are `[h - 27 - dy, h - 27)`, which contains the
whole toolbar — so it is copied once per keyframe. The band is also what the compositor masks out
during seam refinement, so the wrong measurement degrades matching as well.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Loosen `chromeTolerance` / `structureTolerance` so the clock rows read as static | one-line change | The clock is *genuinely different content* — mean 0.31, centered 0.16. Any tolerance loose enough to swallow it also swallows real content, and it re-opens the translucency work of 2026-07-25-01 |
| Bridge short moving runs inside the band (allow a gap of ≤N rows) | keeps the inward scan | Needs a tuned gap constant, and the constant has to hold for bars this codebase has never seen. The 39 px strip here is ~9 profile rows; nothing says the next device's isn't 30 |
| Classify rows by whether they scrolled with `dy` — content moves by the seam offset, chrome doesn't | the actual definition of content | **Unavailable at the boundary.** These screenshots overlap ~50%, so `dy ≈ 318` profile rows; row `i` of A corresponds to row `i − dy` of B only for `i ≥ dy`. The top-chrome boundary sits at row 83, far outside the correspondence region. Works for dense keyframes, not for a photo pick |
| **Content is the longest run of moving rows; chrome is everything outside it (chosen)** | no gap constant; the scrolling region dwarfs any strip inside a bar (505 rows vs 9 and 4 here) | Fails in the mirror direction: a content row that holds still splits the run, and the longer half is mistaken for all of it. Needs a guard |

## Decision

Derive the band from where the **content** is — the longest run of rows that moved in at least one
pair — and refuse the inference when a candidate band is not at least `minChromeStaticFraction`
(0.75) static, falling back to the old inward scan.

## Rationale

The failure mode the fourth option introduces is real and it is not rare — three of the six real
fixture sets produce a candidate band that must be refused:

| candidate band | static fraction | verdict |
|---|---|---|
| youtube, baidu, wechat-bottom, `Screenshots`-bottom, `Example`-none | 1.000 | real, band unchanged |
| `Screenshots2` bottom (toolbar + 15 px moving strip) | 0.923 | real, **the fix** |
| `Screenshots2` top (372 px bar + 39 px of live icons) | 0.892 | real, **the fix** |
| `Example` bottom / top | 0.482 / 0.436 | content, rejected |
| `Screenshots` top — would crop **1130 px** of page | 0.303 | content, rejected |
| `wechat` top — would crop 378 px | 0.232 | content, rejected |

0.75 sits in the middle of a 0.482–0.892 gap. That is a wider margin than
`directionalCostRatio`'s (~1.1x) and comparable to `structureTolerance`'s (8x), and unlike either
it is measured over every real set in the repo rather than one.

The asymmetry decides the bias: failing the guard costs only the older, smaller band — the inward
scan stops at the first moving row, so it can only *under*-crop, and chrome repeating is visible
and honest. Passing it wrongly deletes content permanently. Hence a fallback rather than
`.unlocked`, and a threshold set well above the highest false candidate rather than midway.

The guard is applied per edge, which is strictly better than all-or-nothing: on `Screenshots` the
top candidate is refused (0.303) while the bottom is believed (1.000), and both are correct.

## What Changed

- `Sources/StitchKit/BatchStitcher.swift` — `chromeBand` computes the static-row map once, keeps
  the inward scan as the floor, then widens each edge to the longest-moving-run boundary when
  `readsAsChrome` accepts it. New `longestMovingRun` / `readsAsChrome` helpers and a
  `minChromeStaticFraction` init parameter (default 0.75, documented with the table above).
- `Tests/StitchKitTests/DynamicChromeBandTests.swift` — new. Asserts the measured band against the
  raw-pixel ground truth; counts toolbar occurrences in the *composited pixels*; and pins the
  guard from both sides on `Screenshots` (band unchanged at 242 px with it, >1000 px without).
- `Tests/StitchKitTests/Fixtures/Screenshots2/` — the five screenshots plus a `README.md` carrying
  the row-by-row ground truth and recovered geometry.
- `Package.swift` — `Screenshots2` copied as a test resource.
- `CLAUDE.md` — fixture list mentions the new set.

Result on the fixture: band 81/27 → **377/238** (the extra ~5 px per edge is `sourcePixels`'
deliberate outward rounding of one profile row). Every other fixture's band is **byte-identical**,
which is why the suite stayed green through the change.

## What Was Discovered

- **`git`-clean structural output is not evidence.** Order, segment count, and seam confidence
  were all correct and stayed correct; the defect lived entirely in one manifest field and only
  became visible in rendered pixels. The new test therefore counts occurrences of a chrome row in
  the composite rather than asserting on the manifest alone.
- **The dy-based classifier is the theoretically right answer and is unusable here.** Content is
  "the rows that moved by the seam offset" — but with ~50% overlap the correspondence region
  doesn't reach either chrome boundary. It is viable for dense broadcast keyframes and not for the
  photo-pick shape, so it was rejected rather than deferred.
- **Content really does contain static rows, often.** The assumption that a moving run is the
  content held on `Screenshots2` and youtube, and failed on three of six sets — `Screenshots`
  splits at row 251 of a true 53. That was expected to be the theoretical worst case and turned out
  to be the common case, which is what makes the guard load-bearing rather than defensive.
- Output *height* is invariant to `bottomChrome`: the segment is `(h − chromeBottom) + Σdy +
  chromeBottom`. So a height assertion can never catch this class of bug, and neither can seam
  count. Only the pixels can.
- `Fixtures/Recordings/DSNN4777.MP4` arrived with the screenshots and is referenced by nothing;
  left untracked rather than committed as an unused 11 MB blob.
