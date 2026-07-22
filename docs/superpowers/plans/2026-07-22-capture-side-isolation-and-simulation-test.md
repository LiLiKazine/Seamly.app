# Capture-Side Isolation & Simulation Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the extension's keyframe-picking loop into a pure, testable `ScrollCaptureDriver`, prove it against real frames with two off-device test tiers (synthetic + video), and fix the `BatchStitcher` `edgeConfidence` gate so a real image-heavy overlap is no longer wrongly rejected.

**Architecture:** `ScrollCaptureDriver` (StitchKit, pure/`Sendable`) owns the per-frame `VerticalProfile` → `KeyframeSelector.evaluate` loop, the safety-cue decision, the `broadcastFinished` trailing commit, and `Keyframe` metadata — the capture parallel to `BatchStitcher`. `SampleHandler` becomes a dumb ReplayKit/disk/haptics adapter over it. Two test tiers drive the *same* driver: a deterministic synthetic simulator sliding a viewport down the stitched-Chrome oracle, and a video tier decoding a real screen recording through `AVAssetReader`. The video tier's "single continuous segment" assertion drives an adaptive replacement for `BatchStitcher`'s fixed absolute `edgeConfidence = 0.45` edge gate.

**Tech Stack:** Swift 6 (language mode 6), Swift Testing (`import Testing`, `@Test`, `#expect`), Core Graphics, AVFoundation (`AVAssetReader`), Accelerate/vDSP (existing). No third-party deps. Tests run on macOS via `swift test` from `Longshot/StitchKit` (no simulator).

## Global Constraints

- **Swift 6 language mode** on both `StitchKit` and `StitchKitTests` targets (already set in `Package.swift`). New public types must be `Sendable`.
- **Swift Testing only** — `import Testing`, `@Test`, `@Suite`, `#expect`/`#require`. Never XCTest.
- **Swift Concurrency, not GCD** — no `DispatchQueue`/`NSLock`/`os_unfair_lock`. (This work is synchronous/pure; no concurrency primitives are introduced.)
- **First-party frameworks only** — Vision, Core Image, Core Graphics, CoreVideo, AVFoundation, PhotosUI, SwiftUI.
- **Never swallow errors silently** (CLAUDE.md). Propagate with `throws`/`try`, or handle at the boundary (recover / surface / log). No bare `try?` that drops an error, no empty `catch {}`, no `?? default` masking a failure. When ignoring is genuinely correct, catch narrowly and comment why.
- **The `ScrollCaptureDriver` extraction is behaviour-preserving.** Do NOT tune `KeyframeSelector`. The ONLY behaviour change in scope is the `edgeConfidence` fix (Task 4).
- **Verify with:** `swift test` run from `Longshot/StitchKit`. App build check: `xcodebuild -project Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' build`.
- **Do not commit** the uncommitted deployment-target change (26.5→26.0 in `project.pbxproj` + CLAUDE.md/README.md). Leave it staged/working; it is out of scope.

## Reference facts (from spike + codebase, verified)

- Example fixtures: three `1320×2868` PNGs in `Fixtures/Example/`; `BatchStitcher().stitch(Example)` → one continuous image ≈ **5978 px** tall (the synthetic oracle; generated at test time, no new fixture).
- Real recording: `/Users/lili/Downloads/ScreenRecording_07-22-2026 23-16-50_1.MP4`, `1320×2868` HEVC, 11.17 s, 671 frames. Commits observed only through ~frame 320 (~5.3 s) → trim to ~6 s.
- Spike result (real production pipeline, reproduced): 671 frames decoded / 0 decode failures; **4 keyframes** committed at frames 1/143/237/320 with overlaps 1.00/0.49/0.47/0.49; 0 safety cues. `BatchStitcher` recovered order `[0,1,2,3]` but **broke after kf2** (stitch 8732 px vs 11472 stacked) — the kf2↔kf3 boundary is image-heavy (Witcher/Skyrim art, low horizontal texture) so its confidence scored below the 0.45 gate. This is the bug Task 4 fixes.
- `Fixtures/RealDevice` is registered in `Package.swift` as a whole-directory `.copy`, so a file added there is auto-bundled (accessible via `Bundle.module.url(forResource:withExtension:subdirectory:"RealDevice")`). **No `Package.swift` change is required for the video fixture.**
- `SampleHandler`'s current picking loop (the behaviour to preserve), from `Longshot/LongshotBroadcast/SampleHandler.swift`:
  - per frame: `profile = profiler.profile(image)`; `result = selector.evaluate(profile)`; if `result.overlapFraction < safetyMargin (0.4)` → fire cue (throttled ≥45 frames apart) else `framesSinceCue += 1`; if `result.commit` → write raw + append `Keyframe(filename:"kf-%04d.bgra", pixelWidth, pixelHeight, index)`, `keyframeIndex += 1`; on the FIRST keyframe (`index == 0`) also set `session.orientation` (`width>height ? .landscape : .portrait`) and `session.colorSpaceName` (`image.colorSpace?.name as String?`); always store `lastImage`/`lastProfile`.
  - `broadcastFinished`: if `lastImage`/`lastProfile` present and `selector.hasUncommittedMotion(lastProfile)` → commit the trailing frame.
- `CGImage` conforms to `Sendable` in the iOS 26 / macOS 15 SDK, so a struct holding `CGImage?` can be `Sendable` without `@unchecked`.

---

### Task 1: Extract `ScrollCaptureDriver` and refactor `SampleHandler` to a dumb adapter

**Files:**
- Create: `Longshot/StitchKit/Sources/StitchKit/ScrollCaptureDriver.swift`
- Modify: `Longshot/LongshotBroadcast/SampleHandler.swift` (replace the inline picking loop with driver delegation)
- Test: `Longshot/StitchKit/Tests/StitchKitTests/ScrollCaptureDriverTests.swift`

**Interfaces:**
- Consumes: `VerticalProfile.profile(_:)`, `KeyframeSelector.evaluate(_:)` → `KeyframeSelector.Result{commit, overlapFraction}`, `KeyframeSelector.hasUncommittedMotion(_:)`, `Keyframe(filename:pixelWidth:pixelHeight:index:)`, `FrameProfile`.
- Produces (relied on by Tasks 2 & 3, and by `SampleHandler`):
  - `struct ScrollCaptureDriver: Sendable`
  - `struct ScrollCaptureDriver.CapturedKeyframe: Sendable { let image: CGImage; let metadata: Keyframe }`
  - `struct ScrollCaptureDriver.Step: Sendable { let keyframe: CapturedKeyframe?; let fireSafetyCue: Bool }`
  - `init(profiler: VerticalProfile = .init(), selector: KeyframeSelector = .init(), safetyMargin: Double = 0.4)`
  - `mutating func ingest(_ image: CGImage) -> Step`
  - `mutating func finish() -> CapturedKeyframe?`

- [ ] **Step 1: Write the failing test**

