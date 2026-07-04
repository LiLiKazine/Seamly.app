# Implementation Plan — Broadcast Scroll-Stitching

**Derived from:** `docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md`
**Branch:** `feat/broadcast-scroll-stitching`
**Engine:** subagent-driven-development (StitchKit, sequential TDD) + team-lead-driven project surgery & UI wiring.

## Strategy

Build the pure, fully-testable core (`StitchKit`) first with strict TDD — it needs no
Xcode project, no simulator, no signing, and `swift test` gives green evidence. Then do
the Xcode project surgery (local package dep, App Group, broadcast-extension target) and
wire the thin app + extension layers, verifying each structural change with `xcodebuild`
against the iPhone 17 simulator.

## What is genuinely verifiable autonomously

- **StitchKit**: 100% — `swift test` green. This is the bulk of the product logic.
- **App + extension**: build-verifiable on the simulator; the four "Early on-device
  verifications" in the spec (§ cue-from-extension, lossless-encode memory peak, ReplayKit
  pixel format, iOS 26 picker behavior) require a **physical device + a signing team** and
  are outside autonomous reach. They are flagged as pending device go/no-go checks, not
  blockers for the code deliverable.

## Slices

### Part A — StitchKit (SwiftPM package, TDD, `swift test`)
- **A1** Package scaffold + `StitchSession` Codable manifest model.
- **A2** `VerticalProfile` — frame → downscaled grayscale → per-row `[mean, variance]` (vImage).
- **A3** `OffsetMatcher` — variance-weighted MAD slide → `Match(dy, confidence)`, incidental `dx`.
- **A4** `ChromeDetector` — per-seam static top/bottom bands, tolerance-epsilon, motion-gated.
- **A5** `PositionTracker` — `maxY`/union, tracking vs. relocalize, append/skip/segment-break + safety margin.
- **A6** `FrameSelector` — keep/skip + keyframe-commit state machine (≥30% overlap guarantee).
- **A7** `Compositor` — assemble keyframes, pixel-exact local refinement, hard-cut seam, raster + PDF, color-space preserved.

### Part B — Xcode project integration & app shell
- **B1** Add StitchKit as a local package dependency to the app target; App Group entitlement; verify app builds on sim.
- **B2** App Group session store + launch/foreground pickup scan; `StitchSession` I/O; empty-session handling.
- **B3** Capture-start UX: `RPSystemBroadcastPickerView` SwiftUI wrapper + 3-step onboarding.
- **B4** Library home surface (processing → ready), import from App Group, delete.
- **B5** Assembly + preview (downscaled proxy, inline flags), manual editing (offset/trim/chrome), export (PNG/JPEG/PDF, Photos/Share/Copy/Files).

### Part C — Broadcast extension
- **C1** Add `LongshotBroadcast` Broadcast Upload Extension target + entitlements + Info.plist; embed in app.
- **C2** `RPBroadcastSampleHandler` wired to StitchKit lightweight path (profile, track, select, chrome, cue attempt) writing keyframes + incremental manifest to the App Group.
- **C3** Whole-project simulator build green; end-to-end wiring review.

## Done-criteria (evidence required)

- [ ] `swift test` for StitchKit green — paste output.
- [ ] `xcodebuild build` (app + extension, iPhone 17 sim) green — paste output.
- [ ] Every spec v1 feature mapped to a delivered change (no orphan goals) — traceability table in ledger.
- [ ] Final whole-branch review clean or only Minor findings recorded.
- [ ] On-device go/no-go checks documented as pending (device + team required).
