# Longshot — Broadcast Scroll-Stitching Design

**Date:** 2026-07-04
**Status:** Approved design (grilled + refined), pre-implementation
**Supersedes:** The README's "pick screenshots from Photos" flow as the primary
experience. Album import is not in scope for v1.

## Summary

Longshot lets a user capture a **long screenshot of any app** by scrolling. The user
starts a screen broadcast, switches to the target app, scrolls through the content, and
stops. Longshot receives the live screen frames, tracks the user's absolute scroll
position, and stitches the revealed content into one seamless long image that the user
can review, fine-tune, and export.

On iOS the only way to capture *another app's* screen is ReplayKit system broadcast, so
that mechanism is the foundation of the design.

## Product decisions

- **Capture source:** any app, via ReplayKit system broadcast.
- **Capture model:** process-after-stop. No live preview during scroll (Longshot is
  backgrounded while the user is in the target app). Assembly happens on return.
- **Mid-capture guidance:** a **sound + haptic cue** (never an on-screen banner — a
  broadcast extension can't draw UI, and a notification banner would pollute the very
  frames being captured). The cue fires *early* (before content is lost) and its meaning
  is taught in first-run onboarding.
- **Recovery:** modeled as absolute-position tracking (see "Core model"), so scrolling
  back up is always safe. A truly-lost fast-scroll gap becomes a labeled segment break
  with in-app post-stop recapture — no automatic reconstruction, no fabricated pixels.
- **v1 features:** capture → track/stitch → preview → export; manual editing (offset
  correction at flagged seams, end-trim, chrome-crop override); share + copy; PNG/JPEG
  **and PDF** export; confidence warnings; low-quality frame skipping; a Library of past
  captures as the home surface.
- **Deferred (roadmap):** album import, 2-D/horizontal stitching, annotation tools, a
  Photos share extension, iPad/macOS, Vision-based registration, tiling for unbounded
  raster export, automatic in-session gap reconstruction.

## Architecture — targets

1. **`StitchKit` — local Swift package (pure, testable core).**
   No UIKit, no ReplayKit — Accelerate + Core Graphics only. Imported by both the app and
   the extension. All real logic lives here; this is where TDD happens. As its own
   package it builds in Swift 6 with its own Swift Testing suite, sidestepping the main
   project's "test targets on Swift 5" gotcha.

2. **`Longshot` (app target) — SwiftUI.**
   Capture-start + onboarding, the **Library** of captures, the scrollable preview
   (downscaled proxy) with confidence flags + manual editing, and export. Does the heavy
   pixel compositing and pixel-exact seam refinement (generous memory here).

3. **`LongshotBroadcast` (Broadcast Upload Extension) — new target.**
   An `RPBroadcastSampleHandler` that receives live screen frames, runs only lightweight
   StitchKit steps (1-D profiles, position tracking, relocalization, frame selection,
   chrome detection, the safety cue), and streams selected keyframes + an incremental
   manifest to the App Group. Does **no** compositing.

4. **App Group container.** Shared handoff: the extension writes keyframes + manifest;
   the app reads them after the broadcast stops.

**Memory-safety principle:** the extension only ever holds **one full frame** at a time
plus 1-D data; the app does all assembly afterward. The extension never builds the big
image. (Budget detail under "Extension memory model.")

**Why a broadcast extension at all:** iOS only lets you capture *other apps* via ReplayKit
system broadcast — there is no alternative API. Accepted trade-off: the user explicitly
starts a screen recording (tap → 3-sec countdown → red indicator), switches to the target
app, scrolls, and stops it from the system UI (the app cannot auto-stop it). Onboarding
makes this flow clear.

## Core model — absolute-position tracking ("capture the union")

The whole capture is modeled as tracking the user's **absolute scroll position** in
content-space, not as a sequence of independent pairwise stitches:

