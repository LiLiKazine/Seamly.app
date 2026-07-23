# Longshot

An iOS app that stitches multiple overlapping screenshots into a single seamless long
screenshot — filling the gap where iOS has no scrolling-screenshot capture outside
Safari. On-device only, no accounts, no uploads.

## Status

**Early stage — the app is currently a fresh Xcode template** (`ContentView` still
shows "Hello, world!"). `README.md` describes the *intended* product and structure
(Features, `Features/`+`Core/` layout, `Tests/Fixtures/`), none of which exists yet.
Treat the README as the vision/spec, not a map of the current code — build the
structure as features land rather than assuming it's already there.

## Architecture (intended)

**Vision aligns; Core Image composites.** The Vision framework
(`VNTranslationalImageRegistrationRequest`) finds the vertical offset between adjacent
overlapping screenshots; Core Image / Core Graphics blends them along the computed seam
and crops status bars / notches / home indicators from intermediate frames. All
processing is on-device — the app only ever reads the screenshots the user explicitly
picks and writes on export.

## Tech decisions

- **iOS app, SwiftUI, Swift 6 language mode.** UI is SwiftUI; no UIKit unless a
  capability is unavailable in SwiftUI. The app target is already on `SWIFT_VERSION = 6.0`.
- **Swift Concurrency over GCD.** Use `async`/`await`, `Task`, and structured
  concurrency — not `DispatchQueue`/GCD. `SWIFT_APPROACHABLE_CONCURRENCY` is on.
- **Actors over locks for data safety.** Protect shared mutable state with `actor`
  isolation (and `@MainActor` for UI state), not `NSLock`/`os_unfair_lock`/serial queues.
- **First-party frameworks only.** No third-party dependencies — Vision, Core Image,
  Core Graphics, PhotosUI, SwiftUI.

## Error handling

**Never swallow errors silently.** An error that vanishes with no propagation, no log,
and no user-visible effect turns a real failure (disk full, corrupt manifest, denied
permission) into a silent no-op that's near-impossible to debug. The default is to
*propagate* (`throws`) or *handle* (recover, log, or surface to the user) — not discard.

Avoid these swallowing patterns unless the exception below applies:

- `try?` that drops the error and continues as if nothing happened.
- `catch {}` (empty) or `catch { return nil }` / `catch { return }` that discards the error.
- Fallbacks like `?? someDefault` or `?? image` that mask a failure behind a plausible value.

Instead:

- **Propagate** with `throws` / `try` when the caller can react — most Core functions
  (`StitchAssembler`, `Exporter`) already do this. Prefer it.
- **Handle meaningfully** at the boundary: recover, or surface to the user (e.g.
  `ExportView` sets `status = error.localizedDescription`), or at minimum log the error.
- **When you genuinely must ignore an error** (best-effort cleanup, expected-benign
  failure), do it *explicitly and narrowly*: catch the specific error, and leave a comment
  saying why ignoring is correct — e.g. `catch { /* best-effort cleanup; source already gone */ }`.
  A bare `try?` doesn't document intent; a commented `catch` does.

Rule of thumb: if a reviewer can't tell whether an error was ignored *on purpose*, the
handling is wrong.

## Commands

```bash
# Build (simulator)
xcodebuild -project Longshot/Longshot.xcodeproj -scheme Longshot \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Test (Swift Testing)
xcodebuild -project Longshot/Longshot.xcodeproj -scheme Longshot \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Day-to-day: open `Longshot/Longshot.xcodeproj` in Xcode, select the `Longshot`
scheme, set your development team under *Signing & Capabilities*, ▶ Run. No API keys
or configuration needed.

## Key locations

- App sources: `Longshot/Longshot/` (`LongshotApp.swift`, `ContentView.swift`)
- Unit tests: `Longshot/LongshotTests/` · UI tests: `Longshot/LongshotUITests/`
- Xcode project: `Longshot/Longshot.xcodeproj`

Note the nested layout — the repo root holds `README.md`; the Xcode project lives one
level down in `Longshot/`.

## Testing

- Use **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest. The
  template already uses it.
- Write the stitching core as **pure, testable Swift** (overlap detection, seam
  computation, crop heuristics) and cover it with TDD before wiring up UI.
- Feed the registration/compositing tests with **bundled fixture screenshot sets**, not
  live photo-library access — deterministic and CI-friendly.

## Gotchas

- **Deployment target is iOS 26.0** (not iOS 17 as the README states). The README's
  minimum is aspirational; the project is pinned to 26.0.
- **Test targets are still on `SWIFT_VERSION = 5.0`** while the app target is 6.0.
  Only the app gets strict concurrency checking today.
- **No shared schemes** are checked in — `xcodebuild` relies on the auto-generated
  `Longshot` scheme. If a fresh checkout can't find it, open the project in Xcode once
  (or share the scheme) before scripting builds.
- **Bundle id is `io.github.lilikazine.Longshot`** — signing needs your own team.
