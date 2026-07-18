# 2026-07-19-01: BatchStitcher — re-derive stitch geometry in the app, not the extension

**Status:** Implemented (Step 1 app-side + Step 2 extension); end-to-end device capture pending

## Context

The record→scroll→auto-stitch flow kept failing end-to-end on device: real captures
came out as whole frames **stacked in the wrong order**, with duplicated chrome (status
bar / nav bar repeated per frame). Prior fix cycles chased the matcher (orientation flip,
degenerate signal) and always reported green on synthetic/static fixtures while real
device captures still broke.

To isolate the hardest part off-device, we took three real overlapping Chrome/Discover
screenshots (`example/`, now `StitchKit/Tests/.../Fixtures/Example`) and drove the actual
StitchKit pipeline against them. Findings from the repro:

- The frames were **not in scroll order** (file/time order was spatial mid, bottom, top).
- The live `PositionTracker` (a streaming model) lost lock on every pair and
  segment-broke all three → the compositor stacked them (8620 px vs. correct ~5978 px).
- The alignment math and `Compositor` were **sound**: hand-building a session in correct
  order with per-pair offsets produced a perfect continuous stitch.
- No single matcher config wins every pair — the static-chrome mask helps one pair and
  flips the sign on another; plain matching is the opposite.

Root cause: the only assembly path was `PositionTracker`, which assumes a live, in-order
frame stream. A fixed, possibly-unordered, large-gap set is a category mismatch.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep compositing from the extension's live manifest | No new code | This is exactly what fails; wrong order/seams/bands |
| Fix `PositionTracker` to tolerate unordered, large-gap frames | Reuses existing type | Fights the streaming design; not the model for a fixed set |
| **BatchStitcher: recover order + geometry from the keyframes in the app (chosen)** | Matches the problem (fixed set); off-device, testable; leaves the streaming path untouched | New subsystem; O(n²) pairwise matches (fine for handful of keyframes) |

## Decision

Add `StitchKit.BatchStitcher` — recovers scroll order from pairwise vertical offsets,
measures repeated chrome by intersection across adjacent pairs, and hands a built
`StitchSession` to the existing `Compositor`. In the app, resolve geometry **once at
import** (`StitchAssembler.resolveGeometry`) and persist a corrected manifest, so the
existing composite and edit flows work unchanged on a now-correct manifest.

## Rationale

The repro proved the alignment/compositor core is correct; only the front-end (ordering,
seam/segment/band derivation) was wrong for a fixed set. Doing this in the app (not the
real-time extension) keeps it off the memory-constrained, jetsam-prone hot path and makes
it fully verifiable off-device. Resolving at import (not at every composite) preserves
manual edits (trim/band/offset) — the user still edits a normal manifest.

## What Changed

- **New** `StitchKit/Sources/StitchKit/BatchStitcher.swift` — `plan(_:)` (order + session)
  and `stitch(_:)` / `writePDF(_:to:)`. Ordering via confidence-anchored 1-D position
  solve; downward-only search taking the more-confident of masked/plain per pair;
  non-overlapping frames fall into separate segments.
- **New** `StitchKit/Tests/StitchKitTests/BatchStitcherTests.swift` + `Fixtures/Example/`
  (the three real screenshots as the committed oracle); `Package.swift` registers them.
- **App** `StitchAssembler.resolveGeometry(_:in:)` re-derives + reorders the manifest;
  composite/PDF now use a wider (±16 px) refinement to match BatchStitcher's provisional.
- **App** `LibraryModel.importFromGroup` calls `resolveGeometry` once at import and
  persists the corrected manifest (best-effort; falls back to the extension manifest).
- **New** `LongshotTests/BatchAssemblyTests.swift` — feeds scrambled overlapping keyframes
  through the real `refresh()` flow; asserts reorder + correct stitched height.

## What Was Discovered

- File/time order ≠ scroll order for a real capture set — ordering must be recovered, not
  assumed. The position-solve recovers `[2,0,1]` for the example set.
- `edgeConfidence = 0.45` is the one tuned constant (calibrated on the example set: real
  overlap scored ~0.55, the non-overlapping pair was rejected). It's the most likely knob
  to need replacing with an adaptive relative-confidence gap on other content.
- Chrome must be measured by **intersection** across adjacent pairs, not union: a
  coincidentally-static content row in one pair would otherwise over-crop and eat content.
- Known envelope: vertical scroll only, same-width frames, content with horizontal
  texture, opaque static chrome. Translucent chrome remains a documented gap.
- Step 2 (simplify the extension to dumb "commit a keyframe every ~half-screen" capture,
  retiring the real-time tracker) is deferred until a device capture validates Step 1 and
  shows what the current extension actually captures.

## Step 2 — extension capture (implemented)

On device the capture produced *nothing* (empty Library) — the app never received keyframes.
Since Step 1 proved the app stitches whatever keyframes exist (verified in the simulator by
injecting a session into the App Group, and via `BatchAssemblyTests`), the remaining failure is
capture-side: the streaming `PositionTracker`/`FrameSelector` that drove keyframe selection could
lose lock and never commit.

**Change:** new `StitchKit.KeyframeSelector` — a dumb capture policy that keeps only the last
committed frame's profile and commits when the view has scrolled ≥ `commitFraction` (default 0.5)
of a frame since then, using the static-chrome mask + downward-only search so fixed bars can't pin
scroll to zero. `SampleHandler` now uses it instead of `PositionTracker` + `FrameSelector`, and
writes a **keyframes-only** manifest (no seams/segments/bands) — the app re-derives geometry with
`BatchStitcher` at import (Step 1). Trailing frame committed at `broadcastFinished` only when
`hasUncommittedMotion` (avoids banking a near-duplicate tail the app would read as a gap).

**Discovered / open:**
- The app already handles the new manifest shape: `BatchAssemblyTests` feeds a *scrambled,
  seam-less* keyframe set (harder than the extension's scroll-order output) and stitches correctly.
- Selection must use the chrome mask: without it, a static status/nav bar pins measured scroll to
  zero and the extension would never commit — a plausible cause of the empty capture.
- Still device-gated: whether the extension reliably banks keyframes during a real broadcast
  (memory ceiling, ReplayKit delivery) can only be confirmed on device. The diagnostics trace now
  logs `commit=/overlap=/kf=` per traced frame to make the next device run diagnosable.