Create `Longshot/StitchKit/Tests/StitchKitTests/ScrollCaptureDriverTests.swift`. The driver takes `CGImage`s, so the test builds a tall textured "document" and windows it (a pure vertical gradient has zero horizontal variance and would never match — the profile/matcher need per-row horizontal texture, so use a hashed-texture doc like `RealGeometryStitchTests`).

```swift
import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// `ScrollCaptureDriver` is the pure capture loop extracted from `SampleHandler`: profile each
/// frame, ask `KeyframeSelector` whether to bank it, decide the safety cue, and build `Keyframe`
/// metadata — with the `broadcastFinished` trailing commit as `finish()`. These tests assert the
/// plumbing (commit decisions, monotonic indices, first-frame metadata, trailing commit) on
/// generated textured frames; Tasks 2 & 3 prove it against real content end-to-end.
@Suite struct ScrollCaptureDriverTests {

    static let W = 1152
    static let docH = 6000
    static let window = 1600

    private func hashByte(_ r: Int, _ c: Int, _ seed: Int) -> UInt8 {
        let n = UInt64(bitPattern: Int64((r &* 73856093) ^ (c &* 19349663) ^ (seed &* 83492791)))
        return UInt8((n >> 7) & 0xFF)
    }

    /// A tall document with distinct per-row luma blocks plus left/right texture (high per-row
    /// horizontal variance) so the matcher locks onto vertical offsets unambiguously.
    private func doc() -> [UInt8] {
        var g = [UInt8](repeating: 0, count: Self.docH * Self.W)
        for r in 0..<Self.docH {
            let base = 20 + Int(hashByte(r / 6, 0, 7)) * 216 / 255
            for c in 0..<Self.W {
                let texture = (Int(hashByte(r, c, 3)) - 128) / 3
                g[r * Self.W + c] = UInt8(min(255, max(0, base + texture)))
            }
        }
        return g
    }

    private func frame(_ d: [UInt8], scroll s: Int) -> CGImage {
        let W = Self.W, h = Self.window
        var g = [UInt8](repeating: 0, count: h * W)
        for r in 0..<h {
            let docRow = min(Self.docH - 1, s + r)
            for c in 0..<W { g[r * W + c] = d[docRow * W + c] }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bpr = ctx.bytesPerRow
        ctx.data!.withMemoryRebound(to: UInt8.self, capacity: bpr * h) { p in
            for r in 0..<h { for c in 0..<W {
                let v = g[r * W + c]; let i = r * bpr + c * 4
                p[i] = v; p[i+1] = v; p[i+2] = v; p[i+3] = 255
            } }
        }
        return ctx.makeImage()!
    }

    @Test func firstFrameAlwaysCommitsAsIndexZero() {
        var driver = ScrollCaptureDriver()
        let step = driver.ingest(frame(doc(), scroll: 0))
        let kf = step.keyframe
        #expect(kf != nil)
        #expect(kf?.metadata.index == 0)
        #expect(kf?.metadata.filename == "kf-0000.bgra")
        #expect(kf?.metadata.pixelWidth == Self.W)
        #expect(kf?.metadata.pixelHeight == Self.window)
        #expect(step.fireSafetyCue == false)   // overlap 1.0 on the first frame
    }

    @Test func commitsMonotonicIndicesAsViewScrolls() {
        let d = doc()
        var driver = ScrollCaptureDriver()
        _ = driver.ingest(frame(d, scroll: 0))          // index 0
        // Scroll ~half a window (commitFraction 0.5 of 1600 rows ≈ 800 px) → next commit.
        let mid = driver.ingest(frame(d, scroll: 200))
        #expect(mid.keyframe == nil, "200px < half-window scroll should not commit")
        let next = driver.ingest(frame(d, scroll: 1000))
        #expect(next.keyframe?.metadata.index == 1, "past-threshold scroll commits index 1")
    }

    @Test func finishCommitsTrailingFrameWhenMotionUncommitted() {
        let d = doc()
        var driver = ScrollCaptureDriver()
        _ = driver.ingest(frame(d, scroll: 0))          // index 0 committed
        _ = driver.ingest(frame(d, scroll: 300))        // motion, but below commit threshold
        let tail = driver.finish()
        #expect(tail?.metadata.index == 1, "trailing frame with uncommitted motion is banked")
    }

    @Test func finishReturnsNilWhenNoUncommittedMotion() {
        let d = doc()
        var driver = ScrollCaptureDriver()
        _ = driver.ingest(frame(d, scroll: 0))          // index 0 committed, baseline = 0
        _ = driver.ingest(frame(d, scroll: 0))          // no scroll since baseline
        #expect(driver.finish() == nil, "a near-duplicate tail must not be banked")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd Longshot/StitchKit && swift test --filter ScrollCaptureDriverTests`
Expected: FAIL to compile — `cannot find 'ScrollCaptureDriver' in scope`.

- [ ] **Step 3: Write the driver implementation**

Create `Longshot/StitchKit/Sources/StitchKit/ScrollCaptureDriver.swift`:

```swift
import CoreGraphics
import Foundation

/// The pure, `Sendable` capture loop — the picking parallel to `BatchStitcher`'s assembly.
///
/// `SampleHandler` used to hold this loop inline, tangled with ReplayKit, the App Group, disk
/// writes, and haptics, so none of it could run or be tested off-device. Extracting it here lets
/// the synthetic and video test tiers drive the *real production picking code* against real
/// frames. This type profiles each frame, asks `KeyframeSelector` whether to bank it, decides the
/// safety cue (overlap below `safetyMargin`), builds the `Keyframe` metadata, and — at
/// `finish()` — banks the trailing frame if there is still uncommitted downward motion.
///
/// It does NOT touch ReplayKit, disk, or haptics: the adapter (`SampleHandler`) writes the
/// returned image's bytes, appends the metadata to the manifest, throttles + plays the cue, and
/// maps the first keyframe's image to the session's orientation/color space. This extraction is
/// behaviour-preserving — the commit decisions are exactly what `SampleHandler` produced before.
public struct ScrollCaptureDriver: Sendable {

    /// One committed keyframe: the image whose bytes the adapter writes, plus its manifest entry.
    public struct CapturedKeyframe: Sendable {
        public let image: CGImage
        public let metadata: Keyframe
    }

    /// The outcome of ingesting one frame: a keyframe to commit (or `nil`), and whether the
    /// adapter should fire the safety cue for this frame.
    public struct Step: Sendable {
        public let keyframe: CapturedKeyframe?
        public let fireSafetyCue: Bool
    }

    private let profiler: VerticalProfile
    private var selector: KeyframeSelector
    /// Overlap fraction with the last keyframe below which the safety cue should fire.
    private let safetyMargin: Double

    private var keyframeIndex = 0
    // Most-recent processed frame, retained only so content scrolled past the last committed
    // keyframe can be banked as the trailing keyframe in finish().
    private var lastImage: CGImage?
    private var lastProfile: FrameProfile?

    public init(
        profiler: VerticalProfile = VerticalProfile(),
        selector: KeyframeSelector = KeyframeSelector(),
        safetyMargin: Double = 0.4
    ) {
        self.profiler = profiler
        self.selector = selector
        self.safetyMargin = safetyMargin
    }

    /// Profile one frame and decide whether to bank it. The adapter passes the same image it just
    /// received; when `Step.keyframe` is non-nil the adapter writes *that image's* bytes.
    public mutating func ingest(_ image: CGImage) -> Step {
        let profile = profiler.profile(image)
        let result = selector.evaluate(profile)
        let fireSafetyCue = result.overlapFraction < safetyMargin

        var captured: CapturedKeyframe?
        if result.commit {
            captured = CapturedKeyframe(image: image, metadata: makeMetadata(for: image))
            keyframeIndex += 1
        }
        lastImage = image
        lastProfile = profile
        return Step(keyframe: captured, fireSafetyCue: fireSafetyCue)
    }

    /// The `broadcastFinished` trailing commit: bank the last frame only if there is real
    /// uncommitted downward motion since the last keyframe, so a near-duplicate tail (which the
    /// app would read as a non-overlapping gap) is not banked.
    public mutating func finish() -> CapturedKeyframe? {
        guard let image = lastImage, let profile = lastProfile,
              selector.hasUncommittedMotion(profile) else { return nil }
        let captured = CapturedKeyframe(image: image, metadata: makeMetadata(for: image))
        keyframeIndex += 1
        return captured
    }

    private func makeMetadata(for image: CGImage) -> Keyframe {
        Keyframe(
            filename: String(format: "kf-%04d.bgra", keyframeIndex),
            pixelWidth: image.width,
            pixelHeight: image.height,
            index: keyframeIndex
        )
    }
}
```

