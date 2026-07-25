# 2026-07-25-07: Direction by fit, and a chain-joining pass for weak-but-real edges

**Status:** Implemented (further partial fix for #2 — one break remains, and it is a fixture problem)

## Context

After 2026-07-25-06 fixed the dropped component-merge edge, the video tier still broke at
`[2, 3]`. That is the failure issue #2 is actually named after: on image-heavy content a spurious
"no-scroll" reverse match out-scores the real downward edge, so the real edge is discarded before
any threshold is consulted.

## What `confidence` actually measures

`OffsetMatcher` returns `confidence = confidenceMargin(best, runnerUp)` — how far the winning
offset beat the next distinct alignment. That is **sharpness**, not fit. A spurious alignment can
be sharp (one accidental narrow minimum) while explaining the rows badly.

The direction tie-break compared two *different* matches on that number. Comparing two candidate
explanations of the same pair is a goodness-of-fit question, so it wants the score, which `Match`
did not carry. Measured on the video tier:

| pair | forward | reverse | by confidence | by cost |
|---|---|---|---|---|
| 0-1 | dy=327 c=0.820 cost=0.055 | dy=1 c=0.277 cost=0.331 | fwd | fwd |
| 1-2 | dy=340 c=0.899 cost=0.031 | dy=313 c=0.378 cost=0.225 | fwd | fwd |
| 2-3 | **dy=344** c=0.341 cost=0.177 | dy=1 c=0.432 cost=0.269 | **bwd** ✗ | **fwd** ✓ |
| 3-4 | **dy=297** c=0.047 cost=0.178 | dy=1 c=0.282 cost=0.187 | **bwd** ✗ | **fwd** ✓ |

Cost picks the right direction on all four.

## The failed attempt, and why it failed

Direction-by-cost alone is inert: pairs 2-3 and 3-4 still fail `edgeConfidence` (0.341, 0.047).
So a second acceptance test was needed. The idea tried first: two frames that don't overlap have
no preferred direction, so their two costs converge and `chosenCost / oppositeCost → 1`; a real
edge fits better one way round. Across 16 **adjacent** pairs that separated cleanly — every real
edge ≤0.953, every genuine non-overlap 0.996–0.997.

Applying it to all pairs in `layout` **corrupted the order to `[4, 0, 1, 2, 3]`** — precisely the
inversion issue #2 predicts from a lowered floor. The premise is false for non-adjacent pairs:
video 1-3 and 1-4 score 0.762 and 0.781 in the *reverse* direction, because distant frames from
one scroll share layout statistics and one direction wins by accident. The 16-pair analysis had
only looked at adjacent pairs, which is not the candidate set `layout` uses.

Restricting the test to **chain boundaries** — the bottom frame of one component against the top
frame of another — removes those candidates structurally: a frame can attach to the end of a
chain, never into its middle.

## Decision

1. Settle scroll direction on `Match.cost` (new field) rather than `confidence`.
2. Add a chain-joining pass after the confidence-gated anchoring, admitting a boundary pair when
   its chosen direction fits at most `directionalCostRatio` (0.80) as badly as the opposite.

## Rationale for 0.80

Measured, with both decode cadences, since the app imports video at 30 fps:

| ratio | what | at 0.80 |
|---|---|---|
| 0.658 | video 2-3, full-rate — REAL | rescued |
| 0.777 | video 2-3, 30 fps (production) — REAL | rescued |
| 0.803 | video 3-4, 30 fps — real, unmatchable tail | rejected |
| 0.953 | video 3-4, full-rate — same tail | rejected |
| >0.84 | first `wechat-*` false accept (safe at 0.84, over-merges at 0.88) | rejected |

0.80 is the highest value keeping ≥5% margin below the false-accept zone. Not pushed to ~0.81 to
also take pair 3-4: that leaves ~2% margin on both sides, and it would not close the acceptance
criterion anyway, because the full-rate decode `CaptureVideoTests` uses scores that same pair at
0.953. Its last break needs the fixture re-trimmed (issue #2's candidate 3), not a bolder number.

The bias is downward on purpose. Rejecting a real edge leaves a segment break — visible and
honest. Accepting a false one stitches unrelated screens together.

## What Changed

- `Match` gains `cost` (the winning offset's weighted MAD), documented against `confidence`.
- `BatchStitcher.layout` chooses direction by cost; new `joinChainsAcrossComponents` pass;
  `qualifiesAsEdge` shared with `segmentsAlong` so the two paths cannot drift.
- `CaptureVideoTests` comment rewritten — pair 2-3 is fixed, pair 3-4 is a fixture artifact.

## What Was Discovered

- **Separation here is ~1.1x, where `structureTolerance` next door enjoys 8x.** Each bound is a
  single observation. This is the weakest-evidenced constant in the package and the doc comment
  says so; the three real-fixture guards are the safety net.
- **Cadence matters and nearly hid the result.** The same pair scores 0.658 at full-rate decode
  and 0.777 at the 30 fps the app actually uses. A threshold validated only against
  `CaptureVideoTests` (full-rate) would have looked fine at 0.70 while delivering *nothing* to
  users. Always check the production cadence with `stitch-cli video`.
- **An earlier `inout` mistake:** `joinChainsAcrossComponents` first took the caller's `find`
  closure, which captures `parent`, while also binding `parent` `inout` — a fatal exclusive-access
  violation at runtime. It uses a local non-capturing root lookup instead.
- Visual triage at production cadence: 11683px → 10268px, three segments → two, and the rescued
  seam is placed correctly — the feed runs Skyrim → James Webb continuously with chrome appearing
  once, not duplicated mid-segment.
- Full suite 91 tests / 19 suites green, same 3 known issues; app suite green.
