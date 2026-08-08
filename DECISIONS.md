# Decision Log — Broadcast Scroll-Stitching

Reversible decisions made autonomously during the team-lead loop. Each entry says how to
reverse it. Format: `## [slice] Decision — why — alternatives — reversible? — confidence`.

## [plan] StitchKit built as a standalone SwiftPM package before Xcode integration
- Why: pure logic, no simulator/signing needed, `swift test` gives fast green evidence; the
  spec explicitly wants it as its own Swift-6 package to sidestep the "tests on Swift 5" gotcha.
- Alternatives: build it as an in-project framework target (couples to Xcode, harder to TDD fast).
- Reversible: yes — a package folder is self-contained; can be re-homed as a target later.
- Confidence: high.

## [A3] Incidental `dx` measured in full-res Compositor refinement, not the profile matcher
- Why: `FrameProfile` is a per-row vertical signal with no horizontal information, so
  profile-based `OffsetMatcher` structurally cannot recover `dx`. The spec only wants `dx`
  *monitored* to flag a seam (scroll views are vertically locked). The full-res seam
  refinement in `Compositor` has real pixels and is the natural place to measure a small
  horizontal shift and set `Seam.isLowConfidence`.
- Alternatives: add a per-column HorizontalProfile to every frame (extra per-frame work in
  the memory-constrained extension for a monitoring-only signal) — rejected.
- Reversible: yes — a HorizontalProfile can be added later without changing `Match`'s shape.
- Confidence: high.

## [B2] Keyframes default to raw BGRA-to-disk; lossless HEIC offered but pending device check
- Why: the pixel-exact/hard-cut design depends on byte-faithful keyframes. ImageIO has no
  guaranteed public "lossless HEIC" switch, and the ~50 MB extension encode-memory spike is
  an explicit device go/no-go. Raw BGRA-to-disk is guaranteed lossless and allocation-free
  (a memcpy), which the spec names as the fallback. So the extension defaults to raw; HEIC is
  implemented and selectable once device memory/fidelity is verified.
- Reversible: yes — format is per-keyframe (filename extension), switchable without schema change.
- Confidence: high.

## [plan] On-device "early verifications" treated as pending, not blockers
- Why: cue-from-extension, lossless-encode memory peak, ReplayKit pixel format, and iOS 26
  picker behavior all require a physical device and the developer's signing team — outside
  autonomous reach. Code is written to the spec's documented fallbacks (raw-to-disk, detect-
  and-segment) so it is correct whichever way the device checks land.
- Reversible: yes — they are runtime config toggles, not architectural forks.
- Confidence: high.
- **Verified on device 2026-07-04 (iPhone 17 Pro Max, iOS 26)** — all four passed:
  - cue-from-extension ✅ haptic felt during scroll.
  - memory peak ✅ extension ran a full capture with no jetsam/crash report → raw-BGRA-to-disk
    default confirmed; HEIC stays optional/unneeded.
  - ReplayKit pixel format ✅ end-to-end stitch produced a clean Ready thumbnail with no color
    corruption (CoreImage normalizes whatever format ReplayKit delivers before keyframes are
    written as BGRA).
  - iOS 26 picker behavior ✅ `RPSystemBroadcastPickerView` listed Longshot and started the broadcast.

## [B4] `LibraryModel.importFromGroup` must create the app `sessions/` dir before moving
- Why: `FileManager.moveItem` does not create intermediate directories; on a fresh install
  nothing had created `…/Longshot/sessions/`, so the first import threw and a bare `try?`
  swallowed it — the "coming back from a broadcast does nothing" bug. Fix creates the parent
  first and replaces the swallowing `try?` with logged `do/catch` per CLAUDE.md's error rule.
- Alternatives: create the dir lazily in `SessionStore` on every read (broader surface, hides
  the intent) — rejected in favor of an explicit create at the import site.
- Reversible: yes — a localized guard; covered by `BroadcastImportTests`. — `459f2cc`
- Confidence: high (fix verified on device: capture appeared on return).

---

# Content-Band Stitching Fix (spec 2026-07-04)

