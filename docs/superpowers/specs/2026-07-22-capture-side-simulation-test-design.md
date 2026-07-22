# Design — Capture-Side Isolation & Simulation Test

**Date:** 2026-07-22
**Branch:** `fix/on-device-stitching-real-frames` (continuation)
**Status:** Approved direction; ready for implementation planning.

## Problem

The record→scroll→auto-stitch flow splits into two isolatable halves:

- **Assembly** (`BatchStitcher`) — recovers order + geometry from a fixed keyframe set.
  Already isolated off-device and verified: correct on a densely overlapping set (Example:
  order `[2,0,1]`, one segment, 5978 px continuous), and its failure modes reproduce
  cleanly (baidu/wechat shatter because those captures are sparse fast-flicks).
- **Capture** (`KeyframeSelector` driven through `VerticalProfile`) — decides, per live
  frame, whether to bank a keyframe. This is the half that produced the on-device **empty
  capture**. Its *decision* lives in a pure type (`KeyframeSelector`), but its
  *orchestration* — the loop that turns a frame stream into the committed keyframe set —
  is trapped inside `SampleHandler`, an `RPBroadcastSampleHandler` subclass that imports
  ReplayKit and cannot run off-device.

Two gaps follow:

1. **No isolated capture entry point.** Assembly has `BatchStitcher.plan([CGImage]) -> Plan`
   — frames in, decision out, fully testable. Capture has no equivalent; the per-frame
   profiling, the safety-cue decision, the `broadcastFinished` trailing commit, and the
   keyframe-metadata construction are all inside the untestable `SampleHandler`.
2. **Existing tests are profile-only.** `KeyframeSelectorTests` feed synthetic ramp
   `FrameProfile`s. They verify the commit arithmetic but never exercise real image frames
   through the real `VerticalProfile`, nor the fixed status/nav bar that can pin measured
   scroll to zero — the very condition the dev log (`docs/logs/2026-07-19-01`) names as a
   plausible cause of the empty capture.

Assembly quality is bounded by capture: dense overlapping keyframes stitch; sparse or gappy
ones shatter. So the capture policy must be proven — against real frames, under adversarial
conditions — and it must be the *real production code* that is proven, not a re-implementation.

## What can and cannot be tested off-device

- **Cannot** (device-only, out of scope): ReplayKit delivery cadence, the ~50 MB
  broadcast-extension jetsam ceiling.
- **Can** (this design): the decision policy and its orchestration. Both depend only on the
  content of the frames. Given a synthesized or decoded frame stream, the real capture code
  runs and its commit decisions are fully reproducible.

## Feasibility spike (reproduced, not theorized)

A throwaway scratchpad spike decoded the real screen recording
(`ScreenRecording_07-22-2026 23-16-50_1.MP4`, 1320×2868 HEVC, 11.2 s, 671 frames) with
`AVAssetReader` → `PixelBufferImage.makeCGImage` → the exact `VerticalProfile` +
`KeyframeSelector` pipeline `SampleHandler` uses, then reconstructed with `BatchStitcher`.
Results:

- **671 frames decoded, 0 decode failures.** The real pixel-buffer decode path
  (`PixelBufferImage`, 32BGRA) handles every HEVC frame.
- **4 keyframes committed** at frames 1 / 143 / 237 / 320, overlaps **1.00, 0.49, 0.47,
  0.49** — textbook ~0.5 spacing for `commitFraction 0.5`. **Not an empty capture; no safety
  cue fired.** The capture policy works on real frames.
- **Assembly shattered:** order `[0,1,2,3]` recovered, but a **segment break after kf 2**
  (stitch 8732 px vs. 11472 stacked). kf2↔kf3 genuinely overlap (the same Witcher 3 card is
  in both, matching the selector's 0.49), yet the boundary is image-heavy (Witcher/Skyrim
  art, low horizontal texture) so `BatchStitcher`'s `edgeConfidence = 0.45` gate rejects a
  real edge.

The spike proves the video tier is feasible off-device **and** immediately surfaced a real
**capture↔assembly disagreement** — exactly the `edgeConfidence`-on-image-content risk the
dev log flagged. This is the bug class the closed-loop test exists to catch.

## Approach

### 1. Extract `ScrollCaptureDriver` (StitchKit, pure) — the capture parallel to `BatchStitcher`

A pure, `Sendable` type owning the whole picking loop:

```
mutating func ingest(_ image: CGImage) -> Step   // Step { keyframe: Keyframe?, fireSafetyCue: Bool }
mutating func finish() -> Keyframe?              // the broadcastFinished trailing commit
```

It holds `VerticalProfile` + `KeyframeSelector` + the state currently in `SampleHandler`:
last profile/image, keyframe index, and the orientation/color-space captured on the first
frame. It decides commits, the safety cue (`overlap < safetyMargin`), and builds `Keyframe`
metadata. It does **not** touch ReplayKit, disk, or haptics.

`SampleHandler` becomes a dumb adapter: decode pixel buffer → `driver.ingest` → if a
keyframe is returned, write its raw bytes + append to the manifest; if `fireSafetyCue`, fire
the cue; `driver.finish()` at `broadcastFinished`. Platform specifics (ReplayKit, App Group,
`KeyframeIO`, haptics) stay in the adapter.

This is behaviour-preserving. Because `SampleHandler` is device-gated, only the thin
adapter's on-device behaviour stays unverified; all the picking logic it delegates becomes
fully testable.

### 2. Test tier — synthetic (`CaptureSimulator`, deterministic, no fixture)

