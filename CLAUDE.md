# Seamly

An iOS app that stitches overlapping screenshots into a single seamless long screenshot —
filling the gap where iOS has no scrolling-screenshot capture outside Safari. On-device
only, no accounts, no uploads.

## Status

**The pipeline is built and works end to end.** Live ReplayKit broadcast capture, video
import, photo import, order recovery, stitching, preview, non-destructive editing, and
export (Photos / PNG / JPEG / PDF / clipboard) all ship. `README.md` is now an accurate
description of the code, not a spec — trust it.

Two known gaps are tracked as `withKnownIssue` tests, not hidden:

- `BatchStitcher` mis-scores scroll direction on image-heavy content —
  `docs/logs/2026-07-23-01-batch-stitcher-direction-on-image-heavy-content.md`
- The dense live-frame regression oracle still needs a real capture; the existing device
  fixtures come from a *broken* capture with fast-flick gaps —
  `docs/logs/2026-07-05-03-real-frame-orientation-and-signal-fix.md`

Do not "fix" these by relaxing the assertions. If you make one pass legitimately, remove
its `withKnownIssue` and say so.

## Architecture

Four products: `StitchKit` (local SwiftPM package, the pure core), `Seamly` (SwiftUI app),
`SeamlyBroadcast` (Broadcast Upload Extension), and `stitch-cli` (a package executable for
visual triage). They hand off through an App Group container.

### The invariant that matters most

**The extension banks frames; the app derives all geometry.**

`SeamlyBroadcast` profiles each frame, banks a keyframe when the view has scrolled far
enough, writes raw BGRA bytes, and appends a manifest entry. It computes **no** order, **no**
seams, **no** segment breaks, **no** chrome bands. All of it is re-derived from the keyframes
at import by `BatchStitcher`, via `StitchAssembler.resolveGeometry`, which then *overwrites*
the extension's manifest.

This is a deliberate reversal of the original streaming design (a live tracker in the
extension lost lock and produced nothing). If you find yourself adding geometry computation
to `SampleHandler`, that's the wrong side of the boundary — put it in `BatchStitcher`, where
it has the whole frame set, can be re-run after a fix, and is testable off-device.

The extension is also under a hard **~50 MB** footprint ceiling: hold at most one frame,
`autoreleasepool` per frame, keep everything else 1-D, and never add an encoder or a GPU
`CIContext` to the hot path.

### Stitching approach

No Vision. `VNTranslationalImageRegistrationRequest` is *not* used — its global registration
is corrupted by fixed chrome and isn't pixel-exact. Instead:

`VerticalProfile` renders each frame small and sRGB and reduces every row to a short vector
of BT.601 luma samples (a **row signature**), with `vDSP` supplying row mean and variance.
`OffsetMatcher` scores candidate offsets by variance-weighted MAD over those signatures.
`ContentBandDetector` finds static chrome rows and that band is both masked out of matching
and cropped from every strip but the first. `Compositor` snaps each seam to pixel-exactness
with a full-res local search, then draws **hard cuts** — never feathered.

Two conventions are load-bearing, each paid for with a real bug (see `DECISIONS.md`):

1. **Profile row 0 is the image's top row, and a downward scroll yields positive `dy`.**
   There is no compensating flip anywhere. Do not add one.
2. **Row *signatures*, not row means.** A per-row mean alone collapses to a near-tie between
   a real scroll and its mirror on feed content — that shipped an inverted sign for three
   fix cycles.

## Tech decisions

- **iOS app, SwiftUI, Swift 6 language mode** for the app, extension, and `StitchKit`.
  No UIKit unless a capability is unavailable in SwiftUI (`BroadcastPickerButton` is the
  legitimate exception — `RPSystemBroadcastPickerView` has no SwiftUI equivalent).
- **Swift Concurrency over GCD.** `async`/`await`, `Task`, structured concurrency — not
  `DispatchQueue`. Pixel work goes off the main actor via `Task.detached` with `Sendable`
  boundaries; see `LibraryModel`.
- **Actors / `@MainActor` over locks.** `LibraryModel` is `@MainActor @Observable` and is the
  single source of truth for captures. `StitchKit`'s types are `Sendable` value types.
- **First-party frameworks only.** No third-party dependencies — Core Graphics, Accelerate,
  ReplayKit, AVFoundation, PhotosUI, SwiftUI.

## Error handling

