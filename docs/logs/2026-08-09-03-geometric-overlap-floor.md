# 2026-08-09-03: The overlap floor still capped how far a masked match could measure

**Status:** Implemented

## Context

Four new real fixtures were added — two screenshot sets and two untrimmed handheld screen
recordings, all 1320×2868:

| fixture | what |
|---------|------|
| `Fixtures/Screenshots3` | 5 shots, Chrome for iOS light, a Chinese subsidy article; bottom omnibox that collapses after the first shot |
| `Fixtures/Screenshots4` | 5 shots, Chrome for iOS dark, a Discover feed — same bars as `Screenshots2` |
| `Fixtures/Recordings/CKHQ1876.MP4` | 7.5 s, 60 fps, the `Screenshots3` page |
| `Fixtures/Recordings/KMZK1521.MP4` | 8.5 s, 60 fps, the `Screenshots4` feed |

**All four produced visibly wrong stitches.** Rendered with `stitch-cli`, every one carried browser
chrome stamped through the middle of the page, and `Screenshots4` additionally recovered its order
as `[2, 3, 4, 0, 1]`:

```
Screenshots4  order: [2, 3, 4, 0, 1] (recovered)
  seam 0->1  dy=1680  conf=0.462        segment breaks after: [3]
  seam 1->2  dy=1542  conf=0.845        band[0] topChrome=377 bottomChrome=238
  seam 2->3  dy=238   conf=0.201 LOW    band[1] topChrome=0   bottomChrome=0
KMZK1521      decoded 180 frames at 30fps, 0 failures, 3 keyframes banked
```

What distinguishes these captures from every fixture already in the repo is simply **how far each
swipe went**: consecutive frames overlap 4.6–54% of the page, where the earlier sets sit around
60–70%.

## Evidence

Ground truth was measured on the raw pixels at full vertical resolution — no `VerticalProfile`, no
downsample, plain MAD — as an independent yardstick, then compared against what the matcher does at
each pair's true offset.

`Screenshots4` alignments are near-pixel-perfect at the true offset (MAD under 1 on 0…255), so
there is no question of a hard capture:

| pair | true dy | MAD | next-best margin | matcher, before |
|------|---------|-----|------------------|-----------------|
| 1870→1871 | 1666 px | 0.54 | ×58 | `dy=349 conf=0.230` |
| 1871→1872 | 2159 px | 0.70 | — (4.6% overlap) | `dy=37 conf=0.035` |
| 1872→1873 | 1835 px | 0.59 | ×17 | `dy=375 conf=0.462` |
| 1873→1874 | 1543 px | 0.50 | ×57 | `dy=344 conf=0.845` ✓ |

Instrumenting the exact cost curve `BatchStitcher.downwardMatch` sees showed the masked matcher
returning `Float.greatestFiniteMagnitude` at the true offset on 4 of the 8 new pairs — the offset
was never scored:

| pair | true dy | masked counted | floor | ceiling |
|------|---------|----------------|-------|---------|
| `Screenshots4` 1870→1871 | 372 | 96 | 116 | 346 |
| `Screenshots4` 1872→1873 | 409 | 93 | 116 | 348 |
| `Screenshots3` 1864→1865 | 416 | 77 |  97 | 290 |
| `Screenshots4` 1871→1872 | 482 | 27 | 107 | 322 |

## Root cause

`OffsetMatcher` rejected a candidate offset when `counted < minOverlap`, with
`minOverlap = max(minimumOverlap, minimumOverlapFraction · countableRows)`.

A masked match counts only rows that are content at **both** ends of the shift, so its count falls
as `dy` grows. Requiring that count to be a quarter of *all* countable rows therefore caps any
masked match at `dy ≈ 0.75 · countable`, however clean the alignment is. That is a limit on the
capture, not a test of the match — the floor forbade large offsets by construction.

Two consequences compounded it:

1. **The rejection wins.** `downwardMatch` keeps whichever of the masked and plain variants is more
   confident, and masking usually scores better. So the masked match's best *surviving* offset
   overrode a plain match that had found the true one. `Screenshots4` 1870→1871 is the extreme: a
   pixel-identical overlap reported at confidence **0.003**.