Test scaffolding in `StitchKitTests` (stands in for ReplayKit). Pure and deterministic (no
`Date`/random — seeded LCG for jitter, fixed fling index). Given a tall real oracle (our
stitched Chrome page ≈ 5978 px), a viewport height, a scroll script (per-frame offset with
seeded jitter + one fling gap), and a static top-chrome overlay height, it slides the window
down the oracle and composites the fixed chrome bar onto each emitted `CGImage`. Frames feed
the **real `ScrollCaptureDriver`**.

Two scenarios (approved option B):

1. **Faithful viewport (~2868 px)**, static chrome, gentle jitter — short scroll (~3
   keyframes). Primary purpose: prove capture is non-empty and chrome does not pin scroll.
2. **Long-scroll viewport (~1400 px)**, static chrome, jitter + one fling — richer scroll
   (~6–7 keyframes) exercising cadence, fast-flick recovery, and finger jitter.

**Assertions (precise — known ground truth):**
- Committed keyframes ≫ 1 despite the static bar (empty-capture regression guard).
- Consecutive overlaps ≈ `1 − commitFraction` within tolerance; no near-duplicate commit,
  no lost-overlap skip.
- Across the fling, the selector still commits; the downstream segment outcome is asserted
  explicitly.
- Closed loop: committed keyframes → `BatchStitcher().plan` recovers monotonic order, a
  single segment for the recoverable scenario, height within tolerance, chrome band cropped.

### 3. Test tier — video (`VideoFrameSource`, highest fidelity)

`AVAssetReader` decodes a committed real screen recording to `CVPixelBuffer`s (requested
32BGRA) → `PixelBufferImage.makeCGImage` → the **same `ScrollCaptureDriver`**. This is the
only test exercising the real decode path and real scroll dynamics/chrome/codec.

**Fixture:** the user's real recording, committed under
`StitchKitTests/Fixtures/RealDevice/`. To keep the binary reasonable it is **trimmed to the
useful window (~6 s)** — the spike showed commits only through ~frame 320 (~5.3 s) — via a
one-time offline trim; the committed fixture is the trimmed clip. Registered in
`Package.swift` test resources.

**Assertions (sanity — fuzzy ground truth):**
- Every frame decodes (0 `PixelBufferImage` failures) — locks in the real decode path.
- Capture is **non-empty** and consecutive overlaps sit in a sane band (≈ 0.4–0.6).
- Closed loop: `BatchStitcher` recovers a monotonic order **and stitches into a single
  continuous segment** (no break after kf2). Before the `edgeConfidence` fix (§4) this
  reproduces the shatter and is RED — it *drives* the fix; after the fix it is the
  regression guard. This tier is the acceptance test for §4.

Both tiers drive the same extracted driver, so they prove the real production path.

### 4. Fix the `edgeConfidence` edge-acceptance gate (folded in)

The spike proved the absolute `edgeConfidence = 0.45` gate rejects a *real* overlap
(kf2↔kf3, same Witcher 3 card in both) because the boundary is image-heavy / low horizontal
texture, so the vertical-profile correlation scores below 0.45. Replace the absolute
threshold with an **adaptive / relative-confidence** acceptance: accept the best downward
offset when it stands out confidently from the alternatives (a relative gap between the top
candidate and the runner-up / background), rather than requiring a fixed absolute score.
The exact criterion is for the implementation plan; candidates include a relative-gap test,
a content-adaptive threshold keyed on profile variance, or normalizing correlation by the
pair's texture. Success criterion: the video tier stitches into one continuous segment while
the existing `BatchStitcherTests` (Example, baidu, wechat) do not regress — the non-overlap
pairs that *should* break must still break. This is a scoped `BatchStitcher` change, not a
rewrite of the matcher.

## Deliverables

- `ScrollCaptureDriver` in `StitchKit/Sources/StitchKit/`, with `SampleHandler` refactored
  to a dumb adapter over it.
- `CaptureSimulator` helper + `CaptureSimulationTests` (synthetic tier) in `StitchKitTests`.
- `VideoFrameSource` helper + video-tier test; trimmed `.mov` fixture committed and
  registered in `Package.swift`.
- A `video`/`capture` subcommand on the scratchpad harness (not committed) for visual
  inspection of the committed-keyframe filmstrip and reconstruction.

## Non-goals

- Reproducing ReplayKit delivery or the memory ceiling (device-only).
- **Changing `KeyframeSelector` behaviour.** The `ScrollCaptureDriver` extraction is
  behaviour-preserving.
- Rewriting the `OffsetMatcher` / profile pipeline. The `edgeConfidence` fix (§4) is a
  scoped change to the edge-acceptance criterion, not a matcher rewrite.

## Risks / open points

- The faithful-viewport scenario yields only ~3 keyframes; the long-scroll scenario carries
  the cadence/fling/jitter coverage. Accepted.
- Video-tier ground truth is fuzzy for exact geometry, so its numeric assertions stay
  tolerant; its structural assertions (0 decode failures, non-empty, sane overlap band, and
  — after §4 — single continuous segment) are hard gates. The single-segment gate is what
  makes this tier the acceptance test for the `edgeConfidence` fix.
- The `edgeConfidence` fix must not regress the pairs that *should* break (baidu/wechat
  non-overlap, the Example non-overlapping pair). Guarded by the existing `BatchStitcherTests`.
- Fixture size: the committed clip is trimmed to ~6 s to bound the repo binary.
- The extraction touches `SampleHandler`; behaviour preservation is reviewed by inspection
  and confirmed on the next device capture (device-gated).