Note: `keyframeIndex` advances on every commit decision (monotonic), whereas the old
`SampleHandler.commitKeyframe` advanced it only after a *successful* disk write. On the rare
write-failure path this now leaves a gap in the `kf-NNNN` numbering rather than reusing a number.
This is inert: the manifest references keyframes by filename, not by scanning the folder, so a
numbering gap changes nothing downstream. The adapter (Step 5) logs and skips the manifest append
on write failure exactly as before.

- [ ] **Step 4: Run the driver test to verify it passes**

Run: `cd Longshot/StitchKit && swift test --filter ScrollCaptureDriverTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Refactor `SampleHandler` to a dumb adapter**

In `Longshot/LongshotBroadcast/SampleHandler.swift`:

Replace the `profiler`/`selector` properties (lines ~25–26) with a single driver:

```swift
    // Fallback decoder only — created lazily, so the common 32BGRA path (PixelBufferImage) never
    // pays the GPU CIContext's memory baseline that was pushing the extension past its ceiling.
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])
    /// The pure picking loop (profile → KeyframeSelector → keyframe metadata + safety-cue
    /// decision + trailing commit). This adapter only decodes frames, writes bytes, updates the
    /// manifest, and plays haptics; all capture *decisions* live in the driver.
    private var driver = ScrollCaptureDriver(safetyMargin: 0.4)
```

Delete the now-unused `lastImage`/`lastProfile` stored properties (the driver owns them). Keep
`keyframeIndex`, `framesSinceCue`, `store`, `folder`, `session`, and all diagnostics.

Replace the body of `processSampleBuffer` after the image is decoded (the block from `let profile =
profiler.profile(image)` through `lastProfile = profile`) with:

```swift
            frameCount += 1
            let trace = frameCount <= 5 || frameCount % 60 == 0
            if trace { dlog("frame \(frameCount): decoded \(image.width)x\(image.height) mem=\(memoryFootprintMB())MB") }

            let step = driver.ingest(image)
            if trace { dlog("frame \(frameCount): commit=\(step.keyframe != nil) cue=\(step.fireSafetyCue) kf=\(keyframeIndex) mem=\(memoryFootprintMB())MB") }

            if step.fireSafetyCue { fireSafetyCue() } else { framesSinceCue += 1 }
            if let captured = step.keyframe { commitKeyframe(captured) }
```

Replace `broadcastFinished`'s trailing-commit block (lines ~144–147) with:

```swift
        // Commit the trailing frame so content scrolled past the last keyframe isn't dropped —
        // the driver returns it only when there's real uncommitted motion (never a near-duplicate).
        if let captured = driver.finish() { commitKeyframe(captured) }
```

Rewrite `commitKeyframe` to take the driver's `CapturedKeyframe` (it no longer profiles or builds
metadata — the driver did that):

```swift
    /// Bank one driver-selected keyframe: write its raw bytes and append its manifest entry. No
    /// order/seams/segments/bands here — the app re-derives all geometry with `BatchStitcher`.
    private func commitKeyframe(_ captured: ScrollCaptureDriver.CapturedKeyframe) {
        guard var session, let folder, let store else { return }
        let image = captured.image
        let meta = captured.metadata

        if meta.index == 0 {
            session.orientation = image.width > image.height ? .landscape : .portrait
            session.colorSpaceName = image.colorSpace?.name as String?
        }

        let url = folder.appendingPathComponent(meta.filename)
        do {
            try KeyframeIO.writeRaw(image, to: url)
        } catch {
            // Skip this keyframe but keep the broadcast running. Log so a run that drops frames
            // (e.g. the container filling up) isn't a silent gap in the stitch.
            dlog("keyframe \(meta.index) write FAILED (\(meta.filename)): \(error.localizedDescription)")
            NSLog("Longshot: keyframe write failed (\(meta.filename)): \(error)")
            return
        }

        dlog("keyframe \(meta.index) written (\(image.width)x\(image.height))")
        session.keyframes.append(meta)
        keyframeIndex = meta.index + 1
        self.session = session
        // Best-effort incremental checkpoint: the next keyframe rewrites the manifest and
        // broadcastFinished() writes the authoritative final copy, so a dropped write here is
        // recovered by the following one. Intentionally not surfaced per-frame.
        try? store.writeManifest(session)
    }
```

`keyframeIndex` is now a display/trace mirror of the driver's index; keep it for the diagnostic
`kf=` trace. The `import StitchKit` line already exists.

- [ ] **Step 6: Verify the package builds and all existing StitchKit tests still pass**

Run: `cd Longshot/StitchKit && swift build && swift test`
Expected: build succeeds; all suites PASS (no regressions; new `ScrollCaptureDriverTests` green).

- [ ] **Step 7: Verify the app + extension target still builds**

Run: `xcodebuild -project Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Longshot/StitchKit/Sources/StitchKit/ScrollCaptureDriver.swift \
        Longshot/StitchKit/Tests/StitchKitTests/ScrollCaptureDriverTests.swift \
        Longshot/LongshotBroadcast/SampleHandler.swift
git commit -m "refactor(capture): extract ScrollCaptureDriver; SampleHandler becomes a dumb adapter

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Synthetic test tier — `CaptureSimulator` + `CaptureSimulationTests`

