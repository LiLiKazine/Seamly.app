# Longshot

**Capture beyond the screen.** Longshot stitches multiple screenshots into a single, seamless long screenshot — perfect for saving full conversations, articles, timelines, and any content that scrolls.

iOS doesn't natively support scrolling screenshots outside of Safari's full-page PDF export. Longshot fills that gap for every app.

> **Status: early stage.** The project is currently a fresh SwiftUI app scaffold — the stitching engine and the features below are the roadmap, not yet shipped. Sections marked _(planned)_ describe the intended design.

## Features _(planned)_

- 📸 **Smart stitching** — Import 2+ screenshots and Longshot automatically detects overlapping regions and merges them into one continuous image
- ✂️ **Manual adjustment** — Fine-tune stitch boundaries with a drag handle when auto-detection needs a nudge
- 🧹 **Clean output** — Automatically crops status bars, notches, and home indicators from intermediate frames
- 🖼️ **Flexible export** — Save as PNG/JPEG to Photos, share directly, or copy to clipboard
- 🔒 **Fully offline** — All processing happens on-device. No accounts, no uploads, no tracking

### Planned

- [ ] Screen recording mode — record a scroll session, extract and stitch frames automatically (ReplayKit)
- [ ] Horizontal stitching for wide content
- [ ] Annotation tools (blur sensitive info, arrows, text)
- [ ] Share extension — stitch directly from the Photos share sheet
- [ ] iPad and macOS (Catalyst) support

## How It Works _(planned)_

1. Take overlapping screenshots while scrolling (each shot should share ~20% of content with the previous one)
2. Open Longshot and select the screenshots in order (or let auto-sort handle it)
3. Longshot uses the Vision framework to find matching feature points in adjacent images and computes the optimal seam
4. Review, adjust if needed, and export

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 6 (app target; test targets currently Swift 5) |
| UI | SwiftUI |
| Concurrency | Swift Concurrency (`async`/`await`, actors) — no GCD |
| Image matching | Vision (`VNTranslationalImageRegistrationRequest`) _(planned)_ |
| Image compositing | Core Image / Core Graphics _(planned)_ |
| Photo access | PhotosUI (`PHPickerViewController`) _(planned)_ |
| Testing | Swift Testing (`import Testing`) |
| Minimum target | iOS 26.5 |

## Project Structure

Current (Xcode scaffold):

```
Longshot/                     # repo root (README, CLAUDE.md)
└── Longshot/
    ├── Longshot.xcodeproj
    ├── Longshot/             # app sources — LongshotApp.swift, ContentView.swift, Assets
    ├── LongshotTests/        # unit tests (Swift Testing)
    └── LongshotUITests/      # UI tests
```

Intended, as features land:

```
Longshot/Longshot/Longshot/
├── App/                  # App entry point, root navigation
├── Features/
│   ├── Import/           # Photo picker, screenshot selection & ordering
│   ├── Stitch/           # Stitching engine, overlap detection, seam adjustment UI
│   └── Export/           # Rendering, format options, share sheet
├── Core/
│   ├── ImageRegistration/# Vision-based alignment
│   ├── Compositing/      # Seam blending, cropping heuristics
│   └── Extensions/
└── Resources/
```

## Getting Started

### Requirements

- Xcode 26+ (iOS 26.5 SDK)
- iOS 26.5 deployment target
- No third-party dependencies (100% first-party frameworks)

### Build

```bash
git clone https://github.com/<your-org>/longshot.git
cd longshot
open Longshot/Longshot.xcodeproj
```

Set your development team under *Signing & Capabilities*, select a simulator or device, and hit ⌘R. No API keys or configuration needed.

### Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). Run with ⌘U or:

```bash
xcodebuild test -project Longshot/Longshot.xcodeproj -scheme Longshot \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Once the stitching engine lands, bundle sample screenshot sets as test fixtures so the registration/compositing tests stay deterministic and offline.

## Privacy

Longshot processes all images on-device. It requests read access to your photo library only for the screenshots you explicitly select, and write access only when you export. Nothing ever leaves your phone.

## License

TBD

## Contributing

Early-stage project — issues and PRs welcome once the core stitching engine lands.
