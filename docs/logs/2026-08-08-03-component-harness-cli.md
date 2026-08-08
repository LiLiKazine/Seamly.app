# 2026-08-08-03: Component Harness CLI

**Status:** Implemented

## Context

`StitchKit` had a human-oriented `stitch-cli` for visual end-to-end diagnostics, but no stable,
machine-readable boundary for exercising its individual production components. Tests and automation
needed to invoke profiling, matching, capture, planning, session persistence, and composition without
embedding process behavior or pretending to host ReplayKit and SwiftUI inside a macOS package tool.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Add JSON modes to `stitch-cli` | Reuses one executable | Risks changing the existing visual-triage interface and couples two different contracts |
| Fake ReplayKit and SwiftUI hosts | Appears to cover the entire app | Misrepresents platform integration and adds brittle test doubles |
| Add a `StitchHarness` library and thin `stitch-harness` executable (chosen) | Keeps command dispatch testable, preserves `stitch-cli`, and uses production domain APIs | Adds one package product and a small adapter layer |

## Decision

Add an independent `StitchHarness` target with a thin `stitch-harness` executable that emits one
schema-versioned JSON envelope per invocation and writes artifacts only to caller-selected paths.

## Rationale

The library/executable split keeps argument parsing and command results directly testable while the
process boundary remains responsible only for stdout, stderr, and exit status. The commands exercise
the existing `ScrollCaptureDriver`, `VideoKeyframeSource`, `BatchStitcher`, `SessionStore`, and
`Compositor`, preserving the real domain behavior without expanding the package tool into an app or
ReplayKit host.

## What Changed

- Added `StitchHarness` library, `stitch-harness` executable, and `StitchHarnessTests` package targets.
- Added `profile`, `match`, `capture`, `plan`, `session`, `compose`, and `pipeline` commands for image
  and video inputs.
- Added stable success and error JSON envelopes, strict option validation, persisted-session
  validation, and safe keyframe path handling.
- Added streaming image capture, one-at-a-time inspection, and lazy persisted-image composition to
  bound memory use.
- Added 19 focused tests, including deterministic runtime-generated MP4 coverage for successful video
  capture and pipeline behavior.
- Documented command usage, artifact overwrite semantics, and the ReplayKit/SwiftUI boundary.

## What Was Discovered

- External manifests must be validated before any keyframe access; otherwise malformed indices,
  duplicate IDs, traversal filenames, or escaping symlinks can cross the persistence boundary.
- Capture, inspection, and composition originally retained more decoded images than necessary.
  Streaming capture and lazy persisted-image loading keep memory proportional to active keyframes.
- A one-keyframe session is valid diagnostic data but is not stitchable. Inspection now reports
  `stitchable: false`, while composition continues to reject it.
- `VideoKeyframeSource` reports processed and failed frame counts but does not expose safety-cue
  decisions, so video JSON explicitly uses `null` for that field.
- The built executable provides clean JSON process output; `swift run` may add SwiftPM diagnostics on
  stderr and is therefore not the recommended automation boundary.

## Verification

- `swift test`: 121 tests across 24 suites passed in 615.9 seconds, with one pre-existing recorded
  known issue in `RealDeviceStitchTests`.
- `swift test --filter HarnessDispatcherTests`: 19 focused tests passed.
- Both `stitch-harness` and `stitch-cli` products build.
- Strict-concurrency compilation with warnings treated as errors passes.
- Direct process smoke tests confirm JSON-only stdout on success and JSON-only stderr with exit 1 on
  failure.
- Final specialist audit found no remaining Critical or Important findings.
