# Tile-Consensus Offset Matching

- **Date:** 2026-08-10
- **Branch:** `feat/tile-consensus-matcher`
- **Status:** Implemented

## Context

`OffsetMatcher` reduced every candidate offset to one variance-weighted MAD over the complete
overlap. That is fast and works when all visible content follows one translation, but it gives a
high-contrast local region disproportionate authority. A changing video, ad, or repeated card can
therefore beat the quieter majority of the page.

The regression fixture constructs that failure directly from multi-column `FrameProfile` rows:
six of eight columns follow `dy=15`, while two high-contrast columns follow `dy=5`. Weighted MAD
chooses 5. Spatial consensus must choose 15. A second 50/50 fixture requires low confidence rather
than an arbitrary confident winner.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep weighted MAD only | Fast and already calibrated against existing fixtures | One high-contrast local region can overrule most of the page |
| Rank candidates by median tile cost | Simple robust aggregate | Invented overlap on unrelated pages and selected a false real-fixture valley |
| Confidence-weighted tile votes with weighted-MAD fallback (chosen) | Requires independent spatial agreement while preserving calibrated costs and fallback behavior | Adds an offline scoring pass and needs a conservative override threshold |

## Decision

Use fixed-grid, confidence-weighted tile voting as an offline-only override of the existing
weighted-MAD result, requiring at least 0.72 vote support.

## Rationale

`OffsetMatcher.Aggregation` has two modes:

- `.weightedMean` is the existing algorithm and remains the default.
- `.tileConsensus` first runs weighted MAD as the calibrated fallback, then builds independent
  cost curves for up to sixteen spatial tiles across the same geometrically admissible candidates.
  The grid is fixed to the incoming frame, so every tile retains one screen-region identity across
  candidate offsets.

Each informative tile votes for its best distinct valley, weighted by that valley's separation
from its runner-up. If consensus and weighted MAD agree, the weighted result is returned unchanged.
If they disagree, consensus needs at least 0.72 of total vote weight to override. The chosen offset
is then validated with weighted MAD, whose cost and overlap accounting are returned so downstream
direction and edge gates retain their existing units.

The first implementation ranked candidates by median tile cost. Real fixtures rejected it: it
invented overlap between unrelated Example frames and put the first `Screenshots3` pair 255 px away
from raw-pixel ground truth. Independent votes fixed the non-overlap case, but that real pair still
had a false valley with about 0.67 vote support. Requiring a spatial supermajority preserves the
real result while the controlled dynamic-region case has exactly 0.75 support.

## Boundaries and invariants

- `BatchStitcher` and `Compositor` opt into tile consensus because they run offline in the app.
- `KeyframeSelector` continues constructing plain `OffsetMatcher()`, keeping ReplayKit's live path
  lightweight and behaviorally unchanged.
- Candidate eligibility remains `frameRows - abs(dy) >= minGeometricOverlap`.
- A row mask or an uninformative tile can remove evidence but cannot narrow the geometric search.
- A candidate outside a fixed tile's overlap simply contributes no observation for that tile.
  There is no fraction-of-frame tile floor, so large offsets with little masked content remain
  measurable.
- Profiles shorter than 64 rows fall back to weighted MAD: four vertical bands would otherwise
  promote individual component-fixture rows into misleading spatial votes.
- `stitch-harness.v1` receives no new fields or commands.

## What Changed

- Added selectable aggregation and fixed-grid tile voting to `OffsetMatcher`.
- Enabled tile consensus for `BatchStitcher` and `Compositor`; kept live capture on weighted MAD.
- Added deterministic majority, ambiguity, small-profile, mask, and offline-wiring regressions.
- Recorded the rollout boundary and evidence in `DECISIONS.md` and this log.

## What Was Discovered

The implementation was developed red → green through:

1. Missing aggregation API, then the legacy scorer reproducing the false `dy=5`.
2. Consensus initially returning the same false offset, then recovering `dy=15`.
3. An evenly divided frame requiring confidence below 0.3.
4. Both aggregation modes exercising the full masked-admissibility range.
5. `BatchStitcher` initially using weighted MAD, then recovering the consensus offset while plain
   `OffsetMatcher()` remained the live default.
6. Real fixtures rejecting median ranking and a bare-majority override before the final policy.
7. A complete-package run exposing a low-variance stitch regression in the candidate-local grid;
   anchoring tile identity to the incoming frame restored all eight expected seam offsets and the
   output-height ratio from 0.85 to 0.99.

## Verification

Verification completed during implementation:

- 16 `OffsetMatcherTests`: pass.
- 37 matcher, batch, large-scroll, and seam-refinement tests: pass; one existing moving-toolbar
  known issue recorded.
- 18 order, video, and real-device tests: pass; one existing sparse-capture known issue recorded.
- `Screenshots3`/`Screenshots4` consecutive offsets remain within their 10 px provisional tolerance.
- Focused real matcher timing: 14.35s versus the recorded 7.43s weighted baseline (1.93×).
- A `Screenshots4` CLI render produced one clean, continuous 1320×10063 image with monotonic order.
- The relocated fixture manifest passes `scripts/fetch-fixtures.sh --check`.
- The `Seamly` scheme builds successfully for the iPhone 17 simulator.
- Final clean package run: 157 tests in 28 suites passed in 1221.5s, with only the two
  pre-existing annotated known issues (collapsing toolbar and sparse fast-flick capture).

## Follow-up oracle

A future live capture containing an actually changing video/ad should replace the deterministic
profile as the strongest regression oracle when available.