Goal: content band as a first-class, segment-stable concept via multi-frame consensus +
adaptive bootstrap; use it in matching (Gap 1) and compositing (Gap 2) so output height ≈
unique content (±10%) for high- and low-variance screens.

Baseline (iter 0): `swift test` → 57 tests, 55 pass, 2 RED repro. low-var 264px/1kf (ratio
0.21, whole scroll lost = Gap 1); high-var 594px/3kf, chromeTop=76 (true 24), chromeBottom
23→73 (ratio 0.48 = Gap 2).

## [CB-plan] Central interface design pinned up front for cross-slice consistency
Reversible: yes — additive within StitchKit, behind the package API. Confidence: high.

- **Slice 1 — matcher mask.** `match(_ a, _ b, searchRange, rowMask: [Bool]? = nil)`. Default
  nil = unchanged (keeps 55 baseline green). Term for overlap index k (b row k ↔ a row
  offset+k) included iff `rowMask == nil || (rowMask[k] && rowMask[offset+k])`. Chrome is
  static in *screen* space so one mask indexes both frames. Masked overlap < minimumOverlap →
  rejected (nil). `[Bool]` not `ClosedRange` because bootstrap needs an arbitrary static mask.
- **Slice 2 — `ContentBand { topChrome, bottomChrome, isLowConfidence }`** in *source pixels*,
  Codable/Sendable/Equatable. `ContentBandDetector` (evolve ChromeDetector), works in *profile
  rows*, mutating struct owned per-segment by tracker: `staticMask(a,b)->[Bool]?` (content =
  NOT static vs prev; nil when too few content rows → caller matches unmasked);
  `observe(a,b,dy:)` accumulates per-row static votes over moving pairs, locks after
  `minMovingFrames` (3) when band stable; `lockedBand:(top,bottom)?` in rows;
  `bandChangedSharply(a,b)->Bool`. Delete `ChromeDetector`/`ChromeBands` once unused (slice 3/4).
- **Slice 3 — tracker.** Owns detector reset per segment. Non-first frame: staticMask → masked
  (bootstrap) or unmasked (pre-scroll); observe; post-lock use locked band as mask +
  bandChangedSharply → segment break. Expose `TrackingResult.lockedBand: ContentBand?` (pixels
  via rowScale). No-stall test: low-variance advances from frame 1.
- **Slice 4 — manifest.** `StitchSession.contentBands: [ContentBand]` by segment; graceful
  decode `?? []`; `contentBand(forSegment:)` default {0,0,lowConf}. Remove `Seam.chromeTop/
  BottomPixels` (unknown keys ignored on old-manifest decode). SampleHandler stops calling
  ChromeDetector, writes bands from `result.lockedBand` by segment. No confident lock →
  {0,0}+isLowConfidence (content never lost, chrome merely repeats) + editor override.
- **Slice 5 — compositor.** Crop by `contentBand(forSegment:)` not `refinedSeams.first`; keep
  pixel-exact refine within band. Missing-seam fallback = median of segment's known dys (never
  the full band, which stacks).
- **Slice 6 — EditView.** Per-segment ContentBand steppers bound to `draft.contentBands`,
  non-destructive re-composite.

## [CB-exec] Drive slices with subagent-driven-development; interfaces pinned above
- Why: slices are sequential+dependent (SDD is the composition-map engine). Pinning interfaces
  centrally prevents fresh implementers from choosing inconsistent shapes. Each slice: TDD
  red→green, fresh reviewer. `swift test` is the fast loop for slices 1–5; `xcodebuild` gates
  slices 4/6 (extension + app compile).
- Reversible: yes. Confidence: high.

## [CB-fixtures] Revise repro fixtures to model real content (distinct per-row luminance)
- Finding (measured, ChromeDiagTests): the original repro fixtures produce content with almost
  no vertical signal for a mean+variance profiler. HIGH = per-pixel white noise → every row
  averages to ~0.5 gray → scrolling changes only ~14/211 profile rows. LOW = `220-(r%10)`
  (period 10) with step 110 (multiple of 10) → row means alias to identical values when
  scrolled. Neither is trackable by design, and no masking/consensus can recover absent signal.
