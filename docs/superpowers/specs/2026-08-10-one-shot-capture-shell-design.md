# One-Shot Capture Shell — Design

**Date:** 2026-08-10
**Status:** Approved (brainstorming) — ready for implementation plan.

## Summary

Replace the app's test-harness UI with a product shell built around one flow: **record,
get your long screenshot, save it, done.**

The pipeline is finished and trustworthy — 180 tests across 28 suites pass, with one
documented known issue unrelated to the UI. What sits on top of it was built to verify
that pipeline, not to be used. It is list-first where the product is one-shot, and it
exposes the machinery (seams, chrome, segments, confidence) because that is what a harness
must show.

This spec covers the shell. It deliberately **does not** cover repairing an imperfect
stitch — that is Spec 2 (guided repair), and it is the more novel design problem. Until it
lands, an imperfect stitch is described in plain language and the user is offered a
re-record.

Everything in `Seamly/Core/` and all of `StitchKit` survives unchanged. The work is
confined to `Seamly/Features/`, plus a small new `Seamly/DesignSystem/`.

## Product decisions this rests on

Settled during brainstorming; recorded here because every design choice below follows from
them:

| Decision | Choice |
|---|---|
| Hero path | **Record** (live broadcast). Video and Photos import remain, as secondary entries. |
| End state | **One-shot** — capture → export → gone. No library to curate. |
| Imperfect stitches | **One guided repair, no pipeline vocabulary** (Spec 2). |
| Live scroll guidance | **Verified on device 2026-08-10 — the haptic fires and is felt.** Treated as a real channel. |
| Visual language | **Purely native** iOS 26. No custom identity. |

## Goals

- A record-first home; a finished capture navigates to itself rather than appearing as a
  list row to notice.
- One place that translates pipeline facts into user-facing language.
- Native throughout: system materials, SF Symbols, Dynamic Type, standard controls.
- Export errors surfaced honestly instead of collapsing to `nil`.
- No change to `StitchKit`, and no manifest schema change.

## Non-goals

- **Guided repair.** Spec 2.
- **A style token layer.** Argued against below; system values do the styling.
- Any *behavioural* change to capture, stitching, order recovery, or chrome measurement.
  The single exception is comment-only: replacing the stale unverified-haptic caveat at
  `SampleHandler.swift:217` with the verification result (below). No code path changes.
- Any change to `StitchSession` or the manifest format.
- Localization, iPad-specific layout, or App Store visual identity.

## Architecture & data flow

```
                    ┌──────────────── CaptureModel (@MainActor @Observable) ───────────────┐
                    │  captures: [Capture]  (recents, newest first — SessionStore.loadAll   │
                    │                        already sorts by createdAt descending)         │
                    │  pendingResult: UUID?  ──────────────────────┐                        │
                    └──────────────────────────────────────────────┼────────────────────────┘
                                                                   │ observed
   Home ──BroadcastPickerButton──→ [system picker] ──→ (user scrolls another app)            │
     │                                                                                       ▼
     ├──From Video──┐                          scenePhase .active  ─→ refresh() ─→ assemble ─→ push
     └──From Photos─┘                          Darwin notification ─┘                        │
                                                                                             ▼
                                   ┌───────────┬──────────────┬─────────────────┬────────────────┐
                                   │Processing │   Result     │ Nothing to      │    Failure     │
                                   │           │ (+ Save)     │ stitch          │                │
                                   └───────────┴──────────────┴─────────────────┴────────────────┘
```

The existing capture-pickup triggers are unchanged: the foregrounded scan remains the
source of truth, and the Darwin notification only removes the wait.

### Navigation

A single `NavigationStack` whose path is driven by the model rather than by the user
tapping a row. `pendingResult` is set when an import finishes assembling; the shell
observes it, pushes the result destination, and calls `consumePendingResult()`.

**The clear is mandatory, not hygiene.** If `pendingResult` survives the push, navigating
back re-pushes the same destination and the user cannot return home.

If two captures finish together, newest wins and the other remains in recents.

### Destinations

