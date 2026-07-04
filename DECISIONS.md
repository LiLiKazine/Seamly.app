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