- Real screen content (what "the matcher tracks easily" means, and what mean+variance profiling
  targets) has distinct per-row luminance. Fix: both variants get distinct, non-aliasing
  per-row means via a per-row hash; they differ only in *horizontal variance* — the true HIGH
  vs LOW distinction the two gaps test. Chrome stays high-variance static; geometry, the unique
  marker, and all assertions are preserved (and extended per spec: chrome once, marker once).
- Why legitimate (not gaming): the bug under fix is chrome-bias/wiring, not "track pure noise";
  the spec itself calls for extending this test. The absolute 0.02 static tolerance is correct
  for realistic content (chrome Δ=0 vs content Δ~0.3) — no classifier change needed.
- Reversible: yes — fixture-only; the geometry/assertions contract is unchanged. Confidence: high.

## [CB-seam-fields] Defer removing Seam.chromeTop/BottomPixels to slice 6
- Why: those fields are read by Compositor (slice 5) and EditView (slice 6). Removing them in
  slice 4 breaks compilation before their readers migrate. Sequence: slice 4 stops *writing*
  them (SampleHandler no longer sets chrome on seams, drops ChromeDetector), slice 5 stops the
  Compositor *reading* them (crops by contentBand instead), slice 6 migrates EditView and then
  deletes the now-unused fields. Keeps the package green after every slice.
- Reversible: yes. Confidence: high.

---

# Real-Frame Stitching Fix (2026-07-05, branch fix/on-device-stitching-real-frames)

## [iter 0] Pulled the real failing capture data off the device via devicectl
- The three prior fix cycles all lacked a real-broadcast-frame oracle; the failing
  manifests+keyframes were never captured. Pulled them directly with
  `xcrun devicectl device copy from --domain-type appDataContainer --source "Library/Application Support"`
  (the full-container copy aborts on a locked Library/SplashBoard .ktx; the subpath copy works).
- Two real sessions recovered (884x1918 BGRA keyframes + manifest.json), staged in scratchpad:
  - EA09E4FF — Baidu feed in Safari, 7 keyframes, clean overlapping DOWNWARD scroll.
    Manifest: seams=[] (ZERO), 6 segmentBreaks (one per frame), all bands {0,0} lowConf → TOTAL SHATTER.
  - 80DEBF70 — WeChat: kf0=home screen, kf1=app-launch animation, kf2..4=chat list.
    Manifest: seam0 fromIndex0 dy=2124 (> frame height 1918 = zero overlap, GARBAGE) conf 0.54;
    break after 1 (contentChanged) + after 2 (lostLock); seam fromIndex3 dy=0 conf 1.0
    (matcher locked to static WeChat top/bottom bars = chrome-bias at dy=0).
- Reversible: yes — data is read-only scratchpad; no repo change yet. Confidence: high (visually confirmed frames overlap).

## [iter 0] Done-criteria for this run (confirmed with user)
- Fix the core so real frames stitch; build a REAL-FRAME test oracle from these captures (not windowed screenshots).
- "Done" = StitchKit + app + extension green AND a real-frame regression oracle green AND built/installed
  to the connected iPhone with a one-tap verify flow, AND user confirms a fresh on-device capture is correct.
- Hard-stop allowlist unchanged: no force-push, no new worktree, no App Store submit; the FINAL on-device
  capture confirmation is the user's (I cannot perform a real scroll+broadcast).

## [iter 1] ROOT CAUSE confirmed: grayscale conversion corrupts the match signal
- Reproduced the on-device failure on the real keyframes via the actual StitchKit
  OffsetMatcher/PositionTracker: on the clean Baidu downward scroll the matcher returns
  the right MAGNITUDE but WRONG SIGN (e.g. kf01->02 true +750px, matcher -749px), so the
  tracker treats every real forward scroll as backward -> skips/loses lock -> shatters (0 seams).
