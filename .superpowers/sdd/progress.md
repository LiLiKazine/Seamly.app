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
- CB4+5 eab0836: manifest contentBands + SampleHandler wiring + Compositor per-segment crop +
  missing-seam median fallback. Repro GREEN (both variants ratio 0.99, band (24,20), marker once).
  Supporting fixes: (a) OffsetMatcher confidence 1e-3 floor zeroed low-variance matches → ratio-based;
  (b) repro fixtures pathological → text-line block model, dense frames, upright builder.
- CB6 385e719: EditView per-segment band steppers; removed Seam.chromeTop/Bottom; deleted
  ChromeDetector/ChromeBands + tests.

## Verification (evidence) — DONE
- `swift test` (StitchKit): **69 tests pass**.
- `xcodebuild ... build`: **BUILD SUCCEEDED** (app + LongshotBroadcast extension).
- `xcodebuild ... test`: **TEST SUCCEEDED** (app tests + UI launch).
- ChromeStitchReproTests (acceptance): RED→GREEN, both variants ratio 0.99, band (24,20),
  chrome once + marker once (extended assertions).
- Final whole-branch review (2 independent agents):
  - Correctness reviewer: all focus areas verified correct; 1 Important finding
    (single-pair segment break) → fixed 2e6de2f (persistence streak).
  - Silent-failure hunter: no rule violations; Finding 1 (band low-confidence not
    surfaced) + Finding 2 (fallback undocumented) → fixed b8c8f2d.

## Commits (content-band fix)
b547adb CB1 · 17233b2 CB2 · 486eb74 CB3 · eab0836 CB4+5 · 385e719 CB6 · b8c8f2d review-fix-1/2 · 2e6de2f review-fix-3

STATUS: DONE — all done-criteria met with evidence.

---

# Capture-Side Isolation & Simulation Test (spec 2026-07-22) — active

Spec: `docs/superpowers/specs/2026-07-22-capture-side-simulation-test-design.md`
Plan: `docs/superpowers/plans/2026-07-22-capture-side-isolation-and-simulation-test.md`
Branch: `fix/on-device-stitching-real-frames`. Base commit (plan doc): see git log.

**Goal:** Extract pure `ScrollCaptureDriver` (behaviour-preserving refactor of SampleHandler),
add synthetic + video off-device test tiers driving it, and fix BatchStitcher's fixed
edgeConfidence=0.45 gate to accept real image-heavy overlaps (video → one continuous segment)
without regressing Example/baidu/wechat non-overlap breaks.

**Do NOT commit** the uncommitted deployment-target change (26.5→26.0 in project.pbxproj +
CLAUDE.md/README.md) — out of scope, leave in working tree.

## CSI task status
| # | Task | Status | Commits |
|---|------|--------|---------|
| CSI1 | Extract ScrollCaptureDriver + refactor SampleHandler | done | 8f059b2 a69b9cf |
| CSI2 | Synthetic tier: CaptureSimulator + CaptureSimulationTests | done | aa33902 540f90d |
| CSI3 | Video tier: trim fixture + VideoFrameSource + CaptureVideoTests | done | 8a3981d |
| CSI4 | (RE-SCOPED) Defer stitcher fix; document + known-issue in video tier | done | 50ab986 |

## CSI log
- CSI1: complete (commits 8f059b2..a69b9cf, review clean after 1 comment-only fix). ScrollCaptureDriver extracted; SampleHandler dumb adapter; 91 StitchKit tests pass, app+ext build OK.
- CSI2: implemented (aa33902) + review fixes in flight. DONE_WITH_CONCERNS→reviewed Approved.
  Scenario 1: 4 keyframes (3 regular + 1 trailing), one segment, clean. Scenario 2: 7 keyframes,
  monotonic order recovered, BUT one `.lostLock` segmentBreak at kf3→4.
  **CROSS-TASK → CSI4:** that kf3→4 break is a REAL overlap wrongly rejected by BatchStitcher's
  0.45 edgeConfidence floor (driver committed a correctly-overlapping keyframe; blind pairwise
  match scored the edge low) — the SAME bug class CSI4 fixes. Scenario 2 currently asserts
  `segmentBreaks.count == 1`. When CSI4's adaptive edge gate lands, re-run CaptureSimulationTests:
  if the fix merges that edge (expected → 0 breaks), CSI4 MUST flip scenario 2's assertion to
  `segmentBreaks.isEmpty` (bonus acceptance signal that the fix helps the synthetic tier too).
  If CSI4's criterion happens not to merge it, keep count==1. Either way CSI4 owns this decision.
  Note: full `swift test` now ~5.5 min (debug-build profiling ~130 real frames/scenario) — accepted.
