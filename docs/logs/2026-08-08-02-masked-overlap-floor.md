# 2026-08-08-02: The masked overlap floor capped how far a match could measure

**Status:** Implemented

## Context

A new fixture — `Fixtures/Recordings/DSNN4777.MP4`, an untrimmed 6.43 s handheld screen recording
of a Google Discover feed — produced **no stitch at all**:

```
decoded 138 frames at 30fps, 0 failures, 1 keyframes banked
error: need at least 2 frames to stitch, got 1
```

One keyframe from a 6.4 s scroll, at both the full decode rate and the app's 30 fps, so not a
sampling artifact.

Instrumenting `KeyframeSelector` over the clip showed the capture tracking the scroll cleanly and
then falling off a cliff:

```
f027 t=1.23 overlap=0.573  masked dy=273 c=0.932 | plain dy=273 c=0.592
f028 t=1.28 overlap=0.531  masked dy=300 c=0.007 | plain dy=319 c=0.326
f029 t=1.33 overlap=1.000  masked dy=  0 c=0.175 | plain dy=354 c=0.207
f030 t=1.37 overlap=1.000  masked dy=  0 c=0.185 | plain dy=387 c=0.053
f031+                      masked dy=  0         | plain dy=  0
```

A commit needs `dy ≥ commitFraction · n` = 320 of 640 profile rows. At f029 the true offset is 354
— past the threshold, so it should have committed — but the masked match returns 0. By f031 the
content has scrolled past the one reference frame entirely, no overlap remains, and the selector
can never measure anything again. Hence exactly one keyframe.

## Root cause

`OffsetMatcher.weightedMAD` counts only rows that are unmasked at **both** ends of the shift, then
rejects the offset if `counted < minOverlap`. `minOverlap` was
`max(minimumOverlap, minimumOverlapFraction · referenceRows)` with `referenceRows` = the frame's
row count — a floor measured against the full frame but applied to the masked count.

Measured directly on the failing pair:

| frame | true offset | rows counted at it | floor | outcome |
|-------|-------------|--------------------|-------|---------|
| f029 | 354 | 124 | 160 | rejected → `dy=0` |
| f030 | 387 | 82 | 160 | rejected → `dy=0` |

With the floor lifted, the *same masked match* finds f029 at **354 @ 0.704** and f030 at
**387 @ 0.909** — better than plain matching's 0.207 and 0.053. The offset was never hard to find;
it was being discarded before it could win.

The chrome mask removes ~135 of 640 rows, and a shift removes them twice over, so the countable
rows at offset `dy` are about `505 − dy`. Against a 160-row floor that caps a masked match at
`dy ≈ 345` — **25 rows above the commit threshold of 320**. Every capture had to thread a 25-row
window. A steady scroll lands inside it; this clip's flick stepped 273 → 319 → 354 straight over.

That is also why no existing fixture caught it: every video fixture in the repo was trimmed to a
steady scroll.

## Options

| Approach | Verdict |
|----------|---------|
| Lower `commitFraction` so commits happen below the ceiling | Rejected — treats the symptom, shrinks overlap for every capture, and the ceiling still exists a little further up |
| Have `KeyframeSelector` fall back to the plain match like `BatchStitcher.downwardMatch` does | Rejected — would have worked here (plain reads 354) but leaves the matcher silently returning `dy=0` for a well-defined offset, and the masked match is the *better* measurement once admitted (0.704 vs 0.207) |
| Make the floor a fraction of the **countable** rows (chosen) | The floor asks "did this offset count enough rows to be trusted"; only the mask knows how many there were to count |
| Also make the overlap **penalty** relative to countable rows | Tried and reverted — see below |

## Decision

`minimumOverlapFraction` is measured against the rows the mask makes available
(`countableRows`), not the frame's rows. The overlap penalty keeps the frame as its denominator.

## Rationale

The floor and the penalty answer different questions. The floor is a trust test about the sample
size a match actually had; that is a property of what the mask left behind. The penalty asks how
much of the frame an offset explains, which is a property of the frame.

Moving both was tried first, and the suite caught it: `RealDeviceStitchTests`
`matcherRecoversDownwardOffsetsOnRealFrames` failed with `dy = 0` on a real downward baidu pair.
The mechanism is that the penalty `1 + 0.8 · (1 − counted/reference)` shrinks for every offset when
the reference shrinks, but shrinks *further* for well-overlapped ones — at `dy=0`, 1.21 → 1.00; at
`dy=354`, 1.65 → 1.59 — tilting the whole score curve toward `dy=0`. Narrowing the change to the
floor alone restored baidu byte-for-byte (`kf=7 seams=3 breaks=3 out=9927`).

## What Changed

- `Sources/StitchKit/OffsetMatcher.swift` — new `countableRows`; `minOverlap` derives from it. The
  unmasked path is unchanged by construction (`countableRows(nil) == rows`), so only masked
  matches move at all.
- `Sources/StitchKit/BatchStitcher.swift` — the `isLowConfidence` seam threshold is an init
  parameter (`lowConfidenceSeam`, default 0.4) rather than a literal. See below for why.
- `Tests/.../LongScreenshotFromVideoTests.swift` — new tier: the untrimmed recording must yield
  several overlapping keyframes, in order, one segment, and an image taller than the screen, at
  both decode cadences.
- `Tests/.../CaptureVideoTests.swift` — `withKnownIssue` **promoted to a hard assertion**.
- `Tests/.../ScreenshotOrderRecoveryTests.swift`, `SeamlyTests/PhotoPickOrderTests.swift` —
  re-pointed at a raised flag threshold, plus a new test pinning that the set is clean at 0.4.
- `Tests/.../Fixtures/Recordings/` — the fixture and a README with its ground truth.

## What Was Discovered

- **The "unmatchable trailing keyframe" was not unmatchable, and the fixture was not at fault.**
  `CaptureVideoTests`' last segment break had been diagnosed (2026-07-25-07) as needing the fixture
  re-trimmed: keyframe 4 scored 0.047 and fit 0.953 as well as its own reverse. With the floor
  corrected, the same clip banks 5 keyframes whose weakest seam is 0.732, and that pair measures
  **dy=1268 px at 0.945**. Issue #2's last acceptance criterion closes here — not by re-trimming,
  and not by another threshold, but because the measurement it rested on was wrong. Two fix cycles
  were spent tuning direction and floors around a matcher that was discarding the answer.
- **A wrong confidence looks exactly like a hard problem.** Every number that justified the
  "re-trim it" conclusion was real; they were all computed after the true offset had been thrown
  away, so they described the best *surviving* alignment.
- **The fix improved confidence calibration everywhere a mask is used, and that broke two tests by
  making them vacuous.** `Fixtures/Screenshots` recovers *identical* offsets (1326 / 1636 / 1416 /
  1533 / 1537 px) but its weakest seam went 0.368 → 0.726, because the score curve now includes the
  far offsets the floor had been dropping, so the true valley's prominence is measured against the
  whole curve. That seam was the repo's only sub-0.4 seam on a complete chain, and two tests
  guarding a real shipped bug (`docs/logs/2026-07-25-08`) depended on it existing. Both went green
  and meaningless at once.
- Hence `lowConfidenceSeam` becoming a parameter: a guard that can only fire when some fixture
  happens to produce the right number is a guard with a shelf life. Raising the threshold
  reproduces the condition from the same real pixels, deliberately.
- The baidu known issue (`cleanDownwardScrollStitchesIntoOneSegment`, 3 breaks) is **unchanged** —
  same order, same seams, same output height. Whatever is wrong there is not this.