- Isolated with full-resolution pixel MAD (decisive: +750px MAD 14 vs mirror 56, a 4x margin)
  then a 4-way {mean+var, 2-D} x {manual BT.601 luma, CoreGraphics DeviceGray}:
  * manual luma  -> CORRECT sign for BOTH mean+var and 2-D.
  * CoreGraphics DeviceGray render -> WRONG sign for BOTH.
- Root cause: `VerticalProfile.renderGray` draws the sRGB frame into a DeviceGray CGContext;
  CoreGraphics' gamma-managed sRGB->gray distorts the per-row luma of real COLORED UI enough
  to invert the correlation minimum. The matcher/threshold work from prior cycles was fine;
  the signal feeding it was corrupted.
- Why synthetic tests lied 3x: synthetic gray fixtures have no color/gamma to distort, so the
  bug is invisible to them; real colored screens trigger it. This is the testing-gap meta-lesson,
  finally pinned to a concrete mechanism.
- Fix direction: compute per-row luma from RGB bytes with a fixed BT.601 weighting (no
  DeviceGray gamma conversion). Keeps the validated mean+variance matcher.
- Reversible: yes — localized to VerticalProfile rendering. Confidence: high (validated next).

## [iter 1] Grayscale fix VALIDATED on real frames; two secondary issues scoped
- Rebuilt FrameProfiles with manual BT.601 luma, fed the REAL OffsetMatcher+PositionTracker:
  EA09 Baidu now matches 5/6 pairs with CORRECT sign+magnitude vs full-res ground truth
  (+250,+112,+358,+284,+382 rows); shatter 7 segments -> ~3. The core inversion is fixed.
- Remaining, secondary (partly keyframe-granularity artifacts, need live frames to fully judge):
  * Issue B: matcher gives FALSE high-confidence matches between genuinely non-overlapping
    frames (WeChat home-screen -> app-launch animation, conf 0.73). Pre-app junk corrupts tracking.
    (The "recording started before the app was open" case.)
  * Issue C: CORRECT-magnitude matches on low-overlap (~39%) pairs score low confidence and can
    false-lostLock. Likely a keyframe-gap artifact (live frames overlap much more).
- Decision: land the grayscale fix FIRST (primary, high-confidence, fully verifiable on real
  keyframes), with the real keyframes bundled as the regression oracle. Then add a frame-trace
  debug mode to the extension so the final on-device capture yields a LIVE frame sequence to build
  a faithful oracle for Issues B/C, rather than guessing from sparse keyframes.
- Reversible: yes. Confidence: grayscale fix high; B/C scoping medium (pending live frames).

## [iter 2] CORRECTION + FINAL root cause: orientation + degenerate signal (supersedes the grayscale entry)
- The iter-1 "grayscale is the cause" entry was CONFOUNDED: those scratch tools also toggled a
  vertical flip. Disentangling {flip}x{grayscale} with one controlled render showed grayscale does
  NOT affect the match sign; the FLIP does. Grayscale is not the fix.
- With a DECISIVE 2-D row-signature signal, every real Baidu pair comes out consistently NEGATIVE
  with the correct magnitude at the pipeline's flip orientation -> the flip is a true geometric
  sign inversion. Real downward scroll -> negative dy -> tracker skips (never appends) -> shatter.
- Why synthetic + wikipedia tests passed anyway (3 cycles of false green):
  * PROBE: synthetic gradient content is decisive (conf 1.00); real feed content collapses to a
    near-tie under the mean+variance reduction (degenerate). So synthetic fixtures never exercised
    the degeneracy.
  * RealFrameStitchTests builds "scroll" via `shot.cropping` which is BOTTOM-REFERENCED, so its
    scroll runs OPPOSITE to a real top-down downward capture -- it accidentally validated the
    inverted orientation. This is why the one "real screenshot" oracle still lied.
