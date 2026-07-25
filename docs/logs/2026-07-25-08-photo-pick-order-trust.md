# 2026-07-25-08: A fuzzy seam was cancelling order recovery on the Photos path

**Status:** Implemented

## Context

Reported symptom: a set of overlapping screenshots stitches correctly when picked top-to-bottom,
and shatters when picked in a random order. Read literally, that is "order recovery doesn't work"
— and it is the *only* reading under which the two halves of the report are consistent, since
nothing else in the pipeline sees pick order at all.

Recovery turned out to be innocent. `stitch-cli images` on the six-screenshot set
(`Fixtures/Screenshots`, now checked in) recovers the true order from every permutation tried:

```
sorted    order: [0, 1, 2, 3, 4, 5] (monotonic)
shuffle 1 order: [1, 3, 0, 5, 4, 2] (recovered)   → 1757,1758,1759,1760,1761,1762
shuffle 2 order: [4, 2, 5, 1, 3, 0] (recovered)   → 1757,1758,1759,1760,1761,1762
```

All three produce byte-identical seams, one segment, and the same 1320×10316 output. Rendered and
eyeballed: continuous, every seam clean.

So the ordering was being recovered correctly and then *discarded*. The one place that can happen
is `StitchAssembler.resolveGeometry`:

```swift
let clean = recovered.session.segmentBreaks.isEmpty
         && recovered.session.seams.allSatisfy { !$0.isLowConfidence }
if clean { plan = recovered } else { plan = try stitcher.plan(images, assumingOrder: identity); orderAssumed = true }
```

This set's seam 2→3 measures **0.368**, under the 0.4 that `buildPlan` stamps as
`isLowConfidence`. So `clean == false` on every import, and the Photos path composited in **pick
order**. Picked in scroll order that fallback is a no-op and nothing looks wrong; picked randomly
the fallback *is* the failure. The report's two halves describe one bug.

## The reasoning error

The gate conflated two unrelated measurements:

| signal | what it is evidence of | can the fallback improve it? |
|--------|------------------------|------------------------------|
| `segmentBreaks` non-empty | recovery could not relate some frames at all, so their relative order comes from input index — a guess | **yes** — the caller's guess (pick order) is a better guess than "lowest input index" |
| a seam under 0.4 | *one seam's offset* is fuzzy | **no** — `plan(_:assumingOrder:)` re-measures that same pair with the same matcher, so it comes back at 0.368 either way |

The second row is the bug. The gate paid a correct ordering for a fuzzy seam and got the same
fuzzy seam back. Worth stating plainly because the code read as conservative: two conditions
instead of one, both "quality" checks, and the strictness ran the wrong way.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Lower the 0.4 `isLowConfidence` floor until this set passes | one number, no structural change | fixes nothing — the floor is a *seam* signal used by `EditView` and `Compositor`; moving it to serve an ordering decision breaks its actual meaning, and the next fixture at 0.35 reopens this |
| Require *most* seams confident, or average confidence | keeps some notion of "recovery looked shaky" | no threshold is derivable from anything; and it still answers an ordering question with offset evidence |
| Gate only on `segmentBreaks.isEmpty` (chosen) | each signal used for what it measures; one condition; fallback keeps the one job it can actually do | narrows the safety net for a genuinely mis-recovered order that still chains — see below |
| Trust recovery *within* components, use input order only *between* them | strictly more information preserved than any of the above | larger change; unnecessary for this bug; better as its own piece of work |

## Decision

`.recoverOrInputOrder` falls back to the input order when, and only when, recovery could not chain
the frames into one segment.

## Rationale

A segment break is the only outcome that makes the recovered order a *guess*: unrelated components
are placed by input index, so substituting the caller's order replaces one arbitrary choice with an
informed one. Everything else recovery reports about a complete chain came from the pixels, and
pick order — a user tapping thumbnails — has no standing against it.

