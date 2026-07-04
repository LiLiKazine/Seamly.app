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

- **Deployment target is iOS 26.5** (not iOS 17 as the README states). The README's
  minimum is aspirational; the project is pinned to 26.5.
- **Test targets are still on `SWIFT_VERSION = 5.0`** while the app target is 6.0.
  Only the app gets strict concurrency checking today.
- **No shared schemes** are checked in — `xcodebuild` relies on the auto-generated
  `Longshot` scheme. If a fresh checkout can't find it, open the project in Xcode once
  (or share the scheme) before scripting builds.
- **Bundle id is `io.github.lilikazine.Longshot`** — signing needs your own team.
