# Design — Capture-Side Simulation Test

**Date:** 2026-07-22
**Branch:** `fix/on-device-stitching-real-frames` (continuation)
**Status:** Approved direction (option B); ready for implementation planning.

## Problem

The record→scroll→auto-stitch flow was split into two isolatable halves:

- **Assembly** (`BatchStitcher`) — recovers order + geometry from a fixed keyframe set.
  Isolated off-device and verified against real fixtures; proven correct on a densely
  overlapping set (Example: order `[2,0,1]`, one segment, 5978 px continuous). Confirmed
  again by running it directly on the `RealDevice` sets, which shatter into segments only
  because their keyframes are sparse fast-flicks with no overlap for the matcher to lock.
- **Capture** (`KeyframeSelector` driven through `VerticalProfile`, as `SampleHandler`
  wires them) — decides, per live frame, whether to bank a keyframe. This is the half that
  produced the on-device **empty capture** (Library received nothing). It has *not* been
  isolated and tested the way assembly was.

The existing `KeyframeSelectorTests` feed synthetic ramp `FrameProfile`s. They verify the
commit *arithmetic* but never exercise the real failure path: real image frames through the
real `VerticalProfile`, with a fixed status/nav bar that can pin measured scroll to zero.
Per the dev log (`docs/logs/2026-07-19-01`), a static bar pinning scroll to zero is a
plausible cause of the empty capture — and it is exactly what today's tests cannot catch.

Assembly quality is bounded by capture: dense overlapping keyframes stitch; sparse gappy
ones shatter. So the capture policy must be proven to commit dense-enough overlapping
keyframes from a realistic scroll — including the adversarial conditions (static chrome,
fast flick, jittery finger speed) — before the device round-trip can be trusted.

## What can and cannot be tested off-device

- **Cannot** (device-only, out of scope): ReplayKit frame delivery cadence, the ~50 MB
  broadcast-extension jetsam ceiling, real codec/compression artifacts.
- **Can** (this design): the *decision policy*. `KeyframeSelector` depends only on the
  content of the frames it sees. If we synthesize the frame stream a scroll delivers, the
  real selector code runs and its commit decisions are fully reproducible.

## Approach

Fake a scroll off-device: take a tall real oracle image, slide a fixed-height window down
it to synthesize the CGImage frame stream a scroll would deliver, and run that stream
through the exact pipeline `SampleHandler` uses. Then close the loop by feeding the
committed keyframes into `BatchStitcher` and reconstructing the page.

This mirrors, for capture, what `ChromeStitchRepro`/`BatchStitcher` isolation did for
assembly: drive the *real* code path on controlled inputs, off-device, deterministically.

### Component: `CaptureSimulator` (test helper in `StitchKitTests`)

Test scaffolding, not product code — it stands in for ReplayKit, so it lives with the
tests (peer to the fixture-driven test helpers), not in the shipping library.

Pure and deterministic (no `Date`, no `Math.random` — a seeded LCG for jitter and a fixed
fling index), so runs are reproducible on CI. Given:

- `oracle: CGImage` — a tall real page (our stitched Chrome page ≈ 5978 px; baidu as a
  second oracle),
- `viewportHeight: Int` — the height of the sliding window (the frame height the extension
  would receive); a stated modeling parameter,
- a **scroll script** — per-frame top-offset advancing by ~a few % of the viewport with
  seeded jitter, plus one **fling gap** (a single large jump) at a fixed index,
- `chromeHeight: Int` — a **static top-chrome overlay**: the top `chromeHeight` px of the
  first window, composited onto every emitted frame (the fixed status/nav bar),

it returns `[CGImage]` — each frame the `[offset, offset+viewportHeight)` crop of the
oracle with the static chrome band drawn on top.

### Pipeline under test (exact `SampleHandler` mirror)

Using stock `VerticalProfile()` and `KeyframeSelector()` (defaults; `commitFraction 0.5`),
for each synthesized frame:

1. `let profile = profiler.profile(frame)`
2. `let result = selector.evaluate(profile)`
3. if `result.commit`, record the frame as a committed keyframe (and its profile).

After the stream, mirror `broadcastFinished`: if `selector.hasUncommittedMotion(lastProfile)`,
commit the trailing frame and `markCommitted`.

The committed keyframes are the exact set the extension would have banked.

### Closed loop

Feed the committed keyframe images into `BatchStitcher().plan(_:)` and `stitch(_:)`.

## Test scenarios (`CaptureSimulationTests`, peer to `BatchStitcherTests`)

Both scenarios use real content (the stitched Chrome oracle). Per the approved option B,
both viewport sizes are covered:

1. **Faithful viewport (~2868 px), static chrome, gentle jitter.**
   A short real scroll (~3 keyframes). Primary purpose: prove capture is not empty and the
   chrome bar does not pin scroll to zero.

2. **Long-scroll viewport (~1400 px), static chrome, jitter + one fling.**
   A richer scroll (~6–7 keyframes). Exercises commit cadence, fast-flick recovery, and
   finger-speed jitter.

### Assertions

1. **Not empty / chrome doesn't pin scroll** — committed keyframes ≫ 1 despite the static
   bar. This is the empty-capture regression guard.
2. **Cadence** — consecutive committed keyframes overlap ≈ `1 − commitFraction` (within a
   stated tolerance): no near-duplicate commits (dy too small), no lost-overlap skips.
3. **Fling** — across the fling gap the selector still commits; whether the downstream
   `BatchStitcher` keeps one segment or splits there is asserted explicitly (documented
   behavior, not left implicit).
4. **Closed loop** — committed keyframes → `BatchStitcher().plan` recovers a monotonic
   scroll order, a single segment for the recoverable (non-fling) scenario, a stitched
   height within tolerance of the oracle, and crops the injected chrome band. Proves
   capture + assembly compose.

## Deliverables

- `CaptureSimulator` test helper + `CaptureSimulationTests` suite, committed alongside the
  other StitchKit tests; registered in `Package.swift` if new resources are needed (none
  expected — oracles are built at runtime from existing fixtures).
- A `capture` subcommand added to the scratchpad harness (not committed) to render the
  committed-keyframe filmstrip and the reconstructed page for visual inspection.

## Non-goals

- Reproducing ReplayKit delivery, memory ceiling, or codec artifacts (device-only).
- Changing `KeyframeSelector` / `SampleHandler` behavior. This is a test-only addition; if
  a scenario reveals a real defect, that fix is a separate, follow-up change.
- Tuning `edgeConfidence` or other assembly constants (tracked separately).

## Risks / open points

- The faithful-viewport scenario yields only ~3 keyframes; option B's long-scroll scenario
  is what carries the cadence/fling/jitter coverage. Accepted.
- Oracle realism: the stitched Chrome page has chrome already cropped at its internal
  seams, so re-adding a synthetic static bar is what recreates the fixed-chrome condition.
  The synthetic bar is a faithful stand-in for a real status/nav bar for the purpose of the
  chrome mask, but is not pixel-identical to any specific app's chrome.
