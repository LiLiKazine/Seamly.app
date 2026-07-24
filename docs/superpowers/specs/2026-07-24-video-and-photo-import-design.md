# Video & Photo Import — Design

**Date:** 2026-07-24
**Status:** Approved (brainstorming) — ready for implementation plan.

## Summary

Add two new ways to create a long screenshot, alongside the existing live broadcast
capture:

1. **From Video** — pick one screen recording; the app decodes it and stitches the
   scrolled content into a long screenshot.
2. **From Photos** — pick multiple overlapping screenshots; the app stitches them into
   a long screenshot.

Both ship together in one effort. Both reuse the entire existing downstream pipeline
(Library → Preview → Edit → Export) unchanged: the only genuinely new code is the two
picker front-ends, one shared session-writer, a productionized video decode source, and
one additive `BatchStitcher` overload.

This is cheap precisely because of the recently landed *capture-side separation*: the
pure `ScrollCaptureDriver` (frame-in → keyframe-out) and `BatchStitcher` (fixed unordered
image set → ordered `StitchSession`) already do the hard work, and the video decode path
is already proven by the `VideoFrameSource` test tier against a real recording.

## Goals

- Two new entry points as **three peer buttons** (Record / From Video / From Photos) on
  the empty-Library hero and the capture sheet.
- Video: single screen recording from the Photos library → long screenshot.
- Photos: multiple overlapping screenshots (any pick order) → long screenshot.
- Reuse Library/Preview/Edit/Export with no changes to their contracts.
- Honest surfacing of uncertainty (badges) and errors (no silent swallow, per CLAUDE.md).

## Non-goals

- Fixing the deferred `BatchStitcher` direction-scoring limitation (documented known
  issue). This design *works around* it, it does not fix it.
- Video from Files / arbitrary non-scroll video content. v1 is Photos-library screen
  recordings with steady vertical scrolling.
- Any change to the live broadcast capture behavior.

## Architecture & data flow

```
From Photos ─┐
             ├─→ [ordered CGImages] ─→ MediaImporter ─→ app SessionStore ─→ LibraryModel.adopt()
From Video ──┘   (+ orderTrust)        (write kf bytes         → reload + assemble
                                        + manifest,            → Preview/Edit/Export
                                        resolveGeometry)         (all unchanged)
```

The two entries differ **only** in how they produce the ordered image set and how the
order is trusted. Once images reach `MediaImporter`, the flow is identical to a finished
broadcast: a session folder appears in app storage and the Library adopts it.

### New code and where it lives

**StitchKit (pure, testable):**

- **`VideoKeyframeSource`** — promote the existing `VideoFrameSource` test helper to a
  real source. `AVAssetReader` → 32BGRA `CVPixelBuffer` → `PixelBufferImage.makeCGImage`
  → `ScrollCaptureDriver.ingest` (+ trailing `finish()`). Returns committed keyframes and
  frame / decode-failure counts. The existing test tier keeps using the same path.
  - Adds **timestamp-throttled** sampling (see "Video decode" below).
- **`BatchStitcher.plan(_:assumingOrder:)`** — additive overload that skips `layout()`
  and assembles along a *given* order, still measuring seams / chrome bands and emitting a
  segment break where two *consecutive* frames genuinely don't overlap. This is the
  mechanism behind the photos pick-order fallback and video capture-order trust. It is
  **not** the deferred direction-scoring fix — purely additive.

**App (`Core/`):**

- **`MediaImporter`** — off-main-actor writer. Takes an ordered `[CGImage]`, an
  `orderTrust` (`.recovered` | `.natural`), and a source tag (`.photos` | `.video`).
  Steps:
  1. Mint session id; create its folder in the app `SessionStore` (app storage directly,
     **never** the App Group).
  2. Write each image as `kf-NNNN.bgra` via `KeyframeIO`; capture pixel dims / color
     space from the first image (mirroring how `SampleHandler` sets session orientation +
     color space).
  3. Build the manifest: `.recovered` → `plan(images)`; `.natural` →
     `plan(images, assumingOrder:)`. Persist via `writeManifest`.
  4. Return the new session id and whether a pick-order fallback fired (for the badge).
- **`LibraryModel.adopt(_ id:)`** — reload the freshly written folder and run the existing
  `assemble()` → proxy; phase `processing → ready/failed`.
- **`StitchAssembler.resolveGeometry`** — refactor to take the same `orderTrust` so
  broadcast (`.recovered`) and `MediaImporter` share one plan/`assumingOrder` branch.
  Broadcast stays `.recovered` (behavior-preserving).

**App (`Features/`):** two SwiftUI front-ends (photo picker, video picker) that load
media into `CGImage`s and call `MediaImporter`.

## From Photos

**Picker & loading.** `PhotosPicker` limited to `.images`, multiple selection. Each
`PhotosPickerItem` loads as `Data` → `CGImage` at full device resolution (pipeline already
handles full-res keyframes).

**Guard rails:**

- Fewer than 2 images → refuse with a clear message ("Pick at least two overlapping
  screenshots").
- An item that fails to decode → surface which one failed; do not silently drop it.

**Ordering — recover, with pick-order fallback:**

1. Run `BatchStitcher.plan(images)` — full auto-recovery (handles a shuffled selection).
2. **Trust it** when the result is one clean chain: no `segmentBreaks` and no
   low-confidence seams.
3. **Otherwise fall back** to `plan(images, assumingOrder: identity)` — assume the user
   picked them top→bottom; still emit a genuine break where two *consecutive* picks truly
   don't overlap (so unrelated screenshots aren't force-fused).