- Maintain a captured interval `[0 … maxY]` (how far down we've seen, in content rows).
- Track each frame's position by matching it to the **previous frame** — frame-to-frame
  `dy` is small, so matches are highly reliable with near-zero residual.
- **Append only content beyond `maxY`.** Scrolling *back up* moves the current position
  *within* already-captured range → nothing is appended (no duplication). Scrolling
  *down past* `maxY` → the newly-revealed rows are appended and `maxY` advances.

Consequences:
- **Scrolling up, down, pausing, re-reading, overshooting are all safe** — we capture the
  union of everything revealed.
- **Recovery is automatic**: after the safety cue, the user eases back over content we
  still have (we stay locked), then resumes down slowly and we capture the stretch we were
  about to miss.

Two matching modes:
1. **Tracking** (normal): match current frame vs. previous frame — cheap, tiny `dy`,
   near-zero residual.
2. **Relocalize** (after a lost lock, e.g. a fling with zero frame-to-frame overlap):
   match the current frame's profile against the **accumulated 1-D profile map**, biased
   toward the last known position and requiring a decisive confidence margin (guards
   against repeated-UI false matches). Re-locks → resume tracking. If it genuinely can't
   (truly new, never-seen content) → a real gap: fire the cue and, if unresolved, start a
   new segment (see below).

## Recovery, gaps & segments

- **Safety cue.** When frame-to-frame overlap drops below a safety margin (~40%, before
  content is lost), the extension fires a **sound + haptic** cue. Meaning is taught in
  onboarding ("if you feel a buzz, ease up / scroll back a little"). **No visual banner in
  any case.** Cue-from-extension feasibility must be verified early (see "Early on-device
  verifications"); if neither sound nor haptic works from a broadcast extension, we fall
  back to onboarding-only prevention + detect-and-segment.
- **Real gap → segment break.** If a fling loses the lock and relocalize can't recover, we
  close the current segment and start a new one at a **labeled break**. Everything before
  and after the gap is preserved.
- **Post-stop recapture (in-app).** After the user returns, the preview shows any labeled
  gaps and offers **"Recapture this stretch"** — a second short broadcast the app splices
  in by matching the new pass against the two frames bounding the gap (targeted, not a
  global search). If the recapture still doesn't cover both anchors, the gap stays labeled;
  we never fabricate content. (Automatic in-session reconstruction is out of scope.)

## Fast-scroll robustness

- **Dense-stream accumulation is ground truth.** Match every delivered frame against the
  previous one; keyframes are checkpoints derived from the running cumulative offset — this
  is what guarantees saved keyframes retain enough overlap for the app's pixel-exact
  refinement.
- **Keep per-frame work tiny** so ReplayKit doesn't throttle delivery: build the 1-D
  profile from an aggressively downscaled frame; touch full resolution only when committing
  a keyframe; copy-out-and-release each pixel buffer immediately.
- **Detect and be honest**: overlap below the floor → segment break + low confidence + the
  cue, never a silently garbled image. Onboarding asks for a steady, moderate pace.

## Stitching engine (`StitchKit` internals)

Small, single-purpose, unit-testable pieces.

- **`VerticalProfile`** — reduces a frame to a 1-D signal. Frame → downscale + grayscale
  (vImage) → per-row mean over a few sampled column bands (left/mid/right) **plus per-row
  horizontal variance**. Variance lets us ignore near-uniform rows (solid backgrounds match
  everywhere) and is also used by chrome detection. Output: a compact per-row `[mean,
  variance]`.

- **`OffsetMatcher`** — `match(_ a:, _ b:, searchRange:) -> Match(dy: Int, confidence:
  Double)`. Slides one profile against the other, scores candidates with variance-weighted
  mean-absolute-difference (vDSP). Confidence = how decisively the best offset beats the
  runner-up. Integer `dy`; no sub-pixel. Also reports the incidental horizontal component so
  a nonzero `dx` can be flagged.

- **`PositionTracker`** — implements the core model: holds `maxY`, the accumulated 1-D map,
  and the current position; runs tracking vs. relocalize; emits append/skip/segment-break
  decisions and the safety-margin signal that drives the cue.

- **`ChromeDetector`** — runs **per seam**, from the 1-D profiles (no full previous frame
  needed). A row is "static" if its mean *and* variance are within a **tolerance epsilon**
  of the other frame's (not byte-identical — survives clock ticks / anti-aliasing).
  **Motion-gated**: only runs once a frame pair shows clear non-zero scroll, so pre-scroll
  identical frames aren't mistaken for all-chrome. Contiguous static runs at top/bottom are
  that seam's chrome; a band that jumps vs. the previous seam (collapsing header) flags the
  seam low-confidence rather than being modeled.

- **`FrameSelector`** — keep/skip + keyframe-commit state machine driven by the tracker
  (home of "low-quality frame skipping"). Commits a keyframe each time `maxY` advances
  ~65% of the scroll-band height (guarantees ≥30% overlap between saved keyframes).

- **`Compositor`** — assembles keyframes + manifest into the final output. For each seam,
  performs the **pixel-exact local refinement** (small full-res ±few-px search around the
  extension's provisional offset). Draws frame 1 with its top chrome; each subsequent frame
  contributes only newly-revealed rows via **hard-cut seam** (no feathering — identical
  crisp pixels); the last frame contributes bottom chrome. Renders to a `CGImage` (raster
  path) or incrementally into a `CGContext` PDF (PDF path). Preserves source color space.

- **`StitchSession`** — the `Codable` manifest model: ordered keyframe refs, per-seam
  provisional offsets + confidence, per-seam chrome bands, segment breaks, orientation,
  color space, device scale, and a `status` (`recording` → `complete`). Written
  incrementally.

**No Vision in v1.** `VNTranslationalImageRegistrationRequest`'s global registration is
degraded by fixed chrome and isn't pixel-exact; once chrome is excluded, MAD matching is
simpler and more accurate. Revisit only as a coarse seed if a pathological case demands it.

## Authority split (extension vs. app)

- **Extension owns global structure** (it sees the dense stream): which frames are
  keyframes, their order, segment breaks, per-seam chrome bands, and *provisional* offsets +
  confidence.
- **App refines precision**: for each seam, a small **full-resolution local offset search**
  (±few px) around the provisional value places the cut pixel-exactly. No from-scratch
  global recompute — trust the structure, snap the precision.

## Extension memory model (~50 MB budget)

- **One full frame** at a time (`CVPixelBuffer`, ~14 MB). Copy out what's needed and
  **release immediately** — never retain across frames (retaining stalls ReplayKit's buffer
  pool and *causes* fast-scroll gaps).
- **Everything else is 1-D**: previous-frame profile (tens of KB), accumulated map
  (~8 bytes/row → ~320 KB for a 40k-row page). Chrome detection runs on profiles, so no
  second full frame.
- **Watched spike:** the lossless keyframe encode transiently allocates ~1–2× the image
  (~45 MB peak alongside the live buffer). Keyframes commit only ~once per 65%-band, so the
  spike is infrequent. If it threatens the ceiling on real devices, **fall back to
  raw-to-disk** (a ~14 MB `memcpy`, no encoder allocation). Measured early as a go/no-go.

## Persistence & session lifecycle

- **Session = a uniquely-IDed folder** in the App Group (`sessions/<uuid>/` with keyframes
  + `manifest.json`). Multiple sessions coexist.
- **Keyframes are lossless** — lossless HEIC by default (ReplayKit delivers uncompressed,
  pixel-faithful frames; only our save could lose data, and the pixel-exact/hard-cut design
  depends on faithful pixels). **Fall back to raw BGRA-to-disk** if lossless encode spikes
  memory.
- **Manifest written incrementally** — each keyframe entry appended on commit; `status`
  flips `recording` → `complete` in `broadcastFinished()`. A crash leaves it `recording`.
- **Partial sessions are still usable**: a session stuck at `recording` (OOM / interruption
  / phone call) is stitched from its committed keyframes and **badged "incomplete."** Never
  discard committed work.
- **Pickup source of truth = a scan on every launch *and* foreground** (the Darwin
  notification only makes pickup feel instant when Longshot is already open).
- **Empty/no-scroll session** (<2 keyframes / no real motion) → friendly "Nothing to
  stitch — did you scroll the other app?"; discard.
- **Library owns everything.** Imported sessions move to app storage; the App-Group folder
  is cleaned up after import. User can delete captures.

## Assembly, preview, editing & export (app side)

- **Assembly.** App runs `Compositor` (with pixel-exact seam refinement) over the
  keyframes.
- **Preview — always a downscaled proxy.** A GPU texture maxes out ~16,384 px/side, so a
  full-res stitch can't render as one texture beyond ~3–4 screens; the proxy is mandatory,
  not an optimization. Pinch-to-zoom lazily re-renders full-res **tiles** for the zoomed
  region. Low-confidence seams and segment breaks are marked inline.
- **Manual editing** (non-destructive — manifest edits, instant re-composite thanks to the
  full lossless keyframes), surfaced primarily on **flagged** seams:
  1. **Offset correction at flagged seams** — slide one contributing keyframe against the
     next with a live overlay until it lines up (replaces cut-row nudging, which is a no-op
     on identical-pixel overlaps).
  2. **Global top/bottom trim** — crop unwanted chrome/content at the very start/end.
  3. **Chrome-crop override per segment** — a draggable top/bottom line if auto-detect
     clipped content or left a sliver.
  Annotations / blur → roadmap.
- **Export.**
  - **PNG / JPEG** → Save to Photos, Share, Copy to clipboard. Raster path is bounded by a
    generous **memory-based height cap** (~30–40k px on a 1290-wide frame); full-res within
    the cap.
  - **PDF** → Share + Save to Files (Photos can't hold PDFs). Generated by drawing keyframe
    strips **incrementally into a `CGContext` PDF** — memory-safe and **not** subject to the
    texture limit, so the raster cap is lifted for this path. **Single continuous page**
    under the ~14,400 pt viewer ceiling; **paginate Safari-style** beyond it (with a note).
  - Photos write access requested only at export time.

## Onboarding & capture-start UX

- **First-run onboarding**, 3 steps, re-viewable: (1) "Tap Capture, choose *Longshot*."
  (2) "Switch to the app you want and scroll **steadily** — if you feel a buzz, ease up /
  scroll back a little." (3) "Stop from the red indicator and come back — your long
  screenshot will be waiting." This is where the safety cue's meaning is taught.
- **Use the system picker as-is.** Present the real `RPSystemBroadcastPickerView`
  (SwiftUI-wrapped) as the Capture CTA; set `preferredExtension` to bias toward ours;
  **do not** reach into its private subviews to auto-tap (fragile across versions).
- **Video-only** — mic not requested/needed.
- **Close the loop on return** — the Library shows the new capture (processing → ready), so
  success is unambiguous.

## Frame geometry — orientation & horizontal drift

- **Orientation consistent per segment.** Key off frame dimensions; a rotation mid-capture
  (dimension change) **closes the segment and starts a new one** (a flagged break) rather
  than stitching across orientations. Landscape long-shots are allowed — just not mixed
  within a segment.
- **`dx` assumed 0.** iOS scroll views are vertically locked. Monitor the incidental
  horizontal component; a consistent nonzero `dx` **flags the seam low-confidence** rather
  than being modeled. 2-D/horizontal stitching → roadmap.

## Color management

- **Preserve the source color space end-to-end** (P3-aware): read the pixel buffer's color
  attachments; tag keyframes with that space; composite in a matching (P3 / extended-range)
  `CGContext` working space; export tagged correctly. Never hardcode sRGB.
- **Matching is color-space-agnostic** — it runs on a grayscale profile with a fixed
  luminance conversion; color space only affects the final pixels.
- If ReplayKit delivers **YUV** buffers, use the correct range/matrix so colors aren't
  washed out.

## Early on-device verifications (go/no-go before committing the pipeline)

1. **Cue from a broadcast extension** — can we fire sound and/or haptic? (If not: onboarding
   prevention + detect-and-segment only.)
2. **Lossless-encode memory peak** — does the keyframe encode stay under the ~50 MB ceiling,
   or do we default to raw-to-disk?
3. **ReplayKit pixel format & color space** — BGRA vs. YUV, P3 vs. sRGB, full vs. video
   range.
4. **iOS 26 broadcast-picker API** — `RPSystemBroadcastPickerView` + `preferredExtension`
   behavior (known churn area; launches ours directly vs. shows a one-item sheet).

## Testing strategy

Bottom-heavy pyramid by design.

- **`StitchKit` — the bulk, pure Swift Testing.** Synthetic fixtures from a tall reference
  image sliced at known offsets → assert `OffsetMatcher` recovers exact `dy`,
  `ChromeDetector` finds exact bands (with tolerance + motion-gating), `PositionTracker`
  builds the correct union under up/down/overshoot sequences and relocalizes after a
  simulated lost lock, `Compositor` reproduces the original pixel-for-pixel. Adversarial
  fixtures: uniform bands, repeated list rows, minimal overlap, mid-scroll content change,
  a collapsing-header transition, a zero-overlap fling (→ segment break), a rotation
  (→ segment break).
- **`FrameSelector` / `PositionTracker`** — synthetic frame sequences (pauses, back-scroll,
  flings, direction reversals) → assert correct append/skip/keyframe/segment decisions and
  cue triggering at the safety margin.
- **App & extension layers stay thin** — ReplayKit, PhotosUI, PDFKit, the picker are hard to
  unit test, so they hold as little logic as possible; everything meaningful is delegated to
  `StitchKit`, which is fully covered.

## Risks & constraints

- **~50 MB extension ceiling** — mitigated by one-full-frame + all-1-D + immediate buffer
  release; lossless encode is the watched spike with raw fallback. Primary early check.
- **Cue channel** — depends on sound/haptic being available from the extension (verify).
- **User controls stop, not the app** — broadcast ends via system UI; onboarding must make
  the full flow obvious.
- **Broadcast captures the entire screen** during the session — a genuine privacy point.
  Stated plainly; nothing leaves the device.
- **Fast flings** can still create gaps despite prevention — handled by segment + recapture,
  not hidden.
- **Signing complexity** — App Group + broadcast extension both need provisioning under the
  developer's own team.
- **Very long content** — raster export capped + warned; PDF path uncapped (paginates past
  the viewer ceiling).

## Out of scope for v1 (roadmap)

Album/Photos import, 2-D/horizontal stitching, annotation tools, a Photos share extension,
iPad/macOS support, Vision-based registration, tiling for unbounded *raster* export,
automatic in-session gap reconstruction, and Live-Activity/Dynamic-Island capture status.