**Files:**
- Create: `Longshot/StitchKit/Tests/StitchKitTests/CaptureSimulator.swift` (test helper)
- Create: `Longshot/StitchKit/Tests/StitchKitTests/CaptureSimulationTests.swift`

**Interfaces:**
- Consumes: `ScrollCaptureDriver` (Task 1), `BatchStitcher().plan(_:)`/`.stitch(_:)`, `TestImages`, Example fixtures via `Bundle.module`.
- Produces: `CaptureSimulator` (a deterministic frame-stream generator; no `Date`/random) and its `run(driver:)` returning the committed `[CapturedKeyframe]`, used only within this test file.

- [ ] **Step 1: Write the `CaptureSimulator` helper**

Create `Longshot/StitchKit/Tests/StitchKitTests/CaptureSimulator.swift`:

```swift
import CoreGraphics
import Foundation
@testable import StitchKit

/// Deterministic stand-in for ReplayKit's frame delivery. Slides a viewport window down a tall
/// oracle image, composites a fixed top-chrome bar onto every emitted frame, adds seeded jitter
/// and one optional fling, and feeds each frame to the *real* `ScrollCaptureDriver`. Pure and
/// reproducible: a seeded LCG drives jitter and the fling index is fixed — no `Date`, no `random`.
///
/// This models the exact condition the empty-capture bug lived in: a static top bar that must NOT
/// pin the measured scroll to zero, plus normal finger jitter and one fast flick.
struct CaptureSimulator {
    let oracle: CGImage
    /// On-screen viewport height in source px (top chrome + content).
    let viewportHeight: Int
    /// Fixed top-chrome bar height in source px, composited identically onto every frame.
    let topChromeHeight: Int
    /// Nominal per-frame scroll of the content region (px).
    let scrollStep: Int
    /// Max ± jitter added to each step (px), from the seeded LCG.
    let jitter: Int
    /// Frame index at which a single fling occurs (a large extra jump), or nil for none.
    let flingAtFrame: Int?
    /// Extra px added on the fling frame.
    let flingExtra: Int
    var seed: UInt64 = 0x9E3779B97F4A7C15

    /// The fixed top-chrome strip taken once from the oracle's very top (real Chrome bar pixels).
    private func chromeBar() -> CGImage {
        oracle.cropping(to: CGRect(x: 0, y: 0, width: oracle.width, height: topChromeHeight))!
    }

    /// Compose one on-screen frame at content-scroll `s`: fixed top bar, then a window of the
    /// oracle content beneath it. Assembled in an UNFLIPPED context so buffer row 0 is the top
    /// row (matching real top-down frames and `VerticalProfile`, which does not flip).
    private func frame(chrome: CGImage, contentScroll s: Int) -> CGImage {
        let W = oracle.width
        let contentH = viewportHeight - topChromeHeight
        let content = oracle.cropping(to: CGRect(x: 0, y: topChromeHeight + s, width: W, height: contentH))!
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: W, height: viewportHeight, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .none
        // Unflipped: an image drawn at y = viewportHeight - h lands upright with its top at
        // buffer row 0's offset; top chrome sits at the top, content beneath it.
        ctx.draw(content, in: CGRect(x: 0, y: 0, width: W, height: contentH))
        ctx.draw(chrome, in: CGRect(x: 0, y: contentH, width: W, height: topChromeHeight))
        return ctx.makeImage()!
    }

    /// Seeded scroll script: nominal step + jitter each frame, plus one fling. Deterministic.
    private func scrollScript() -> [Int] {
        let contentH = viewportHeight - topChromeHeight
        let maxScroll = oracle.height - topChromeHeight - contentH   // last valid content window
        var positions: [Int] = []
        var s = 0
        var rng = seed
        var frameIndex = 0
        while s < maxScroll {
            positions.append(min(s, maxScroll))
            // LCG (Numerical Recipes constants); deterministic jitter in [-jitter, +jitter].
            rng = 6364136223846793005 &* rng &+ 1442695040888963407
            let j = jitter == 0 ? 0 : Int(rng >> 33) % (2 * jitter + 1) - jitter
            var advance = scrollStep + j
            if frameIndex == flingAtFrame { advance += flingExtra }
            s += max(1, advance)
            frameIndex += 1
        }
        if positions.last != maxScroll { positions.append(maxScroll) }
        return positions
    }

    /// Drive the real driver over the generated stream; return the committed keyframes (including
    /// the trailing finish() commit).
    func run(driver: inout ScrollCaptureDriver) -> [ScrollCaptureDriver.CapturedKeyframe] {
        let chrome = chromeBar()
        var committed: [ScrollCaptureDriver.CapturedKeyframe] = []
        for s in scrollScript() {
            if let kf = driver.ingest(frame(chrome: chrome, contentScroll: s)).keyframe {
                committed.append(kf)
            }
        }
        if let tail = driver.finish() { committed.append(tail) }
        return committed
    }
}
```

- [ ] **Step 2: Write the failing synthetic-tier tests**

Create `Longshot/StitchKit/Tests/StitchKitTests/CaptureSimulationTests.swift`:

