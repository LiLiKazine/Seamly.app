# Seamly

An iOS app that stitches overlapping screenshots into a single seamless long screenshot —
filling the gap where iOS has no scrolling-screenshot capture outside Safari. On-device
only, no accounts, no uploads.

## Status

**The pipeline is built and works end to end.** Live ReplayKit broadcast capture, video
import, photo import, order recovery, stitching, and export (Photos / PNG / JPEG / PDF /
clipboard) all ship. `README.md` is now an accurate description of the code, not a spec —
trust it.

The UI around it is a deliberately **one-shot shell**: a record-first home (record button,
"From Video", "From Photos", a recents strip) that navigates itself to a single result
screen whose primary action is **Save to Photos**. There is **no way to fix a bad stitch —
only re-record.** `EditView` and the seam/chrome controls were removed with the rest of the
test-harness UI, pending a guided-repair spec
(`docs/superpowers/specs/2026-08-10-one-shot-capture-shell-design.md`). Do not re-add an
edit surface as a "missing feature": its absence is an accepted decision. The manifest is
still non-destructive and `CaptureModel.update(_:)` is still there, unused, as the
reconnection point.

One known gap is tracked as a `withKnownIssue` test, not hidden:

- The dense live-frame regression oracle still needs a real capture; the existing device
  fixtures (`RealDevice/baidu-*`) come from a *broken* capture with fast-flick gaps, and
  still split a clean downward scroll into 4 segments —
  `docs/logs/2026-07-05-03-real-frame-orientation-and-signal-fix.md`

Do not "fix" this by relaxing the assertion. If you make it pass legitimately, remove the
`withKnownIssue` and say so.

