# 2026-08-18-03: Final whole-branch review fix wave for guided repair

**Status:** Implemented

## Context

`feat/guided-repair` built the repair screen over seven tasks, each reviewed on its own. A review of
the whole branch found three Important defects that no per-task review could see, because each is an
interaction *between* commits — state written by one screen and read by another, a background set on
one of three branches, a `busy` flag whose only feedback lives behind a full-screen cover — plus a
set of documentation claims that are simply false.

All three defects sit on the branch's central promise: **the pixels under your finger are the pixels
you get.**

1. **The light-mode title fix covered one state of three.** `.background(.black)` was on the
   `else if let frames, let alignment` branch, but `.toolbarColorScheme(.dark, for: .navigationBar)`
   applies to the whole stack. So in light mode the spinner state (two full-resolution keyframe reads
   on every open *and* every chevron tap) and the load-failure state were the system's white ground
   under a forced-*white* title — no title at all. For the failure state that is permanent. This is
   the second appearance-legibility bug this app has shipped.
2. **A repair did not invalidate cached export artifacts.** `pngURL`/`pdfURL` are `@State`, set when
   the user taps Share or PDF, which turns each button into a `ShareLink` over that file. Nothing
   cleared them, and `fullScreenCover(item:)` had no `onDismiss`. Tap PDF → notice the bad join →
   repair → tap PDF → you are handed the file rendered from the **pre-repair** manifest. `Save to
   Photos` and `Copy` re-composite per tap, so exactly two of four export paths broke the promise.
   Worse: `savedToPhotos` was never cleared either, so *"Done — remove from Seamly"* stayed on screen
   after a repair — inviting the user to delete the capture while the copy in Photos is the stale,
   un-repaired one. The repaired image is then gone for good. Data loss, not a stale cache.
3. **The screen froze with no feedback while committing.** `commit()` sets `busy = true`, awaits
   `model.update(_:)` (manifest write plus a full-resolution re-composite and proxy), and only then
   dismisses. Cancel, Done and both chevrons are disabled for all of it, with nothing on screen
   saying so. The spec claimed no new state was needed because "`ResultView` already renders
   `ProcessingView` for that phase" — but `ProcessingView` is *behind* the cover.

## Options

### Where the black ground belongs (defect 1)

| Approach | Pros | Cons |
|---|---|---|
| Repeat `.background(.black)` on each of the three branches | Local, no new modifiers | Three places to keep in step; this defect *is* a per-branch background that fell out of step |
| Drop `.toolbarColorScheme(.dark, ...)` and let the bar follow the system | One fewer forced value | Re-opens the original bug: a dark title on the black canvas in light mode |
| `.preferredColorScheme(.dark)` on the `NavigationStack` | Covers everything in the cover at once | Presentation-scoped semantics that can leak to the presenter during dismissal; also darkens the position bar, which was not under review |
| **`.background(.black)` + `.environment(\.colorScheme, .dark)` on `content` itself** | **Chosen.** One ground for all three states; content drawn *for* that ground | Two modifiers rather than one |

### Which state to clear on returning from repair (defect 2)

| Approach | Pros | Cons |
|---|---|---|
| Clear only on a *committed* change | Keeps a prepared file across a Cancel | `ResultView` cannot see whether anything moved; needs new plumbing to find out, for a one-tap saving |
| Clear `pngURL`/`pdfURL` only | Fixes the two stale-byte paths named in the review | Leaves `savedToPhotos` set, i.e. leaves the data-loss affordance in place |
| **Clear all three on any dismissal** | **Chosen.** One-sided trade | Re-preparing a file after a Cancel costs one tap |

### How to show commit progress (defect 3)

| Approach | Pros | Cons |
|---|---|---|
| Reuse `content`'s `ProgressView` branch | No new view | Impossible: that branch requires `frames == nil`, and the frames are still loaded |
| Set `frames = nil` while committing | Reuses the branch | Throws away the canvas the user just aligned, and would re-trigger a load if the commit fails |
| **A dimming overlay over the canvas while `busy`** | **Chosen.** Keeps the join in view; the dimming is itself the "not live" signal | One more `@ViewBuilder` |