```swift
import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import StitchKit

/// The synthetic capture tier. A tall real oracle — our own stitched Chrome page (`BatchStitcher`
/// over the Example fixtures, ≈ 5978 px) — is scrolled past a fixed top-chrome bar with seeded
/// jitter (+ one fling in the long scenario), and every frame drives the REAL `ScrollCaptureDriver`.
/// Ground truth is known, so the assertions are precise: capture is non-empty despite the static
/// bar, consecutive overlaps sit near `1 − commitFraction`, and the committed keyframes re-stitch
/// (closed loop through `BatchStitcher`) into a monotonic, single-segment page.
@Suite struct CaptureSimulationTests {

    /// The stitched Chrome oracle, generated once from the committed Example fixtures.
    private func chromeOracle() throws -> CGImage {
        let names = ["20260718-225057", "20260718-225102", "20260718-225107"]
        let images = try names.map { name -> CGImage in
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Example"))
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            return try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        }
        return try BatchStitcher().stitch(images)
    }

    /// Consecutive overlap fractions between committed keyframes, measured the same way capture
    /// does (downward masked/plain match, taking the more confident) — for asserting cadence.
    private func overlaps(_ kfs: [ScrollCaptureDriver.CapturedKeyframe]) -> [Double] {
        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        let detector = ContentBandDetector()
        let profiles = kfs.map { profiler.profile($0.image) }
        var out: [Double] = []
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let n = min(a.rowCount, b.rowCount)
            let bound = max(1, n - matcher.minimumOverlap)
            let mask = detector.staticMask(a, b)
            let masked = matcher.match(a, b, searchRange: 1...bound, rowMask: mask)
            let plain = matcher.match(a, b, searchRange: 1...bound)
            let m = masked.confidence >= plain.confidence ? masked : plain
            let dy = min(max(0, m.dy), n)
            out.append(Double(n - dy) / Double(n))
        }
        return out
    }

    // MARK: - Scenario 1: faithful ~2868px viewport, gentle jitter, short scroll

    @Test func faithfulViewportCapturesNonEmptyPageDespiteStaticChrome() throws {
        let oracle = try chromeOracle()
        let sim = CaptureSimulator(
            oracle: oracle,
            viewportHeight: 2868,        // faithful device viewport
            topChromeHeight: 210,        // fixed status/search bar
            scrollStep: 40,              // gentle reading scroll
            jitter: 8,
            flingAtFrame: nil,
            flingExtra: 0
        )
        var driver = ScrollCaptureDriver()
        let kfs = sim.run(driver: &driver)

        // Empty-capture regression guard: the static bar must not pin scroll to zero.
        #expect(kfs.count >= 3, "faithful viewport should bank ≥3 keyframes, got \(kfs.count)")
        #expect(kfs.first?.metadata.index == 0)
        #expect(kfs.map { $0.metadata.index } == Array(0..<kfs.count), "indices must be monotonic 0…n")

        // Cadence: consecutive overlaps ≈ 1 − commitFraction (0.5), no near-duplicate, no lost overlap.
        for (i, o) in overlaps(kfs).enumerated() {
            #expect(o > 0.30 && o < 0.75, "overlap[\(i)] = \(o) outside the sane cadence band")
        }

        // Closed loop: the captured keyframes re-stitch into a monotonic single segment.
        let plan = try BatchStitcher().plan(kfs.map { $0.image })
        #expect(plan.order == Array(0..<kfs.count), "captured order should already be scroll order")
        #expect(plan.session.segmentBreaks.isEmpty, "faithful capture should be one continuous segment")
        let out = try BatchStitcher().stitch(kfs.map { $0.image })
        #expect(out.width == oracle.width)
        // Stitched height recovers most of the scrolled span (chrome cropped to appear once).
        #expect(out.height >= oracle.height - 2868, "stitch collapsed: \(out.height) vs oracle \(oracle.height)")
        #expect(out.height <= oracle.height + 2868, "stitch stacked: \(out.height) vs oracle \(oracle.height)")
    }

    // MARK: - Scenario 2: long-scroll ~1400px viewport, jitter + one fling

    @Test func longScrollViewportCapturesCadenceAcrossJitterAndFling() throws {
        let oracle = try chromeOracle()
        let sim = CaptureSimulator(
            oracle: oracle,
            viewportHeight: 1400,        // long-scroll viewport → more keyframes
            topChromeHeight: 150,
            scrollStep: 35,
            jitter: 10,
            flingAtFrame: 12,            // one deterministic fast flick
            flingExtra: 260             // large jump that still overlaps (< a full content window)
        )
        var driver = ScrollCaptureDriver()
        let kfs = sim.run(driver: &driver)

        #expect(kfs.count >= 6, "long scroll should bank ≥6 keyframes, got \(kfs.count)")
        #expect(kfs.map { $0.metadata.index } == Array(0..<kfs.count))

        // Selector still commits across the fling; overlaps stay in the sane band (the fling is a
        // fast-but-overlapping scroll, not a lost-lock gap).
        for (i, o) in overlaps(kfs).enumerated() {
            #expect(o > 0.20 && o < 0.80, "overlap[\(i)] = \(o) outside the sane band")
        }

        // Explicit downstream outcome: an overlapping fling keeps the page one continuous segment.
        let plan = try BatchStitcher().plan(kfs.map { $0.image })
        #expect(plan.order == Array(0..<kfs.count))
        #expect(plan.session.segmentBreaks.isEmpty, "an overlapping fling must not shatter the capture")
    }
}
```

- [ ] **Step 3: Run to verify it fails, then diagnose expected numbers**

Run: `cd Longshot/StitchKit && swift test --filter CaptureSimulationTests`
Expected initially: may FAIL on the exact `kfs.count`/overlap-band/height thresholds (the oracle
height and cadence are empirical). This is the calibration point: read the actual committed count
and overlaps from the failure output.

- [ ] **Step 4: Pin the assertion thresholds to the observed ground truth**

If the counts/bands differ from the guesses above, adjust ONLY the numeric literals in the
assertions (keep the structure: non-empty ≫ 1, overlaps near `1 − commitFraction`, monotonic
order, single segment) to the observed values with sane tolerances. Do NOT change
`ScrollCaptureDriver`/`KeyframeSelector` — the driver behaviour is fixed; only the test's expected
numbers are being locked to the real cadence. If scenario 2's fling breaks the segment, that IS
the explicit outcome — assert `segmentBreaks.count == 1` and document why (the fling exceeded
overlap); prefer tuning `flingExtra` down so it stays overlapping per the spec's "still commits,
one segment" intent.

- [ ] **Step 5: Run to verify both scenarios pass**

Run: `cd Longshot/StitchKit && swift test --filter CaptureSimulationTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Longshot/StitchKit/Tests/StitchKitTests/CaptureSimulator.swift \
        Longshot/StitchKit/Tests/StitchKitTests/CaptureSimulationTests.swift
git commit -m "test(capture): synthetic tier — CaptureSimulator drives the real driver

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Video test tier — trim fixture + `VideoFrameSource` + video-tier test (pre-fix assertions)

**Files:**
- Create (binary, offline): `Longshot/StitchKit/Tests/StitchKitTests/Fixtures/RealDevice/scroll-recording.mp4` (trimmed ~6 s)
- Create: `Longshot/StitchKit/Tests/StitchKitTests/VideoFrameSource.swift` (test helper)
- Create: `Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift`
- (No `Package.swift` change — `Fixtures/RealDevice` is already a whole-directory `.copy`.)

**Interfaces:**
- Consumes: `AVAssetReader`/`AVAssetReaderTrackOutput`, `PixelBufferImage.makeCGImage(from:)`, `ScrollCaptureDriver` (Task 1), `BatchStitcher`.
- Produces: `VideoFrameSource.decodeCommittedKeyframes(url:driver:) -> (frames: Int, decodeFailures: Int, keyframes: [ScrollCaptureDriver.CapturedKeyframe])`, used within the video test.

- [ ] **Step 1: Trim and commit the video fixture (one-time offline step)**

Trim to the useful ~6 s window, keeping the real HEVC codec (stream copy, lossless, fast):

```bash
ffmpeg -y -ss 0 -t 6 -i "/Users/lili/Downloads/ScreenRecording_07-22-2026 23-16-50_1.MP4" \
  -c copy "Longshot/StitchKit/Tests/StitchKitTests/Fixtures/RealDevice/scroll-recording.mp4"
```

Verify it: `ffprobe -v error -show_entries format=duration:stream=width,height,codec_name \
  -of default=noprint_wrappers=1 "Longshot/StitchKit/Tests/StitchKitTests/Fixtures/RealDevice/scroll-recording.mp4"`
Expected: `width=1320 height=2868 codec_name=hevc duration≈6.0`, file size well under the 20 MB original.

If `-c copy` produces a clip whose first frames fail to decode (GOP boundary), re-run with
`-c:v hevc_videotoolbox -b:v 12M` instead of `-c copy` to force a clean re-encoded HEVC.

- [ ] **Step 2: Write the `VideoFrameSource` helper**

Create `Longshot/StitchKit/Tests/StitchKitTests/VideoFrameSource.swift` (adapted from the verified
feasibility-spike wiring — the exact decode path `SampleHandler` uses):

```swift
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@testable import StitchKit

