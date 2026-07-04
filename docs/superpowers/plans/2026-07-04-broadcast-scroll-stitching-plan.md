# Implementation Plan — Broadcast Scroll-Stitching

**Derived from:** `docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md`
**Branch:** `feat/broadcast-scroll-stitching` (13 commits, pushed to origin)
**Engine:** subagent-driven-development (StitchKit, sequential TDD) + team-lead-driven project surgery & UI wiring.

## Status: ✅ COMPLETE — all slices delivered

- **StitchKit:** `swift test` → **55 tests / 8 suites pass** (incl. golden pixel-exact reproduction).
- **App + extension:** `xcodebuild` → **BUILD SUCCEEDED** on iPhone 17 sim, no warnings in our code; app launches and renders.
- **Review:** two parallel reviewers; all Critical/Important/Minor findings fixed (commit `ca4653e`).
- **On-device verification (iPhone 17 Pro Max, iOS 26, 2026-07-04):** ✅ all four early go/no-go checks passed (cue, memory, pixel format, picker) and the full "coming back from a broadcast" flow works. A fresh-install import bug found during this pass is fixed (`459f2cc`, `BroadcastImportTests`); see `DECISIONS.md`.
- Live status ledger: `.superpowers/sdd/progress.md`. PR-open blocked by a `gh` account mismatch (branch pushed; user opens the PR).

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
- [x] **A1** Package scaffold + `StitchSession` Codable manifest model. — `8e3fc26`
- [x] **A2** `VerticalProfile` — frame → downscaled grayscale → per-row `[mean, variance]` (CoreGraphics + vDSP). — `6f90e6c`
- [x] **A3** `OffsetMatcher` — variance-weighted MAD slide → `Match(dy, confidence)`. — `ecb948a`
- [x] **A4** `ChromeDetector` — per-seam static top/bottom bands, tolerance-epsilon, motion-gated. — `108d5a5`
- [x] **A5** `PositionTracker` — `maxY`/union, tracking vs. relocalize, append/skip/segment-break + safety margin. — `0024325`
- [x] **A6** `FrameSelector` — keep/skip + keyframe-commit state machine (≥30% overlap guarantee). — `f45e376`
- [x] **A7** `Compositor` — assemble keyframes, pixel-exact local refinement, hard-cut seam, raster + PDF, color-space preserved; incidental `dx` flagging. — `496f399`
- [x] Plus `SessionStore` + `KeyframeIO` (raw BGRA lossless + HEIC) and manifest global trim. — `4100a9b`, `510602c`

### Part B — Xcode project integration & app shell
- [x] **B1** StitchKit local package dependency on the app target; App Group entitlement; app builds on sim. — `479a0ea`
- [x] **B2** App Group session store + launch/foreground **and Darwin-notification** pickup scan; `StitchSession` I/O; empty-session handling. — `4100a9b`, `510602c`
- [x] **B3** Capture-start UX: `RPSystemBroadcastPickerView` SwiftUI wrapper + 3-step onboarding. — `510602c`
- [x] **B4** Library home surface (processing → ready), import from App Group, delete. — `510602c`
- [x] **B5** Assembly + preview (downscaled proxy, flags), manual editing (offset/trim/chrome), export (PNG/JPEG/PDF, Photos/Share/Copy/Files). — `510602c`

### Part C — Broadcast extension
- [x] **C1** `LongshotBroadcast` Broadcast Upload Extension target + entitlements + Info.plist; embedded in app. — `da4b8de`
- [x] **C2** `RPBroadcastSampleHandler` wired to StitchKit lightweight path (profile, track, select, chrome, cue attempt) writing keyframes + incremental manifest to the App Group; trailing-frame commit on finish. — `da4b8de`, `ca4653e`
- [x] **C3** Whole-project simulator build green; end-to-end wiring review + fixes. — `da4b8de`, `ca4653e`

## Done-criteria (evidence)

- [x] `swift test` for StitchKit green — **55 tests / 8 suites passed**.
- [x] `xcodebuild build` (app + extension, iPhone 17 sim) green — **BUILD SUCCEEDED**, no warnings in our code.
- [x] Every spec v1 feature mapped to a delivered change — traceability table in `.superpowers/sdd/progress.md`.
- [x] Final whole-branch review clean — all Critical/Important/Minor findings fixed; one PLAUSIBLE-only thread-safety note documented (ReplayKit serializes callbacks).
- [x] On-device go/no-go checks **verified passed** (iPhone 17 Pro Max, iOS 26) — `DECISIONS.md`.
- [x] Fresh-install App Group import bug fixed and regression-tested — `459f2cc`, `BroadcastImportTests`.

## Deviations from the original plan
- **Engine:** the team lead drove StitchKit's sequential TDD directly (single package target makes parallel edits collide); subagents were used for the final parallel code review. App UI was written directly rather than swarmed.
- **`dx`:** the vertical profile carries no horizontal signal, so incidental `dx` is measured in the full-res `Compositor` refinement (and flags the seam), not in `OffsetMatcher`. — `DECISIONS.md`
- **Keyframe format:** defaults to raw BGRA-to-disk (guaranteed lossless, no encoder spike); lossless HEIC implemented but gated on the device memory check. — `DECISIONS.md`
- **Platforms:** the project was narrowed from the multiplatform template to iOS-only (ReplayKit broadcast is iOS-only).
