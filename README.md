# Longshot

**Capture beyond the screen.** Longshot turns a scroll into a single, seamless long
screenshot — of *any* app. Start a capture, scroll through the content you want, stop,
and Longshot stitches everything you revealed into one continuous image.

iOS doesn't natively support scrolling screenshots outside of Safari's full-page PDF
export. Longshot fills that gap for every app.

> **Status: early stage.** The project is currently a fresh SwiftUI app scaffold — the
> capture pipeline and stitching engine below are the roadmap, not yet shipped. The
> approved design lives in
> [`docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md`](docs/superpowers/specs/2026-07-04-broadcast-scroll-stitching-design.md).

## How It Works

Because iOS only lets an app see *another* app's screen through **ReplayKit system
broadcast**, capture works like a screen recording you drive yourself:

1. Open Longshot and tap **Capture**. Choose *Longshot* in the system sheet; after a
   short countdown the red recording indicator appears.
2. Switch to the app you want and **scroll steadily**. Longshot tracks your position and
   captures the union of everything you reveal — scrolling **back up is always safe**, it
   never duplicates. If you scroll too fast, you'll feel a **buzz** — just ease up.
3. Stop the broadcast (from the red indicator / Control Center) and return to Longshot.
4. Your capture is waiting in the **Library**, already stitched. Review it, fine-tune any
   flagged seam, and export.

Capture is *process-after-stop*: Longshot is backgrounded while you scroll another app, so
the stitched result is assembled when you come back — not shown live. (A broadcast
extension can't draw on screen, so mid-capture guidance is a sound/haptic cue, never a
banner that would land in your capture.)

## Features _(planned)_

- 📜 **Scroll to capture** — no manual screenshotting; scroll the target app and Longshot
  grabs the frames automatically via a screen broadcast
- 🧭 **Position-aware stitching** — tracks your absolute scroll position and captures the
  union of everything you reveal, so scrolling up, down, or re-reading is all safe
- 🧠 **Pixel-exact seams** — detects the vertical scroll offset between frames and merges
  them with a hard cut on identical pixels (no blurry blending of crisp text)
- 🧹 **Automatic chrome handling** — the fixed status bar, nav bar, and tab bar are
  detected (as the rows that don't move) and kept only once, not repeated down the image
- 📳 **Too-fast warning + recovery** — a haptic/sound cue when you outrun the frame rate;
  if content is genuinely missed, the gap is labeled and you can recapture just that stretch
- ⚠️ **Confidence warnings** — seams where the match is uncertain (an ad loaded, a fast
  scroll, a collapsing header) are flagged so you know where to look
- ✂️ **Manual fine-tuning** — correct a flagged seam's alignment, trim the ends, or adjust
  the auto chrome-crop — all non-destructive
- 🖼️ **Flexible export** — PNG/JPEG to Photos, or **PDF** (Safari-style, paginated for very
  long pages) to Files; plus system share and copy to clipboard
- 🗂️ **Library** — every capture is kept, so nothing is lost even if a broadcast is
  interrupted (partial captures are stitched and badged)
- 🔒 **Fully offline** — all processing happens on-device. The broadcast sees your screen
  only during the session you start, and nothing ever leaves your phone

### Roadmap

- [ ] Import existing screenshots from Photos (the manual alternative to broadcast)
- [ ] Automatic in-session gap reconstruction (v1 labels the gap + offers recapture)
- [ ] Horizontal / 2-D stitching for wide content
- [ ] Annotation tools (blur sensitive info, arrows, text)
- [ ] Share extension — stitch directly from the Photos share sheet
- [ ] Tiling assembly for unbounded-height raster export
- [ ] iPad and macOS (Catalyst) support

## Architecture

Three build products plus a shared container:

| Piece | Role |
|---|---|
| **`StitchKit`** (local Swift package) | Pure, testable core — vertical-offset matching, absolute-position tracking + relocalization, per-seam chrome detection, frame selection, and compositing. Accelerate + Core Graphics only. Imported by both the app and the extension. |
| **`Longshot`** (app target, SwiftUI) | Capture-start + onboarding, the Library, the scrollable preview (downscaled proxy) with confidence flags + manual editing, pixel-exact seam refinement, and export. Does the heavy compositing. |
| **`LongshotBroadcast`** (Broadcast Upload Extension) | `RPBroadcastSampleHandler` that receives live frames, runs only lightweight tracking + frame selection + the safety cue, and streams keyframes + an incremental manifest to disk. Holds one frame at a time; does no compositing (stays under the ~50 MB extension memory limit). |
| **App Group container** | Shared handoff — the extension writes lossless keyframes + a manifest; the app reads them after the broadcast stops. |

**Capture model.** Longshot tracks the user's absolute scroll position and appends only
content past the deepest point seen, so back-and-forth scrolling is free and never
duplicates. A fling that outruns the frame rate is detected, cued, and (if content is
truly lost) turned into a labeled segment break rather than a garbled image.

**Stitching approach.** Adjacent frames differ by a pure integer *vertical* shift, and
overlap pixels are *identical* — so Longshot does **not** use Vision's
`VNTranslationalImageRegistrationRequest` (its global registration is corrupted by the
fixed chrome and isn't pixel-exact). Instead it reduces each frame to a 1-D grayscale
profile and finds the offset by minimizing mean-absolute-difference with **Accelerate
(vDSP/vImage)** — pixel-exact, fast, and deterministically unit-testable. The extension
owns global structure (keyframes, offsets, chrome bands, segment breaks); the app snaps
each seam to pixel-exactness with a small full-res local search. Seams are a **hard cut**,
never feathered.

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 6 (app + `StitchKit`; legacy test targets on Swift 5) |
| UI | SwiftUI |
| Concurrency | Swift Concurrency (`async`/`await`, actors) — no GCD |
| Screen capture | ReplayKit system broadcast (`RPSystemBroadcastPickerView` + Broadcast Upload Extension) |
| Offset matching | Accelerate — `vImage` (pixel extraction/grayscale), `vDSP` (MAD scoring) |
| Compositing | Core Graphics (`CGContext`, hard-cut seams; PDF context for PDF export) |
| Export | Photos (PNG/JPEG), PDFKit/Core Graphics (PDF), share sheet, clipboard |
| Color | Source-preserving (Display P3-aware) end-to-end |
| Testing | Swift Testing (`import Testing`) |
| Minimum target | iOS 26.0 |

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
│   ├── Sources/StitchKit/    # VerticalProfile, OffsetMatcher, PositionTracker,
│   │                         #   ChromeDetector, FrameSelector, Compositor, StitchSession
│   └── Tests/StitchKitTests/ # synthetic-fixture TDD
└── Longshot/
    ├── Longshot.xcodeproj
    ├── Longshot/             # app target
    │   ├── App/              # entry point, root navigation
    │   ├── Features/
    │   │   ├── Capture/      # broadcast start UI, onboarding, capture status
    │   │   ├── Library/      # list of past captures (home surface)
    │   │   ├── Preview/      # scrollable proxy preview, confidence flags, manual editing
    │   │   └── Export/       # Photos / PDF / share / clipboard
    │   └── Shared/           # App Group paths, session store
    └── LongshotBroadcast/    # Broadcast Upload Extension (RPBroadcastSampleHandler)
```

## Getting Started

### Requirements

- Xcode 26+ (iOS 26.0 SDK)
- iOS 26.0 deployment target
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
overlapping tiles at known offsets, so matching, position tracking, chrome detection, and
compositing are verified deterministically and offline.

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