/// Decodes a real screen recording through the SAME path the extension uses on device —
/// `AVAssetReader` → 32BGRA `CVPixelBuffer` → `PixelBufferImage.makeCGImage` → `ScrollCaptureDriver`
/// — so the video tier exercises the real decode path, real scroll dynamics, real chrome, and the
/// real codec. This is the only tier that touches `PixelBufferImage`/`AVAssetReader`.
enum VideoFrameSource {
    struct Result {
        let frames: Int
        let decodeFailures: Int
        let keyframes: [ScrollCaptureDriver.CapturedKeyframe]
    }

    /// Decode every frame of `url` into the driver and collect the committed keyframes (including
    /// the trailing `finish()` commit). Throws if the asset has no video track or the reader can't
    /// start — a decode failure of an individual frame is counted, not thrown (mirrors the
    /// extension's per-frame skip).
    static func decodeCommittedKeyframes(url: URL, driver: inout ScrollCaptureDriver) throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoError.noVideoTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var frames = 0, decodeFailures = 0
        var committed: [ScrollCaptureDriver.CapturedKeyframe] = []
        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            autoreleasepool {
                guard let image = PixelBufferImage.makeCGImage(from: pb) else { decodeFailures += 1; return }
                frames += 1
                if let kf = driver.ingest(image).keyframe { committed.append(kf) }
            }
        }
        if reader.status == .failed {
            throw VideoError.readFailed(reader.error)
        }
        if let tail = driver.finish() { committed.append(tail) }
        return Result(frames: frames, decodeFailures: decodeFailures, keyframes: committed)
    }

    enum VideoError: Error { case noVideoTrack, readFailed(Error?) }
}
```

- [ ] **Step 3: Write the video-tier test (assertions that hold BEFORE the §4 fix)**

Create `Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift`. The single-continuous-
segment assertion is deferred to Task 4 (it is RED until the `edgeConfidence` fix); everything here
passes on the current code.

```swift
import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

/// The video capture tier — highest fidelity. A trimmed real screen recording is decoded through
/// the exact on-device path (`AVAssetReader` → `PixelBufferImage` → `ScrollCaptureDriver`) and the
/// committed keyframes are re-stitched with `BatchStitcher`. Ground truth is fuzzy, so numeric
/// assertions are tolerant; the structural ones (0 decode failures, non-empty, sane overlap band,
/// monotonic order) are hard gates. The "single continuous segment" gate lives in the §4 fix test.
@Suite struct CaptureVideoTests {

    private func fixtureURL() throws -> URL {
        try #require(Bundle.module.url(forResource: "scroll-recording", withExtension: "mp4", subdirectory: "RealDevice"),
                     "missing trimmed video fixture (see plan Task 3 Step 1)")
    }

    @Test func everyFrameDecodesThroughTheRealPath() throws {
        var driver = ScrollCaptureDriver()
        let r = try VideoFrameSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        #expect(r.frames > 100, "expected a real frame stream, got \(r.frames)")
        #expect(r.decodeFailures == 0, "real BGRA decode path must handle every HEVC frame")
    }

    @Test func captureIsNonEmptyWithSaneOverlaps() throws {
        var driver = ScrollCaptureDriver()
        let r = try VideoFrameSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        #expect(r.keyframes.count >= 3, "capture should bank several keyframes, got \(r.keyframes.count)")
        #expect(r.keyframes.map { $0.metadata.index } == Array(0..<r.keyframes.count))

        // Consecutive overlaps sit in a sane band (spike measured ≈ 0.47–0.49).
        let profiler = VerticalProfile()
        let matcher = OffsetMatcher()
        let detector = ContentBandDetector()
        let profiles = r.keyframes.map { profiler.profile($0.image) }
        for i in 0..<(profiles.count - 1) {
            let a = profiles[i], b = profiles[i + 1]
            let n = min(a.rowCount, b.rowCount)
            let bound = max(1, n - matcher.minimumOverlap)
            let mask = detector.staticMask(a, b)
            let masked = matcher.match(a, b, searchRange: 1...bound, rowMask: mask)
            let plain = matcher.match(a, b, searchRange: 1...bound)
            let m = masked.confidence >= plain.confidence ? masked : plain
            let overlap = Double(n - min(max(0, m.dy), n)) / Double(n)
            #expect(overlap > 0.30 && overlap < 0.70, "video overlap[\(i)] = \(overlap) outside sane band")
        }
    }

    @Test func batchStitcherRecoversMonotonicOrder() throws {
        var driver = ScrollCaptureDriver()
        let r = try VideoFrameSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        let plan = try BatchStitcher().plan(r.keyframes.map { $0.image })
        // A single forward scroll: recovered order is the capture order.
        #expect(plan.order == Array(0..<r.keyframes.count), "expected monotonic scroll order, got \(plan.order)")
    }
}
```

- [ ] **Step 4: Run the video tier**

Run: `cd Longshot/StitchKit && swift test --filter CaptureVideoTests`
Expected: PASS (3 tests). If `everyFrameDecodesThroughTheRealPath` shows `decodeFailures > 0`,
re-encode the fixture per Step 1's fallback (`hevc_videotoolbox`) and re-run.

- [ ] **Step 5: Commit (video fixture + tier)**

```bash
git add Longshot/StitchKit/Tests/StitchKitTests/Fixtures/RealDevice/scroll-recording.mp4 \
        Longshot/StitchKit/Tests/StitchKitTests/VideoFrameSource.swift \
        Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift
git commit -m "test(capture): video tier — decode real recording through the real driver

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Adaptive `edgeConfidence` — accept the real image-heavy overlap without merging true non-overlaps

**Files:**
- Modify: `Longshot/StitchKit/Sources/StitchKit/BatchStitcher.swift` (the edge-acceptance test in `layout(_:)`, lines ~119–135)
- Modify: `Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift` (add the single-segment acceptance test — RED before the fix)
- Modify: `Longshot/StitchKit/Tests/StitchKitTests/BatchStitcherTests.swift` (add baidu/wechat regression guards — the "must still break" cases)

**Interfaces:**
- Consumes: existing `BatchStitcher` internals (`downwardMatch`, `edgeConfidence`, `minEdgeDy`, `Match{dy, confidence}`), `FrameProfile.variances`, baidu/wechat fixtures via `Bundle.module`.
- Produces: no new public API — a scoped change to the edge-acceptance criterion inside `layout(_:)`, plus a possible new `init` parameter (`weakEdgeFloor` / `textureFloorScale`) with a default that preserves existing behaviour for high-texture pairs.

- [ ] **Step 1: Add the acceptance test that drives the fix (RED)**

Append to `CaptureVideoTests` in `CaptureVideoTests.swift`:

```swift
    /// The §4 acceptance test. The real recording is a single continuous downward scroll, so its
    /// committed keyframes must stitch into ONE segment. The kf2↔kf3 boundary is image-heavy
    /// (low horizontal texture), so the fixed absolute `edgeConfidence = 0.45` gate wrongly
    /// rejects a real overlap and breaks the stitch after kf2 (spike: 8732px vs 11472 stacked).
    /// This is RED before the adaptive edge-acceptance fix and the regression guard after it.
    @Test func videoStitchesIntoOneContinuousSegment() throws {
        var driver = ScrollCaptureDriver()
        let r = try VideoFrameSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        let images = r.keyframes.map { $0.image }
        let plan = try BatchStitcher().plan(images)
        #expect(plan.session.segmentBreaks.isEmpty,
                "real single scroll must be one segment; breaks: \(plan.session.segmentBreaks.map { $0.afterKeyframeIndex })")
        #expect(plan.session.seams.count == r.keyframes.count - 1,
                "expected \(r.keyframes.count - 1) seams, got \(plan.session.seams.count)")

        let out = try BatchStitcher().stitch(images)
        let stacked = images.reduce(0) { $0 + $1.height }
        #expect(out.height < stacked, "stitched (\(out.height)) must be shorter than stacked (\(stacked))")
        #expect(out.height > images[0].height, "stitched must exceed a single frame")
    }
```

- [ ] **Step 2: Add the baidu/wechat regression guards (the "must still break" cases)**

Append to `BatchStitcherTests` in `BatchStitcherTests.swift` a loader for the RealDevice fixtures
and two guards. These characterize the *correct* current behaviour that the fix must preserve:

```swift
    private func loadRealDevice(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "RealDevice"))
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
    }

    /// WeChat starts on the home screen + launch animation, which genuinely do NOT overlap the
    /// chat list. Those non-overlapping frames must stay segmented off — the adaptive edge gate
    /// must not merge a true non-overlap. (Guards the §4 fix against over-acceptance.)
    @Test func wechatNonOverlapStillBreaks() throws {
        let frames = try (0...4).map { try loadRealDevice("wechat-0\($0)") }
        let plan = try BatchStitcher().plan(frames)
        #expect(!plan.session.segmentBreaks.isEmpty,
                "home/launch frames must segment off from the list; got no break")
    }

    /// Baidu is a clean downward scroll: no seam may point the wrong way and the stitch must be
    /// sane (not collapsed, not absurdly stacked). Direction/sanity guard — not an exact segment
    /// count (these are sparse fast-flick keyframes).
    @Test func baiduDownwardScrollStaysSane() throws {
        let frames = try (0...6).map { try loadRealDevice("baidu-0\($0)") }
        let plan = try BatchStitcher().plan(frames)
        #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 }, "no seam may point upward")
        let out = try BatchStitcher().stitch(frames)
        let frameH = frames[0].height
        #expect(out.height >= frameH, "stitch collapsed below one frame")
        #expect(out.height <= frameH * frames.count + 64, "stitch absurdly tall")
    }
```

- [ ] **Step 3: Run to confirm the RED and the current-correct guards**

Run: `cd Longshot/StitchKit && swift test --filter "CaptureVideoTests/videoStitchesIntoOneContinuousSegment" && swift test --filter BatchStitcherTests`
Expected: `videoStitchesIntoOneContinuousSegment` FAILS (a break after kf2). `BatchStitcherTests`
(including the two new guards) PASS — establishing the behaviour the fix must not regress.

- [ ] **Step 4: Measure per-pair confidence + texture to pick the criterion (calibration)**

Add a temporary, `.disabled` diagnostic test to `CaptureVideoTests.swift` that prints, for the
video keyframes AND for wechat AND for the Example non-overlap pair, each candidate edge's
`(above→below, dy, confidence, texture)`, where `texture` is the mean over the overlap of
`(a.variances[i] + b.variances[i]) / 2`. Reuse `BatchStitcher`'s own `downwardMatch` via a small
`@testable` shim (add an `internal func debugEdges(_ images:)` to `BatchStitcher` returning
`[(above: Int, below: Int, dy: Int, confidence: Double, texture: Double)]`, or replicate the
fwd/bwd match inline in the test). Run it, and record: the confidence of the real kf2↔kf3 edge
(the one wrongly rejected), the confidence of every wechat non-overlap pair (must stay rejected),
and their textures.

```swift
    @Test(.disabled("diagnostic — read output to calibrate the adaptive edge gate"))
    func dumpEdgeConfidences() throws {
        var driver = ScrollCaptureDriver()
        let r = try VideoFrameSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
        for e in BatchStitcher().debugEdges(r.keyframes.map { $0.image }) {
            print("video \(e.above)->\(e.below): dy=\(e.dy) conf=\(String(format: "%.3f", e.confidence)) texture=\(String(format: "%.4f", e.texture))")
        }
        // (Repeat for wechat-00..04 and the Example top/bottom pair, loaded as in BatchStitcherTests.)
    }
```

The goal of this step is a concrete separating criterion: a floor that admits the real edge
(observed confidence, ~just below 0.45) while rejecting every true non-overlap (observed
confidences, expected well below the real edge and/or spurious `dy`). Record the numbers in the
commit message so the chosen constant is justified.

- [ ] **Step 5: Implement the adaptive edge-acceptance criterion**

Based on Step 4's numbers, replace the fixed gate in `layout(_:)`. Concrete mechanism
(content-adaptive floor keyed on the pair's texture — the spec's "content-adaptive threshold keyed
on profile variance"): a low-texture (image-heavy) pair legitimately produces a compressed
confidence margin, so its required floor is scaled down toward a hard minimum, while high-texture
pairs keep the full `edgeConfidence`. The hard minimum is set from Step 4 so it sits *below* the
real kf2↔kf3 edge but *above* every measured non-overlap confidence.

Add to `BatchStitcher`'s stored properties + `init` (preserving existing defaults so high-texture
behaviour is unchanged):

```swift
    /// Hard floor the adaptive edge gate never drops below — set so a real low-texture overlap is
    /// admitted while true non-overlaps stay rejected (calibrated on the video + wechat oracles).
    let minEdgeConfidence: Double
    /// Texture (mean overlap variance) at/above which the full `edgeConfidence` floor applies.
    /// Below it, the floor is interpolated down toward `minEdgeConfidence`.
    let edgeTextureReference: Double
```
```swift
        edgeConfidence: Double = 0.45,
        minEdgeConfidence: Double = <VALUE FROM STEP 4>,
        edgeTextureReference: Double = <VALUE FROM STEP 4>,
        minEdgeDy: Int = 2,
```
```swift
        self.minEdgeConfidence = minEdgeConfidence
        self.edgeTextureReference = edgeTextureReference
```

Add a texture helper and use it in the edge loop of `layout(_:)`. Replace:

```swift
                if m.confidence >= edgeConfidence, m.dy >= minEdgeDy {
                    edges.append(Edge(above: above, below: below, dy: m.dy, conf: m.confidence))
                }
```

