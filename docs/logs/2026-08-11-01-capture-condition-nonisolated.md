# 2026-08-11-01: `CaptureCondition` and the app target's default-`@MainActor` isolation

**Status:** Implemented

## Context

First task of the one-shot-capture-shell spec (`.superpowers/sdd/2026-08-10-one-shot-capture-shell/`):
add `CaptureCondition`, a pure value type that is the *only* place pipeline facts
(`StitchSession.segmentBreaks`, `.seams`, chrome-review state, `.orderAssumed`) become
user-facing English. The task brief specified it as a plain struct/enum stack deliberately
kept off the main actor — "keeping this a plain struct keeps the verdict below a pure
function — off the main actor, off disk, and table-testable across every combination" — and
gave the complete implementation verbatim, expected to compile and pass as-is.

It didn't. Copying the brief's code into `Seamly/Seamly/DesignSystem/CaptureCondition.swift`
and running the test target produced compiler errors the brief never anticipated:

```
Call to main actor-isolated initializer 'init(ready:)' in a synchronous nonisolated context
Main actor-isolated property 'kind' can not be referenced from a nonisolated context
```

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Wrap every test call in `await MainActor.run { ... }` | No source change to the type | Defeats the stated purpose of the type (pure, off-main-actor, synchronously testable); brief's tests are plain sync `@Test` funcs, would need rewriting; masks the real issue for every future type added to `DesignSystem/` |
| Move the type into `StitchKit` | `StitchKit` has no default-isolation setting | Explicitly forbidden — brief and CLAUDE.md are clear this is app-layer, translates *StitchKit* facts into UI language, and must not live in the pure core; also contradicts "No changes to StitchKit" constraint |
| Mark declarations `nonisolated` (chosen) | Matches the type's stated intent exactly; zero behavior change; the fix is exactly the annotation the doc comments already claim is true | Must be applied per-declaration — marking a type `nonisolated` does not cover a separately-declared `extension` of it, discovered by trial |

## Decision

Mark `CaptureFacts`, `Severity`, `Imperfection`, `CaptureCondition`, and their two extensions
(`extension CaptureFacts` for `init(_ session:)`, and `private extension Imperfection` for the
failable `init?(kind:facts:)`) all `nonisolated`.

## Rationale

The `Seamly` app target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
(confirmed via `xcodebuild -showBuildSettings`, surfacing as `-default-isolation=MainActor`
on the frontend invocation) — Swift 6.2's default-actor-isolation feature. Under this setting
every declaration in the target defaults to `@MainActor` unless explicitly opted out. This is
invisible from source inspection alone; it only shows up as a build setting, so a task brief
written by pasting known-good code (presumably drafted/tested outside this exact target
configuration, or before the setting was added) can't see it.

`nonisolated` is the correct fix, not a workaround: the brief's own rationale for this type
*requires* it be usable synchronously off the main actor (pure fact → English mapping, tested
with zero async ceremony). The annotation makes the code match its own documented intent
rather than silently drifting from it.

## What Changed

- `Seamly/Seamly/DesignSystem/CaptureCondition.swift` (new) — brief's implementation verbatim,
  plus `nonisolated` on: `struct CaptureFacts`, `extension CaptureFacts` (the `StitchSession`
  init), `enum Severity`, `struct Imperfection`, `enum CaptureCondition`, and
  `private extension Imperfection` (the `init?(kind:facts:)` builder). Added a short doc
  comment on `CaptureFacts` explaining why the modifier is there.
- `Seamly/SeamlyTests/CaptureConditionTests.swift` (new) — brief's test file verbatim, no
  changes needed.

## What Was Discovered

- Marking a type declaration `nonisolated` does **not** implicitly cover a separately written
  `extension` of that type — the extension needs its own `nonisolated` modifier. Found by
  incremental build: marking `CaptureFacts`/`Severity`/`Imperfection`/`CaptureCondition`
  `nonisolated` fixed most errors, but `private extension Imperfection`'s `init?(kind:facts:)`
  stayed main-actor-isolated until it got the same modifier directly.
- The brief's implicit-memberwise-init-only type (`CaptureFacts`, before its extension was
  added) apparently didn't surface a main-actor isolation error even before any `nonisolated`
  was added — only the hand-written `CaptureCondition.init(ready:)` and `Imperfection`'s stored
  property access did. Synthesized memberwise initializers on structs appear cheaper to call
  from a nonisolated context than hand-written ones under this setting; not verified further
  since the `nonisolated` fix makes the distinction moot, but worth knowing if it recurs.
- Every subsequent task in this spec that adds a plain, non-UI type under
  `Seamly/Seamly/DesignSystem/` (or anywhere in the app target) that is meant to be usable off
  the main actor will need the same treatment. Worth calling out explicitly in later task
  briefs rather than rediscovering this per task.
