# Longshot — Broadcast Scroll-Stitching Design

**Date:** 2026-07-04
**Status:** Approved design, pre-implementation
**Supersedes:** The README's "pick screenshots from Photos" flow as the primary experience. Album import is not in scope for v1.

## Summary

Longshot lets a user capture a **long screenshot of any app** by scrolling. The user
starts a screen broadcast, switches to the target app, scrolls through the content,
and stops. Longshot receives the live screen frames, selects overlapping keyframes,
and stitches them into one seamless long image that the user can review, fine-tune,
and export.

The product pivot from the original README: instead of manually taking and picking
screenshots from the Photos library, capture is **automatic while the user scrolls**.
On iOS the only way to capture *another app's* screen is ReplayKit system broadcast, so
that mechanism is the foundation of the design.

## Product decisions (from brainstorming)

- **Capture source:** any app, via ReplayKit system broadcast. (Not: album picker, not
  in-app browser.)
- **Capture model:** process-after-stop. No live preview during scroll (the app is
  backgrounded while the user is in the target app, so live preview is effectively
  impossible). Assembly happens when the user returns to Longshot.
- **v1 features (all in):** core capture→stitch→preview→save; manual seam adjustment;
  share + copy to clipboard; confidence warnings; low-quality frame skipping.
- **Deferred (roadmap):** horizontal stitching, annotation tools, share extension from
  Photos, iPad/macOS, Vision-based coarse seeding.

## Architecture — targets

Broadcast capture forces a three-piece structure plus a shared container.

1. **`StitchKit` — local Swift package (pure, testable core).**
   No UIKit, no ReplayKit — Accelerate + Core Graphics only. Imported by both the app
   and the extension. All real logic lives here; this is where TDD happens. As its own
   package it builds in Swift 6 with its own Swift Testing suite, sidestepping the main
   project's "test targets on Swift 5" gotcha.

2. **`Longshot` (app target) — SwiftUI.**
   Start-capture screen, a Library of past captures, the scrollable preview with
   confidence flags + manual seam adjustment, and export. Does the heavy pixel
   compositing (generous memory here).

3. **`LongshotBroadcast` (Broadcast Upload Extension) — new target.**
   An `RPBroadcastSampleHandler` that receives live screen frames. Runs only lightweight
   StitchKit steps (1-D profiles, offset math, frame selection) and streams selected
   keyframes + a manifest to disk. Does **no** compositing — this keeps it under the
   ~50 MB extension memory ceiling.

4. **App Group container.** Shared handoff: extension writes keyframes (HEIC) + manifest
   JSON; app reads them after the broadcast stops.

**Memory-safety principle:** the extension only ever holds ~2 frames plus tiny 1-D
profiles and decides *which* frames to keep; the app does the actual assembly afterward.
The extension never builds the big image.

**Why a broadcast extension at all:** iOS only lets you capture *other apps* via
ReplayKit system broadcast — there is no alternative API. Accepted trade-off: the user
explicitly starts a screen recording (tap → 3-sec countdown → red indicator), switches
to the target app, scrolls, and stops it from the system UI (the app cannot auto-stop
it). Onboarding must make this flow clear.

## Capture data flow (broadcast → extension → disk)

A broadcast delivers a continuous video stream (many frames, tiny shifts between them),
which matches more reliably than sparse discrete screenshots.

**Startup (first two frames):**
1. Frame 1 → 1-D grayscale profile (vImage→vDSP); keep the full frame buffered.
2. Frame 2 → **chrome detection**: rows byte-identical between the two frames are the
   non-scrolling chrome. Yields top-chrome band, bottom-chrome band, and the *scrolling
   band* between them. All offset math runs on the scrolling band only (this is what
   stops the fixed nav/tab bars from corrupting the offset).

**Steady state (each subsequent frame):**
3. Compute `dy` + confidence vs. the previous frame, over the scrolling band (MAD/vDSP).
4. Classify:
   - `dy ≈ 0` → paused / duplicate → **skip**.
   - low confidence or implausibly large `dy` → mid-animation / blur / ad reflow →
     **skip**, mark a potential break (feeds confidence warnings).
   - good match → add `dy` to a running cumulative offset since the last keyframe.
5. **Keyframe commit:** when cumulative offset since the last saved keyframe reaches
   ~65% of the scroll-band height, save the current frame as a keyframe (HEIC → App
   Group) and append a manifest entry `{keyframeID, dy-from-previous-keyframe,
   confidence}`. The 65% threshold guarantees ≥30% overlap between saved keyframes —
   ample for a robust re-match at assembly time.

**Stop:** `broadcastFinished()` writes the final manifest (chrome bands, ordered
keyframe list, per-seam confidence, device scale) and flags the session complete.

**On disk:** an ordered set of overlapping keyframes + a small manifest. Memory stays
flat regardless of scroll length.

Two implementation decisions:
- **Offsets are recomputed authoritatively in the app** at assembly, from the saved
  keyframes; the extension's `dy` is a provisional hint. The precise seam math runs
  where memory is ample and code is testable.
- **Keyframes are full frames, not pre-cut strips** — simpler, and lets manual seam
  adjustment re-cut anywhere later without having discarded pixels.

## Stitching engine (`StitchKit` internals)