Closed since: `BatchStitcher` mis-scoring scroll direction on image-heavy content (issue #2)
— the video tier now stitches into one continuous segment. Its last break was blamed on an
"unmatchable" fixture keyframe for two cycles; the real cause was `OffsetMatcher` discarding
large offsets, `docs/logs/2026-08-08-02-masked-overlap-floor.md`.

## Architecture

Four products: `StitchKit` (local SwiftPM package, the pure core), `Seamly` (SwiftUI app),
`SeamlyBroadcast` (Broadcast Upload Extension), and `stitch-cli` (a package executable for
visual triage). They hand off through an App Group container.

### The invariant that matters most

**The extension banks frames; the app derives all geometry.**

`SeamlyBroadcast` profiles each frame, banks a keyframe when the view has scrolled far
enough, writes raw BGRA bytes, and appends a manifest entry. It computes **no** order, **no**
seams, **no** segment breaks, **no** chrome measurements. All of it is re-derived from the keyframes
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
`ChromeStaticRowDetector` supplies a same-screen static-row signal; `BatchStitcher` combines it with
aligned seam residuals to persist chrome per keyframe UUID. Matching and full-resolution refinement
use asymmetric masks when adjacent frames have different chrome. `Compositor` resolves per-edge
user overrides over automatic measurements, snaps each seam to pixel-exactness, and draws **hard
cuts** — never feathered.

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
  boundaries; see `CaptureModel`.
- **Actors / `@MainActor` over locks.** `CaptureModel` is `@MainActor @Observable` and is the
  single source of truth for captures. `StitchKit`'s types are `Sendable` value types.
- **Pure app-level types are `nonisolated`.** The app target sets
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so anything meant to be usable off the main
  actor (`CaptureCondition`, `CaptureFacts`, `ZoomState`, `StitchAssembler`, `MediaImporter`)
  must say so. SwiftUI views must **not**.
- **First-party frameworks only.** No third-party dependencies — Core Graphics, Accelerate,
  ReplayKit, AVFoundation, PhotosUI, SwiftUI.

## Error handling

**Never swallow errors silently.** A bare `try?` around the App Group import is exactly why
"coming back from a broadcast does nothing" shipped (`DECISIONS.md`, `[B4]`).

Don't: `try?` that drops the error · empty `catch {}` / `catch { return nil }` · masking
fallbacks like `?? someDefault` or `?? image`.

Do, in order of preference:

- **Propagate** with `throws` / `try` — most of `StitchKit` already does.
- **Handle at the boundary**: recover, surface it (`CaptureModel.importError`,
  `Capture.Phase.failed`), or log via `Diagnostics`.
- **Never show a raw error to a user.** `StitchKit`'s error types are plain `Error` enums, so
  `localizedDescription` bridges them to *"The operation couldn't be completed.
  (StitchKit.Compositor.CompositorError error 1.)"*. Anything user-visible goes through
  `CaptureCondition.message(for:)`; the raw error still goes to `Diagnostics`.
- **Ignore explicitly and narrowly** when you must: catch it and comment why — e.g.
  `catch { /* best-effort cleanup; source already gone */ }`. If a reviewer can't tell the
  error was ignored *on purpose*, the handling is wrong.

The extension can't show UI and its container isn't reliably pullable over USB, so its errors
go to `Diagnostics` (unified log + a durable App Group file `DiagnosticsView` reads back).

## Commands

```bash
# Fetch the binary test fixtures — REQUIRED ONCE on a fresh clone, before any test run.
# They are GitHub Release assets, not committed; see "Fixtures" below.
scripts/fetch-fixtures.sh

# StitchKit tests — the fast, primary loop (no simulator, no signing).
swift test --package-path Seamly/StitchKit

# One suite while iterating
swift test --package-path Seamly/StitchKit --filter OffsetMatcherTests

# Visual triage on a real file — run this before believing a stitch is correct
cd Seamly/StitchKit
swift run stitch-cli video ~/Pictures/scroll.mp4 --out /tmp/stitch
# --prefix required: RealDevice/ holds three unrelated captures
swift run stitch-cli images ./Tests/StitchKitTests/Fixtures/RealDevice --prefix youtube --out /tmp/stitch

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
  `ChromeDomain`/`ChromeStaticRowDetector` (per-keyframe chrome + row signal),
  `KeyframeSelector`/`ScrollCaptureDriver` (frame picking),
  `BatchStitcher` (order recovery + manifest), `Compositor` (assembly, PDF),
  `StitchSession`/`SessionStore`/`KeyframeIO`/`Diagnostics` (persistence),
  `AppGroup` (identifiers shared with the extension)
- **App:** `Seamly/Seamly/` — `Core/` (`CaptureModel`, `StitchAssembler`, `MediaImporter`,
  `AppGroup+Observer`), `DesignSystem/` (`CaptureCondition` — the *only* place pipeline facts
  and errors become English — plus `ConditionNotice`, `CaptureCanvas`, `ZoomState`), and
  `Features/` (`Capture`, `Home`, `Result`, `Export`, `Onboarding`, `Diagnostics`)
- **Extension:** `Seamly/SeamlyBroadcast/SampleHandler.swift`
- **Tests:** `Seamly/StitchKit/Tests/StitchKitTests/` (the bulk) ·
  `Seamly/SeamlyTests/` (app-level import/assembly) · `Seamly/SeamlyUITests/`
- **Fixtures:** `Seamly/StitchKit/Tests/StitchKitTests/Fixtures/` — synthetic, `wikipedia.png`,
  `Example/`, `RealDevice/` (broadcast keyframes), `Screenshots/` (Photos-app screenshots),
  `Screenshots2/` (same, but with a live clock inside the bars), `Screenshots3/` (a large scroll
  step, and a bottom bar that *collapses* after the first shot), `Screenshots4/` (a very large
  scroll step — one pair overlaps only 4.6%), `Recordings/` (three untrimmed handheld screen
  recordings). The last five carry a `README.md` with ground truth and resolution — read it before
  measuring.
- **Why the code is like this:** `DECISIONS.md` + `docs/logs/` (one log per significant
  change) · `docs/superpowers/plans/` and `docs/superpowers/specs/`

## Testing

- Use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest, except
  `SeamlyUITests` (XCUIApplication requires it).
- Keep the stitching core pure and testable, and cover it with TDD before wiring up UI.
- Fixtures are read from disk — never the photo library. Bundled (`Bundle.module`) or
  source-relative `#filePath`, either is fine.
- **The binary fixtures are not committed.** They are hosted as assets on the `fixtures-v1`
  GitHub Release and fetched by `scripts/fetch-fixtures.sh`, which verifies each set's SHA-256
  against `Fixtures/manifest.json`. Every set's `README.md` — the ground truth — *is* in the repo
  and must stay there; only the pixels live outside. `wikipedia.png` is also still committed,
  because `Package.swift` declares it as a single-file resource and SwiftPM fails the whole
  **build** when a declared resource path is missing.
- **Adding a fixture set is a three-step change:** drop it in `Fixtures/`, write its `README.md`
  with raw-pixel ground truth, then re-cut and upload its tarball and update `manifest.json`.
  `FixturePresenceTests` fails if a set on disk is missing from the manifest — otherwise it would
  work here and be absent from every fresh clone.
- A missing fixture must **fail**, never skip. `FixturePresenceTests` is the single actionable
  failure for an unfetched checkout; do not add `withKnownIssue` or an early return to it.

**A green suite here has lied three times** — synthetic fixtures built upside-down cancelled out
a flip in `VerticalProfile`, and a later cycle passed at half resolution. Every real capture
shattered while the suite stayed green. So:

- Prefer **real pixels**. A green synthetic suite is necessary but not sufficient.
- Fixtures must be **full resolution** — a different downsample changes `rowScale` and so
  matching. (`RealDevice/youtube-*` is a documented exception — see its README.)
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
- **The real-frame test tiers are slow** (several minutes for the package). Inherent to the
  fixtures, not a hang; use `--filter` while iterating.
- **`#expect` over `contains(where:)` / `allSatisfy` won't compile** — the macro loses the
  `rethrows` conversion and demands a `try`. Bind to a local first. Not a `SWIFT_VERSION`
  artifact; it reproduces in `StitchKit`'s Swift 6 tests too.
