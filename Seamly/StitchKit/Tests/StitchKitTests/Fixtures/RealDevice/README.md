# Real device capture fixtures

These are **real ReplayKit broadcast keyframes** pulled off a physical iPhone 17 Pro Max
(iOS 26) via `xcrun devicectl device copy from`. They are the regression oracle the project
lacked for three fix cycles: synthetic and static-screenshot fixtures repeatedly reported
green while real broadcast frames stitched wrong (see `docs/logs/2026-07-05-02-...`).

**Resolutions differ per set, and the number matters** — `rowScale` is derived from frame
height, so a resolution change silently changes matching:

| set | checked-in resolution |
|-----|----------------------|
| `baidu-*`, `wechat-*` | **884×1918** — native, the full-res device originals |
| `youtube-*` | 660×1434 — half of the 1320×2868 recording it was decoded from |

This file described everything here as "half resolution (442×959)" until 2026-07-25, which
was true only before `cf7c511`. That commit replaced the half-res copies with the full-res
originals precisely because *"half-res fixtures (rowScale 1.5) passed while the full-res
device geometry failed"* — and left this README describing the files it had just deleted.
The `baidu-*` offsets below were doubled to match. If you are about to measure something
against this file, check the resolution line above first.

Both *broadcast* sessions — `baidu-*` and `wechat-*` — were captured with the shipped (broken)
pipeline and reproduced the field failure: total shatter / stacked panels. `youtube-*` is not a
broadcast at all; it came from a screen recording (`scroll-recording.mp4`) decoded through
`VideoKeyframeSource`.

## `baidu-00..06.png` — Baidu feed in Safari, clean **downward** scroll (7 keyframes)

The easy case. Every consecutive pair overlaps heavily and scrolls **down** (later frames
show content further down the document). Full-pixel ground-truth vertical offsets, in px at
this set's native 884×1918 — all **positive** = downward:

| pair | dy (px) |
|------|---------|
| 0→1  | 1167 |
| 1→2  | 750 |
| 2→3  | 336 |
| 3→4  | 1074 |
| 4→5  | 849 |
| 5→6  | 1146 |

These are `RealDeviceStitchTests.baiduGroundTruth`, which is the authority: the test asserts
every recovered offset within 25% of them against the checked-in 884×1918 files, and passes.

The shipped pipeline produced **0 seams / 7 segments** on this (manifest recovered from the
device). A correct pipeline stitches it into essentially one segment.

## `wechat-00..04.png` — WeChat, capture started before the app opened (5 keyframes)

- `wechat-00`: iOS home screen
- `wechat-01`: app-launch animation (WeChat zooming in)
- `wechat-02..04`: WeChat chat list, scrolling **down**

Offsets (px): 0→1 = −767, 1→2 = −679 (home/launch genuinely do **not** overlap the list —
spurious negative "best" matches), 2→3 = +175, 3→4 = +25 (the real list scroll). This
exercises the "junk pre-app frames must not corrupt tracking / must segment off" case.

⚠️ **These four numbers were measured on the superseded half-res copies and have not been
re-measured at 884×1918** — unlike the `baidu-*` table, nothing corroborates them, so they
are not doubled here on the assumption that they scale. Do not cite them as ground truth.
What is load-bearing, and what `OrderRecoveryTests.wechatNonOverlapStillBreaks` actually
asserts, is the **signs**: 0→1 and 1→2 are non-overlaps that must segment off, 2→3 and 3→4
are real downward scroll. Re-measuring them at native resolution is an open doc gap.

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

## Regenerating

`baidu-*` and `wechat-*` are the full-resolution originals: raw BGRA at 884×1918, pulled from
the app container at `Library/Application Support/Seamly/sessions/<uuid>/` and encoded to PNG
with color/gamma preserved (that content is what drives the matcher). Nothing here is
downsampled from them — keep it that way, per CLAUDE.md's full-resolution fixture rule.

`youtube-*` is the exception, and an acknowledged one: it was decoded from
`scroll-recording.mp4` through `VideoKeyframeSource` and stored at half of that recording's
1320×2868. Its purpose is the translucent tab bar, which survives the downsample, but its
`rowScale` differs from the other two sets — so do not read a matcher measurement across sets
as comparable.