The fallback trigger — "auto-recovery couldn't connect them into one confident scroll" —
is exactly when the deferred direction bug tends to bite. The user can still correct
order / breaks by hand in the existing EditView afterward.

**Badging:** when the pick-order fallback fires, the resulting `Capture` is badged in the
existing `statusLabel` vocabulary (alongside `Incomplete` / flagged-seam), e.g.
"Order assumed" — honest that order was assumed, not confidently recovered.

## From Video

**Picker.** `PhotosPicker` limited to `.videos`, single selection. The item is loaded to a
temporary file URL (`AVAssetReader` needs a URL; video is too large to hold as `Data`).

**Decode → keyframes.** `VideoKeyframeSource` decodes frames through the real driver:
`AVAssetReader` → 32BGRA → `PixelBufferImage.makeCGImage` → `ScrollCaptureDriver.ingest`,
plus the trailing `finish()` commit. The driver selects keyframes; only committed
keyframes are retained. This is the exact path the video test tier exercises against a
real recording.

**Video decode — timestamp-throttled sampling.** We do **not** profile every frame. The
driver already discards non-keyframes; the cost is *profiling* each frame. The selector
commits based on overlap with the last *committed keyframe*, so sampling coarser than the
source frame rate loses nothing as long as scroll between samples stays inside the overlap
budget. Plan: profile a frame only when ≥ `1 / targetFps` has elapsed since the last
profiled frame (target ~10–15 fps; robust to variable frame rates). Sample buffers are
still pulled sequentially (inter-frame codecs require it), but `makeCGImage` +
`VerticalProfile` are skipped on throttled frames — that's the saving.

> Note: a video codec's I-frames ("keyframes" in codec terms) are a compression artifact,
> unrelated to scroll position — they cannot be used as scroll keyframes.

**Re-validation gate:** the driver was tuned/proven on the full-rate stream, so the chosen
cadence MUST be re-validated against the existing `scroll-recording.mp4` fixture —
re-run the video tier at the throttled cadence and confirm keyframe count and overlap
bands stay healthy (baseline today: 5 keyframes, overlaps 0.469–0.536). Pick the coarsest
cadence that keeps those healthy.

**Ordering.** Driver keyframes come out in **capture (scroll) order**, which is
authoritative (nothing shuffled them). Video therefore *trusts the natural order*:
assemble with `plan(assumingOrder:)` along capture order, using measurement only to place
seams / chrome bands and to break at a genuinely non-overlapping jump. This also sidesteps
the direction-scoring bug the video test tier documents on its trailing frame.

**Guard rails:**

- No video track / unreadable asset → throw, surface the error.
- Per-frame decode failures are *counted* (expected-benign skip, matching the extension),
  logged via `Diagnostics`; a **zero-keyframe** outcome is "nothing to stitch," not
  success.

## UI & states

**Entry surface (three peer buttons).** On the empty-Library hero and the capture sheet,
`CaptureStartView` presents three peers:

- **Record** — today's live broadcast (`BroadcastPickerButton`); stays first/primary,
  copy unchanged.
- **From Video** — `.videos` `PhotosPicker` (single).
- **From Photos** — `.images` `PhotosPicker` (multiple).

The toolbar `+` presents this three-way sheet.

**States after picking.** Both new entries create a `Capture` immediately in
`.processing`, so it appears in the Library as work starts (consistent with a finishing
broadcast):

- **Photos:** brief processing (a handful of images) → `.ready`.
- **Video:** determinate progress (frames decoded / total by duration) on the row while
  `MediaImporter` runs → `.ready`.
- **Badging:** pick-order fallback → badge in the existing `statusLabel`. Video's
  trusted-order case is unbadged unless a genuine break was found.

**Empty/degenerate results** reuse the existing "Nothing to stitch" nudge (no-scroll video
or non-overlapping single-segment result).

## Error handling (per CLAUDE.md — no silent swallow)

- < 2 photos, no video track, unreadable asset, all-frames-decode-fail, item decode
  failure → each throws or surfaces a specific user-visible message; none default to a
  plausible-looking empty result.
- Per-frame video decode failures are counted (expected-benign, documented skip) and the
  total logged via `Diagnostics`; a zero-keyframe outcome is "nothing to stitch."
- `MediaImporter` failures propagate to the front-end, which sets a visible error state
  (mirroring `ExportView`'s `status = error.localizedDescription`).

## Testing (TDD, StitchKit-first)

- **`BatchStitcher.plan(assumingOrder:)`** — ordered assembly matches recovery on a clean
  in-order set; breaks still appear where consecutive frames don't overlap; a shuffled set
  assembled in-order stays in-order.
- **`VideoKeyframeSource`** — reuse the existing `CaptureVideoTests` fixture; add a test
  asserting the timestamp-throttled cadence keeps keyframe count + overlap bands healthy
  vs. the full-rate baseline (the §"Video decode" re-validation gate).
- **`MediaImporter`** (app tests) — from a bundled small overlapping-screenshot fixture
  set: writes a well-formed session folder + manifest; `resolveGeometry` / adopt produce a
  `.ready` capture; pick-order fallback fires and badges on a set recovery can't
  confidently chain.
- **Fixtures:** a 2–3 image overlapping screenshot set under the test bundle (photos),
  plus the existing `scroll-recording.mp4` (video).

## Reused unchanged

- `Compositor`, `Exporter`, `PreviewView`, `EditView`, `ExportView`, `SessionStore`,
  `KeyframeIO`, `StitchSession` model, `LibraryView` list/rows (plus badge string), the
  `assemble` / `fullComposite` / `exportPDF` / `update` / `delete` paths.
```
