# 2026-07-25-03: Refresh the project docs; consolidate the App Group identifiers into StitchKit

**Status:** Implemented.

## Context

A request to describe the project's architecture turned into a documentation audit. Both
top-level docs still described the repo as it was on day one:

- `CLAUDE.md` opened with *"Early stage — the app is currently a fresh Xcode template
  (`ContentView` still shows 'Hello, world!')"* and told the reader to treat `README.md` as
  vision rather than a map of the code.
- `README.md` carried a *"Status: early stage … the capture pipeline and stitching engine below
  are the roadmap, not yet shipped"* banner.

Neither was true: broadcast capture, video import, photo import, order recovery, compositing,
editing, and export all ship. Worse than being merely out of date, three claims were actively
misleading:

1. **The app/extension split was backwards.** `README.md` said the extension "owns global
   structure (keyframes, offsets, chrome bands, segment breaks)" and the app only refines seams.
   The shipped design is the reverse, and deliberately so (2026-07-19-01): the extension banks
   keyframes and computes no geometry; `BatchStitcher` re-derives all of it at import. An agent
   or contributor following the README would add geometry to `SampleHandler` — the exact design
   that failed on device.
2. **The matching description was wrong in detail** — it described 1-D grayscale profiles with
   "vDSP (MAD scoring)" and "vImage (pixel extraction/grayscale)", predating the row-signature
   rewrite in 2026-07-05-03.
3. **`CLAUDE.md`'s documented test command didn't work.** `swift test --package-path StitchKit`
   does not resolve from the repo root; the package is at `Seamly/StitchKit`.

While verifying a claim about the App Group before writing it down, a second problem surfaced:
`Seamly/Core/AppGroup.swift`'s doc comment said *"Both targets compile this file."* It does not.
The project uses Xcode synchronized folder groups, one per target folder, so that file is
app-only — which is why `SampleHandler` repeated the group identifier as a literal. The group id
existed in 5 places (`AppGroup.identifier`, twice in `SampleHandler`, both `.entitlements`) and
the Darwin notification name in 2.

That duplication has a nasty failure mode: a wrong group id doesn't error, it just returns `nil`
for the container, so the symptom is a capture that silently produces nothing — the same class of
bug as `[B4]` in `DECISIONS.md`.

## Options

For where the shared identifiers should live:

| Approach | Pros | Cons |
|----------|------|------|
| Leave the duplication; just document it | Zero risk | Keeps 5 copies of a constant whose mismatch mode is a silent no-op capture; the misleading source comment stays |
| Share `Seamly/Core/AppGroup.swift` with the extension via a synchronized-group membership exception | File stays where it is | Hand-editing Xcode-managed `PBXFileSystemSynchronizedBuildFileExceptionSet` entries; fights the folder-per-target model and is fragile across Xcode versions |
| Add a new shared app-level folder synced into both targets | The conventional pre-Xcode-16 answer | Needs a fifth synchronized root group and both targets syncing it; more project surgery than the problem warrants |
| **Move the shared identifiers into `StitchKit` (chosen)** | It is the only compilation unit both targets already import; one declaration site each; no `.pbxproj` change at all | Puts a Seamly-specific constant in what is otherwise a general-purpose core |

And for the app-side Darwin-notification observer:

| Approach | Pros | Cons |
|----------|------|------|
| Move it into `StitchKit` alongside the identifiers | One `AppGroup` in one place | Puts app lifecycle behaviour in the core, and breaks under the package's isolation rules (see Discovered) |
| **Keep it app-side as `extension AppGroup` (chosen)** | Core stays configuration-only; preserves the isolation semantics it compiles under today | `AppGroup` is now split across two modules |

## Decision

Rewrite `README.md` and `CLAUDE.md` against the actual code, verifying every command and factual
claim by running it. Move `identifier`, `sessionFinishedNotification`, and `containerURL` into
`StitchKit.AppGroup`; keep the app-only broadcast-finish observer in the app target as an
extension on that type.

