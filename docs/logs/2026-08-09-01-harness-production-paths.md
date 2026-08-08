# 2026-08-09-01: Harness inputs must preserve their production path

**Status:** Implemented and verified

## Context

The component harness originally sent every image directory through `ScrollCaptureDriver` and
planned only the keyframes it committed. That is faithful for dense chronological frames, but not
for Photos import: the app writes every selected image and asks `BatchStitcher` to recover their
order, falling back to the user's selection order when recovery cannot form a continuous chain.

It is also wrong for `Fixtures/RealDevice`. Those files are keyframes already committed by the
broadcast driver. Running the selector again applies a video-rate sampling policy to an already
sampled sequence.

The mismatch produced a plausible-looking success envelope while dropping half of the six real
Photos screenshots:

| Path | Frames planned | Seams | Breaks | Composite |
|---|---:|---:|---:|---:|
| `stitch-cli images` production-shaped oracle | 6 | 5 | 0 | 1320×10316 |
| Old `stitch-harness pipeline images` | 3 | 1 | 1 | 1320×7279 |
| Fixed `stitch-harness pipeline photos` | 6 | 5 | 0 | 1320×10316 |
| Fixed `pipeline images` legacy spelling | 6 | 5 | 0 | 1320×10316 |

The old result also repeated browser chrome at the invented break and omitted content, despite
reporting `ok: true`. Structural success alone was therefore not evidence that the harness mirrored
the app.

## Decision

Make the source name select an explicit ingestion contract:

- `pipeline photos` plans every discovered image and defaults to `recover-or-input`. `pipeline
  images` remains its legacy spelling. This preserves old invocations, not old behavior: the
  original command incorrectly ran the driver over the directory.
- `pipeline committed` plans every discovered keyframe without selecting again and defaults to
  `recover-or-input`. It models broadcast keyframes such as `Fixtures/RealDevice`, which have
  already passed through `ScrollCaptureDriver`.
- `pipeline frames` accepts dense chronological raw frames, sends them through
  `ScrollCaptureDriver`, and defaults to `input` order.
- `pipeline video` decodes through `VideoKeyframeSource`, sends the frames through the same driver,
  and defaults to `input` order.
- `capture frames` is the directory-based driver probe. `capture images` remains its compatibility
  alias; capture does not claim to model Photos import.

Expose all three planning policies as `recover`, `recover-or-input`, and `input`.
`recover-or-input` first attempts pixel-overlap recovery; if that cannot form one continuous chain,
it keeps the input chronology and sets the persisted and reported `orderAssumed` flag. A successful
recovery and an explicitly trusted `input` order both report `orderAssumed: false`.

Directory-backed sources discover supported images after prefix filtering and ingest them in
lexical filename order. That order is the chronology trusted by `input` and the fallback used by
`recover-or-input`; a fixture directory cannot preserve a Photos picker sequence that was never
encoded into its filenames.

Keep `match` as a symmetric, bounded component probe over `OffsetMatcher`: it searches both signs
and reports the best candidate. It does not claim to reproduce production's directional layout
selection or its edge gates; `plan` and `pipeline` are the production-gate diagnostics.

## Rationale

`KeyframeSelector` is tuned for closely spaced, video-rate frames. Photos screenshots commonly have
about 50% overlap, while broadcast fixture directories have already passed selection. Applying the
driver to either shape conflates capture sampling with stitching and can silently reject legitimate
inputs. Keeping `frames` as a component probe, `photos` as the Photos-shaped pipeline, and
`committed` as the broadcast-keyframe path makes the diagnostic claim visible in the command
itself.

The fallback badge distinguishes two otherwise identical-looking input-order plans: `input` means
the chronology is authoritative, while `orderAssumed: true` means recovery was incomplete and the
input chronology was used as a best-effort fallback. Segment breaks remain in the plan so the
discontinuity is not hidden.

## What Changed

- Split pipeline directory input into canonical `photos`, `committed`, and `frames` paths. The old
  `images` spelling remains as a legacy spelling for Photos pipelines, but no longer has the old
  harness behavior of re-running selection.
- Renamed the directory capture probe to `frames`, with `capture images` retained as its compatibility
  alias.
- Added the production Photos ordering policy to the shared planner and harness option surface, and
  persisted `orderAssumed` through session inspection.
- Preserved underlying error descriptions in the optional JSON `error.cause` field while keeping
  `error.code` as the stable automation contract.
- Replaced the matcher mask smoke test with displaced real frames that exercise masked rows and pin
  the production offset.
- Named the mask-independent geometric metric `geometricOverlapFraction`; retained
  `overlapFraction` as its legacy JSON-field alias.
- Documented `match` as a symmetric matcher probe and directed production-gate questions to `plan`
  and `pipeline`.
- Added process-level tests that launch the built `stitch-harness` executable rather than
  reimplementing its boundary.

## Verification

- The six-image `Fixtures/Screenshots` oracle now pins all six planned frames, five seams, no segment
  break, and a 1320×10316 composite for `photos` and the legacy `images` spelling.
- The canonical `committed` test pins direct all-image planning and its `recover-or-input` default
  on nine generated keyframes. A direct executable check additionally confirmed that all seven
  lexically discovered `baidu-*` files under `Fixtures/RealDevice` reached planning without
  another driver pass (7 processed, 7 keyframes, 7 planned).
- `HarnessDispatcherTests`: 24/24 passed, including the real mask pair, full-resolution Photos
  oracle, canonical/legacy source spellings, recover-or-input persistence, and detailed corrupt-file
  causes.
- `HarnessProcessTests`: 2/2 passed against the built executable. Success exits 0 with one JSON
  envelope on stdout and empty stderr; failure exits 1 with empty stdout and one typed JSON envelope
  on stderr.
- `BatchStitcherOrderStrategyTests`: 5/5 passed, including a non-identity partial recovery that
  proves fallback replaces recovered order with input order.
- The complete SwiftPM run passed 133 tests in 26 suites. Its only known issue is the pre-existing,
  documented sparse-keyframe limitation in
  `RealDeviceStitchTests.cleanDownwardScrollStitchesIntoOneSegment`.
- A strict-concurrency, warnings-as-errors test build passed and linked both `stitch-cli` and
  `stitch-harness`.
- Selected simulator integration tests passed: `MediaImportTests`, `PhotoPickOrderTests`, and
  `BroadcastOrderStrategyTests`.
- `git diff --check` passed.