Six small, single-purpose, unit-testable pieces.

- **`VerticalProfile`** — reduces a frame to a 1-D signal. `CGImage`/`CVPixelBuffer` →
  downscale + grayscale (vImage) → per-row mean over a few sampled column bands
  (left/mid/right). Stores per-row horizontal variance so near-uniform rows can be
  ignored (solid backgrounds match everywhere; this prevents false matches). Output: a
  compact `[Float]` per frame.

- **`OffsetMatcher`** — `match(_ a:, _ b:, searchRange:) -> Match(dy: Int, confidence:
  Double)`. Slides B's top against A's bottom, scores each candidate with variance-
  weighted mean-absolute-difference (vDSP). Confidence = how decisively the best offset
  beats the runner-up (guards against repeated-row UI producing multiple near-equal
  minima). Integer `dy`; no sub-pixel (screenshots never scroll fractionally).

- **`ChromeDetector`** — `detect(_ a:, _ b:) -> ChromeBands(top: Int, bottom: Int)`.
  Contiguous run of ~identical rows from the top and from the bottom between two frames.
  Content-driven and exact — no hardcoded status-bar heights or device tables.

- **`FrameSelector`** — the keep/skip + cumulative-offset state machine. Pure function of
  `(incoming match, running state) -> Decision`. Home of "low-quality frame skipping."

- **`Compositor`** — `assemble(keyframes:, manifest:) -> CGImage`. Canvas width = min
  keyframe width. Draws frame 1 *with* its top chrome; each subsequent frame contributes
  only newly-revealed rows (below the verified overlap) via **hard-cut seam** — no
  feathering (identical pixels; blending would only blur crisp text); the final frame
  contributes its bottom chrome. Core Graphics `CGContext`.

- **`StitchSession`** — `Codable` manifest model (keyframe refs, offsets, confidences,
  chrome bands, device scale) shared across extension↔app.

**No Vision in v1.** Research showed `VNTranslationalImageRegistrationRequest`'s global
registration is degraded by fixed chrome and is not pixel-exact; once chrome is excluded,
MAD matching is both simpler and more accurate. Revisit Vision only as a coarse seed if a
pathological case ever demands it.

## Assembly, preview, editing & export (app side)

- **Session pickup.** On broadcast end, the app notices the completed session (Darwin
  notification if foregrounded, else on next launch/foreground) and loads manifest +
  keyframes from the App Group. New captures land in a **Library** list so nothing is
  lost if the user doesn't act immediately.
- **Assembly.** App runs `Compositor` on the keyframes, re-verifying each seam offset
  authoritatively. Per-seam confidence travels with it.
- **Preview.** Vertically-scrollable stitched result. Low-confidence seams marked inline
  (subtle divider + tappable marker) so the user knows where to look / re-capture.
- **Manual seam adjustment.** Tapping a seam opens a focused editor on that junction:
  the two contributing frames with a **drag handle** to nudge the cut row. Because full
  keyframes are kept, we re-cut anywhere and re-composite instantly. Adjustments update
  the manifest; the rest of the image is untouched.
- **Export.** Save to Photos, Share (system share sheet), Copy to clipboard. Photos
  write access requested only at export time.
- **Very tall images.** v1: assemble at full resolution but **cap total height** with a
  clear warning if exceeded (rare); render the preview from a downscaled proxy while
  keeping the full-res image for export. No tiling engine in v1.

## Testing strategy

Bottom-heavy pyramid by design.

- **`StitchKit` — the bulk, pure Swift Testing.** Synthetic fixtures from a tall
  reference image sliced at known offsets → assert `OffsetMatcher` recovers exact `dy`,
  `ChromeDetector` finds exact bands, `Compositor` reproduces the original pixel-for-
  pixel. Adversarial fixtures: uniform bands, repeated list rows, minimal overlap,
  mid-scroll content change, a low-confidence seam.
- **`FrameSelector`** — synthetic frame sequences (pauses, jumps, blur-like low-
  confidence frames) → assert correct keep/skip/keyframe-commit decisions.
- **App & extension layers stay thin** — ReplayKit and PhotosUI are hard to unit test,
  so they hold as little logic as possible; everything meaningful is delegated to
  `StitchKit`, which is fully covered.

## Risks & constraints

- **~50 MB extension memory ceiling** — mitigated by holding only ~2 frames + 1-D
  profiles and never compositing in the extension. Primary thing to watch during build;
  if HEIC encode spikes, fall back to writing lighter frames.
- **User controls stop, not the app** — broadcast ends via system UI. Onboarding must
  make the full flow obvious (start → switch apps → scroll → stop → return).
- **Broadcast captures the entire screen** during the session — a genuine privacy point.
  State it plainly; nothing leaves the device (consistent with README's promise).
- **Signing complexity** — App Group + broadcast extension both need provisioning under
  the developer's own team.
- **Pixel format** — broadcast frames arrive as BGRA `CVPixelBuffer` at device
  resolution; vImage handles conversion. Preserve device scale in the manifest for
  correct export resolution.
- **Very tall images** — cap + warn in v1.

## Out of scope for v1

Album/Photos import, horizontal stitching, annotation tools, a Photos share extension,
iPad/macOS support, Vision-based registration, and a tiling engine for extreme-height
images. These remain on the roadmap.