- CSI2: complete (commits aa33902..540f90d, review Approved; fixes: fling/break framing re-scoped, overlaps() doc corrected, bands tightened 0.40-0.60, tolerance-coupling note). Both scenarios green.
- CSI3: complete (commit 8a3981d, review Approved, no Critical/Important). 362 frames / 0 decode
  failures / 5 keyframes / overlaps 0.469-0.536 / order [0..4]. Fixture scroll-recording.mp4
  ~10.5MB HEVC 1320x2868 6.03s (-c copy). Current-code segmentBreaks=[2,3] (two breaks) — the
  bug CSI4 fixes; correctly NOT asserted here.
  MINOR findings (defer to final whole-branch review, do not fix now — video suite is ~7-8 min/test):
    (a) VideoFrameSource.swift:40 — CMSampleBufferGetImageBuffer nil -> continue doesn't count as
        a decode failure (effectively unreachable for a 32BGRA track output; from the brief verbatim).
    (b) CaptureVideoTests.swift ~:31/:40 — keyframe-count floor uses #expect not #require; a
        0-keyframe failure would crash the subsequent 0..<(-1) loop instead of failing cleanly.
- CSI4: BLOCKED — spec §4 premise is mis-diagnosed. Measured per-pair edges on the 5 video keyframes:
  0->1 conf0.82, 1->2 conf0.90 (accepted). But 2-3: forward 2->3 dy329 conf0.35 LOSES to reverse
  3->2 dy1 conf0.43 (spurious "no-scroll") -> rejected by minEdgeDy. 3-4: forward conf0.048, reverse
  4->3 dy1 conf0.28 wins -> rejected. Frame 4 (trailing finish() commit of a mid-scroll trim) is
  ~unmatchable: best forward edge 0->4 conf0.173, within 0.006 of worst true non-overlap (wechat
  4->1 conf0.167). Full layout sweep floors 0.45->0.05: NO floor yields order=[0,1,2,3,4] breaks=[];
  low floors attach frame4 only via wrong-direction 4->0 (0.335) -> order=[4,0,1,2,3] (regresses
  monotonic-order test). => An adaptive/relative *floor* (the whole §4 mechanism) operates on the
  WINNING direction and cannot override a wrong-direction winner. Real fix needs a directional-
  consistency edge model in layout() (BatchStitcher, not OffsetMatcher) + re-trimming the fixture to
  drop the unmatchable trailing tail. ESCALATED to user for scope decision (matcher-adjacent work
  was scoped out). Tree reverted clean; guards prototyped GREEN on current code then reverted.
- CSI4 DECISION (user): accept the stitcher-side flaw for now, finish capture side, leave the
  BatchStitcher direction-mis-scoring fix as a documented FOLLOW-UP. Re-scoped CSI4 = (a) add a
  `withKnownIssue` stitch assertion to the video tier documenting the current break + follow-up
  (reusing the existing plan, no new video decode), (b) write a dev log capturing the root-cause
  finding + candidate fixes + deferral. NO Sources change, edgeConfidence untouched, wechat/baidu
  guards deferred with the fix. Then: whole-branch review + finishing-a-development-branch.
- CSI4 (re-scoped) complete (commit 50ab986): video tier records the deferred BatchStitcher direction-scoring limitation as a withKnownIssue (auto-activates when fixed); dev log docs/logs/2026-07-23-01 captures the root cause + candidate fixes. Capture side complete. NEXT: whole-branch review + finishing-a-development-branch.