## Decision

Move the ground and colour scheme onto `content` so all three states share them; give the repair
cover an `onDismiss` that clears `pngURL`, `pdfURL` and `savedToPhotos`; and overlay a scrim plus
spinner while `busy`, keeping every control disabled.

## Rationale

The three fixes have one shape in common: a fact that was true of *one* branch or *one* manifest was
being treated as true of the screen. The ground belonged to the loaded branch but the forced-dark bar
spans all three. The prepared export URLs were true of the manifest as it was, but survived a
manifest rewrite. `busy` was true of the model but had no expression in the only view the user could
see. So each fix moves the fact up to the scope that actually owns it — `content`, the cover's
dismissal, the canvas overlay — rather than adding a second copy at the lower scope.

**One addition beyond the review's letter, deliberately.** The review asked only for
`.background(.black)` to move. Moving it alone would have made the *bar title* legible and left the
states' own content painting in the system label colour: the load-failure
`ContentUnavailableView`'s "Can't show this join" headline would have been black-on-black in light
mode, and the spinner a dim grey on black. That is the same defect one layer down, so `content` also
gets `.environment(\.colorScheme, .dark)`. Scoped to `content`, so the position bar (a
`safeAreaInset` applied outside it) and everything outside the cover are untouched — confirmed by
screenshot: `ResultView` behind the presenting cover still renders light.

## What Changed

- `Seamly/Seamly/Features/Repair/RepairView.swift` — `.frame(maxWidth:maxHeight:)`,
  `.overlay { committingProgress }`, `.background(.black)`, `.environment(\.colorScheme, .dark)` and
  `.ignoresSafeArea(edges: .horizontal)` moved onto `content` in `body`; new `committingProgress`
  overlay; `.interpolation(.none)` on the shared `window(...)` image; both load-error sentences
  replaced by `CaptureCondition` constants; `content` gained the doc comment the toolbar comment had
  been referencing.
- `Seamly/Seamly/Features/Result/ResultView.swift` — `fullScreenCover(item:onDismiss:content:)` with
  a new `discardPreparedExports()` clearing `pngURL`, `pdfURL`, `savedToPhotos`.
- `Seamly/Seamly/DesignSystem/CaptureCondition.swift` — `nothingToLineUpMessage` and
  `joinNotDescribedMessage`, next to `liningUpActionTitle`.
- `Seamly/Seamly/Features/Repair/JoinAlignment.swift` — `lowerPixelHeight`'s comment corrected: the
  strip keeps the lower frame's bottom chrome only when that frame is its segment's *last*
  (`Compositor.swift:275`); an interior join's rows are never drawn. Comment only.
- `Seamly/Seamly/Core/CaptureModel.swift` — deleted the stale "Otherwise has no caller in the shipped
  shell" sentence from `update(_:)`; corrected the spec path it cited.
- `Seamly/SeamlyUITests/RepairUITests.swift` — explanatory comment (and the final assertion's failure
  *message*) rewritten to the real mechanism. Assertions unchanged.
- `docs/superpowers/specs/2026-08-17-guided-repair-design.md` — the export-cost claims replaced with
  what actually collapses (candidate count) and an explicit refusal to claim an unmeasured cost.
- `docs/logs/2026-08-18-01-frozen-geometry.md` — the `isLowConfidence` bullet rewritten: structural
  contract, known-tautological assertion.
- `docs/logs/2026-08-18-02-guided-repair.md` — "Correction 4" rewritten (see below).
- `DECISIONS.md` — the equivalence fixture is `Screenshots/`, not `RealDevice/`.
- `CLAUDE.md` — records `-SeamlySeedMisalignedCapture`.

## What Was Discovered

