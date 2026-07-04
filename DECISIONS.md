# Decision Log — Broadcast Scroll-Stitching

Reversible decisions made autonomously during the team-lead loop. Each entry says how to
reverse it. Format: `## [slice] Decision — why — alternatives — reversible? — confidence`.

## [plan] StitchKit built as a standalone SwiftPM package before Xcode integration
- Why: pure logic, no simulator/signing needed, `swift test` gives fast green evidence; the
  spec explicitly wants it as its own Swift-6 package to sidestep the "tests on Swift 5" gotcha.
- Alternatives: build it as an in-project framework target (couples to Xcode, harder to TDD fast).
- Reversible: yes — a package folder is self-contained; can be re-homed as a target later.
- Confidence: high.

## [plan] On-device "early verifications" treated as pending, not blockers
- Why: cue-from-extension, lossless-encode memory peak, ReplayKit pixel format, and iOS 26
  picker behavior all require a physical device and the developer's signing team — outside
  autonomous reach. Code is written to the spec's documented fallbacks (raw-to-disk, detect-
  and-segment) so it is correct whichever way the device checks land.
- Reversible: yes — they are runtime config toggles, not architectural forks.
- Confidence: high.
