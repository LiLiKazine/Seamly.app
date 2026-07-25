# 2026-07-25-06: `layout` was discarding the edge that joins two placed components

**Status:** Implemented (partial fix for #2 — the direction tie-break remains)

## Context

Issue #2 says `BatchStitcher` mis-scores scroll **direction** on image-heavy content, so a real
downward overlap loses a tie-break to a spurious reverse match and a continuous scroll shatters.
A comment on the issue added a second reproduction: the `youtube-*` set, where `plan(_:)` yields
`segmentBreaks=[after 1]` while `plan(_:assumingOrder:)` on the *same frames* yields none.

Measuring the full pairwise matrix on `youtube-*` before changing anything:

```
0-1 fwd dy=332 conf=0.932 | bwd dy=1 conf=0.370 | accepted=YES
1-2 fwd dy=320 conf=0.922 | bwd dy=1 conf=0.267 | accepted=YES
2-3 fwd dy=324 conf=0.942 | bwd dy=1 conf=0.202 | accepted=YES
3-4 fwd dy=337 conf=0.824 | bwd dy=1 conf=0.184 | accepted=YES
4-5 fwd dy=322 conf=0.762 | bwd dy=1 conf=0.326 | accepted=YES
```

**Every adjacent edge is accepted, and no non-adjacent edge is** — yet the capture still split.
So on this fixture the direction tie-break was never the problem, and neither was the confidence
floor. The edges were fine; something downstream threw one away.

## The actual mechanism

`layout` anchors edges in descending confidence, assigning each frame a position, and unions
their components. The four cases were:

```swift
case (nil, nil): pos[above] = 0; pos[below] = Double(dy)
case (let pa?, nil): pos[below] = pa + Double(dy)
case (nil, let pb?): pos[above] = pb - Double(dy)
case (.some, .some): continue   // both already placed in different components: skip
```

Replaying the youtube edges in confidence order:

| order | edge | conf | outcome |
|---|---|---|---|
| 1 | 2-3 | 0.942 | seeds component {2,3} |
| 2 | 0-1 | 0.932 | seeds component {0,1} |
| 3 | **1-2** | **0.922** | both endpoints placed, different components → **`continue`, edge dropped** |
| 4 | 3-4 | 0.824 | extends {2,3,4} |
| 5 | 4-5 | 0.762 | extends {2,3,4,5} |

Two components survive, so `buildPlan` emits a break after slot 1 — exactly the observed output.
The break location is an artifact of how the confidences happened to sort, carrying no
information about the capture at all.

The `continue` treats "both endpoints already have positions" as a conflict. It isn't one:
positions are only meaningful *within* a component — each component starts its own frame of
reference at 0 — so an edge spanning two components is precisely the datum that relates them.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Keep `continue` | No change | Silently drops the strongest edges once two components exist; on any capture with ≥3 frames this is a coin flip |
| Re-run layout until stable | Might converge | Unbounded, and doesn't address why the edge is dropped |
| **Translate and merge (chosen)** | Uses the edge for what it is — the offset between two reference frames. One pass, no new state | Requires touching every position in one component (O(n) per merge, n ≤ frame count) |

## Decision

When an edge's endpoints are both placed in different components, shift the `below` component by
`(pos[above] + dy) − pos[below]` so the edge is satisfied, then union.

## What Changed

- `BatchStitcher.layout` — the `(.some, .some)` case translates and merges instead of `continue`.
- `OrderRecoveryTests` (new, 4 tests) — the youtube one-segment guard, recovered-vs-assumed
  agreement, plus the two guards issue #2 asks for: `wechatNonOverlapStillBreaks` and
  `baiduDownwardScrollStaysSane`.
- `CaptureSimulationTests` scenario 2 — `segmentBreaks.count == 1` → `.isEmpty`, per issue #2's
  third acceptance criterion.

## What Was Discovered

- **Issue #2 is two independent bugs wearing one title.** This one (dropped merge edge) fully
  explains the youtube reproduction. The direction tie-break it is actually titled after is real
  but separate, and still open — see below.
- **`CaptureSimulationTests` scenario 2's stated cause was wrong.** Its comment attributed the
  break to "one internal edge falls under the 0.45 edge-confidence floor". A genuinely sub-floor
  edge cannot be rescued by a merge fix, so that edge had always cleared the floor and was being
  discarded afterwards. The comment has been corrected rather than just the assertion.
- **Baidu measurement, for whoever picks up the rest of #2.** Ground truth in profile rows is
  389 / 250 / 113 / 358 / 284 / 383. The forward matcher recovers the *correct dy* on five of
  six adjacent pairs; what loses them is the tie-break:

  | pair | forward | reverse | outcome |
  |---|---|---|---|
  | 0-1 | **389** @ 0.176 | dy=38 @ 0.324 | reverse wins → rejected |
  | 3-4 | **358** @ 0.387 | dy=1 @ 0.429 | reverse wins → rejected |
  | 4-5 | dy=1 @ 0.321 | dy=1 @ 0.476 | genuine forward-match failure |

  So #2's candidate fix 1 (prefer a real-`dy` edge over a spurious no-scroll one) would rescue
  3-4 but not 0-1, whose spurious reverse match has `dy=38 ≥ minEdgeDy` and so isn't caught by a
  "`dy < minEdgeDy`" test. And rescuing 3-4 needs the floor at ≤0.387, which is a separate
  measurement exercise across all four fixtures.
- **Reformulating the tie-break alone is inert.** Discarding sub-`minEdgeDy` directions before
  choosing, while keeping the floor at 0.45, changes nothing on any fixture we have (checked:
  baidu 3-4 still fails 0.387 < 0.45, wechat 1-2 still fails 0.118 < 0.45, youtube unaffected).
  It only matters combined with a floor change, so it wasn't worth landing as dead code.
- **Video tier unchanged**, still `breaks=[2, 3]`. Its `withKnownIssue` stays.
- Visual triage: `youtube-*` goes 5822px → 5097px, and the duplicated status bar + tab bar that
  sat mid-image are gone. Suite 87 → 91 tests, 19 suites, same 3 known issues; app suite green.