The cost is real but small: a mis-recovered order that nonetheless chains completely now stands
where before a fuzzy seam might have knocked it back to input order. That protection was never
aimed, though — issue #2's inversion produces a *confident* wrong chain, so the confidence term
would not have caught it, and on the fixtures we have `.recover` and `.inputOrder` agree
everywhere (measured in `d51f972`). Trading an accident for a fix on a reproducible failure is the
right side of that trade, and the over-merge guards (`BroadcastOrderStrategyTests`, all three)
still pass.

`orderAssumed` becomes honest as a side effect. `d51f972` recorded as a wrinkle that the badge read
"recovery wasn't clean" rather than "the order is suspect"; with the seam term gone, it means what
its label says.

## What Changed

- `Seamly/Seamly/Core/StitchAssembler.swift` — the gate drops the seam-confidence term; comment
  records why confidence is not order evidence and what it cost. `OrderStrategy` doc corrected
  ("one unbroken chain", not "one clean, confident chain").
- `Seamly/Seamly/Core/LibraryModel.swift` — `importPhotos` doc corrected.
- `Seamly/StitchKit/Tests/StitchKitTests/Fixtures/Screenshots/` — new fixture tier: 6 real
  screenshots at native 1320×2868 (8.6 MB) + `README.md` recording ground truth and recovered
  geometry. Declared in `Package.swift`, which also clears six "unhandled files" build warnings.
- `Seamly/StitchKit/Tests/StitchKitTests/ScreenshotOrderRecoveryTests.swift` — new: recovery is
  permutation-invariant (2 permutations), recovered ≡ assumed order, and the chain carries a
  sub-0.4 seam.
- `Seamly/SeamlyTests/PhotoPickOrderTests.swift` — new: the app-level regression. Both tests fail
  before the fix.
- `CLAUDE.md` — dropped the stale exact test count from the `swift test` comment (see below).

## What Was Discovered

- **The 3-image subset `1758,1759,1760` reproduces the trap minimally** — one segment, correct
  order, and the 0.368 seam is its 1→2. That is what the app test uses, so it writes 3 keyframes
  instead of 6.
- **`#expect(xs.contains(where: \.isLowConfidence))` does not compile** in the Xcode test target:
  the macro expansion emits `$0.contains(where: $1)` and the `rethrows` conversion is lost, so it
  reports "call can throw, but it is not marked with 'try'". `xs.filter(...)` into a local, then
  expect on that. Cost a build cycle; worth knowing before writing the next one.
- **The app test loads fixtures by source-relative path (`#filePath`), not from a bundle.**
  CLAUDE.md's testing rule is "fixtures are bundled, never live photo-library access" — the intent
  is determinism, which a checked-in source path satisfies equally, and the alternative was
  duplicating 8.6 MB of PNGs into the app test bundle to reproduce a seam that only exists at
  native resolution. Flagged here rather than silently deviating.
- **`CLAUDE.md`'s "80 tests / 17 suites" had already rotted** — the real numbers were ~92/20
  before this change and 96/21 after. Deleted rather than refreshed, and the whole comment with it.
  A count changes every time anyone adds a test, an event nobody updates a doc for; and CLAUDE.md is
  paid for on every request of every session, so it earns its length by being a rulebook, not a
  ledger. The ledger already exists — `docs/logs/`, git history, issues — and Status points into it.
  The first replacement attempt kept "~6 min" and "green means passed *with* the known issues", both
  of which fail the same test: Gotchas already says the real-frame tiers are slow and not a hang,
  Status already names both gaps and forbids relaxing their assertions, and the only original
  content left ("a `━` line is expected") was a state claim that goes stale the day both gaps close
   — quietly licensing a red line to be ignored. A `Commands` block should say what to type.
- **Not changed, worth its own issue:** `.recoverOrInputOrder` is shared with broadcast import, so
  this loosens broadcast's net identically — even though a broadcast's input order is a *timeline*
  and therefore stronger evidence than a photo pick order. `d51f972` chose `.recoverOrInputOrder`
  there deliberately (recovery gets first refusal), and no device fixture changes behaviour, so
  re-deciding it belongs in a separate change with its own measurement.
- Full suites after the fix: StitchKit **96 tests / 21 suites**, passing with the 3 pre-existing
  known issues across 2 tests; app **13 tests**, all green.
