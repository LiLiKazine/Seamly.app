# 2026-07-25-02: Remove the legacy incremental-tracking tier

**Status:** Implemented.

## Context

While scoping the translucent-chrome fix (2026-07-25-01) it turned out that `PositionTracker` and
`FrameSelector` had **no production callers**. `PositionTracker` appeared outside its own file only
in doc comments and five test files; `FrameSelector` not even in a doc comment. Capture had moved to
`SampleHandler` → `ScrollCaptureDriver` → `KeyframeSelector`, which banks overlapping keyframes and
leaves every geometry decision to `BatchStitcher` at import. `ContentBandDetector`'s entire consensus
half (`observe`, `lockedBand`, `bandChangedSharply`, plus `motionThreshold`, `minMovingFrames`,
`staticFraction`, `jumpThreshold` and 5 of its 7 tests) was reachable only from the tracker.

Dead code was the smaller half of the problem. `RealFrameStitchTests` and `ChromeStitchReproTests`
each carried a private `buildSession` helper labelled *"Faithful mirror of SampleHandler's capture →
session pipeline"*, and `RealDeviceStitchTests` a third copy. Those are the project's real-device
oracles — per `Fixtures/RealDevice/README.md`, "the regression oracle the project lacked for three
fix cycles" — and all three were driving the retired tracker. They were validating a pipeline the app
no longer shipped, and nothing said so.

That had a concrete cost: the translucent-chrome fix in 2026-07-25-01 could not make
`stitchesRealScreenshotWithTranslucentChrome` pass, because that test never reached `BatchStitcher`.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Leave it; document that the tracker is legacy | Zero risk | The oracles keep testing a dead pipeline, and the `withKnownIssue` blocks keep reading as live product gaps |
| Delete the tracker and its own tests only | Small, obvious | The four other suites reference it, so it doesn't compile — not actually an option |
| Delete the tracker and *delete* the suites that depend on it | Fastest way to green | Throws away the real-device oracles — the most valuable tests in the repo |
| **Delete the tier and re-point the oracles at the shipped path (chosen)** | Oracles start testing what actually ships; one shared harness replaces three drifting copies | Changes what those tests measure, so every assertion needs re-baselining against real behaviour |

## Decision

Delete `PositionTracker`, `FrameSelector`, their tests, and `ContentBandDetector`'s consensus half.
Replace the three `buildSession` copies with one `CaptureHarness` that runs the real
`ScrollCaptureDriver` and then `BatchStitcher`, mirroring `SampleHandler` + `StitchAssembler`
`resolveGeometry`.

## Rationale

An oracle that tests a retired pipeline is worse than no oracle: it reports green about code nobody
runs, and — as 2026-07-25-01 showed — it can hide a real fix as easily as a real bug. Re-pointing was
worth the re-baselining because it converts the repo's best fixtures into coverage of the shipping
path.

One harness rather than three copies is the same reasoning as folding `chromeBand`'s inlined static
test into `ContentBandDetector`: duplicated logic is what allowed the drift in the first place.

## What Changed

- Deleted `Sources/StitchKit/PositionTracker.swift` (240 lines) and `FrameSelector.swift`.
- Deleted `Tests/StitchKitTests/PositionTrackerTests.swift` (12 tests) and `FrameSelectorTests.swift`
  (8 tests).
- `ContentBandDetector`: removed `observe`, `lockedBand`, `bandChangedSharply`, `consensusBand`, the
  vote state and the four consensus parameters; removed the 5 tests covering them. What remains is
  the per-pair chrome test (`staticMask`, `isStatic`) that both shipping callers use.
- Added `Tests/StitchKitTests/CaptureHarness.swift`: `capture(_:)` for frame streams (runs the real
  picker) and `assemble(_:)` for inputs that are already keyframes, both ending in `BatchStitcher`.
- Re-pointed `RealFrameStitchTests`, `ChromeStitchReproTests` and `RealDeviceStitchTests` at it.
- Promoted `stitchesRealScreenshotWithTranslucentChrome`'s `withKnownIssue` block to hard assertions.

## What Was Discovered

- **The removal immediately paid for itself: it exposed a live regression in the previous commit.**
  Once `ChromeStitchReproTests` ran the shipped path it collapsed — 272px against 1244px expected —
  because the new shape-only chrome test measured 240px of bottom chrome where the truth is 20px.
  That is a real production defect on low-horizontal-variance content, and the pre-existing fixtures
  could not have caught it while they bypassed `BatchStitcher`. Diagnosis and fix are recorded in
  2026-07-25-01.
- **A long-standing known issue closed for free.**
  `stitchesRealScreenshotWithTranslucentChrome` — the "pixel-only translucent-chrome detection is
  unsolved" gap from 2026-07-05-01 — now passes at the same tolerances as the opaque case (band
  238/262 against a truth of 210/260, output ratio 1.00) and is promoted to a hard assertion. It
  needed *both* the new measure and a test that reaches the code the measure lives in.
- **Suite totals: 105 tests / 7 known issues → 80 tests / 3 known issues.** The 25 removed are
  exactly 12 + 8 + 5. Of the four known issues that went away, three were the promoted translucent
  block and one was `cleanDownwardScrollStitchesIntoOneSegment`'s "expected stitched seams": on the
  shipped path the baidu fixture now produces seams where the tracker produced none. Its segment
  count moved 2 → 3 breaks, still short of the ideal, so that half stays deferred.
- Assertions that *improved* on the shipped path, worth noting because the old numbers were the
  tracker's: `ChromeStitchRepro` bands went from ±6-of-truth to 25/21 against 24/20 with an output
  ratio of 0.99, and `RealFrameStitch` reproduces its document at ratio 1.00 exactly.
- `KeyframeSelector` is the only remaining live consumer of `ContentBandDetector`, and it uses just
  `staticMask`. Live capture therefore computes no content band at all — worth remembering before
  anyone reintroduces band logic on the capture side.
