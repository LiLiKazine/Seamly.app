# Longshot

**Capture beyond the screen.** Longshot turns a scroll into a single, seamless long
screenshot — of *any* app. Start a capture, scroll through the content you want, stop,
and Longshot stitches the frames into one continuous image.

iOS doesn't natively support scrolling screenshots outside of Safari's full-page PDF
export. Longshot fills that gap for every app.

> **Status: early stage.** The project is currently a fresh SwiftUI app scaffold — the
> capture pipeline and stitching engine below are the roadmap, not yet shipped. The
> approved design lives in
> [`docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md`](docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md).

## How It Works

Because iOS only lets an app see *another* app's screen through **ReplayKit system
broadcast**, capture works like a screen recording you drive yourself:

1. Open Longshot and tap **Capture**. iOS shows the broadcast picker and a 3-second
   countdown, then the red recording indicator appears.
2. Switch to the app you want to capture and **scroll** through the content.
3. Stop the broadcast (from the system red indicator / Control Center) and return to
   Longshot.
4. Longshot has already selected overlapping keyframes while you scrolled; it now
   stitches them into one long image. **Review, fine-tune any seam, and export.**

Capture is *process-after-stop*: the app is backgrounded while you scroll another app,
so the stitched result is assembled when you come back — not shown live.

## Features _(planned)_

- 📜 **Scroll to capture** — no manual screenshotting; scroll the target app and Longshot
  grabs the frames automatically via a screen broadcast
- 🧠 **Smart stitching** — detects the vertical scroll offset between frames and merges
  them into one continuous image, pixel-exact along each seam
- 🧹 **Automatic chrome handling** — the fixed status bar, nav bar, and tab bar are
  detected (as the rows that don't move) and kept only once, not repeated down the image
- ⚠️ **Confidence warnings** — seams where the match is uncertain (an ad loaded, a fast
  scroll, a mid-animation frame) are flagged in the preview so you can re-capture
- ✂️ **Manual seam adjustment** — drag a handle to nudge any stitch boundary when the
  automatic cut needs a correction
- 🖼️ **Flexible export** — save as PNG/JPEG to Photos, share via the system sheet, or
  copy to the clipboard
- 🔒 **Fully offline** — all processing happens on-device. No accounts, no uploads, no
  tracking. The broadcast captures your screen only during the session, and nothing
  ever leaves your phone

### Roadmap

- [ ] Import existing screenshots from Photos (the manual alternative to broadcast)
- [ ] Horizontal stitching for wide content
- [ ] Annotation tools (blur sensitive info, arrows, text)
- [ ] Share extension — stitch directly from the Photos share sheet
- [ ] Tiling assembly for extreme-height captures
- [ ] iPad and macOS (Catalyst) support

## Architecture

Three build products plus a shared container:

| Piece | Role |
|---|---|
| **`StitchKit`** (local Swift package) | Pure, testable core — vertical-offset matching, chrome detection, frame selection, compositing. Accelerate + Core Graphics only. Imported by both the app and the extension. |
| **`Longshot`** (app target, SwiftUI) | Start-capture UI, Library of captures, scrollable preview with confidence flags + manual seam adjustment, export. Does the heavy pixel compositing. |
| **`LongshotBroadcast`** (Broadcast Upload Extension) | `RPBroadcastSampleHandler` that receives live screen frames, runs only lightweight matching + frame selection, and streams keyframes + a manifest to disk. Does no compositing (stays under the ~50 MB extension memory limit). |
| **App Group container** | Shared handoff — the extension writes keyframes (HEIC) + manifest JSON; the app reads them after the broadcast stops. |

**Stitching approach.** Adjacent frames differ by a pure integer *vertical* shift, and
overlap pixels are *identical* — so Longshot does **not** use Vision's
`VNTranslationalImageRegistrationRequest` (its global registration is corrupted by the
fixed chrome and isn't pixel-exact). Instead it reduces each frame to a 1-D grayscale
profile and finds the offset by minimizing mean-absolute-difference with **Accelerate
(vDSP/vImage)** — pixel-exact, fast, and deterministically unit-testable. Seams are a
**hard cut**, never feathered: blending two identical copies of crisp text only blurs it.

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 6 (app + `StitchKit`; legacy test targets on Swift 5) |
| UI | SwiftUI |
| Concurrency | Swift Concurrency (`async`/`await`, actors) — no GCD |
| Screen capture | ReplayKit system broadcast (`RPSystemBroadcastPickerView` + Broadcast Upload Extension) |
| Offset matching | Accelerate — `vImage` (pixel extraction/grayscale), `vDSP` (MAD scoring) |
| Compositing | Core Graphics (`CGContext`, hard-cut seams) |
| Photo export | PhotosUI / Photos |
| Testing | Swift Testing (`import Testing`) |
| Minimum target | iOS 26.5 |

## Project Structure

Current (Xcode scaffold):

```
Longshot/                     # repo root (README, CLAUDE.md, docs/)
└── Longshot/
    ├── Longshot.xcodeproj
    ├── Longshot/             # app sources — LongshotApp.swift, ContentView.swift, Assets
    ├── LongshotTests/        # unit tests (Swift Testing)
    └── LongshotUITests/      # UI tests
```

Intended, as the design lands:

```
Longshot/
├── StitchKit/                # local Swift package (pure core, Swift Testing)
│   ├── Sources/StitchKit/    # VerticalProfile, OffsetMatcher, ChromeDetector,
│   │                         #   FrameSelector, Compositor, StitchSession
│   └── Tests/StitchKitTests/ # synthetic-fixture TDD
└── Longshot/
    ├── Longshot.xcodeproj
    ├── Longshot/             # app target
    │   ├── App/              # entry point, root navigation
    │   ├── Features/
    │   │   ├── Capture/      # broadcast start UI, onboarding, capture status
    │   │   ├── Library/      # list of past captures
    │   │   ├── Preview/      # scrollable long-image preview, confidence flags,
    │   │   │                 #   manual seam adjustment
    │   │   └── Export/       # Photos / share / clipboard
    │   └── Shared/           # App Group paths, session store
    └── LongshotBroadcast/    # Broadcast Upload Extension (RPBroadcastSampleHandler)
```

## Getting Started

### Requirements

- Xcode 26+ (iOS 26.5 SDK)
- iOS 26.5 deployment target
- No third-party dependencies (100% first-party frameworks)
- A device for real capture — the broadcast picker and system broadcast are best
  exercised on hardware

### Build

```bash
git clone https://github.com/<your-org>/longshot.git
cd longshot
open Longshot/Longshot.xcodeproj
```

Set your development team under *Signing & Capabilities* (both the app and the
`LongshotBroadcast` extension need signing, and both must share the same **App Group**),
select a device, and hit ⌘R. No API keys or configuration needed.

### Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). The bulk of coverage
lives in `StitchKit`, fed by synthetic fixtures — a tall reference image sliced into
overlapping tiles at known offsets, so matching and compositing are verified
deterministically and offline.

```bash
# StitchKit package tests
swift test --package-path StitchKit

# App/UI tests
xcodebuild test -project Longshot/Longshot.xcodeproj -scheme Longshot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Privacy

Longshot processes all images on-device. During a capture, the ReplayKit broadcast sees
your screen only for the duration of the session you start, and Longshot only ever keeps
the frames it stitches. It requests write access to your photo library only when you
export. Nothing ever leaves your phone.

## License

TBD

## Contributing

Early-stage project — issues and PRs welcome once the core stitching engine lands.