| State | Surface | Notes |
|---|---|---|
| Idle | Home | Record primary; Video/Photos secondary; recents strip; How it works |
| Importing / stitching | Processing | Indeterminate. `StitchAssembler.composite` reports no progress, and a fake bar would be a lie. Video *decode* does report progress and keeps its determinate bar. |
| Ready | Result | The proxy in `CaptureCanvas`; **Save to Photos** primary; Share / Copy / PDF secondary |
| No stitchable content | Nothing to stitch | Guidance, not an error. Offers Record again. |
| Failed | Failure | The real underlying message. Offers Record again. |

### Home

- `BroadcastPickerButton` as the large primary action — unchanged, and still the one
  legitimate UIKit exception (`RPSystemBroadcastPickerView` has no SwiftUI equivalent).
- `VideoImportButton` and `PhotoImportButton` as secondary actions. They keep earning
  their place; they are simply no longer co-equal with Record.
- **Recents strip**: a horizontally scrolling row of capture thumbnails, newest first,
  visually transient. It is a way back to something you just made and have not saved — not
  a library.

  It shows **all** stored captures rather than a capped window. Capping would leave older
  captures on disk with no way to reach or delete them, which is worse than a long strip.
  It stays short in practice because the default path deletes after a save, and long-press
  on a thumbnail deletes — so the user always has a way to clear it without the app
  deleting anything on their behalf.
- "How it works" → the re-viewable onboarding.
- Settings row → `DiagnosticsView`.

## The design system

**For a purely-native one-shot utility, the design system is a semantic layer, not a
style layer.**

No token file is proposed. System spacing, system materials, SF Symbols and Dynamic Type
already do the styling; a hand-maintained `Spacing`/`Radius` enum would be a second source
of truth that drifts from the system it mirrors and buys nothing a native app does not get
free. If a literal repeats three or more times across views, extract it *then*.

What must be shared is **meaning**, and one type carries all of it.

### `CaptureCondition`

Today the same underlying state is rendered twice, independently, with different wording,
different icons and inconsistent severity colors: `CaptureRow.statusLabel`
(`LibraryView.swift:124`) and `PreviewView.warnings` (`PreviewView.swift:71`). The new
shell needs the same meaning in three places (result, recents, nothing-to-stitch). It
should exist once.

```swift
/// The single user-facing verdict on a capture. This type owns the *only* translation
/// from pipeline facts into language a user reads — "seam", "chrome", "segment", and
/// "confidence" never appear on the far side of it.
enum CaptureCondition {
    case stitching
    case clean
    case imperfect(primary: Imperfection, all: [Imperfection])
    case nothingToStitch
    case failed(String)
}

/// One plain-language observation about a capture.
struct Imperfection {
    let kind: Kind              // declaration order is the ranking
    let headline: String
    let detail: String
    let severity: Severity      // guidance | warning
    let recommendsRecordingAgain: Bool
}
```

`recommendsRecordingAgain` was originally specified as `isRepairable`, a flag Spec 2 would
key off and Spec 1 would leave inert. Inverting it makes it earn its place immediately:
re-recording is the only fix when content is genuinely **missing** (the recording ended
early, or gaps from scrolling too fast), and is *useless* when everything was captured and
merely joined imperfectly — that is what guided repair exists for. So the result screen
offers "Record again" only where it would actually help, instead of on every imperfection.
Spec 2 can still read the same flag from the other direction.

Translations — each currently leaks pipeline vocabulary into the UI:

| Pipeline fact | What the user reads |
|---|---|
| `segmentBreaks > 0` | "You scrolled too fast in places — this is joined from 3 pieces." |
| `flaggedSeamCount > 0` | "One join might not line up exactly." |
| `unresolvedChromeCount > 0` | "Couldn't tell which parts were the app's bars, so they may repeat." |
| `isIncomplete` | "The recording ended early — this is what was saved." |
| `orderAssumed` | "Kept these in the order they were taken." |

**Ranked, with one shown.** `imperfect` carries a primary and the full ranked list. The
result screen shows only the primary unless the user asks for more. Presenting four badges
to someone who wanted a screenshot is precisely what makes the current UI read as a tool
rather than an app.

