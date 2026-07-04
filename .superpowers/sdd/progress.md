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
| C1 | Broadcast extension target scaffold | done | (this) |
| C2 | RPBroadcastSampleHandler wiring | done | (this) |
| C3 | Whole-project build (review pending) | done | (this) |

## Log
(one line per completed task with commit range)
