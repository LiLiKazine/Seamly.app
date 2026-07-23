# 2026-07-23-01: BatchStitcher mis-scores scroll direction on image-heavy content

**Status:** Follow-up / deferred. The capture-side isolation effort (`ScrollCaptureDriver` pure
capture loop, synthetic test tier, and a video test tier that decodes a real screen recording
through the real driver) is done and landed. This assembly-side fix is **deferred** to a
follow-up.

## Context

The video tier (`CaptureVideoTests`) closes the loop: a trimmed real screen recording is decoded
through the exact on-device path (`AVAssetReader` → `PixelBufferImage` → `ScrollCaptureDriver`),
and the 5 committed keyframes are re-stitched with `BatchStitcher`. This surfaced a
capture↔assembly disagreement: capture banks all 5 keyframes correctly (consecutive overlaps
0.469–0.536, a sane band for a continuous downward scroll), and `BatchStitcher.plan(_:)` recovers
the correct monotonic order `[0,1,2,3,4]` — but it still cannot reassemble the frames into one
continuous segment. `segmentBreaks == [after slot 2, after slot 3]`, splitting one real scroll into
three fake segments (`{0,1,2} | {3} | {4}`).

The originally-planned fix (task 4) was to replace `BatchStitcher`'s fixed
`edgeConfidence = 0.45` acceptance threshold with an adaptive one. A full measurement pass (see
`.superpowers/sdd/task-4-report.md`) proved that mechanism cannot work, for reasons below.

## Finding

`BatchStitcher.layout` matches every keyframe pair in both directions (`i` above `j`, and `j`
above `i`) and keeps only the **more-confident** of the two before running any acceptance
threshold. On this video's 5 keyframes (true scroll order 0→1→2→3→4), that direction-selection
step throws away the real edge on two of the four adjacent pairs *before* `edgeConfidence` ever
gets a vote:

| pair | fwd (correct dir for adjacents) | bwd | winner used by `layout` |
|------|------|-----|-----|
| 0-1 | `0→1 dy=327 conf=0.8199` | `1→0 dy=1 conf=0.2765` | **0→1 ✓** accepted |
| 1-2 | `1→2 dy=340 conf=0.8989` | `2→1 dy=313 conf=0.3781` | **1→2 ✓** accepted |
| 2-3 | `2→3 dy=329 conf=0.3501` | `3→2 dy=1 conf=0.4322` | **3→2 dy=1** → rejected (dy<2) |
| 3-4 | `3→4 dy=297 conf=0.0482` | `4→3 dy=1 conf=0.2823` | **4→3 dy=1** → rejected (dy<2) |
| 0-4 | `0→4 dy=68 conf=0.1730` | `4→0 dy=64 conf=0.3349` | **4→0 dy=64** (WRONG dir, higher conf) |

For pairs 2-3 and 3-4, the matcher's spurious "didn't move" (`dy=1`, i.e. reverse/no-scroll)
match scores **higher confidence** than the real downward scroll (e.g. pair 2-3: real
`2→3 dy=329 conf=0.35` loses to spurious `3→2 dy=1 conf=0.43`). `layout` keeps only the winning
direction, so the real edge is discarded before `edgeConfidence` (or any threshold) runs at all.
Textures are uniformly low across the whole clip (~0.014–0.035) — this is image-heavy content
throughout, so a texture-scaled floor can't distinguish the real edges from the failures either.

There is a second, independent artifact: keyframe 4 is a trailing capture-finish commit (created
by trimming the source video mid-scroll). Its best *correct-direction* edge is
`0→4 dy=68 conf=0.1730` — but the worst true non-overlap in the reject-set fixtures is
`wechat 4→1 dy=13 conf=0.1668`. The margin between "frame 4's honest forward match" and "a
genuine non-overlap" is **0.006** — not a real separation, effectively unmatchable without
overfitting a single fixture. Simulating the full `layout` union-find across floors 0.45→0.05
confirms no floor produces `order=[0,1,2,3,4]` with `breaks=[]`: floors ≥0.35 leave frame 4
isolated (its correct-direction edge never clears the floor); floors ≤0.25 do connect frame 4,
but only via the wrong-direction `4→0` edge, which **corrupts the recovered order** to
`[4,0,1,2,3]` — failing the existing (and correct) `batchStitcherRecoversMonotonicOrder` test.

## Why the planned §4 fix (adaptive/relative `edgeConfidence` floor) is insufficient

An adaptive floor — whether an absolute value, a texture-scaled value, or a relative-gap
fallback — only operates on the direction `layout` has already selected as the winner for a
pair. It cannot:

- Resurrect a real edge (`2→3`, `3→4`) that lost the direction tie to a spuriously-higher-scoring
  reverse (`dy=1`) match — the real edge is never even considered once the winner is chosen.
- Admit frame 4's forward edge (0.1730) without also admitting the higher-confidence
  wrong-direction `4→0` edge (0.3349) first, since both would clear the same lowered floor and
  the wrong one sorts first in the confidence-ordered union-find — merging genuine non-overlaps
  is the unavoidable side effect of any floor low enough to reach 0.1730.

In short: the failure is a **direction-scoring** problem upstream of acceptance, not a
threshold-tuning problem, so no threshold-only change can fix it without regressing order
correctness or admitting false merges elsewhere.

## Candidate real fixes (for the follow-up)

1. **Directional-consistency edge model in `BatchStitcher.layout`** — prefer a real downward
   `dy≥2` edge over a spurious `dy=1` (or wrong-direction) winner when the real edge clears an
   adaptive floor, instead of always taking the single higher-confidence direction per pair.
2. **Improve `OffsetMatcher`/`VerticalProfile` confidence or offset estimation** on low-texture,
   image-heavy content, so the real downward edge scores above its spurious reverse instead of
   below it.
3. **Re-trim the video fixture** so the trailing (5th) keyframe overlaps its predecessor with
   enough structure to score a confident, unambiguous forward edge, removing the
   trailing-keyframe artifact independently of (1)/(2).

Whichever fix is chosen, the wechat/baidu `BatchStitcher` regression guards (must-still-break
non-overlap cases, e.g. `wechatNonOverlapStillBreaks`, `baiduDownwardScrollStaysSane` — both
confirmed green on current code) should be added alongside it, so the fix can't be validated by
merging things that must stay separate.

## Decision

Deferred by the user. The capture side (`ScrollCaptureDriver`, synthetic tier, video tier) is
accepted as complete and correct as-is. The video tier records this gap as a `withKnownIssue`
block in `CaptureVideoTests.batchStitcherRecoversMonotonicOrder()`, asserting the *ideal*
end-state (`segmentBreaks.isEmpty`, one seam per adjacent pair) — it passes today only because
those expectations currently fail (a recorded known issue), and it will auto-flip to a hard
failure requiring promotion to a real assertion once the assembly-side fix above lands.