**It is a pure function over plain facts** — break count, flagged count, unresolved-chrome
count, incomplete flag, order-assumed flag — *not* over `Capture`. That keeps it off the
main actor and off disk, so it is table-testable across every combination. This is the one
type that can silently tell a user something false about their capture, and a wrong
fact-to-language mapping is invisible in code review.

### Components

**`CaptureCanvas`** — the scrollable, zoomable long-image viewer. Used by Result now and
inherited by guided repair in Spec 2. It takes a display proxy, never a full composite, so
that the ~16,384 px texture ceiling cannot be breached by a careless caller.

It also fixes a live bug. `PreviewView.swift:61` assigns `zoom = max(1, $0.magnification)`,
but `MagnifyGesture.magnification` is relative to *gesture start*. Zoom to 3×, lift, pinch
again, and the image snaps back to ~1× instead of continuing. Accumulating across gestures
is table stakes for a viewer whose entire subject is a very tall image.

**`ConditionNotice`** — renders a `CaptureCondition` inline and natively. One
implementation, one severity scale, used everywhere a condition is shown.

Location: `Seamly/DesignSystem/`, app target only. `StitchKit` stays pure — the pipeline
should not know how its facts get worded.

## `CaptureModel`

`LibraryModel` renamed. Despite its name, only `captures` and `delete` are library
concepts; the other ~300 lines are capture lifecycle (import from the App Group, resolve
geometry, assemble proxies, composite full-res, export PDF, persist edits) and survive
intact. `CaptureStore` is avoided deliberately — it would read as a sibling of
`StitchKit.SessionStore`, which it is not.

Changes:

- **Add** `pendingResult: UUID?` and `consumePendingResult()`.
- **Reinterpret** `captures` as recents. No new sorting code needed.
- **Make `fullComposite` and `exportPDF` throw** instead of returning optionals (below).
- **Retain `update(_:)` with no caller.** Deleting `EditView` leaves it unused in Spec 1;
  it is the persist-and-reassemble path guided repair needs, and removing it now only to
  re-add it in Spec 2 is churn. It must carry a comment saying so, or the next reader will
  correctly read it as dead code and delete it.

### Retention

Captures are not cheap: full keyframes stay on disk because non-destructive editing needs
them. One-shot implies a retention policy, and the options were weighed:

| Policy | Verdict |
|---|---|
| Keep until saved, then offer to delete | **Chosen.** One-shot as a default *path*, never as silent deletion. |
| Auto-prune after N days | Rejected — silently destroys user data, and a failed save leaves no copy. |
| Never auto-delete | Rejected — recents grows unbounded; rebuilds the library we just removed. |

**Kept deliberately cheap.** Knowing a capture was saved would, if persisted, require a
`StitchSession` schema change — a `StitchKit` change with a manifest version bump, for a UI
convenience. Instead the offer is in-session only: it appears on the result screen after a
successful save. If the app is killed first, the capture simply remains in recents. Spec 1
touches no schema.

## Error handling

`CaptureModel` already follows the project's rules — `importError`, `Phase.failed`,
`Diagnostics`. The new surfaces mostly need to *present* what it already captures. Two
substantive changes:

**"Nothing to stitch" is not an error.** Today it is an alert with that title, which reads
as failure. It means the user did not scroll the recorded app. It becomes a coaching
destination with a Record-again action, rendered at guidance severity.

**Export stops masking its errors.** `fullComposite` returns `CGImage?` and `exportPDF`
returns `URL?`; both log the real cause to `Diagnostics` and hand the UI a `nil` that
`ExportView.swift:47` turns into `"Nothing to export."` That is the masking-fallback
pattern CLAUDE.md names explicitly — the user is told something generic and wrong while the
actual cause goes only to a log they cannot read. Both become `throws`, and the result
screen shows the real failure.

`DiagnosticsView` survives, behind a Settings row. The extension cannot draw UI and its
container is not reliably pullable over USB, so that durable log is the only window into a
failed capture on a real device.

## Testing

