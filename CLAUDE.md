# Seamly

An iOS app that stitches overlapping screenshots into a single seamless long screenshot —
filling the gap where iOS has no scrolling-screenshot capture outside Safari. On-device
only, no accounts, no uploads.

## Status

**The pipeline is built and works end to end.** Live ReplayKit broadcast capture, video
import, photo import, order recovery, stitching, and export (Photos / PNG / PDF /
clipboard) all ship. `README.md` is now an accurate description of the code, not a spec —
trust it.

**The UI is now built to `design-system/`** (`docs/logs/2026-08-20-paper-interface.md`).
Direction **Paper**; IA **return-home**. Four screens and two sheets:

- **Home** opens on the most recent capture, because the common launch context is "I just
  stopped a broadcast — what did I get?" A dock carries Record / From Video / From Photos.
- **Library** lists every capture, and grids them at regular width. Diagnostics is behind
  its overflow.
- **Review** is the capture at length, with a margin rail at regular width.
- **Repair is a queue** (`Features/Repair/RepairQueueView.swift`, `RepairQueueModel.swift`):
  the capture enumerates its own problems and asks about them one at a time — seams, bars
  and gaps — with a wide affirmative answer, because most flagged seams turn out fine and
  the common case must be one tap. Numeric steppers live behind an explicit *Adjust
  manually* path. That is a narrow secondary affordance, **not** a return of the old
  `EditView` form, which was a test harness rather than a design.

This puts the pipeline's own words on screen (`UNCERTAIN SEAM`, `dy +420 px`), which
supersedes `docs/superpowers/specs/2026-08-17-guided-repair-design.md` — it rejected
per-seam and per-bar controls and kept "seam", "chrome", "confidence", "offset" and
"segment" off the screen entirely. **That earlier prohibition no longer holds.**

`CaptureModel.update(_:)` is the reconnection point the manifest's non-destructive design
was kept for; `RepairQueueModel` is its caller.

**Some things about that UI are load-bearing and easy to break by accident:**

1. **`CaptureGeometry` is the one coordinate space.** The margin marker, the rule on the
   sheet, the image and the scale bracket all resolve from a single `scrollY` in a single
   `GeometryReader`, so there is nothing for them to drift relative to. Do not add a second
   source of scroll position, and note that `CaptureView`'s overlay must stay
   `alignment: .topLeading` — at the default `.center` every mark is displaced by half the
   viewport/content difference, which looks plausible until the capture is long.
2. **`SeamlyColor.sheet` is fixed white in BOTH themes**, and `seamConfident` is fixed ink.
   A capture must never be dimmed at night. Do not "fix" either into a semantic colour.
3. **Never fade `BroadcastPickerButton` to hide it.** SwiftUI does not route touches into a
   near-transparent `UIViewRepresentable` host, and its cutoff is far above UIKit's documented
   0.01 alpha floor. A `.opacity(0.02)` on it shipped a Record button that swallowed every tap
   while `window.hitTest` still returned the picker's private `UIButton` and XCUITest still
   called it `isHittable` — so both dock UI tests stayed green over a dead button. `CaptureDock`
   now stacks the picker *underneath* an opaque slab with `allowsHitTesting(false)` on the
   covers. A `#if DEBUG` guard in `BroadcastPickerButton` trips if it is ever faded again
   (`docs/logs/2026-08-22-02-record-button-dead-tap.md`).
4. **`--icon-field` / `--icon-join` are theme-stable too**, for the same class of reason.
   The app icon ("Ruled, three uneven" — `docs/logs/2026-08-22-app-icon.md`) is ink-dominant
   by construction: paper joins over an ink field. `--ink` and `--paper` both flip in the dark
   scope, so building the mark on them inverts it at night and the joins become cuts in a
   sheet. Only the accent changes appearance, and `--mark-flag` does that by itself. Do not
   "tidy" them into `--ink`/`--paper`.
5. **The extension needs its own copy of the icon, and `make-app-icon.swift` writes both.**
   The broadcast picker's row is the *extension's* row. An appex with no icon does not borrow
   the app's current one — iOS resolves a fallback once, caches it per extension bundle id, and
   an iconless appex has nothing whose bytes ever change to invalidate it. That shipped a picker
   still showing the pre-Paper gradient while the Home Screen was correct. Once a device has
   cached that fallback, **only a reboot clears it** — a delete + reinstall does not, because the
   rendition lives in a system-wide cache keyed by bundle id + version and the version has never
   been bumped. Do not delete `SeamlyBroadcast/Assets.xcassets` or its
   `ASSETCATALOG_COMPILER_APPICON_NAME`; the catalog cannot be shared with the app's because
   target membership follows the folder (`docs/logs/2026-08-22-03-broadcast-extension-icon.md`).

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

## Design