2. **Everything downstream is derived from it.** With the true offsets discarded, `layout` had no
   edge for 1870→1871, joined `IMG_1874 → IMG_1870` on a spurious `dy=238` instead, and left
   `IMG_1871` alone in its own segment.

This is the same defect as `docs/logs/2026-08-08-02`, not fully closed. That log moved the floor's
reference from the frame's rows to the countable rows, raising the ceiling from `content − 160` to
`0.75 · content` — which fixed `DSNN4777.MP4`. These captures scroll past the new ceiling. A
ceiling proportional to the countable rows is still a ceiling.

**A second, independent defect** surfaced only because the first one broke the chain: `buildPlan`
measures each segment's content band from the *pairs* inside that segment, and a segment holding a
single frame has none — so `chromeBand` answered `.unlocked` and that frame was composited with its
status bar and toolbar intact.

## Options

| Approach | Verdict |
|----------|---------|
| Lower `minimumOverlapFraction` | Rejected — treats the symptom, weakens the guard for every match, and the ceiling still exists a little further up. Exactly the reasoning `2026-08-08-02` rejected for `commitFraction` |
| Have `downwardMatch` prefer the plain match when the masked one rejects the true offset | Rejected — nothing at that layer knows which offset is true; that is the question being asked |
| Pick the variant on `cost` rather than `confidence` | Rejected — refuted previously (see `MEMORY`/issue #11); confidence is the right criterion for the variant, and it was the *input* that was wrong, not the comparison |
| Make the fractional floor **geometric** (chosen) | The floor asks "is this a plausible scroll or a degenerate boundary shift", which is a question about `dy` |

## Decision

Split the one gate into the two questions it was conflating:

- **Plausibility is geometric.** `minimumOverlapFraction` applies to `frameRows − |dy|`, measured
  against the frame's rows. This is what rejects extreme boundary shifts.
- **Signal is what the mask governs.** `minimumOverlap` — the absolute floor — continues to gate
  the scored row count, alongside the existing non-degenerate `weightTotal` check.

The invariant this restores: **masking changes how an offset is scored, never which offsets are
admissible.** The unmasked path is unchanged by construction, since without a mask `counted` *is*
the geometric overlap.

`overlapPenalty` is untouched and keeps the frame as its denominator — it expresses "more overlap
is better" as a continuous preference rather than a cliff, and moving it was tried and reverted in
`2026-08-08-02`.

For the band: a segment with no pairs of its own falls back to every within-segment pair in the
capture. The frames come from one device, one app, one session, so a sibling segment's measurement
describes this frame's bars too. Pairs spanning a segment break are never used — those frames don't
overlap, so comparing them is comparing unrelated screens.

## What Changed

- `Sources/StitchKit/OffsetMatcher.swift` — the fractional floor becomes a geometric gate on the
  candidate offset; `weightedMAD` receives only the absolute `minimumOverlap`. The unmasked path is
  unchanged by construction: without a mask `counted` *is* `frameRows − |dy|`, so the new gate is
  the old check.
- `Sources/StitchKit/Match.swift` — `OverlapAccounting.minimumRequiredRows` now documents that it
  reports the floor applied to `countedRows` (the fractional floor is no longer expressed there).
- `Sources/StitchKit/BatchStitcher.swift` — a segment with no pairs of its own takes the band
  measured from every within-segment pair in the capture; `downwardMatch` is internal so tests can
  pin the offset a pair resolves to.
- `Tests/.../LargeScrollStepTests.swift` — new suite over both screenshot sets: per-pair offsets
  against raw-pixel truth, masked/plain admissibility equivalence, order and segmentation, chrome
  against truth, every segment banded, and the bar-occurrence check.
- `Tests/.../OffsetMatcherTests.swift` — `maskingDoesNotNarrowAdmissibility`, asserted as an
  equivalence across the whole search range rather than at one offset.
- `Tests/.../LongScreenshotFromVideoTests.swift` — `aSteadyScrollBanksKeyframesThroughout` for
  `KMZK1521.MP4`; the overlap check covers both clips.
- `Package.swift`, fixture `README.md`s — the four new fixtures and their ground truth.

## Results

| fixture | before | after |
|---------|--------|-------|
| `Screenshots3` | 2 segments, seam 1→2 measured 820 px against a true 1863 | one segment, order `[0…4]`, seams within 1 px of truth |
| `Screenshots4` | order `[2, 3, 4, 0, 1]`, spurious `dy=238` seam, `band[1]` zeroed | one segment, order `[0…4]`, seams within 8 px of truth |
| `KMZK1521.MP4` | 3 keyframes from 8.5 s, 2 segments | 6 keyframes, one segment, every seam ≥ 0.697 |
| `CKHQ1876.MP4` | 6 keyframes, break after 2, seam 0→1 at 0.078 | unchanged — see below |

Full package suite: 144 tests, the pre-existing baidu `withKnownIssue` unchanged (still 3 breaks),
no other regressions. Notably `RealDeviceStitchTests`, `RealFrameStitchTests`,
`ScreenshotOrderRecoveryTests`, `DynamicChromeBandTests` and `TranslucentChromeTests` are all clean,
which is the regression `2026-08-08-02` warned a change here would cause.

## What Was Discovered

- **A ceiling is invisible from below, so "the fixture is fixed" does not mean "the mechanism is
  fixed."** `2026-08-08-02` diagnosed this defect correctly and removed it *for the capture in
  hand*, because raising the ceiling and removing it look identical to any fixture that only needed
  it raised. The corrective is in the new unit test: assert masked and plain admissibility as an
  **equivalence over the whole search range**, not at the one offset a fixture happens to need.
- **The yardstick had the same bug as the code.** The raw-pixel oracle written to check the matcher
  carried its own minimum-overlap cutoff, and so reported 2142 px for `Screenshots4` 1871→1872 —
  the best offset *below its own floor* — when the truth is 2159 px. An independent measurement is
  only independent of the implementation, not of the mistake.
- **The occurrence-counting chrome probe cannot see a bar that appears once.** `Screenshots2`'s
  defect stamped a toolbar once per keyframe, so counting occurrences caught it. `Screenshots3`'s
  bar exists in a single frame, so the same probe reports `1` for both the broken and the correct
  output. The first version of that test passed and proved nothing; the question had to be inverted
  to "this row must appear **zero** times."
- **Confidence was inverted on the worst cases, not merely low.** On `Screenshots4` the two
  easiest pairs (raw MAD 0.54 and 0.59, margins ×58 and ×17) scored 0.003 and 0.040, while the
  near-impossible 4.6%-overlap pair scored 0.445 — because a chrome-aligned `dy≈0` was the best
  *surviving* candidate once the true offset had been discarded. Every number that would have
  justified "these captures are too hard" was real, and all of them described the wrong question.

## Still Open

- **A bar that changes size mid-capture.** `Screenshots3` and `CKHQ1876.MP4` collapse Chrome's
  bottom toolbar after the first frame. `ContentBand` is per segment and these frames are correctly
  one segment, so one pair of numbers cannot describe both bar heights and ~475 px of toolbar is
  left in the first strip. Fixing it means chrome per keyframe, which changes the persisted manifest
  and the editor's model. Recorded as `withKnownIssue` in `LargeScrollStepTests`.
- **`CKHQ1876.MP4` seam 2→3 still breaks**, against a true `dy=1436` that raw pixels separate by
  ×2.62 — wide enough that it should be recoverable. Its seam 0→1 lands on a competing basin, but
  that pair is a ×1.09 near-tie even at full resolution, so that half is content, not code.
- **Order recovery on densely-sampled video keyframes.** At full decode rate `KMZK1521.MP4` recovers
  `[0, 1, 3, 2, 4, 5, 6]`. The app imports video with `.inputOrder`, so nothing ships wrong, but
  recovery is genuinely weaker here than at 30 fps.