with:

```swift
                let texture = overlapTexture(profiles[above], profiles[below], dy: m.dy)
                // Image-heavy (low-texture) pairs legitimately score a smaller margin, so scale the
                // required floor down toward a hard minimum; textured pairs keep the full gate.
                let t = min(1, texture / edgeTextureReference)
                let floor = minEdgeConfidence + t * (edgeConfidence - minEdgeConfidence)
                if m.confidence >= floor, m.dy >= minEdgeDy {
                    edges.append(Edge(above: above, below: below, dy: m.dy, conf: m.confidence))
                }
```

Add the helper near `downwardMatch`:

```swift
    /// Mean per-row texture over the pair's downward overlap at offset `dy` — the average of the
    /// two frames' horizontal variances on the overlapping rows. Low on image-heavy content
    /// (photos/art), high on text/list content. Drives the content-adaptive edge floor.
    private func overlapTexture(_ a: FrameProfile, _ b: FrameProfile, dy: Int) -> Double {
        let kEnd = min(b.rowCount, a.rowCount - dy)
        guard kEnd > 0 else { return 0 }
        var sum: Double = 0
        for k in 0..<kEnd { sum += Double(a.variances[dy + k] + b.variances[k]) * 0.5 }
        return sum / Double(kEnd)
    }
```

If Step 4 shows texture does NOT cleanly separate the real edge from the non-overlaps, fall back to
the spec's alternate criterion — a relative gap between the pair's confidence and the *background*
(median) of all pairwise confidences: accept when `m.confidence >= max(minEdgeConfidence,
relativeFactor * medianConfidence)`. Choose whichever criterion Step 4's numbers actually separate;
implement exactly one, with the constants pinned from the measurement.

Also add the `internal` diagnostic accessor used by Step 4 (keep it — it is useful for future
calibration and is `internal`, not public API):

```swift
    /// Per-pair edge diagnostics (the more-confident direction of each pair), for calibration.
    func debugEdges(_ images: [CGImage]) -> [(above: Int, below: Int, dy: Int, confidence: Double, texture: Double)] {
        let profiles = images.map { profiler.profile($0) }
        var out: [(Int, Int, Int, Double, Double)] = []
        for i in 0..<profiles.count { for j in (i + 1)..<profiles.count {
            let fwd = downwardMatch(profiles[i], profiles[j])
            let bwd = downwardMatch(profiles[j], profiles[i])
            let (above, below, m) = fwd.confidence >= bwd.confidence ? (i, j, fwd) : (j, i, bwd)
            out.append((above, below, m.dy, m.confidence, overlapTexture(profiles[above], profiles[below], dy: m.dy)))
        } }
        return out.map { (above: $0.0, below: $0.1, dy: $0.2, confidence: $0.3, texture: $0.4) }
    }
```

- [ ] **Step 6: Run the acceptance test — it must go GREEN**

Run: `cd Longshot/StitchKit && swift test --filter "CaptureVideoTests/videoStitchesIntoOneContinuousSegment"`
Expected: PASS (one segment, `n-1` seams).

- [ ] **Step 7: Run the full regression guard — nothing that should break may now merge**

Run: `cd Longshot/StitchKit && swift test`
Expected: ALL suites PASS. Specifically confirm `BatchStitcherTests`:
`reordersFileOrderIntoScrollOrder`, `nonOverlappingFramesSplitIntoSegments`,
`wechatNonOverlapStillBreaks`, `baiduDownwardScrollStaysSane` all GREEN — the Example/wechat
non-overlaps and the baidu direction/sanity guards did not regress.

- [ ] **Step 8: Remove or keep the diagnostic test**

Delete the `.disabled` `dumpEdgeConfidences` test (its purpose — calibration — is done), or leave
it `.disabled` if useful for future tuning. Keep `debugEdges` (internal, harmless).

- [ ] **Step 9: App build check**

Run: `xcodebuild -project Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 10: Commit**

```bash
git add Longshot/StitchKit/Sources/StitchKit/BatchStitcher.swift \
        Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift \
        Longshot/StitchKit/Tests/StitchKitTests/BatchStitcherTests.swift
git commit -m "fix(batch): adaptive edge-acceptance gate accepts real image-heavy overlaps

The fixed absolute edgeConfidence=0.45 gate rejected a real overlap (video kf2<->kf3,
low horizontal texture) and shattered a continuous scroll. Scale the required floor by
the pair's texture so image-heavy overlaps pass while true non-overlaps (Example
top/bottom, wechat home/launch) still segment off. Acceptance: the video tier stitches
into one continuous segment; BatchStitcher Example/baidu/wechat guards unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 Extract `ScrollCaptureDriver` + refactor `SampleHandler` → **Task 1** (driver with `ingest`/`finish`, `Step`, `CapturedKeyframe`; adapter delegates decode/write/haptics; behaviour-preserving; safety-cue decision in driver, throttle+haptic in adapter; trailing commit in `finish()`; first-keyframe orientation/colorspace in adapter via `metadata.index == 0`).
- §2 Synthetic tier `CaptureSimulator` + `CaptureSimulationTests`, two scenarios (faithful ~2868 px ~3 kf; long-scroll ~1400 px + fling ~6–7 kf), static chrome, seeded jitter, closed loop → **Task 2**.
- §3 Video tier `VideoFrameSource` (AVAssetReader→32BGRA→`PixelBufferImage`→driver), trimmed ~6 s fixture under `Fixtures/RealDevice/`, decode/non-empty/overlap-band/order assertions → **Task 3**. (Package.swift already registers the dir — noted, no edit.)
- §4 Adaptive `edgeConfidence` fix; acceptance = video one continuous segment while Example/baidu/wechat guards hold → **Task 4** (RED-first video single-segment test, calibration measurement, content-adaptive floor with a relative-gap fallback, regression guards).

**Placeholder scan:** The only deliberately-deferred literals are Task 2 Step 4's cadence thresholds and Task 4 Step 5's `minEdgeConfidence`/`edgeTextureReference` — both are *empirical constants with a defined measurement procedure and a defined acceptance gate*, not vague "tune later" placeholders. Every code step ships complete code.

**Type consistency:** `ScrollCaptureDriver.CapturedKeyframe{image, metadata}` and `Step{keyframe, fireSafetyCue}` are used identically across Tasks 1–4. `driver.ingest(_:) -> Step` and `driver.finish() -> CapturedKeyframe?` match everywhere. `VideoFrameSource.Result{frames, decodeFailures, keyframes}` is consistent between helper and test. `debugEdges`/`overlapTexture` signatures match between Task 4 steps.

**Behaviour-preservation risk (called out, not hidden):** the driver advances `keyframeIndex` on the commit *decision* rather than after a successful disk write; on the rare write-failure path this leaves a numbering gap instead of reusing the index. Documented in Task 1 Step 3 as inert (manifest is filename-driven). No other behaviour change outside the Task 4 `edgeConfidence` fix.
