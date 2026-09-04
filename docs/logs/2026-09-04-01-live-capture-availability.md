# 2026-09-04-01 — App Review 5.6: a Record button with nothing behind it

**Status:** Implemented (code); the Resolution Center reply and resubmission are still to do.

## The report

Submission `c7ecaf91` (iOS 1.0, build 41) was rejected on 2026-08-27 under **Guideline 5.6 —
Developer Code of Conduct**:

> We've identified a pattern of unusual behavior with the app that is commonly associated with
> fraudulent activity. Specifically, the app contains features that appear to have been
> intentionally hidden during the review process.

The message linked App Review's forum post *Support your app on compatible devices*, which says
reviewers run iPhone/iPad apps on Apple silicon Macs and Apple Vision Pro, and that an app must
either work there or opt out in App Store Connect.

The public App Store Connect API carries the rejection state but not the reviewer's words; they
had to be pulled over an authenticated web session (`asc web review show`). That took an `asc`
upgrade from 3.5.1 to 4.11.0 — the older login flow failed 2FA verification with a 401 — and a
cleared session cache.

## What was ruled out

- **The reviewed build.** Build 41 is Xcode Cloud run 41 from `d8bece2`, so it already carried
  the Record dead-tap fix (`2026-08-22-02`) and the extension icon (`2026-08-22-03`). On an
  iPhone the reviewed build's Record button worked.
- **Hidden test hooks.** `DebugSeed` and its launch arguments are inside `#if DEBUG`; nothing of
  the kind is in a release build.
- **Everything else the API can see.** Build `VALID`, no encryption issue, review notes and both
  screenshot sets present, no IAPs or subscriptions, `asc validate` reports zero blockers.

## Root cause, by elimination

Seamly was opted **in** to both Mac and Apple Vision Pro (`iosAppOnMac: true`,
`iosAppOnVisionPro: true`) and the code had no awareness of either. ReplayKit broadcast upload
extensions do not exist on macOS or visionOS, so on those devices the dock's hero — the one
control the listing is about — was a button that did nothing when tapped. A listing that promises
screen capture plus a primary control that silently does nothing is what Apple's boilerplate
calls "features hidden during review". The linked forum post is the tell; the exact device is not
recorded in the rejection.

## Options

| Approach | Pros | Cons |
|----------|------|------|
| Opt out of Mac and Vision Pro only | One store setting; what Apple's post prescribes | Leaves the same dead button on a restricted iPhone/iPad, on TestFlight-on-Mac and on dev installs; the reply to App Review has nothing in the app to point at |
| Code guard only, leave the store opt-in | The app is honest everywhere | Ships Seamly to two stores where its core feature can never work — a 4.2/2.1 rejection waiting to happen |
| Gate on `RPScreenRecorder.isAvailable` alone | One signal, documented | macOS's own ReplayKit supports in-app recording, so the flag can be true where the broadcast picker still has nothing behind it |
| Gate on platform macros (`#if os(visionOS)`, `targetEnvironment(macCatalyst)`) | Compile-time, zero runtime cost | An iPad app on Vision Pro or a Mac is the iOS binary; both macros are false there. Detects nothing |
| **Both: opt out, and a runtime capability check with a Mac override (chosen)** | Closes the reviewer's path; honest on every remaining device; the sentence is the reply's evidence | Two things to maintain; the Mac line is insurance the store setting mostly makes redundant |

## The fix

Two parts. The first closes the path the reviewer took; the second makes the app honest anywhere
the button cannot work.

1. **Opted out of Mac and Vision Pro** in App Store Connect
   (`asc web apps compatibility edit --ios-app-on-mac false --ios-app-on-vision-pro false`),
   verified by re-reading the setting. This is what Apple's own post prescribes for an app whose
   core feature needs iPhone/iPad hardware.

2. **The dock never shows a Record button that cannot work.** `LiveCaptureAvailability` is a pure
   `nonisolated` enum decided from three facts — `isiOSAppOnMac`, `RPScreenRecorder.isAvailable`,
   `isSimulator` — and `CaptureDock` swaps the picker slab for its `explanation` when it is not
   `.available`. `LiveCaptureMonitor` (owned by `AppShell`) reads the facts from ReplayKit and
   re-decides on `screenRecorderDidChangeAvailability(_:)`, because availability is live: AirPlay
   mirroring can take it away and give it back while the app is on screen.

   - **Mac wins over the recorder flag.** macOS has its own ReplayKit with in-app recording, so
     `isAvailable` can be true there while the broadcast picker still has nothing behind it. The
     store opt-out makes this a TestFlight/dev-install case only; the check is one line.
   - **The recorder's reasons are indistinguishable** — Screen Time or an MDM profile disallowing
     screen recording, AirPlay/TV-out, another app holding the recorder — and some are transient,
     so those words stay generic ("isn't available right now"). Apple documents the hardware,
     mirroring and other-recorder cases; the restrictions case is observed, not documented.
   - **Every explanation ends by naming the import alternatives**, because those are the two
     buttons sitting either side of it. That sentence is also what the Resolution Center reply
     can point at.
   - **The simulator is treated as available.** It has no recording service, so `isAvailable` is
     always false there; honouring that would swap the picker out from under every dock UI test
     and they would silently stop exercising the real control. A debug-only launch argument,
     `-SeamlyLiveCaptureUnavailable`, forces the unavailable branch so the UI test can reach it —
     the same narrow shape as `DebugSeed`'s arguments.
   - `#if os(visionOS)` would not have helped: an iPad app on Vision Pro is still the iOS binary
     and that macro is false. Hence a runtime, capability-based check.

