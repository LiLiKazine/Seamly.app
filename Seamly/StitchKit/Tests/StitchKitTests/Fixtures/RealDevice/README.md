# Real device capture fixtures

These are **real ReplayKit broadcast keyframes** pulled off a physical iPhone 17 Pro Max
(iOS 26) via `xcrun devicectl device copy from`, downscaled to half resolution (442×959,
color preserved) for the repo. They are the regression oracle the project lacked for three
fix cycles: synthetic and static-screenshot fixtures repeatedly reported green while real
broadcast frames stitched wrong (see `docs/logs/2026-07-05-02-...`).

Both sessions were captured with the shipped (broken) pipeline and reproduced the field
failure — total shatter / stacked panels.

## `baidu-00..06.png` — Baidu feed in Safari, clean **downward** scroll (7 keyframes)

The easy case. Every consecutive pair overlaps heavily and scrolls **down** (later frames
show content further down the document). Full-pixel ground-truth vertical offsets (px, at
this fixture's half resolution — all **positive** = downward):

| pair | dy (px) |
|------|---------|
| 0→1  | 583 |
| 1→2  | 375 |
| 2→3  | 169 |
| 3→4  | 537 |
| 4→5  | 425 |
| 5→6  | 573 |

The shipped pipeline produced **0 seams / 7 segments** on this (manifest recovered from the
device). A correct pipeline stitches it into essentially one segment.

## `wechat-00..04.png` — WeChat, capture started before the app opened (5 keyframes)

- `wechat-00`: iOS home screen
- `wechat-01`: app-launch animation (WeChat zooming in)
- `wechat-02..04`: WeChat chat list, scrolling **down**

Ground-truth offsets (px): 0→1 = −767, 1→2 = −679 (home/launch genuinely do **not** overlap
the list — spurious negative "best" matches), 2→3 = +175, 3→4 = +25 (the real list scroll).
This exercises the "junk pre-app frames must not corrupt tracking / must segment off" case.

## `youtube-00..05.png` — YouTube feed, **translucent bottom tab bar** (6 keyframes)

Six committed keyframes from an iPhone 17 Pro Max (iOS 26) screen recording of the YouTube
feed, decoded through `VideoKeyframeSource` at the app's 30fps cadence and stored at half
resolution (660×1434). A single clean downward scroll.

The point of this set is the **translucent** tab bar. Unlike the opaque chrome in the sets
above, its pixels change frame to frame as bright thumbnails scroll behind it, so per-row
*mean* comparison reads it as moving content:

| bottom-edge row | Δmean (pairs 0-1 … 4-5) | Δvariance | Δ centered signature |
|---|---|---|---|
| 639 | 0.003, 0.002, **0.049**, **0.023**, **0.051** | ≤ 0.0007 | ≤ 0.024 |

Three of five pairs blow past the 0.02 mean tolerance while the variance and the
*mean-centered* shape barely move — the signature that `ContentBandDetector`'s
`structureTolerance` keys on. Ground truth: the bar's top edge sits ~124px above the frame
bottom; rows inside the bar keep a centered difference ≤ 0.057 while the first real content
row jumps to ≥ 0.449.

Before the fix this set produced `bottomChrome == 0` — the bar baked into the stitch once per
keyframe, hiding the content beneath each copy — plus a thin dark line at every seam from
rounding the band to the nearest profile row. See `TranslucentChromeTests`.

## Regenerating / full-resolution

Full-resolution raw BGRA originals (884×1918) were pulled from the app container at
`Library/Application Support/Seamly/sessions/<uuid>/`. The half-res color PNGs here
preserve the color/gamma content that drives the matcher, at a fraction of the size.
