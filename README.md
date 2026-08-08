# Seamly

**Capture beyond the screen.** Seamly turns a scroll into a single, seamless long
screenshot — of *any* app. Start a capture, scroll through the content you want, stop,
and Seamly stitches everything you revealed into one continuous image.

iOS doesn't natively support scrolling screenshots outside of Safari's full-page PDF
export. Seamly fills that gap for every app.

> **Status: the pipeline is built and works end to end** — live broadcast capture, video
> import, photo import, stitching, preview, editing, and export all ship. One known gap is
> tracked as a `withKnownIssue` test rather than hidden: the sparse broken-capture fixture still
> needs to be replaced by a dense live-frame regression oracle
> ([log](docs/logs/2026-07-05-03-real-frame-orientation-and-signal-fix.md)).
> Design specs live in [`docs/superpowers/specs/`](docs/superpowers/specs/); every
> significant decision is logged in [`DECISIONS.md`](DECISIONS.md) and [`docs/logs/`](docs/logs/).

## How It Works

There are three ways to get a long screenshot, all converging on the same stitching core.

### Record (live broadcast)

Because iOS only lets an app see *another* app's screen through **ReplayKit system
broadcast**, capture works like a screen recording you drive yourself:

1. Open Seamly and tap **Capture → Record**. Choose *Seamly* in the system sheet; after a
   short countdown the red recording indicator appears.
2. Switch to the app you want and **scroll steadily**. Seamly banks a frame each time you've
   scrolled far enough to need one. If you scroll too fast, you'll feel a **buzz** — just ease up.
3. Stop the broadcast (from the red indicator / Control Center) and return to Seamly.
4. Your capture is waiting in the **Library**, already stitched. Review it, fine-tune any
   flagged seam, and export.

Capture is *process-after-stop*: Seamly is backgrounded while you scroll another app, so
the stitched result is assembled when you come back — not shown live. (A broadcast
extension can't draw on screen, so mid-capture guidance is a sound/haptic cue, never a
banner that would land in your capture.)

### From Video

Already have a screen recording? **Capture → From Video** decodes it through the *same*
frame-picking code the live path uses (sampled at 30 fps) and stitches in capture order.

### From Photos

**Capture → From Photos** stitches a set of overlapping screenshots you took by hand.
Scroll order is recovered from the pixels; if the frames can't be confidently chained,
Seamly falls back to your pick order and badges the capture *Order assumed*.

## Features

- 📜 **Scroll to capture** — no manual screenshotting; scroll the target app and Seamly
  grabs the frames automatically via a screen broadcast
- 🎞️ **Three ways in** — live broadcast, an existing screen recording, or a set of
  hand-taken screenshots
- 🧭 **Order recovery** — scroll order is derived from pairwise pixel overlap, so shuffled
  or unordered input still assembles correctly
- 🧠 **Pixel-exact seams** — detects the vertical scroll offset between frames and merges
  them with a hard cut on identical pixels (no blurry blending of crisp text)
