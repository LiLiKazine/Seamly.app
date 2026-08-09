# Example capture

Three real screenshots at native resolution **1320×2868**, timestamped `20260718-225057`,
`…225102`, `…225107` — **ascending filename order is scroll order, top→bottom**, five seconds
apart.

This README was added later than the set itself, when the binary fixtures moved out of the repo and
every set needed its ground truth to survive its pixels being absent. It records what can be
verified from the files and from the tests that consume them, and **deliberately does not invent
measurements the other fixture READMEs carry**: this set has no recorded per-seam `dy`, confidence,
or content band. If you measure them, add them here.

## Who uses it

- `BatchStitcherTests` — assembly over a small real set
- `BatchStitcherOrderStrategyTests` — `.recover` / `.recoverOrInputOrder` / `.inputOrder` policy
- `CaptureSimulationTests` — the capture→stitch pipeline over real pixels

## What it is known to exercise

`BatchStitcher.chromeBand`'s plausibility guard reads this set's candidate top and bottom bands as
**content, not chrome** (0.436 and 0.482 static — see `minChromeStaticFraction` in
`BatchStitcher.swift`), so it is one of the three fixtures that must have their candidate band
*refused*. That makes it load-bearing for the guard, not just another sample.

Kept at native resolution, like every other real set here: a downscaled copy changes `rowScale` and
so the matcher's downsample.
