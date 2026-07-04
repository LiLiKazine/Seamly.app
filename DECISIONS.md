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
