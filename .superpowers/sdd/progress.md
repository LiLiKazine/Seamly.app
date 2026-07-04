# Progress Ledger — Broadcast Scroll-Stitching

**Goal:** Implement the approved broadcast scroll-stitching design end-to-end: a pure
`StitchKit` core (TDD), a SwiftUI app (capture-start, library, preview, edit, export),
and a `LongshotBroadcast` upload extension, all building on the iPhone 17 simulator with
StitchKit tests green.

**Branch:** `feat/broadcast-scroll-stitching` (in main worktree `/Users/leo/Developer/Longshot`)

**Done-criteria:**
1. `swift test` (StitchKit) green — pasted evidence.
2. `xcodebuild` app + extension build green on iPhone 17 sim — pasted evidence.
3. Every spec v1 feature mapped to a delivered change.
4. Final whole-branch review clean / only Minor findings.
5. On-device go/no-go checks (cue, memory peak, pixel format, picker) documented as pending device+team work.

**Hard-stop allowlist (task-specific):** no signing-team-dependent device runs, no App Store
submission, no force-push, no new worktree. On-device verifications are out of autonomous reach.

## Task status

| # | Task | Status | Commits |
|---|------|--------|---------|
| A1 | StitchKit scaffold + StitchSession | done | 8e3fc26 |
| A2 | VerticalProfile | done | 6f90e6c |
| A3 | OffsetMatcher | done | ecb948a |
| A4 | ChromeDetector | done | 108d5a5 |
| A5 | PositionTracker | done | 0024325 |
| A6 | FrameSelector | done | f45e376 |
| A7 | Compositor | done | 496f399 |
| B1 | Project: package dep + App Group | done | 479a0ea |
| B2 | App Group session store + pickup | done | 510602c |
| B3 | Capture-start + onboarding | done | 510602c |
| B4 | Library home surface | done | 510602c |
| B5 | Preview + edit + export | done | 510602c |
| C1 | Broadcast extension target scaffold | done | da4b8de |
| C2 | RPBroadcastSampleHandler wiring | done | da4b8de |
| C3 | Whole-project build + review | done | 66ef035 |

## Verification (final)
- StitchKit: `swift test` → **55 tests in 8 suites passed** (incl. golden pixel-exact reproduction).
- App + extension: `xcodebuild ... -scheme Longshot` → **BUILD SUCCEEDED** (iPhone 17 sim), no warnings in our code.
- App launches on sim (Library + first-run onboarding verified via screenshot).
- Whole-branch review (2 parallel reviewers): all Critical/Important/Minor findings fixed; one
  PLAUSIBLE-only thread-safety note left documented (ReplayKit serializes callbacks).

## Spec v1 feature → delivered change
| v1 feature | Where |
|---|---|
| Capture via ReplayKit broadcast | LongshotBroadcast SampleHandler + BroadcastPickerButton |
| Track/stitch (union model) | StitchKit PositionTracker + OffsetMatcher + VerticalProfile |
| Keyframe selection / low-quality skip | StitchKit FrameSelector |
| Chrome crop | StitchKit ChromeDetector + Compositor |
| Assembly (pixel-exact, hard-cut, color space) | StitchKit Compositor |
| Preview (downscaled proxy, flags) | PreviewView + StitchAssembler.makeProxy |
| Manual editing (offset/trim/chrome) | EditView + StitchSession trim + Compositor |
| Export PNG/JPEG + PDF, Photos/Share/Copy/Files | Exporter + ExportView + Compositor.writePDF |
| Confidence warnings / segment breaks | Seam.isLowConfidence, SegmentBreak, PreviewView warnings |
| Safety cue (sound+haptic) | SampleHandler.fireSafetyCue (device go/no-go pending) |
| Library home + pickup + delete | LibraryModel + LibraryView + SessionStore |
| Partial/incomplete sessions usable | SessionStore.loadAll tolerance + import staleness gate |
| App Group handoff | AppGroup + SessionStore + KeyframeIO |

## Pending (require a physical device + signing team — out of autonomous reach)
Spec's four early on-device verifications: cue-from-extension audibility, lossless-encode
memory peak (raw-to-disk is the safe default now), ReplayKit pixel format/color range, and
iOS 26 broadcast-picker behavior. Code is written to the spec's documented fallbacks.

## Log
- A1–A7 StitchKit core (8e3fc26 6f90e6c ecb948a 108d5a5 0024325 f45e376 496f399)
- B1 project integration (479a0ea) · B3–B5 app UI (510602c)
- C1–C3 broadcast extension (da4b8de)
- Review fixes (ca4653e)

---

# Content-Band Stitching Fix (spec 2026-07-04) — active

Spec: `docs/superpowers/specs/2026-07-04-content-band-stitching-fix-design.md`
Decisions: `DECISIONS.md` → "Content-Band Stitching Fix" section (interfaces pinned there).

**Goal:** content band as first-class, segment-stable concept (multi-frame consensus +
adaptive bootstrap), used in matching (Gap 1) and compositing (Gap 2) → output ≈ unique
content (±10%) for high- and low-variance screens.

**Done-criteria:** ChromeStitchReproTests GREEN both variants (+ extended: chrome once, marker
once); new per-slice unit tests green; 55 baseline stay green; `xcodebuild` app + extension
GREEN; final review clean/Minor.

**Baseline (CB iter 0):** `swift test` → 57 tests, 55 pass, 2 RED. low-var 264px/1kf (0.21×);
high-var 594px/3kf, chromeTop=76 (true 24), chromeBottom 23→73 (0.48×).

## CB task status
| # | Task | Status | Commit(s) |
|---|------|--------|-----------|
| CB1 | Row mask in OffsetMatcher | done | b547adb |
| CB2 | ContentBand model + ContentBandDetector (consensus + bootstrap + change signal) | done | 17233b2 |
| CB3 | Wire detector into PositionTracker (bootstrap→locked; TrackingResult.lockedBand; no-stall) | done | 486eb74 |
| CB4 | Manifest contract (contentBands per segment; SampleHandler) | done | (with CB5) |
| CB5 | Compositor crop by segment band; missing-seam fallback; repro GREEN | done | (commit below) |
| CB6 | EditView per-segment band adjustment; remove Seam chrome fields; delete ChromeDetector | done | (commit below) |

## CB log
- CB iter 0: baseline captured; interfaces pinned in DECISIONS.md.
- CB1 b547adb, CB2 17233b2, CB3 486eb74.
- CB4+5: manifest contentBands + SampleHandler wiring + Compositor per-segment crop + missing-seam
  median fallback. Repro GREEN (both variants ratio 0.99, band (24,20), marker once). Required two
  supporting fixes discovered via diagnostics: (a) OffsetMatcher confidence had an absolute 1e-3
  floor that zeroed low-variance matches → made ratio-based; (b) repro fixtures were pathological
  (per-pixel noise averages to gray; period-10 aliased with step; builder upside-down) → rewrote to
  text-line block model, dense frames, upright builder (DECISIONS CB-fixtures). Seam.chromeTop/Bottom
  fields still present (removed in CB6 after EditView migrates). 74 StitchKit tests green.