## Rationale

The docs are read by agents as instructions, not as prose, so a stale architecture section is not
a cosmetic problem — an inverted responsibility split actively steers work toward the design that
already failed on device. That justified rewriting rather than patching, and justified verifying
each command instead of copying it forward.

`StitchKit` is the right home for the identifiers because it is the only place both targets can
see, and because the package is already container-aware: `SessionStore` and `Diagnostics` are both
built around a `containerURL`. This is configuration for machinery that already lives there, not
app logic leaking inward. The alternative — project-file surgery on Xcode-managed exception sets —
carries more ongoing risk than the constant is worth.

The observer stays app-side for a concrete reason, not taste: see below.

## What Changed

- `README.md` — rewrote Status, How It Works (all three ingest routes; only broadcast was
  documented), Architecture (corrected split, added the "capture banks frames, the app derives
  geometry" section and `stitch-cli` as a fourth product), Stitching approach (row signatures,
  the two load-bearing conventions), Tech Stack, Project Structure, and Testing (the three
  fixture tiers and why the third exists). Checked off Photos import; added the unlisted video
  import; added the direction-scoring gap.
- `CLAUDE.md` — rewrote Status, Architecture (with the extension/app boundary as an explicit
  invariant), Commands (all verified, all repo-root-relative), Key locations, Testing (the
  false-green history as working guidance), and Gotchas.
- Added `Seamly/StitchKit/Sources/StitchKit/AppGroup.swift` — `public enum AppGroup` with the two
  identifiers and `containerURL`.
- Deleted `Seamly/Seamly/Core/AppGroup.swift`; added `Seamly/Seamly/Core/AppGroup+Observer.swift`
  with the Darwin observer and the `Notification.Name` extension, verbatim.
- `SeamlyBroadcast/SampleHandler.swift` — replaced 3 literals with `AppGroup` references and
  deleted `debugGroupID`.

## What Was Discovered

- **Target membership follows the folder.** The project has four
  `PBXFileSystemSynchronizedRootGroup` entries, one per target folder. Adding
  `AppGroup+Observer.swift` and deleting `AppGroup.swift` required no `.pbxproj` edit at all —
  confirmed by a clean build. The flip side is that there is no shared app-level folder, so code
  both targets need has exactly one home: `StitchKit`.
- **The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; the package does not.** This
  is why the observer had to stay app-side. `startBroadcastFinishObserver` holds a mutable
  `static var isObservingFinish` and installs a C-function-pointer callback; both are safe only
  under the app module's main-actor default. Moved into `StitchKit` (plain Swift 6, no default
  isolation) the mutable static becomes a concurrency error and the callback's isolation
  inference changes. Left in the app module unannotated, the semantics are unchanged.
- **The entitlements copies are irreducible.** Entitlements are build configuration and cannot
  reference Swift, so 2 literal copies of the group id necessarily remain. They are now the only
  ones, and `CLAUDE.md` records that they must match `AppGroup.identifier`.
- **Accelerate *is* used, contrary to my first reading** — `vDSP` for per-row mean/meanSquare in
  `VerticalProfile` and one `vDSP.divide` in `Compositor`. But `vImage` is not used anywhere (a
  `CGContext` RGBA render replaced it) and the MAD scoring in `OffsetMatcher.rowDifference` is
  plain Swift. The old README had the frameworks right and their roles wrong.
- **Measured baseline for the docs:** `swift test --package-path Seamly/StitchKit` → 80 tests in
  17 suites, green with 3 known issues across 2 tests, ~4.75 min. `xcodebuild -scheme Seamly
  -destination 'platform=iOS Simulator,name=iPhone 17' build` → BUILD SUCCEEDED. Both are now
  documented as verified rather than asserted.
- The slow real-frame tiers make the package suite ~5 min, which is worth stating in `CLAUDE.md`
  so it doesn't read as a hang; `--filter` is the iteration path.
