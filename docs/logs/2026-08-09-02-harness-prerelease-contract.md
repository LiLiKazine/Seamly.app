# 2026-08-09-02: Finalize the unreleased stitch-harness v1 contract

**Status:** Implemented and verified

## Commits

| Commit | Summary |
|---|---|
| This commit | Freeze the unreleased harness contract around canonical sources, stage-owned schema fields, authoritative matcher accounting, and executable-boundary errors. |

## Context

The first harness correction separated Photos, committed keyframes, raw frames, and video into
production-shaped paths. Its decision and verification remain recorded in
[`2026-08-09-01-harness-production-paths.md`](2026-08-09-01-harness-production-paths.md).

That work had not been released when a second review found that its provisional compatibility
surface was already imposing v2-shaped costs on v1: two `images` spellings meant different things,
pipeline facts appeared both at the result root and inside stages, ingestion fields had synonymous
names, and the match command re-derived overlap accounting instead of reporting the core matcher's
own values. There are no released callers to preserve, so carrying these choices forward would turn
an unreleased draft into permanent compatibility debt.

## Options

| Decision | Option | Trade-off | Outcome |
|---|---|---|---|
| Version timing | Retain the draft aliases and duplicate fields until v2 | Avoids breaking provisional scripts, but cements ambiguity and requires every producer and consumer to keep synonymous values consistent. | Rejected |
| Version timing | Correct v1 before release | Breaks yesterday's local spellings and fields, but gives the first released contract one canonical representation. | **Chosen** |
| Error boundary | Publish the wrapped implementation error | Makes in-process failures inspectable, but presents the executable-support target as a supported library API. | Rejected |
| Error boundary | Keep the dispatcher package-scoped and serialize its private wrapper at the executable boundary | Keeps implementation detail inside the package while preserving stable JSON codes and causes for automation. | **Chosen** |
| Overlap accounting | Re-derive matcher overlap in the harness | Keeps the harness self-contained, but can drift from masks, floors, and row accounting in the production matcher. | Rejected |
| Overlap accounting | Report accounting carried by the core `Match` | Makes the matcher the single source of truth for counted rows and the minimum-overlap gate. | **Chosen** |

## Decision

Correct the unreleased `stitch-harness.v1` contract in place.

- Canonical capture sources are `frames` and `video`.
- Canonical pipeline sources are `photos`, `committed`, `frames`, and `video`.
- A pipeline result contains only `source` and `stages`. The stages are `ingestion`, `plan`,
  `session`, and `composition`; each fact has one owning stage.
- Ingestion reports source-specific measurements only when that source produces them. An unavailable
  measurement is omitted rather than emitted as `null`, zero, or a synonym of another field.
- `match.geometricOverlapFraction` remains the mask-independent geometric intersection fraction.
  `match.matcherOverlap` reports the core matcher's `countedRows`, `countableRows`,
  `minimumRequiredRows`, `fraction`, and `passesMinimum` values.
- The executable JSON envelope is the supported automation boundary. The dispatcher and wrapped
  implementation failure remain package details; the executable serializes caught failures through
  `HarnessDispatcher.errorData` so stable codes and underlying causes survive.

This intentionally removes the prior draft's `capture images` and `pipeline images` spellings, the
match `overlapFraction` alias, synonymous ingestion keys such as `inputCount` and `directory`, and
pipeline fields duplicated between the result root and `stages`. It also renames the pipeline's
`capture` stage to `ingestion`, because Photos and committed-keyframe sources deliberately perform
no capture selection.

## Rationale

Source names are behavioral contracts, not file-format labels. One canonical spelling per behavior
makes it harder to send Photos or already-committed keyframes through the raw-frame selector by
mistake. Naming the first pipeline stage `ingestion` describes all four sources without pretending
that direct Photos or committed-keyframe loading is capture.

One field owner also matters for automation. A duplicated value can be consistent today and still
become contradictory when one copy gains a field, changes meaning, or is forgotten in a test. The
stage-only shape makes ownership visible and keeps the result root stable.

Overlap accounting is especially sensitive to implementation detail: the chrome mask changes which
rows are countable, and the core matcher owns the minimum-overlap rule. Carrying those measurements
on `Match` prevents a diagnostic from presenting a plausible number that production did not use.

The reversal boundary is release. Before the first release, this cleanup may replace the provisional
contract directly. Once `stitch-harness.v1` is released or adopted by external automation, further
breaking spellings or schema changes require a versioned contract and an explicit migration rather
than another in-place rewrite.

## What Changed

- Removed provisional source aliases so each capture and pipeline path has one name.
- Normalized pipeline output to `source` plus the four canonical stages.
- Renamed the first pipeline stage from `capture` to `ingestion`.
- Removed synonymous and duplicate result fields instead of keeping them synchronized.
- Replaced the harness-derived overlap alias with geometric overlap plus the core matcher's nested
  overlap accounting.
- Kept wrapped implementation errors private to the package while documenting
  `HarnessDispatcher.errorData` as the required executable serialization boundary.

## What Was Discovered

- Compatibility code added before a release is not free: tests and documentation immediately begin
  treating provisional names as permanent API.
- The word `images` had opposite operational meanings depending on the command: raw frames for
  `capture`, but already-selected Photos input for `pipeline`.
- A raw `[String: Any]` envelope made it easy to expose the same value at multiple paths without
  making either path the clear owner.
- A diagnostics tool can disagree with production even when both numbers look reasonable; overlap
  rows and floors must come from the core match that made the decision.
- Making the dispatcher type visible across package targets does not make StitchHarness a supported
  public library. The stable external contract is the executable's JSON and process behavior.

## Verification

- Focused matcher/order tests passed: 17 tests in 2 suites.
- `HarnessDispatcherTests` passed: 28/28. This includes the checked-in six-photo oracle using all
  6 inputs, producing 5 seams, 0 breaks, and a 1320×10316 composition, plus exact result/stage key
  sets and absence checks for removed aliases.
- `HarnessProcessTests` passed: 3/3. The real executable preserves stdout/stderr exclusivity,
  exit 0/1 behavior, stable JSON envelopes, and wrapped causes.
- The complete StitchKit package passed: 139 tests in 26 suites in 590.332 seconds, with the one
  pre-existing documented RealDevice known issue.
- A strict package build with complete concurrency checking and warnings as errors passed.
- Selected app integration tests (`PhotoPickOrderTests`, `BroadcastOrderStrategyTests`, and
  `MediaImportTests`) passed, and the simulator app build succeeded after moving order policy into
  StitchKit.
- Final specialist reviews covering structure, interface/security, testing/performance, and
  agentic readiness returned GO with no remaining Critical or Important findings.
- Active README/source searches found no removed command aliases or obsolete error codes; historical
  decision records and explicit alias-rejection assertions remain intentionally. `git diff --check`
  passed.
