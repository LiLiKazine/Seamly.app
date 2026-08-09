# Handheld screen-recording fixtures

Three untrimmed handheld screen recordings, all **60 fps, 1320×2868 HEVC**. Each pairs with a
screenshot set of the same page, so the video tier and the photo tier can be cross-checked against
one another:

| clip | length | page | pairs with |
|------|--------|------|------------|
| `DSNN4777.MP4` | 6.43 s | Google Discover feed | `../Screenshots2` |
| `KMZK1521.MP4` | 8.50 s | Google Discover feed | `../Screenshots4` |
| `CKHQ1876.MP4` | 7.48 s | `article.95516.com` subsidy article | `../Screenshots3` |

`DSNN4777.MP4` — a **6.43 s** recording (387 frames) of the same
Google Discover feed as `../Screenshots2`, scrolled by hand in Chrome for iOS.

Unlike `../RealDevice/scroll-recording.mp4`, this clip is **not trimmed**. It contains what a real
capture contains and a hand-picked clip does not:

- a **fast flick** that advances more than half a frame between consecutively sampled frames
  (measured at 30 fps: `dy` steps 273 → 319 → 354 profile rows across two frames), and
- **pauses** where several consecutive frames are identical.

## Recovered geometry (30 fps, the cadence the app imports at)

```
decoded 138 frames, 0 failures, 9 keyframes banked
order: [0, 1, 2, 3, 4, 5, 6, 7, 8] (monotonic)
  seam 0->1  dy=1586  conf=0.699      seam 4->5  dy=1497  conf=0.779
  seam 1->2  dy=1474  conf=0.894      seam 5->6  dy=1542  conf=0.873
  seam 2->3  dy=1483  conf=0.707      seam 6->7  dy=1438  conf=0.945
  seam 3->4  dy=1479  conf=0.745      seam 7->8  dy=233   conf=0.861
  segments: 1 (continuous)
  band[0] topChrome=377 bottomChrome=238
stitched 1320x13591
```

The band matches `../Screenshots2` exactly (377 / 238) — same app, same bars — which is a useful
cross-check between the video tier and the photo tier.

## Why this recording is kept

It is the fixture that exposed the **masked overlap floor** defect. `OffsetMatcher` measured its
`minimumOverlapFraction` against the full frame while counting only the rows a mask left available,
so a masked match could not measure an offset past ~345 of 640 profile rows. A commit needs
`dy ≥ 320`, so a 25-row window was all the selector had, and this clip's flick stepped straight
over it — after which every later frame had scrolled past the one reference frame entirely.

The result was the worst kind of failure: **1 keyframe banked from a 6.4 s scroll**, no stitch at
all, and not a single structural assertion in the suite to notice, because every existing video
fixture was trimmed to a steady scroll that never crossed the window.

See `docs/logs/2026-08-08-02-masked-overlap-floor.md` and `LongScreenshotFromVideoTests`, which
asserts the product promise end to end — several overlapping keyframes, in order, composited into
one image taller than the screen — at **both** the full decode rate and the app's 30 fps.

---

# `KMZK1521.MP4` — a slow scroll that banked almost nothing

**8.50 s, 511 frames**, the same Google Discover feed as `../Screenshots4`, scrolled steadily.

Ground truth on the raw pixels (sampled at 1 fps, full vertical resolution): chrome **368 px top /
226 px bottom**, matching `../Screenshots4`'s 372 / 234 — same app, same bars. Per-second offsets
run 706 → 1824 px, so roughly 7 800 px of page passes in eight seconds.

## Why this clip is kept

It banked **3 keyframes from 8.5 s of scrolling**, and split them into two segments:

```
decoded 180 frames at 30fps, 0 failures, 3 keyframes banked
order: [0, 1, 2] (monotonic)
  seam 0->1  dy=1434  conf=0.932
  segment breaks after: [1]
  band[0] topChrome=462 bottomChrome=274
  band[1] topChrome=0   bottomChrome=0
```

This is `KeyframeSelector` losing the scroll for the same reason `DSNN4777.MP4` did — the masked
overlap floor capping how far a match can measure — but at a *higher* ceiling than the one
`docs/logs/2026-08-08-02` removed, so that fix left it in place. The lone third keyframe then landed
in a segment of its own, where `chromeBand` had no pair to measure from and returned `.unlocked`,
compositing that frame with its status bar and toolbar intact.