`design-system/` is the **design source of truth**: tokens, 20 components each with a
`.d.ts` contract and a `.prompt.md`, guideline cards, and a live click-through UI kit
covering six screens in both size classes. Also published at
[claude.ai/design](https://claude.ai/design/p/f9e8831d-2cc1-4513-9cf0-aea67fd27259).
The shipped UI is built to it. Where the two ever disagree again, **the design is the
intent and the code is history.**

- **Direction: Paper.** The capture is a sheet lying on a desk — warm light ground,
  square-cornered sheets, depth from rules rather than shadow.
- **The load-bearing rule.** On a light ground a thin rule over white captured content is
  easy to miss, so the mark on the sheet stays quiet and *findability lives in the margin*,
  where the ground is always paper and contrast is guaranteed whatever was captured.
- **IA: return-home.** The app opens on the most recent capture, because its most common
  launch context is "I just stopped a broadcast — what did I get?"
- **Repair: a queue.** The capture enumerates its own problems and asks about them one at
  a time, rather than the user hunting a 15 000 px image.
- `design-system/swiftui/SeamlyTokens.swift` — token port, typechecks under Swift 6
  against the iOS 26 SDK. `FEASIBILITY.md` beside it records what does **not** port:
  line-height is a multiplier in CSS but additive leading in SwiftUI, `.tracking()` does
  not scale with Dynamic Type, and the CSS breakpoints should be replaced by
  `horizontalSizeClass` rather than translated.

Colour tokens are contrast-solved against the ground, not picked by eye; every token
clears 4.5:1. If you change one, re-check it.

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

# Regenerate the app icon into BOTH appiconsets (app + broadcast extension). Parses the
# hexes out of design-system/tokens/colors.css, so the icon stays derivable from the design
# system — never hand-edit the PNGs, and never update just one of the two.
swift scripts/make-app-icon.swift

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

**Launching with `-SeamlySeedMisalignedCapture` (`#if DEBUG` only) writes a deliberately
misaligned two-keyframe capture straight into app storage** (`Core/DebugSeed.swift`) — the only way
to reach guided repair from a UI test or by hand, since the real import paths are system pickers a
test cannot drive. This narrowly reverses Spec 1's "no test-only hooks in app storage" decision; it
stays a single explicit launch argument, not a general fixture mechanism (`docs/logs/
2026-08-18-02-guided-repair.md`).

**Launching with `-SeamlyLiveCaptureUnavailable` (`#if DEBUG` only) forces the dock into its
"live capture cannot work here" branch**, where the Record slab is replaced by a sentence naming the
import paths. The simulator has no recording service and is deliberately treated as *available* so
the dock UI tests keep touching the real picker, which leaves that branch unreachable there without
this argument (`docs/logs/2026-09-04-01-live-capture-availability.md`). The decision itself is
`LiveCaptureAvailability`, a pure enum; `LiveCaptureMonitor` only feeds it from ReplayKit.

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
- **App:** `Seamly/Seamly/` — `AppShell` (routing), `Core/` (`CaptureModel`,
  `StitchAssembler`, `MediaImporter`, `Capture+Design`, `AppGroup+Observer`), `DesignSystem/`
  (`Tokens/SeamlyTokens`, `Components/` — 20 components in seven folders — plus
  `CaptureGeometry` (the one coordinate space), `CaptureView` (the shared capture surface),
  `CaptureFinding` (a capture's own problems, enumerated), `ZoomState`, and `CaptureCondition`
  — the *only* place pipeline facts and errors become English), and `Features/` (`Capture`,
  `Home`, `Library`, `Result`, `Repair`, `Import`, `Export`, `Onboarding`, `Diagnostics`)
- **Extension:** `Seamly/SeamlyBroadcast/SampleHandler.swift` — plus its own
  `Assets.xcassets` holding the app icon, which the broadcast picker needs and cannot
  inherit from the app
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
- **Landscape iPhone is unproven on screen.** `SeamlyLayout.isShort` moves the position scale
  under the sheet, and no automated run has ever photographed it: `XCUIDevice.shared.orientation`
  rotates the screenshot buffer but the app's window scene does not resize, so every landscape
  capture is portrait content rotated 90° on black — with or without test clones. The branch is
  self-consistent by inspection (`CaptureView.swift:85`, `:96`, `:106`), but rotate a device by
  hand before trusting it (`docs/logs/2026-08-20-paper-interface.md`).
- **The real-frame test tiers are slow** (several minutes for the package). Inherent to the
  fixtures, not a hang; use `--filter` while iterating.
- **`#expect` over `contains(where:)` / `allSatisfy` won't compile** — the macro loses the
  `rethrows` conversion and demands a `try`. Bind to a local first. Not a `SWIFT_VERSION`
  artifact; it reproduces in `StitchKit`'s Swift 6 tests too.
- **`StitchAssembler.composite` no longer refines — it draws the manifest verbatim.**
  `freezeGeometry` (import-time only) is where the ±16 px seam search now happens; `composite`
  and `writePDF` build `Compositor(refinementDelta: 0)`, which collapses the search range to
  `lo == hi == provisional`. This is load-bearing for guided repair: a user's hand-aligned
  `provisionalDy` is exactly what gets drawn, with nothing re-searching around it. **Freezing
  must never move into the draw path** (`assemble`, `fullComposite`, `exportPDF`, or anywhere
  `update(_:)` touches) — it would re-center its ±16 px window on the user's own value and can
  silently move it, undoing a repair the next time the app opens. See
  `docs/logs/2026-08-18-01-frozen-geometry.md` and `[GR-1]` in `DECISIONS.md`.
- **A SwiftUI `.frame(w,h).clipped()` thumbnail can still report an inflated tap/accessibility
  frame.** `.clipped()` only affects painting; without an explicit `.contentShape(Rectangle())`,
  the hit-test and accessibility geometry follow the *unclipped* content's own render size. This
  bit `HomeView`'s recents thumbnail for exactly this reason — see `docs/logs/
  2026-08-18-02-guided-repair.md`, "What Was Discovered." Any new fixed-box image thumbnail
  needs `.contentShape(Rectangle())` alongside `.clipped()`, not instead of it.