**Never swallow errors silently.** An error that vanishes with no propagation, no log, and no
user-visible effect turns a real failure (disk full, corrupt manifest, denied permission)
into a silent no-op that's near-impossible to debug. This is not hypothetical here: a bare
`try?` around the App Group import is exactly why "coming back from a broadcast does
nothing" shipped (`DECISIONS.md`, `[B4]`).

Avoid these swallowing patterns unless the exception below applies:

- `try?` that drops the error and continues as if nothing happened.
- `catch {}` (empty) or `catch { return nil }` / `catch { return }` that discards the error.
- Fallbacks like `?? someDefault` or `?? image` that mask a failure behind a plausible value.

Instead:

- **Propagate** with `throws` / `try` when the caller can react — most of `StitchKit`
  (`BatchStitcher`, `Compositor`, `SessionStore`) already does. Prefer it.
- **Handle meaningfully** at the boundary: recover, surface to the user (`LibraryModel`
  sets `importError`; `Capture.Phase.failed` carries the message), or log via `Diagnostics`.
- **When you genuinely must ignore an error** (best-effort cleanup, expected-benign
  failure), do it *explicitly and narrowly*: catch it, and leave a comment saying why
  ignoring is correct — e.g. `catch { /* best-effort cleanup; source already gone */ }`.
  A bare `try?` doesn't document intent; a commented `catch` does.

The extension can't show UI and its container isn't reliably pullable over USB, so its
errors go to `Diagnostics` (unified log + a durable App Group file the app reads back in
`DiagnosticsView`). A capture that produces nothing must stay diagnosable after the fact.

Rule of thumb: if a reviewer can't tell whether an error was ignored *on purpose*, the
handling is wrong.

## Commands

```bash
# StitchKit tests — the fast, primary loop (no simulator, no signing).
swift test --package-path Seamly/StitchKit

# One suite while iterating
swift test --package-path Seamly/StitchKit --filter OffsetMatcherTests

# Visual triage on a real file — run this before believing a stitch is correct
cd Seamly/StitchKit
swift run stitch-cli video ~/Pictures/scroll.mp4 --out /tmp/stitch
# --prefix is not optional here: RealDevice/ holds three unrelated captures.
swift run stitch-cli images ./Tests/StitchKitTests/Fixtures/RealDevice --prefix youtube --out /tmp/stitch
swift run stitch-cli images ./Tests/StitchKitTests/Fixtures/Screenshots --out /tmp/stitch

# Build (simulator) — verified working
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# App/UI tests
xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

All paths above are from the **repo root**. Note the nested layout: the root holds
`README.md`, `CLAUDE.md`, `DECISIONS.md`, and `docs/`; the Xcode project and the package
live one level down in `Seamly/`.

Day-to-day: open `Seamly/Seamly.xcodeproj`, select the `Seamly` scheme, set your development
team under *Signing & Capabilities*, ▶ Run. No API keys or configuration needed.

## Key locations

- **Core (start here):** `Seamly/StitchKit/Sources/StitchKit/`
  — `VerticalProfile`/`FrameProfile` (signal), `OffsetMatcher` (matching),
  `ContentBandDetector` (chrome), `KeyframeSelector`/`ScrollCaptureDriver` (frame picking),
  `BatchStitcher` (order recovery + manifest), `Compositor` (assembly, PDF),
  `StitchSession`/`SessionStore`/`KeyframeIO`/`Diagnostics` (persistence),
  `AppGroup` (identifiers shared with the extension)
- **App:** `Seamly/Seamly/` — `Core/` (`LibraryModel`, `StitchAssembler`, `MediaImporter`,
  `AppGroup+Observer`) and `Features/` (`Capture`, `Library`, `Preview`, `Export`,
  `Onboarding`, `Diagnostics`)
- **Extension:** `Seamly/SeamlyBroadcast/SampleHandler.swift`
- **Tests:** `Seamly/StitchKit/Tests/StitchKitTests/` (the bulk) ·
  `Seamly/SeamlyTests/` (app-level import/assembly) · `Seamly/SeamlyUITests/`
- **Fixtures:** `Seamly/StitchKit/Tests/StitchKitTests/Fixtures/` — synthetic,
  `wikipedia.png`, `Example/`, `RealDevice/` (real broadcast keyframes + a screen recording),
  and `Screenshots/` (real Photos-app screenshots, the "From Photos" shape). `RealDevice/` and
  `Screenshots/` each carry a `README.md` recording ground truth **and their resolution** —
  read it before measuring anything against them.
- **Why the code is like this:** `DECISIONS.md` + `docs/logs/` (one log per significant
  change) · `docs/superpowers/plans/` and `docs/superpowers/specs/`

## Testing

- Use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest. The exception is
  `SeamlyUITests`, which is XCTest because `XCUIApplication` has no Swift Testing equivalent;
  don't "convert" it.
- Keep the stitching core pure and testable, and cover it with TDD before wiring up UI.
- Fixtures are **checked in and read from disk** — never the photo library, never the network,
  so a run is deterministic and CI-friendly. Bundled resources are the norm (`Bundle.module`);
  the app test target has no fixture bundle, so `SeamlyTests/PhotoPickOrderTests` reads
  `StitchKit`'s by source-relative `#filePath` rather than duplicating the PNGs. Either is
  fine; a live library lookup is not.