- FINAL FIX (two coupled parts, both needed):
  1. Correct profile ORIENTATION so a real captured (top-down) frame's downward scroll yields
     POSITIVE dy (matching the extension's max(0,dy) seam convention + the compositor's positive
     refinement search + top-down draw).
  2. Replace the mean+variance match signal with PER-ROW LUMINANCE SIGNATURES (2-D MAD, variance-
     weighted). Decisive on real content (proven ~5x margin at 64x640); kills the degeneracy that
     made prior threshold-tuning fragile. ContentBandDetector keeps using per-row mean/variance
     (fine for static-row chrome detection).
- Oracle: bundle the real device keyframes (Baidu 7kf downward, WeChat 5kf) as the regression
  fixture and assert correct-sign stitching; FIX the wikipedia test's bottom-ref orientation so it
  models a real downward scroll.
- Reversible: yes (all within StitchKit + tests). Confidence: HIGH — root cause reproduced and the
  fix signal proven decisive on the real frames.

## [iter 3] Fix implemented in core; synthetic test fixtures need re-orientation
- Implemented: FrameProfile now carries per-row luminance SIGNATURES (dual init: mean-only init
  synthesizes 1-col rows so array-built matcher tests are unchanged); OffsetMatcher does
  variance-weighted 2-D MAD over signatures (rowDifference); VerticalProfile computes BT.601
  luma from an sRGB RGBA render and NO LONGER FLIPS (the flip inverted real top-down frames).
- Proven on the real oracle: with the bootstrap chrome mask (as PositionTracker uses it) ALL 6
  Baidu pairs now recover correct POSITIVE (downward) offsets matching full-res ground truth.
  Core bug fixed.
- Consequence: the synthetic test fixtures were built UPSIDE-DOWN and compensated by the old VP
  flip (two flips cancelled) — so real upright frames were always inverted/broken while synthetic
  tests passed. Removing the VP flip exposes this: 12 tests fail because their fixture builders
  (TestImages.make via makeImage; RealGeometryStitchTests.image via `dst=h-1-r`; RealFrameStitch
  bottom-ref crop; ChromeStitchRepro; Compositor reference) encode the old inverted convention.
- GROUND TRUTH for the fix (established empirically): new VerticalProfile maps CGImage data-row-0
  -> profile row 0 (top-down), and real frames (CGImageSource/readRaw, status bar at data row 0)
  stitch correctly downward=positive. Synthetic builders must be re-oriented to match: a frame's
  visual TOP must be profile row 0, and a downward scroll (later frame shows lower doc content)
  must yield positive dy — with NO compensating flip anywhere.
- Reversible: yes. Confidence: HIGH on core fix; test re-orientation is mechanical-but-careful.

## [iter 4] CAUGHT a false-green oracle via end-to-end visual check (critical)
- The matcher fix is proven correct: with the bootstrap chrome mask, ALL 6 real Baidu pairs
  recover correct POSITIVE offsets near ground truth. And the Compositor had a SECOND real bug:
  drawStrip block-reversed multi-piece segments vertically (masked by single-frame/symmetric test
  fixtures) — matching the field symptom "scrolled-to-top frame rendered below scrolled-down
  (inverted order)". Both fixes landed; full unit suite green (74).
- BUT compositing the real FULL-RES keyframes end-to-end still produced 3 stacked, DUPLICATED
  frames (top third == middle third). The half-res fixtures passed the oracle falsely: 2 breaks
  cleared the (relaxed) <=2 bound, 0 seams made the positive-seam check vacuous, and 3 stacked
  frames happened to fall in the height band. Exactly the meta-lesson (false green) — caught only
  by rendering the real output and looking at it.
- Root oracle flaw: HALF-RES fixtures (rowScale 959/640=1.5) do not match real device geometry
  (1918/640=3.0); the different downsample changes matching, so half-res passed while full-res
  shattered. FIX: fixtures must be FULL RESOLUTION.
- Deeper truth: the sparse keyframes from the *broken* capture have huge frame-to-frame gaps
  (kf00->01 ~1165px, ~60% of a frame = a fast flick). On such gaps the correct match reads
  low-confidence (feed periodicity) -> lostLock -> segment break. That is arguably correct
  behavior (fast scroll -> segment); a normal-speed LIVE capture yields dense frames (small gaps,
  high confidence) that stitch. So full end-to-end CANNOT be validated from these sparse keyframes
  — it needs a live dense-frame capture (the frame-trace task + device capture).
