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