## CSI final whole-branch review (opus, c88314c..50ab986) — Ready to merge: YES
No Critical/Important. Extraction confirmed behaviour-preserving; deferral honest + evidence-backed;
withKnownIssue correctly encoded; assertions verify real ground truth; determinism solid.
MINOR fixes to apply (batched, after the running full-suite finishes to avoid concurrent-build collision):
  1. CaptureVideoTests `batchStitcherRecoversMonotonicOrder`: stale comment says the break is what
     "Task 4's edgeConfidence fix addresses" — contradicts the deferral; reword to point at the
     deferral/dev-log (the fix does NOT address it). [most important — could misdirect follow-up]
  2. CaptureSimulationTests scenario 2 (count==1): add cross-ref to docs/logs/2026-07-23-01 + note to
     revisit with the fix. (Leave assertion; it currently passes so can't be withKnownIssue-wrapped.)
  3. CaptureVideoTests keyframe-count floor: use `try #require` not `#expect` (avoid 0..<(-1) trap).
  4. VideoFrameSource nil-buffer `continue`: one-line comment that the skip is intentional.
  5. SampleHandler: extend the divergence comment to note that on a first-keyframe WRITE FAILURE,
     orientation/colorSpace capture is skipped (meta.index==0 never lands) — reviewer judged
     comment-only, not a code change. Comment-only (no logic change).
Task-3 triage (a)/(b) folded into #3/#4 above.
- Final-review Minor fixes applied (commit 2010b6c): stale edgeConfidence comment corrected to point
  at the deferral/dev-log, keyframe-count floor -> try #require, nil-buffer skip documented,
  SampleHandler first-frame-write-failure orientation edge documented. CaptureVideoTests 3/3 pass
  (2 expected known-issues); xcodebuild BUILD SUCCEEDED. Full suite (pre-fixes) 96 tests green / 7
  known-issues. Working tree: only the intentional deployment-target change (uncommitted, out of scope).
STATUS: capture-side effort COMPLETE. Ready for finishing-a-development-branch.
- FINISHED: deployment target committed (1df6d2a, 26.5->26.0) per user request; branch pushed to
  origin; PR opened → https://github.com/LiLiKazine/Longshot/pull/1 (base main). Suite 96 green
  (7 known-issue xfails), app+ext build SUCCEEDED. Effort COMPLETE.

---

# Video & Photo Import (spec 2026-07-24) — active

Spec: docs/superpowers/specs/2026-07-24-video-and-photo-import-design.md
Plan: docs/superpowers/plans/2026-07-24-video-and-photo-import.md
Branch: feat/video-and-photo-import. Base: 06825c3.

## VPI task status
- Task 1: complete (commit c3dd0e6, review clean — spec ✅, quality Approved). BatchStitcher.plan(assumingOrder:) + buildPlan/segmentsAlong extraction; 8 BatchStitcherTests green.
- Task 2: complete (commit d8dbb1f, review clean — spec ✅, quality Approved). StitchSession.orderAssumed (Codable, decodeIfPresent default false). Full StitchKit suite 100 tests green (7 expected known-issue xfails). Note: implementer stalled before committing; controller verified tests+build and committed as bookkeeping. task-2-report.md left stale (prior-effort content) — did not mislead (reviewer verified against source).
- Task 3: complete (commit 246941a, controller-verified). VideoKeyframeSource (public, AVAssetReader→PixelBufferImage→ScrollCaptureDriver, timestamp throttle + progress); VideoFrameSource deleted; video tests async. CADENCE FINDING: re-validation gate failed at 12 fps (trailing pair 0.666) and 20 fps (near-dup 0.998); 30 fps passes (reproduces full-rate 5-keyframe set, ~2.7x less profiling). Plan Task 6 updated 12→30 fps. Full CaptureVideoTests 30 fps: 3 pass + batchStitcherRecoversMonotonicOrder 2 known-issue xfails (expected). Note: implementer stalled on the ~8min video test; controller did the cadence tuning + verification + commit.
- Task 4: complete (commit f5b59fd, review clean — spec ✅, quality Approved). OrderStrategy{recover,recoverOrInputOrder,inputOrder} + resolveGeometry(strategy:) sets orderAssumed; broadcast call site pinned to .recover (behaviour-preserving). MediaImportTests + BatchAssemblyTests TEST SUCCEEDED.