- Actions: (1) full-res fixtures; (2) keep the strong matcher-recovers-offsets oracle (faithful);
  (3) make the pipeline test HONEST (assert positive seams + correct segment order; mark the ideal
  "dense stitch, no duplication" as a withKnownIssue pending live dense-frame verification — do NOT
  fake green); (4) add extension frame-trace so the user's capture produces the dense-frame oracle.
- Reversible: yes. Confidence: matcher+compositor fixes HIGH; full end-to-end PENDING live capture.

## [iter 5] Fixed app built + installed to the device; awaiting user's live capture
- `xcodebuild ... -destination id=<iPhone>` device build SUCCEEDED (signed: Li Sheng Apple
  Development); `devicectl device install` succeeded (bundleID io.github.lilikazine.Longshot).
- The one remaining step is external and user-reserved ("I prep + you do final capture"): a real
  ReplayKit broadcast scroll on device, which I cannot perform. Reached the agreed hand-back gate.
- Round-1 capture guidance (to isolate the core fix from the secondary WeChat pre-app issue):
  open the target app FIRST, then start the broadcast; scroll one direction at a normal reading
  pace. I'll pull the resulting session via devicectl and inspect the stitched output.
- Reversible: install is replaceable; no irreversible action taken.

---

# Component Harness CLI (2026-08-08, branch feat/component-harness-cli)

## [CH-plan] Add a separate testable harness product without changing `stitch-cli`
- Why: the existing `stitch-cli images|video` is a human-oriented end-to-end visual triage
  tool. Component diagnostics need stable JSON, strict argument validation, and in-process
  tests. A `StitchHarness` library target plus a thin `stitch-harness` executable provides that
  contract without breaking existing commands or mixing `@main` process behavior into tests.
- Commands: `profile`, `match`, `capture`, `plan`, `session`, `compose`, and `pipeline`.
  Inputs are real image files/directories, videos, or persisted session folders that map to
  current `StitchKit` APIs; stdout is one schema-versioned JSON envelope and artifact-producing
  commands write only under an explicit output directory.
- Boundary: the macOS SwiftPM executable exercises the extracted production seams
  (`ScrollCaptureDriver`, `BatchStitcher`, `SessionStore`, `Compositor`). It does not pretend to
  host ReplayKit or SwiftUI; those platform adapters remain app/extension integration concerns.
- Alternatives: retrofit JSON modes into `stitch-cli` (compatibility risk), or fake app/ReplayKit
  hosts (misleading coverage). Both rejected.
- Reversible: yes — the new product/targets are additive and can be removed independently.
- Confidence: high.

## [CHP-1] Split raw-frame capture from Photos/committed-image pipelines
- Why: the merged `pipeline images` feeds sparse Photos screenshots and already-committed
  keyframes through `ScrollCaptureDriver`, which is tuned for dense temporal frames. On the six
  ground-truth Photos fixtures it retains 3 of 6 images, invents a segment break, drops content,
  repeats chrome, and still reports success. The production Photos path plans every selected image.
- Decision: expose distinct raw-frame, Photos, and committed-image semantics. Photos and committed
  inputs bypass capture selection, while raw frames explicitly exercise `ScrollCaptureDriver`;
  video retains its real decoder → driver path. Retain `images` only as a documented legacy
  spelling: `pipeline images` now canonicalizes to the corrected Photos path, while
  `capture images` canonicalizes to the raw-frame component probe.
- Shared prerequisite: move recover/input/recover-or-input planning into `StitchKit` so the app and
  harness call the same implementation and produce the same `orderAssumed` result.
- Alternatives considered: keep one `images` mode plus `--frames all|committed` (easy to misuse),
  or document the current behavior only (leaves the Photos diagnostic gap and bad success output).
- Reversible: yes — additive modes and a shared planning API can be reverted on this branch.
- Confidence: high; reproduced against full-resolution ground-truth pixels and visually inspected.
