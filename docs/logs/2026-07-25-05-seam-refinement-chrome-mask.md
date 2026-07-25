# 2026-07-25-05: Seam refinement matches with the chrome band masked, not on wider columns

**Status:** Implemented

## Context

Issue #9 reported that `Compositor.refineVertical` can land 1px off, and diagnosed the cause as
horizontal sampling: refinement matches on `VerticalProfile` output whose *width* is downscaled
to 64 columns (`forcingHeight:` pins the row count to full pixel resolution, but not the column
count). The proposed fix was to refine on full-width columns.

Evidence in the issue, measured at full resolution (1320×2868):

| pair | refined dy | true dy | MAD at refined | MAD at true |
|---|---|---|---|---|
| 3–4 | 1510 | 1509 | 0.05911 | 0.04998 |

with the other four pairs pixel-exact.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Refine on full-width columns (the issue's proposal) | Directly addresses the stated diagnosis | **Measured: changes nothing.** ~10x render cost for an identical answer |
| Widen the search window when confidence is low | Addresses "silently keeps an unconfirmed provisional" | Speculative — no measurement shows it helps, and searching further from a known-good seed is how a refinement finds a *worse* match. The confidence gate exists to prevent exactly that |
| **Mask the segment's chrome band during refinement (chosen)** | Chrome is the one part of the frame that isn't a function of scroll position; excluding it deepens the score valley. Consistent with every other matching path | Doesn't move the argmin on the measured fixture — the win is confidence, not placement |

## Decision

Refine with the segment's `ContentBand` masked out of the match, and explicitly do **not**
widen `VerticalProfile.targetWidth` for refinement.

## Rationale

Measured on `youtube-*` (660×1434 half-res, band 115/124), refined `dy` against a full-width
brute-force MAD over raw pixels in the content band:

| pair | truth | unmasked | masked |
|------|-------|----------|--------|
| 0-1  | 744   | 744 @ 0.74 | 744 @ 0.95 |
| 1-2  | 716†  | 716 @ 0.57 | 717 @ 0.79 |
| 2-3  | 726   | 726 @ 0.70 | 726 @ 0.95 |
| 3-4  | 755†  | **754** @ 0.16 | 755 @ 0.73 |
| 4-5  | 721   | 721 @ 0.47 | 721 @ 0.98 |

Across 64 / 128 / 256 / 512 / 660 columns every cell above is identical to within 0.01
confidence. **Width is not the variable.** The issue's diagnosis was wrong, and its proposed fix
would have cost ~10x the render work for no change.

What masking buys is depth of the score valley, and that is what `refinementConfidence` gates
on. Pair 3-4 — the hardest pair, the one the issue is about — scored 0.16 unmasked, below the
0.3 threshold, so **its refinement was discarded and the coarse provisional kept**. The seam
that most needed refining was the only one that never got refined, and it was flagged
low-confidence to the user. Masked it scores 0.73 and is actually used.

Masking is safe here in a way it is not in the coarse path. `BatchStitcher.downwardMatch`
chooses between masked and unmasked on confidence because "the mask helps some real pairs and
flips the sign on others" — but that search spans the whole frame, where removing rows can hand
the win to a spurious global alignment. Refinement searches `provisional ± 6` px around an
already-established offset: it cannot flip a sign or jump to a different alignment, only pick
among neighbours. Different risk profile, same mask.

## What Changed

- `Compositor.refineSeams` — builds a per-seam content-row mask from the segment's band and
  passes it down; added `contentRowMask` and `contentBandByKeyframeIndex` helpers.
- `Compositor.refineVertical` — takes a `rowMask` and forwards it to `OffsetMatcher.match`.
- `SeamRefinementTests` (new) — brute-force ground-truth pin, the confidence regression guard,
  and a test pinning that profile width does not change refined offsets.

## What Was Discovered

- **The two pairs that "disagree" are sub-pixel, not wrong.** Full-resolution ground truth is
  1488 / 1433 / 1452 / 1509 / 1442. Halved for the stored fixtures that is 744 / **716.5** /
  726 / **754.5** / 721 — the only two pairs where masked and unmasked differ are exactly the
  two with no integer answer, and their brute-force costs at the two neighbours are a near tie
  (716: 0.01578 vs 717: 0.01580). Unmasked takes the floor, masked takes the ceiling. Both are
  defensible; neither is a defect. The three pairs with an exact integer truth are pixel-exact
  either way. This is why the ground-truth test asserts only those three.
- **This fix changes no pixels on any fixture we have.** The composited `youtube-*` output is
  byte-identical before and after (sha256 `6618d56b…`), because the low-confidence fallback was
  already keeping the provisional 755 — which happens to be right. That is luck, not design:
  the provisional comes from a coarse profile at `rowScale ≈ 2.24`, so on another capture it
  could be several px off and the same low confidence would preserve that error. What changed
  is that the system now *knows* the seam is right instead of flagging it for the user to
  fine-tune.
- **The issue's acceptance criterion 2 was already met.** "Refinement no longer silently accepts
  a provisional offset it could not confirm" — it never did so silently: `refineSeams` sets
  `isLowConfidence`, `LibraryView` shows a flag badge, and `PreviewView` says "N seam(s)
  flagged. Tap Edit to fine-tune." The real problem was that the fallback fired far more often
  than it should have. No new logging was added, because a user-visible flag is a stronger
  signal than a log line and it already exists.
- Full suite 84 → 87 tests, 18 suites, same 3 known issues. Real-fixture metrics unchanged
  (`ChromeStitchRepro` 25/21 ratio 0.99, `RealFrameStitch` 238/262 ratio 1.00).