The design system carries the same state: `CaptureDock` gains an `unavailable` prop in the JSX
source, its copy, the `.d.ts` and the `.prompt.md`, and both bundles were rebuilt with the
documented commands. Rebuilding also renamed esbuild's internal `src_exports` to `index_exports`
in both bundles (esbuild 0.28.1 vs. whatever cut the previous ones); the footer alias is intact
and the change is otherwise confined to `CaptureDock`.

## What changed

- `Seamly/Seamly/DesignSystem/LiveCaptureAvailability.swift` — new; the pure decision and its words.
- `Seamly/Seamly/Features/Capture/LiveCaptureMonitor.swift` — new; ReplayKit-backed `@Observable`
  owner of the facts, with the debug-only launch argument.
- `Seamly/Seamly/DesignSystem/Components/Capture/CaptureDock.swift` — `liveCapture` parameter; the
  slab becomes `recordSlab` and yields to the sentence when unavailable.
- `Seamly/Seamly/AppShell.swift`, `Features/Home/HomeScreen.swift`,
  `Features/Library/LibraryScreen.swift` — thread the value through.
- `Seamly/SeamlyTests/LiveCaptureAvailabilityTests.swift` — new; every branch of the rule.
- `Seamly/SeamlyUITests/SeamlyUITests.swift` — `testDockExplainsWhenLiveCaptureIsUnavailable`.
- `design-system/src/capture/CaptureDock.jsx`, `components/capture/CaptureDock.{jsx,d.ts,prompt.md}`,
  `_ds_bundle.js`, `ui_kits/seamly-ios/components.js` — the `unavailable` prop, both bundles rebuilt.
- `CLAUDE.md`, `README.md` — the launch argument; where Record does not work.

## What was discovered

- **The reviewer's words are not in the public API.** `reviewSubmissions` carries `UNRESOLVED_ISSUES`
  and nothing else; Resolution Center threads need `asc web review show` over an Apple web session.
- **`asc` 3.5.1's web login was dead against Apple's current flow** — the 2FA step came back
  `failed to get session info with status 401` twice with correct codes. 4.11.0 logged in first
  try after clearing the stale August session cache. The `--two-factor-code-command` runs under
  `ASC_TIMEOUT`, so a code prompt that waits on a human needs that raised (600 s worked).
- **`asc review history` labels the single submission item `inAppPurchaseVersion`.** There are no
  IAPs; the item id decodes to `<submission>|6|<resource>` and the web session confirms it is the
  `appStoreVersion`. A CLI decode artefact, not a second review item.
- **`RPScreenRecorder.isAvailable` is false on the simulator**, always — there is no recording
  service. Honouring it there would have swapped the picker out from under both existing dock UI
  tests, which would have gone on passing against the sentence.
- **`#if os(visionOS)` is false for an iPad app on Vision Pro**; compatibility mode runs the iOS
  binary. Same for Mac Catalyst macros on a Designed-for-iPad Mac install.
- **esbuild 0.28.1 names the module wrapper `index_exports`** where the committed bundles had
  `src_exports`. Six lines of rename noise per bundle, semantically nil, the footer alias intact.
- The App Store Connect record also holds a **macOS 1.0 version in `PREPARE_FOR_SUBMISSION`**,
  created with the app on 2026-07-24. Unrelated to this review; will surface as unfinished metadata
  later.

## Verified

- Red first, both layers: `LiveCaptureAvailabilityTests` failed to compile without the type;
  `testDockExplainsWhenLiveCaptureIsUnavailable` failed for want of the `record-unavailable`
  element. Both green after.
- Rendered and looked at: launched on the iPhone 17 simulator with the launch argument, the
  sentence sits between the two import buttons, centred, `--ink-muted` footnote, three lines.
- Full app suite (`xcodebuild test` on the iPhone 17 simulator, unit + UI): 119 test cases
  passed, 0 failed, including all six UI tests — the two existing dock tests still find the real
  picker, and the new one finds the sentence.

## Still to do (not code)

Reply in the Resolution Center thread (it accepts developer notes), add a line to the review
notes that Record needs an unrestricted iPhone or iPad, bump the build number, and resubmit the
same 1.0 version. Do not cancel the submission; do not appeal unless the same text comes back.