- 🧹 **Automatic chrome handling** — the fixed status bar, nav bar, and tab bar are
  detected (as the rows that don't move) and kept only once, not repeated down the image
- 📳 **Too-fast warning** — a haptic cue when overlap with the last banked frame drops
  toward the loss threshold
- ⚠️ **Confidence warnings** — seams where the match is uncertain, sections whose chrome
  band didn't lock, and gaps from fast scrolling are all flagged so you know where to look
- ✂️ **Manual fine-tuning** — correct a flagged seam's alignment, trim the ends, or adjust
  the auto chrome-crop — all non-destructive, re-composited from the stored manifest
- 🖼️ **Flexible export** — PNG/JPEG to Photos, or **PDF** (paginated for very long pages)
  to Files; plus system share and copy to clipboard
- 🗂️ **Library** — every capture is kept, so nothing is lost even if a broadcast is
  interrupted (partial captures are recovered and badged)
- 🩺 **Diagnostics** — the broadcast extension can't show UI, so it logs to a shared file
  the app can read back and share
- 🔒 **Fully offline** — all processing happens on-device. The broadcast sees your screen
  only during the session you start, and nothing ever leaves your phone

### Roadmap

- [x] Import existing screenshots from Photos (the manual alternative to broadcast)
- [x] Import an existing screen recording
- [ ] Robust scroll-direction scoring on image-heavy content
- [ ] Automatic in-session gap reconstruction (today: the gap is labeled as a segment break)
- [ ] Horizontal / 2-D stitching for wide content
- [ ] Annotation tools (blur sensitive info, arrows, text)
- [ ] Share extension — stitch directly from the Photos share sheet
- [ ] Tiling assembly for unbounded-height raster export
- [ ] iPad and macOS (Catalyst) support

## Architecture

Three build products plus a diagnostic CLI and a shared container:

| Piece | Role |
|---|---|
| **`StitchKit`** (local Swift package) | Pure, testable core — vertical profiling, offset matching, chrome-band detection, frame picking, order recovery, and compositing. Core Graphics + Accelerate only; no UIKit, no ReplayKit. Imported by both the app and the extension. |
| **`Seamly`** (app target, SwiftUI) | Capture entry points + onboarding, the Library, the scrollable preview (downscaled proxy) with confidence flags and manual editing, and export. **Derives all stitch geometry** and does the heavy compositing. |
| **`SeamlyBroadcast`** (Broadcast Upload Extension) | `RPBroadcastSampleHandler` that receives live frames and does only the minimum real-time work: profile each frame, bank a keyframe when the view has scrolled far enough, fire the safety cue. Holds one frame at a time and computes **no** geometry (stays under the ~50 MB extension memory limit). |
| **`stitch-cli`** (package executable) | Runs the real pipeline over an arbitrary clip or screenshot directory and writes the result where you can look at it. Exists because the failure modes here are *visual* — see [Testing](#testing). |
| App Group container | Shared handoff — the extension writes raw keyframes + a manifest; the app reads them after the broadcast stops, then moves them into app storage. |

### Component harness

`stitch-harness` is the machine-readable component boundary for exercising the extracted
production capture and stitching code. Build or run it from the package directory:

```sh
cd Seamly/StitchKit
swift build --product stitch-harness
swift run stitch-harness profile Tests/StitchKitTests/Fixtures/Example/20260718-225057.png
```

| Command | Example |
|---|---|
| `profile` | `stitch-harness profile <image>` |
| `match` | `stitch-harness match <a> <b> [--mask-chrome]` |
| `capture` | `stitch-harness capture frames <dir> [--prefix P] [--out DIR]`<br>`stitch-harness capture images <dir> [--prefix P] [--out DIR]` (compatibility alias for `frames`)<br>`stitch-harness capture video <file> [--fps N] [--out DIR]` |
| `plan` | `stitch-harness plan <dir> [--prefix P] [--order recover\|recover-or-input\|input] [--out DIR]` |
| `session` | `stitch-harness session create <dir> --out <container> [--prefix P] [--order recover\|recover-or-input\|input]`<br>`stitch-harness session inspect <session-folder>` |
| `compose` | `stitch-harness compose <session-folder> --out <image.png>` |
| `pipeline` | `stitch-harness pipeline photos <dir> --out <dir> [--prefix P] [--order recover\|recover-or-input\|input]`<br>`stitch-harness pipeline committed <dir> --out <dir> [--prefix P] [--order recover\|recover-or-input\|input]`<br>`stitch-harness pipeline frames <dir> --out <dir> [--prefix P] [--order recover\|recover-or-input\|input]`<br>`stitch-harness pipeline video <file> --out <dir> [--fps N] [--order recover\|recover-or-input\|input]`<br>`stitch-harness pipeline images <dir> --out <dir> [--prefix P] [--order recover\|recover-or-input\|input]` (legacy spelling for `photos`) |

Pipeline source names select a production-shaped ingestion path, not merely a file format:

| Source | Ingestion and default planning |
|---|---|
| `photos` (`pipeline images` legacy spelling) | Treat every discovered file as an already selected Photos item. All images reach `BatchStitcher`; none are re-selected. Defaults to `recover-or-input`, matching Photos import. |
| `committed` | Treat every discovered file as a keyframe already committed by the broadcast driver. All keyframes go directly to planning without another selection pass. Defaults to `recover-or-input`, matching broadcast import. |
| `frames` | Treat the directory as dense, chronological raw frames and pass them through `ScrollCaptureDriver`, which emits committed keyframes. Defaults to `input`. |
| `video` | Decode the video chronologically and pass decoded frames through `ScrollCaptureDriver`. Defaults to `input`. |

Directory inputs are discovered after prefix filtering and ingested in lexical filename order. For
`recover-or-input`, a fallback to input order therefore means that lexical order; a directory does
not retain the user's original Photos picker order. The `pipeline images` spelling is retained for
old invocations, but its behavior changed from the original harness's driver path to the
production-shaped `photos` path. Use `frames` when the input really is a dense raw-frame stream.

For ordering, `recover` requires pixel-overlap recovery, `input` trusts the supplied chronology,
and `recover-or-input` tries recovery first but falls back to input order when recovery cannot form
one continuous chain. `orderAssumed` is `true` only when that fallback was used; it remains `false`
for successfully recovered order and for an explicitly trusted `input` order. The value is persisted
in the session manifest and reported by planning, pipeline, and session-inspection results.

`match.geometricOverlapFraction` reports the fraction of profile rows that geometrically overlap at
the chosen offset; it deliberately does not use the chrome mask or the matcher's countable-row
floor. `overlapFraction` is the legacy JSON-field alias for the same value.

`match` is a symmetric, bounded `OffsetMatcher` component probe: it searches both offset signs and
reports the best candidate. Production planning and pipeline commands additionally perform
directional layout selection and apply the production edge gates. Use `plan` or `pipeline` when the
question is whether production would accept, orient, and connect the frames.

The built executable emits exactly one pretty-printed JSON envelope: successes go to stdout and
failures to stderr with a non-zero exit. The envelope contains `schemaVersion`, `command`, `ok`,
and either `result` or a stable `error.code` plus message. When an operation wraps an underlying
error, the error object also carries the optional `cause` field so diagnostics retain the original
failure; automation should branch on `error.code`, not parse `message` or `cause`. `swift run` may
additionally emit SwiftPM build diagnostics on stderr, so scripts that require clean JSON should
invoke the built `.build/.../stitch-harness` executable. Capture reports measured safety-cue counts
for frame directories; video reports that field as `null` because its decoder result does not
expose cue decisions.
Capture `--out` directories contain committed keyframes as PNGs. Plan output can contain a
manifest. Session output uses raw BGRA keyframes plus `manifest.json`; pipeline output places
that real `SessionStore` at `<out>/store/sessions/<session-id>/` and writes
`<out>/stitched.png`.

Output paths are caller-owned fixed locations. Commands intentionally replace their named
artifacts (`manifest.json`, `kf-NNNN.*`, and `stitched.png`) when rerun with the same `--out`
directory; use a fresh output directory when prior artifacts must be preserved.

This executable does not host ReplayKit or SwiftUI. Its capture and pipeline commands exercise
the production ingestion path selected by the source: raw frames and decoded video use the
extracted `ScrollCaptureDriver`, while Photos and committed-keyframe inputs go directly to planning
with every image. `Fixtures/RealDevice` contains keyframes already committed by the broadcast
driver, and Photos screenshot directories contain discrete user selections; sending either through
the driver again can silently discard valid frames and invent segment breaks. The existing
`stitch-cli` remains the human-oriented visual-triage tool for inspecting arbitrary captures.

### The load-bearing decision: capture banks frames, the app derives geometry

The extension's only job is to save overlapping keyframes and a list of them. It computes
no order, no seams, no segment breaks, no chrome bands. All of that is re-derived from the
keyframes at import time by `BatchStitcher`, which then *overwrites* the extension's
manifest.

This is a deliberate reversal of the original streaming design. A live tracker inside the
extension has one shot at every frame, is memory-starved, and cannot revisit a decision —
so when it lost lock it produced nothing at all. Re-deriving on the app side has the whole
frame set available, can be re-run after a fix, and is testable off-device.

### Pipeline

```
ReplayKit raw frames ── SampleHandler ── ScrollCaptureDriver ── committed keyframes ────────────┐
`frames` directory ── lexical load ───── ScrollCaptureDriver ── committed keyframes ────────────┤
video file ────────── VideoKeyframeSource ── ScrollCaptureDriver ── committed keyframes ────────┤
picked screenshots / `photos` ── all selected; recover-or-input ───────────────────────────────┤
keyframe directory / `committed` ── all already selected; recover-or-input ────────────────────┤
App Group keyframes ── LibraryModel.importFromGroup (move; recover killed broadcasts) ─────────┘
      │
      ▼
StitchAssembler.resolveGeometry → BatchStitcher.plan
      │   pairwise offsets → order recovery → segments → per-segment chrome band
      ▼
StitchSession (corrected manifest, persisted, user-editable)
      │ Compositor
      ▼
refineSeams (full-res snap) → hard-cut strips → CGImage / paginated PDF
      │
      ├─ makeProxy (≤4096 px tall — GPU texture ceiling) → Library, Preview
      └─ full-res on demand                              → Photos / PNG / JPEG / PDF / clipboard
```

### Stitching approach

Adjacent frames differ by a pure integer *vertical* shift, and overlap pixels are
*identical* — so Seamly does **not** use Vision's
`VNTranslationalImageRegistrationRequest` (its global registration is corrupted by the
fixed chrome and isn't pixel-exact).

Instead, `VerticalProfile` reduces each frame to a stack of **per-row luminance
signatures**: the frame is drawn into a small sRGB RGBA bitmap and each row becomes a short
vector of BT.601 luma samples across the width, with `vDSP` computing the row's mean and
variance. `OffsetMatcher` then scores candidate offsets by **variance-weighted mean
absolute difference** over those signatures, rewarding offsets that explain more of the
frame, and derives confidence from how far the best score sits below the best *distinct*
competitor (found by walking out of the winning score's valley).

Two details are load-bearing and were each paid for with a real bug:

- **A per-row *mean* alone is not enough.** On feed content it collapses to a near-tie
  between a real scroll and its mirror image, which is how the matcher shipped an inverted
  sign for three fix cycles. Comparing the whole horizontal signature disambiguates it.
- **Orientation has exactly one convention.** Profile row 0 is the image's top row, and a
  downward scroll yields a positive `dy`. There is no compensating flip anywhere.

`ContentBandDetector` finds fixed chrome as the rows that don't change between frames
(including translucent bars, recognized by shape rather than brightness), and that band is
both masked out of matching — so a static tab bar can't pin the alignment to `dy = 0` — and
cropped from every strip but the first. Seams are a **hard cut**, never feathered; the app
snaps each one to pixel-exactness with a small full-res local search before compositing.

## Tech Stack

| Layer | Choice |
|---|---|
| Language | Swift 6 (app, extension, and `StitchKit`; the Xcode test targets are still on Swift 5) |
| UI | SwiftUI + Observation (`@Observable`) |
| Concurrency | Swift Concurrency (`async`/`await`, actors, `Task.detached` for pixel work) — no GCD |
| Screen capture | ReplayKit system broadcast (`RPSystemBroadcastPickerView` + Broadcast Upload Extension) |
| Profiling / matching | Core Graphics render + `vDSP` row statistics; variance-weighted MAD over row signatures |
| Compositing | Core Graphics (`CGContext`, hard-cut seams; PDF context for PDF export) |
| Video decode | AVFoundation (`AVAssetReader`), sampled at 30 fps |
| Export | Photos (PNG/JPEG), Core Graphics PDF, share sheet, clipboard |
| Color | Source-preserving (the capture's color space is carried through the manifest) |
| Testing | Swift Testing (`import Testing`) |
| Minimum target | iOS 26.0 |

No third-party dependencies.

## Project Structure

```
Seamly/                            # repo root (README, CLAUDE.md, DECISIONS.md, docs/)
└── Seamly/
    ├── Seamly.xcodeproj           # app + extension + test targets (schemes are shared)
    ├── StitchKit/                 # local Swift package — the pure core
    │   ├── Sources/StitchKit/
    │   │   ├── VerticalProfile, FrameProfile        # signal
    │   │   ├── OffsetMatcher, Match                 # matching
    │   │   ├── ContentBand, ContentBandDetector     # chrome
    │   │   ├── KeyframeSelector, ScrollCaptureDriver # frame picking
    │   │   ├── BatchStitcher, Compositor            # order recovery + assembly
    │   │   ├── StitchSession, SessionStore, KeyframeIO, Diagnostics
    │   │   ├── AppGroup                              # ids shared by app + extension
    │   │   └── PixelBufferImage, VideoKeyframeSource # adapters
    │   ├── Sources/stitch-cli/                      # visual triage driver
    │   └── Tests/StitchKitTests/                    # + Fixtures/ (synthetic, wikipedia, RealDevice)
    ├── Seamly/                    # app target
    │   ├── SeamlyApp.swift, ContentView.swift
    │   ├── Core/                  # LibraryModel, MediaImporter, StitchAssembler, AppGroup+Observer
    │   └── Features/
    │       ├── Capture/           # broadcast picker, video + photo import buttons
    │       ├── Library/           # list of captures (home surface)
    │       ├── Preview/           # proxy preview, confidence flags, EditView
    │       ├── Export/            # Photos / PDF / share / clipboard
    │       ├── Onboarding/
    │       └── Diagnostics/       # reads back the extension's shared log
    ├── SeamlyBroadcast/           # Broadcast Upload Extension (RPBroadcastSampleHandler)
    ├── SeamlyTests/               # app-level tests (import, batch assembly)
    └── SeamlyUITests/
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
git clone https://github.com/<your-org>/seamly.git
cd seamly
open Seamly/Seamly.xcodeproj
```

Set your development team under *Signing & Capabilities* (both the app and the
`SeamlyBroadcast` extension need signing, and both must share the same **App Group**),
select a device, and hit ⌘R. No API keys or configuration needed.

## Testing

Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`). The bulk of coverage
lives in `StitchKit`, in three deliberately different tiers:

- **Synthetic** — a tall reference image sliced into overlapping tiles at known offsets, so
  matching, chrome detection, and compositing are verified deterministically.
- **Real screenshots** — a real page (`wikipedia.png`) windowed into a scroll.
- **Real device keyframes** — actual broadcast output from a physical device
  (`Fixtures/RealDevice`), kept as a regression oracle.

That third tier exists because the first two produced **three consecutive cycles of false
green**: synthetic fixtures were built upside-down and compensated by a flip in the
profiler, so the two inverted conventions cancelled and every real capture shattered while
the suite stayed green. When adding a test here, prefer real pixels, and treat a green
synthetic suite as necessary but not sufficient.

For the same reason `stitch-cli` exists: a stitch can pass every structural gate — right
order, no segment breaks, high seam confidence — and still be visibly wrong. Run it on a
real file and *look* at the output, then pin whatever it turns up as a fixture-backed test.

```bash
# StitchKit package tests (the real-frame tiers are slow by design)
swift test --package-path Seamly/StitchKit

# Visual triage on a real file
cd Seamly/StitchKit
swift run stitch-cli video ~/Pictures/scroll.mp4 --out /tmp/stitch
swift run stitch-cli images ./Tests/StitchKitTests/Fixtures/RealDevice --out /tmp/stitch

# App/UI tests
xcodebuild test -project Seamly/Seamly.xcodeproj -scheme Seamly \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The only expected known issue is the sparse broken-capture oracle in
`RealDeviceStitchTests.cleanDownwardScrollStitchesIntoOneSegment`, recorded with
`withKnownIssue` and linked to its decision log rather than deleted or faked green. Treat any
additional known issue as a regression that needs investigation.

## Privacy

Seamly processes all images on-device. During a capture, the ReplayKit broadcast sees
your screen only for the duration of the session you start, and Seamly only ever keeps
the frames it stitches. It requests write access to your photo library only when you
export. Nothing ever leaves your phone.

## License

TBD

## Contributing

Issues and PRs welcome. Please read [`DECISIONS.md`](DECISIONS.md) first — it records why
the architecture is shaped the way it is, including several approaches that were tried and
abandoned.
