# Handheld screen-recording fixture

`DSNN4777.MP4` — a **6.43 s, 60 fps, 1320×2868 HEVC** screen recording (387 frames) of the same
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