- **The UI test's final assertion was right for a reason nobody had stated, including the ruling that
  blessed it.** The accepted explanation was that `waitForNonExistence` is satisfied by a
  `.processing` flip. It isn't: `commit()` awaits `update(_:)` — manifest write *plus* `assemble` to
  completion — **before** `dismiss()`, so the capture is already `.ready` when the cover drops and
  `ProcessingView` never renders on this path. The real reason is worse: while the cover is up,
  `ResultView` (notice included) is not in the accessibility tree at all, so the wait is satisfied by
  *the cover*, from the moment "Line it up" was tapped and before a byte was written. What that first
  wait reports is therefore timing, not correctness — consistent with the recorded discrimination
  run, where `{ dismiss() }` failed on the *first* assertion because `XCUIElement.tap()`'s post-tap
  idle wait had already let the cover finish dismissing. The hittability-gated re-assertion is doing
  all the real work.
- **Frozen geometry never made exports cheaper, and the spec claimed twice that it did.**
  `Compositor.composite` and `writePDF` call `refineSeams` unconditionally
  (`Compositor.swift:102`, `:146`); `refinementDelta: 0` does not skip it. Every draw still loads two
  full-resolution images per seam, profiles both — `refineVertical` profiles *before* it checks
  whether its search range is even valid (`:351-354`) — and runs the full-width `measureHorizontal`.
  What collapses is the **candidate count**: up to 33 offsets at delta 16, exactly one
  (`lo == hi == provisional`) at delta 0. That is the geometric guarantee the repair needs, and it is
  the only thing the change buys.
- **`freezeGeometry`'s field-preservation contract is structural, and the test named as proof cannot
  fail.** It copies exactly one field (`provisionalDy`), so `confidence`, `provisionalDx` and
  `isLowConfidence` survive by construction. `refineSeams` only overwrites `isLowConfidence` when the
  match comes back unconfident or `abs(dx) >= 2` (`:93`), and
  `freezingCorrectsAStoredOffsetToThePixelExactValue` establishes neither — its seam is pixel-exactly
  correctable, so the refined value is `false` either way. The assertion documents the contract; it
  does not pin it. A real test would have to construct an unconfident seam.
- **Two of the three defects are invisible to any test this branch has, and only reachable on screen
  by slowing the app down.** The seeded capture is 300×700, so both the load and the commit finish in
  well under the presentation animation. Photographing them needed a throwaway
  `try? await Task.sleep(for: .seconds(6))` in `load()` and `commit()`, a rebuild, and a restore from
  a byte-for-byte copy afterwards (md5 identical, `grep -c THROWAWAY` = 0). Worth remembering the
  next time a "there is no feedback during X" defect needs confirming rather than arguing about.
- **A `ShareLink` and a `Button` are indistinguishable in the accessibility tree** — both report as
  `Button` with the same label. Verifying defect 2 therefore had to be behavioural: tap once and see
  whether a share sheet appears. It did before the repair (a real sheet reading *"PDF Document · 165
  KB"*) and did not after, which is the observable the fix is about.
- The error state (`KeyframeIO` throwing, e.g. `sizeMismatch` or a deleted `.bgra`) was **not**
  reproduced on device — there was no safe way to induce it mid-session. Its legibility rests on the
  structural argument that all three branches now share one ground, not on a screenshot. Called out
  rather than glossed.

## Verification

- Simulator build: succeeded.
- Full app suite, fresh result bundle: **72 passed / 0 failed** — the stated baseline exactly
  (device-level 79, from two parameterized tests running 9 instances).
- `-only-testing:SeamlyUITests/RepairUITests`: **1 passed / 0 failed**.
- `swift test --package-path Seamly/StitchKit` not run — nothing under `Seamly/StitchKit/` was
  touched, and its suite was verified separately at 180 tests / 28 suites / 1 known issue.
- Screenshots for all three defects, in both appearances where applicable:
  `.superpowers/sdd/2026-08-18-guided-repair/task-7-report.md`, "Final fix wave".