**Read this before trusting a green suite.** The synthetic tier produced *three consecutive
cycles of false green*: the fixtures were built upside-down and compensated by a flip in
`VerticalProfile`, so two inverted conventions cancelled out — every real capture shattered
while the suite passed. A later cycle passed on half-resolution fixtures and shattered at
real device geometry.

Consequences for how you test here:

- Prefer **real pixels**. A green synthetic suite is necessary but not sufficient.
- Fixtures must be **full resolution** — a different downsample factor changes `rowScale` and
  therefore matching. `RealDevice/youtube-*` is a knowing exception (half of its recording,
  kept for the translucent tab bar); its README says so, and measurements don't cross sets.
- For anything visual, render the output and **look at it** (`stitch-cli`). A stitch can
  clear every structural gate — right order, no breaks, high confidence — and still be
  plainly wrong; the translucent-chrome bug did exactly that.
- When a test can't yet pass honestly, use `withKnownIssue` with a link to its decision
  log. Never fake green.

## Gotchas

- **Deployment target is iOS 26.0.**
- **Test targets are on `SWIFT_VERSION = 5.0`** while the app, extension, and `StitchKit`
  are on 6.0 — so strict concurrency checking does not cover the Xcode test targets.
  `StitchKit`'s own tests *are* Swift 6.
- **Schemes are shared** (`Seamly`, `SeamlyBroadcast`), so `xcodebuild` works from a fresh
  checkout without opening Xcode first.
- **Bundle ids:** app `io.github.lilikazine.Seamly`, extension
  `io.github.lilikazine.Seamly.Broadcast`, App Group
  `group.io.github.lilikazine.Seamly`. Signing needs your own team, and the app and
  extension must share the App Group or every capture silently produces nothing.
- **The App Group id and the Darwin notification name live in `StitchKit.AppGroup`** —
  one declaration each, used by both targets. The two `.entitlements` files still repeat the
  group id literally (entitlements are build config and can't reference Swift); those are the
  only remaining copies, and they must match `AppGroup.identifier` or every capture silently
  produces nothing (a wrong group id just yields `nil` for the container).
- **Target membership follows the folder.** The project uses **Xcode synchronized folder
  groups** (one `PBXFileSystemSynchronizedRootGroup` per target folder), so adding or deleting
  a source file needs no `.pbxproj` edit — but a file under `Seamly/` is app-only and one under
  `SeamlyBroadcast/` is extension-only. There is no shared app-level folder, so **code both
  targets need belongs in `StitchKit`**; that's why `AppGroup` lives there rather than in the
  app. App-only glue can still extend it (`Core/AppGroup+Observer.swift`).
- **Older logs say "Longshot."** That was the previous product name; it survives in
  `DECISIONS.md` and `docs/logs/` as historical record. The bundle ids are `Seamly`.
- **A stopped broadcast doesn't fire `scenePhase`** when stopped from Control Center, so the
  extension posts a Darwin notification that `AppGroup.startBroadcastFinishObserver()`
  bridges to `NotificationCenter`. The foreground scan is still the source of truth.
- **Display proxies are capped at 4096 px tall.** A GPU texture tops out ~16,384 px/side, so
  a full-res stitch cannot render as one texture — never bind a full composite to an `Image`.
- **The real-frame test tiers are slow** — several minutes for the package, and the number
  grows with every real-pixel fixture. That's inherent to them, not a hang; use `--filter`
  while iterating.