- **`StitchKit`'s 180 tests are untouched.** This is the safety property that makes an
  in-place `Features/` replacement sensible: the UI can churn freely without endangering
  the core.
- **`SeamlyTests`** gains a table-driven `CaptureCondition` suite (Swift Testing) covering
  every combination of facts, including ranking order.
- **`SeamlyUITests`** covers the one-shot flow end to end through the Photos path — launch
  → import → result → save — the only entry a UI test can drive.

**What cannot be tested automatically, stated plainly:** the hero path. The broadcast flow
needs a physical device, an interaction with the system picker, and a human scrolling a
third-party app. It stays a manual pass.

## The safety cue — verified, and now a designed signal

`SampleHandler.fireSafetyCue()` calls `AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)`
when overlap drops below `safetyMargin`. The code carried an unresolved caveat:

> Whether either channel is audible from a broadcast extension is a device go/no-go
> (see the design's early verifications); if neither works we fall back to onboarding +
> detect-and-segment. — `SampleHandler.swift:217`

**Resolved 2026-08-10: verified by hand on a physical device — the haptic fires and is
felt mid-broadcast.** This could not have been settled in the simulator or by any
automated test; it needed a human running a real broadcast and scrolling fast enough to
trip the cue.

Consequences for this spec:

- The cue is a **real feedback channel**, and the only one that reaches a user who is
  inside another app. Onboarding step 2 already promises a buzz; that promise is honest
  and stays, upgraded from an aside into an explicitly taught signal ("one buzz means ease
  up") rather than a parenthetical.
- `SampleHandler.swift:217`'s caveat comment should be replaced with the verification
  result and its date, so the next reader does not re-open a settled question.

**Where the cue's behaviour actually lives.** The decision is pure and off-device:

```swift
let fireSafetyCue = result.overlapFraction < safetyMargin   // ScrollCaptureDriver.swift:67
```

`safetyMargin` is an injectable init parameter defaulting to `0.4`, and the extension does
nothing but throttle (one per ~45 frames) and play. So the cue's *timing* is a `StitchKit`
parameter exercised by the existing off-device `CaptureSimulationTests` tier — not
extension work.

**Deliberately not changed here.** There is no evidence that `0.4` is the wrong threshold,
and tuning it on a hunch would be unfounded. If real use shows the buzz arrives too late to
act on, that is a small, testable `StitchKit` change with its own decision log — not part
of this shell.

**Rejected: richer haptic patterns.** Distinct vibrations for distinct meanings would need
Core Haptics in the broadcast extension, which is under a hard ~50 MB footprint ceiling and
whose hot path `CLAUDE.md` explicitly protects. One blunt vibration carrying one meaning is
the right ceiling for this channel.

## What is deleted

`LibraryView` as home (and `CaptureRow`'s status rendering), `PreviewView`'s warnings
banner, the `showEmptyNudge` alert, and `EditView`'s stepper form. `EditView` is removed
rather than restyled: it is the surface Spec 2 replaces, and keeping a pixel-offset stepper
form alive in the meantime would contradict the "no pipeline vocabulary" decision.

**The resulting capability gap was raised and explicitly accepted (2026-08-10):** between
this shell shipping and Spec 2 landing there is *no way to fix a bad stitch* — the only
recourse is to record again. No interim repair affordance will be designed; building a
throwaway one would cost roughly what the real one costs and would seed exactly the
vocabulary Spec 2 exists to remove.

## What survives

All of `StitchKit`. All of `Seamly/Core/` — `LibraryModel` is renamed, gains
`pendingResult`/`consumePendingResult()`, and has two return types changed
(`fullComposite`, `exportPDF`); its logic is otherwise untouched.
`BroadcastPickerButton`, `PhotoImportButton`, `VideoImportButton`, `Exporter`,
`DiagnosticsView`, `OnboardingView` (copy revised to teach the now-verified safety cue).

## Open question deferred to Spec 2

Guided repair: a direct-manipulation surface where the user drags two halves of the image
until they line up, with live pixels under the finger and no pipeline vocabulary anywhere.
It inherits `CaptureCanvas` and `CaptureCondition` from this spec.