After `docs/logs/2026-08-09-03`:

```
decoded 180 frames at 30fps, 0 failures, 6 keyframes banked
order: [0, 1, 2, 3, 4, 5] (monotonic)
  seam 0->1 dy=1434 conf=0.932    seam 3->4 dy=1815 conf=0.835
  seam 1->2 dy=1618 conf=0.697    seam 4->5 dy=1438 conf=0.909
  seam 2->3 dy=1474 conf=0.793
  segments: 1 (continuous)        band[0] topChrome=462 bottomChrome=238
stitched 1320x10650
```

Six keyframes, one continuous segment, every seam over 0.69. The band still reads 462 px against a
true 368 px; that over-crop is absorbed by the overlap at every seam (the smallest here leaves
1 053 px against a 462 px crop) so no content is lost, but it is a real over-measurement and worth
watching. At full decode rate the same clip banks 7 keyframes and measures the band at 377 / 238,
so the over-measurement is a property of *which* frames get banked, not of the page.

`aSteadyScrollBanksKeyframesThroughout` asserts this at 30 fps, the cadence the app imports at.

**Not asserted:** at full decode rate, `BatchStitcher().plan(...)` recovers the order as
`[0, 1, 3, 2, 4, 5, 6]` — two adjacent keyframes swapped. It is left out rather than pinned because
the app never asks that question of a video: `LibraryModel.importVideo` uses `.inputOrder`, since
capture chronology is authoritative (see `BatchStitcher.OrderStrategy`). So this is a gap in how
strictly the clip is tested, not a defect in what ships — but it is a real weakness in recovery on
densely-sampled video keyframes, and the next person to touch ordering should know it is there.

---

# `CKHQ1876.MP4` — low-texture content the video tier still splits

**7.48 s, 450 frames**, the `article.95516.com` page from `../Screenshots3`, in Chrome for iOS.

Ground truth on the six keyframes the driver actually banks:

| pair | dy (px) | content overlap | runner-up margin |
|------|---------|-----------------|------------------|
| 0→1  | 1240 | 52.4% | **×1.09** |
| 1→2  | 1541 | 40.9% | ×3.08 |
| 2→3  | 1436 | 44.9% | ×2.62 |
| 3→4  | 1609 | 38.3% | ×2.28 |
| 4→5  | 669  | 74.3% | ×11.17 |

Chrome measures **175 px top / 86 px bottom** across those keyframes.

## Why this clip is kept — and what it still gets wrong

It is the hardest fixture in the repo, and it is **not fully fixed**. Current state:

```
decoded 159 frames at 30fps, 0 failures, 6 keyframes banked
  seam 0->1  dy=1497  conf=0.078  LOW CONFIDENCE     <- true dy is 1240
  seam 1->2  dy=1542  conf=0.755                     <- true 1541
  segment breaks after: [2]                          <- true dy is 1436
  seam 3->4  dy=1609  conf=0.859                     <- true 1609
  seam 4->5  dy=668   conf=0.724                     <- true 669
```

Three of the five seams are exact. Two are not:

- **Seam 0→1 lands on the wrong basin** (1497 against a true 1240). Note 1497 is within a pixel or
  two of the *raw-pixel runner-up*, 1496 — so the matcher is picking a real competing alignment, not
  inventing one. At full resolution that pair beats its runner-up by only **×1.09**: the page is a
  large flat red banner, and the evidence genuinely is close to a tie. This one is content, not code.
- **Seam 2→3 breaks** despite a true `dy=1436` that raw pixels separate by ×2.62. That margin is
  wide enough that this should be recoverable, and it is the honest open item on this clip.

Video frames of this page also score far worse than screenshots of it — MADs of 14–27 against
`../Screenshots4`'s 0.5–0.7 — because of motion blur and HEVC compression on low-texture content.

This clip additionally carries the **collapsing bottom bar** described in `../Screenshots3/README.md`,
so its toolbar is stamped mid-page for that separate, unfixed reason.

Nothing here is asserted as passing. `CKHQ1876.MP4` is deliberately *not* wired into
`LongScreenshotFromVideoTests` yet — doing so would either fail or need its assertions weakened to
the point of proving nothing, and both are worse than recording the measurements above and leaving
the clip as the next piece of work.
