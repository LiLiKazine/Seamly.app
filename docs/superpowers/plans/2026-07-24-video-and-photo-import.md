# Video & Photo Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new ways to make a long screenshot — "From Video" (decode one screen recording) and "From Photos" (stitch several overlapping screenshots) — reusing the existing Library → Preview → Edit → Export pipeline.

**Architecture:** Both entries produce an ordered `[CGImage]` and hand it to a new off-main-actor `MediaImporter`, which writes a session folder into app storage (raw BGRA keyframes + manifest), resolves geometry, and lets `LibraryModel` adopt it — exactly the shape of a finished broadcast, minus the cross-process handoff. The two entries differ only in how images are produced (photos = the picks; video = `ScrollCaptureDriver` keyframes) and how scroll order is trusted (photos = recover-then-fall-back-to-pick-order; video = trust capture order).

**Tech Stack:** Swift 6, SwiftUI, PhotosUI, AVFoundation (`AVAssetReader`), Core Graphics, StitchKit (local SwiftPM package). Swift Testing.

## Global Constraints

- **iOS deployment target 26.0.** App target `SWIFT_VERSION = 6.0`; StitchKit package on Swift 6 language mode. Test targets are still Swift 5.0.
- **First-party frameworks only.** No third-party dependencies.
- **Swift Concurrency, not GCD.** `async`/`await`, `Task`, structured concurrency. Actors / `@MainActor`, not locks.
- **Never swallow errors silently** (CLAUDE.md). Propagate with `throws`, or handle meaningfully (recover / surface to user / log via `Diagnostics`). A deliberate ignore must be a narrow, commented `catch` — never a bare `try?`.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) — never XCTest.
- **Stitching core is pure/testable in StitchKit**; UI-free logic goes in StitchKit or `Core/`, driven by tests before UI.

## Commands

```bash
# StitchKit unit tests (run on macOS via SwiftPM — AVAssetReader works here)
cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test

# One StitchKit suite
cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test --filter BatchStitcherTests

# App build + app/UI tests (simulator)
xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# App + extension build only
xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## File Structure

**StitchKit (`Longshot/StitchKit/Sources/StitchKit/`):**
- Modify `BatchStitcher.swift` — add `plan(_:assumingOrder:)`; extract shared plan-building tail.
- Modify `StitchSession.swift` — add `orderAssumed: Bool` field (Codable, defaults false).
- Create `VideoKeyframeSource.swift` — production video decode → `ScrollCaptureDriver` keyframes, timestamp-throttled, with progress. Replaces the test-only `VideoFrameSource`.

**App core (`Longshot/Longshot/Core/`):**
- Modify `StitchAssembler.swift` — `OrderStrategy` enum; `resolveGeometry(strategy:)`.
- Create `MediaImporter.swift` — write ordered images to a new session folder + resolve.
- Modify `LibraryModel.swift` — `importPhotos`, `importVideo`, `importProgress`; `Capture.orderAssumed`.

**App features (`Longshot/Longshot/Features/Capture/`):**
- Modify `CaptureStartView.swift` — three peer buttons.
- Create `PhotoImportButton.swift` — `.images` multi picker → `importPhotos`.
- Create `VideoImportButton.swift` — `.videos` single picker (+ `Movie` transferable) → `importVideo`.
- Modify `Features/Library/LibraryView.swift` — `orderAssumed` badge in `CaptureRow`; import-progress surface.

**Tests:**
- Modify `StitchKit/Tests/StitchKitTests/BatchStitcherTests.swift` — `assumingOrder` cases.
- Modify `StitchKit/Tests/StitchKitTests/StitchKitTests.swift` (or add) — `orderAssumed` round-trip.
- Modify `StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift` — call `VideoKeyframeSource`; add throttled-cadence test. Delete `VideoFrameSource.swift`.
- Create `LongshotTests/MediaImportTests.swift` — `MediaImporter` + `LibraryModel.importPhotos` end-to-end.

---

### Task 1: `BatchStitcher.plan(_:assumingOrder:)`

Add an overload that assembles along a **given** order instead of recovering it, still measuring seams/bands and breaking where *consecutive* frames don't overlap. This is the mechanism behind the photos pick-order fallback and video capture-order trust.

**Files:**
- Modify: `Longshot/StitchKit/Sources/StitchKit/BatchStitcher.swift`
- Test: `Longshot/StitchKit/Tests/StitchKitTests/BatchStitcherTests.swift`

**Interfaces:**
- Consumes: existing `BatchStitcher` privates (`layout`, `downwardMatch`, seam/band building), `FrameProfile`, `StitchSession`.
- Produces:
  - `public func plan(_ images: [CGImage], assumingOrder order: [Int]) throws -> Plan`
  - Behaviour: `Plan.order == order`; one segment while consecutive pairs overlap (`downwardMatch.confidence >= edgeConfidence && dy >= minEdgeDy`), a new segment (a `SegmentBreak(reason: .lostLock)`) at the first non-overlapping consecutive pair.

- [ ] **Step 1: Write the failing tests**

Add to `BatchStitcherTests.swift` (reuses the existing `load` helper and `Self.names`):

```swift
/// Assembling in a supplied order keeps that order verbatim (no re-sort), and a truly
/// in-scroll-order set still stitches into one continuous segment with the right seam count.
@Test func assumingOrderKeepsGivenOrderForOverlappingSet() throws {
    // names are spatial mid, bottom, top; true top→bottom is [2, 0, 1].
    let images = try [Self.names[2], Self.names[0], Self.names[1]].map { try load($0) }  // already top→bottom
    let plan = try BatchStitcher().plan(images, assumingOrder: [0, 1, 2])
    #expect(plan.order == [0, 1, 2])
    #expect(plan.session.segmentBreaks.isEmpty)
    #expect(plan.session.seams.count == 2)
    #expect(plan.session.seams.allSatisfy { $0.provisionalDy > 0 })
}

/// A wrong supplied order is NOT silently corrected — the whole point of the fallback is to
/// trust the caller's order. Non-overlapping consecutive pairs become segment breaks.
@Test func assumingOrderDoesNotReorderAndBreaksNonOverlappingNeighbours() throws {
    // Supplied order bottom, top, mid: neighbours (bottom,top) don't overlap → a break.
    let images = try [Self.names[1], Self.names[2], Self.names[0]].map { try load($0) }
    let plan = try BatchStitcher().plan(images, assumingOrder: [0, 1, 2])
    #expect(plan.order == [0, 1, 2])
    #expect(!plan.session.segmentBreaks.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test --filter BatchStitcherTests`
Expected: FAIL — `plan(_:assumingOrder:)` does not exist (compile error).

- [ ] **Step 3: Refactor `plan` and add the overload**

In `BatchStitcher.swift`, replace the body of `plan(_ images:)` so it delegates to a shared builder, and add the overload + an ordered-layout helper. Keep the existing `layout`, `downwardMatch`, `chromeBand` unchanged.

```swift
/// Recover scroll order and build the stitch manifest without touching pixels.
public func plan(_ images: [CGImage]) throws -> Plan {
    guard !images.isEmpty else { throw StitchError.empty }
    let profiles = images.map { profiler.profile($0) }
    let (order, segmentOfSlot) = layout(profiles)
    return buildPlan(profiles: profiles, order: order, segmentOfSlot: segmentOfSlot)
}

/// Build the stitch manifest assembling along `order` verbatim (no re-sort). Consecutive
/// frames stay in one segment while they overlap; the first non-overlapping neighbour starts
/// a new segment. Used when the caller's order is trusted (video capture order) or assumed
/// (photos pick-order fallback).
public func plan(_ images: [CGImage], assumingOrder order: [Int]) throws -> Plan {
    guard !images.isEmpty else { throw StitchError.empty }
    precondition(order.count == images.count && Set(order) == Set(0..<images.count),
                 "assumingOrder must be a permutation of 0..<images.count")
    let profiles = images.map { profiler.profile($0) }
    let segmentOfSlot = segmentsAlong(order, profiles)
    return buildPlan(profiles: profiles, order: order, segmentOfSlot: segmentOfSlot)
}
```

Add the two private helpers:

```swift
/// Segment index per ordered slot when the order is fixed: increment at the first consecutive
/// pair that does not clear the overlap gate.
private func segmentsAlong(_ order: [Int], _ profiles: [FrameProfile]) -> [Int] {
    guard !order.isEmpty else { return [] }
    var segmentOfSlot = [0]
    for slot in 1..<order.count {
        let a = profiles[order[slot - 1]], b = profiles[order[slot]]
        let m = downwardMatch(a, b)
        let overlaps = m.confidence >= edgeConfidence && m.dy >= minEdgeDy
        segmentOfSlot.append(overlaps ? segmentOfSlot[slot - 1] : segmentOfSlot[slot - 1] + 1)
    }
    return segmentOfSlot
}

/// Shared manifest assembly from a resolved (order, segmentOfSlot). Extracted verbatim from the
/// original `plan` body so recovered and assumed-order paths build identical structures.
private func buildPlan(profiles: [FrameProfile], order: [Int], segmentOfSlot: [Int]) -> Plan {
    var session = StitchSession(
        createdAt: Date(timeIntervalSince1970: 0),
        status: .complete,
        deviceScale: 1,
        orientation: .portrait
    )
    for (slot, src) in order.enumerated() {
        session.keyframes.append(Keyframe(filename: "kf-\(slot)", pixelWidth: profiles[src].sourceWidth, pixelHeight: profiles[src].sourceHeight, index: slot))
    }
    for slot in 0..<max(0, order.count - 1) {
        if segmentOfSlot[slot] == segmentOfSlot[slot + 1] {
            let a = profiles[order[slot]], b = profiles[order[slot + 1]]
            let m = downwardMatch(a, b)
            let dyPx = Int((Double(m.dy) * a.rowScale).rounded())
            session.seams.append(Seam(fromIndex: slot, provisionalDy: dyPx, confidence: m.confidence, isLowConfidence: m.confidence < 0.4))
        } else {
            session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: slot, reason: .lostLock))
        }
    }
    let segmentCount = (segmentOfSlot.max() ?? 0) + (order.isEmpty ? 0 : 1)
    for seg in 0..<segmentCount {
        let slots = order.indices.filter { segmentOfSlot[$0] == seg }
        let pairs = zip(slots, slots.dropFirst()).map { (profiles[order[$0]], profiles[order[$1]]) }
        session.contentBands.append(chromeBand(pairs, rowScale: profiles[order[slots[0]]].rowScale))
    }
    return Plan(order: order, session: session)
}
```

> Note: the original inline `plan` body is now `buildPlan`; delete the duplicated statements from `plan(_ images:)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test --filter BatchStitcherTests`
Expected: PASS (new cases + all pre-existing `BatchStitcherTests`).

- [ ] **Step 5: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/StitchKit/Sources/StitchKit/BatchStitcher.swift Longshot/StitchKit/Tests/StitchKitTests/BatchStitcherTests.swift
git commit -m "feat(stitchkit): BatchStitcher.plan(assumingOrder:) for trusted/assumed order

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `StitchSession.orderAssumed`

Persist whether scroll order was *assumed* (pick-order fallback) rather than confidently recovered, so the Library can badge it honestly and the badge survives relaunch.

**Files:**
- Modify: `Longshot/StitchKit/Sources/StitchKit/StitchSession.swift`
- Test: `Longshot/StitchKit/Tests/StitchKitTests/StitchKitTests.swift`

**Interfaces:**
- Produces: `public var orderAssumed: Bool` on `StitchSession`, default `false`; memberwise-init param `orderAssumed: Bool = false`; decoded via `decodeIfPresent(...) ?? false`.

- [ ] **Step 1: Write the failing test**

Add to `StitchKitTests.swift`:

```swift
@Test func orderAssumedDefaultsFalseAndRoundTrips() throws {
    var s = StitchSession(createdAt: Date(timeIntervalSince1970: 0), deviceScale: 1, orientation: .portrait)
    #expect(s.orderAssumed == false)
    s.orderAssumed = true
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(StitchSession.self, from: data)
    #expect(back.orderAssumed == true)
}

@Test func orderAssumedMissingKeyDecodesFalse() throws {
    // A manifest written before this field existed must decode, defaulting to false.
    let json = #"{"id":"\#(UUID().uuidString)","createdAt":"1970-01-01T00:00:00Z","status":"complete","deviceScale":1,"orientation":"portrait","keyframes":[],"seams":[],"segmentBreaks":[]}"#
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    let s = try d.decode(StitchSession.self, from: Data(json.utf8))
    #expect(s.orderAssumed == false)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test --filter StitchKitTests`
Expected: FAIL — no member `orderAssumed`.

- [ ] **Step 3: Add the field**

In `StitchSession.swift`, add the stored property (after `bottomTrim`):

```swift
/// True when scroll order was *assumed* from input order rather than confidently recovered
/// from pixel overlap (the photos pick-order fallback). Drives an "order assumed" badge.
/// Never set for confidently recovered order or for trusted capture order (video/broadcast).
public var orderAssumed: Bool
```

Add to the memberwise `init` — parameter (before `topTrim` is fine, keep defaults last-compatible; place it with a default):

```swift
// in the parameter list:
orderAssumed: Bool = false,
// in the body:
self.orderAssumed = orderAssumed
```

Add to `init(from:)` (after the `bottomTrim` line):

```swift
orderAssumed = try c.decodeIfPresent(Bool.self, forKey: .orderAssumed) ?? false
```

- [ ] **Step 4: Run to verify pass**

Run: `cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test --filter StitchKitTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/StitchKit/Sources/StitchKit/StitchSession.swift Longshot/StitchKit/Tests/StitchKitTests/StitchKitTests.swift
git commit -m "feat(stitchkit): StitchSession.orderAssumed flag (Codable, defaults false)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `VideoKeyframeSource` (production decode + throttle)

Promote the test-only `VideoFrameSource` into a production StitchKit type that decodes a screen recording through the real driver, sampling by timestamp (not every frame) and reporting progress. Re-validate the cadence against the existing fixture.

**Files:**
- Create: `Longshot/StitchKit/Sources/StitchKit/VideoKeyframeSource.swift`
- Delete: `Longshot/StitchKit/Tests/StitchKitTests/VideoFrameSource.swift`
- Modify: `Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift`

**Interfaces:**
- Consumes: `ScrollCaptureDriver`, `PixelBufferImage`, `AVAssetReader`.
- Produces:
  - `public struct VideoKeyframeSource`
  - `public struct Result { public let frames: Int; public let decodeFailures: Int; public let keyframes: [ScrollCaptureDriver.CapturedKeyframe] }`
  - `public enum VideoError: Error { case noVideoTrack, readFailed(Error?) }`
  - `public static func decodeCommittedKeyframes(url: URL, driver: inout ScrollCaptureDriver, targetFPS: Double? = nil, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Result`
  - `targetFPS == nil` → profile every frame (full rate, back-compat with the baseline tests). Non-nil → profile a frame only when ≥ `1/targetFPS` s elapsed since the last profiled frame's presentation timestamp.

- [ ] **Step 1: Create the production type**

`VideoKeyframeSource.swift`:

```swift
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// Decodes a real screen recording through the SAME path the broadcast extension uses on device —
/// `AVAssetReader` → 32BGRA `CVPixelBuffer` → `PixelBufferImage.makeCGImage` → `ScrollCaptureDriver`
/// — so "From Video" reuses the proven capture picking against real decode, scroll, chrome, codec.
///
/// Sampling: the driver commits based on overlap with the last *committed keyframe*, so we do not
/// need every source frame. When `targetFPS` is set, a frame is profiled only when at least
/// `1/targetFPS` seconds have elapsed (by presentation timestamp) since the last profiled frame —
/// far less work on a 60fps recording, with enough granularity to catch each commit point. The
/// coarsest healthy cadence is validated against the fixture (see CaptureVideoTests).
public struct VideoKeyframeSource: Sendable {
    public struct Result: Sendable {
        public let frames: Int
        public let decodeFailures: Int
        public let keyframes: [ScrollCaptureDriver.CapturedKeyframe]
    }

    public enum VideoError: Error { case noVideoTrack, readFailed(Error?) }

    /// Decode `url` into `driver`, collecting committed keyframes (including the trailing
    /// `finish()` commit). Throws if there is no video track or the reader can't start; an
    /// individual frame that yields no image buffer is counted, not thrown (mirrors the
    /// extension's per-frame skip).
    public static func decodeCommittedKeyframes(
        url: URL,
        driver: inout ScrollCaptureDriver,
        targetFPS: Double? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoError.noVideoTrack }
        let duration = try await asset.load(.duration)
        let totalSeconds = max(CMTimeGetSeconds(duration), 0.0001)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        let minInterval = targetFPS.map { 1.0 / $0 }
        var lastProfiledSeconds = -Double.greatestFiniteMagnitude
        var frames = 0, decodeFailures = 0
        var committed: [ScrollCaptureDriver.CapturedKeyframe] = []

        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let seconds = CMTimeGetSeconds(pts)
            // Throttle: skip decoding/profiling this frame if it's too close to the last one we
            // profiled. Sample buffers are still pulled sequentially (inter-frame codec needs it);
            // the saving is skipping makeCGImage + VerticalProfile.
            if let minInterval, seconds - lastProfiledSeconds < minInterval { continue }
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            autoreleasepool {
                guard let image = PixelBufferImage.makeCGImage(from: pb) else { decodeFailures += 1; return }
                frames += 1
                lastProfiledSeconds = seconds
                if let kf = driver.ingest(image).keyframe { committed.append(kf) }
            }
            progress?(min(1, max(0, seconds / totalSeconds)))
        }
        if reader.status == .failed { throw VideoError.readFailed(reader.error) }
        if let tail = driver.finish() { committed.append(tail) }
        progress?(1)
        return Result(frames: frames, decodeFailures: decodeFailures, keyframes: committed)
    }
}
```

- [ ] **Step 2: Point the existing tests at the production type and make them `async`**

Delete `VideoFrameSource.swift`. In `CaptureVideoTests.swift`, replace `VideoFrameSource` with `VideoKeyframeSource`, mark the three tests `async`, and `await` the decode. E.g. the first test becomes:

```swift
@Test func everyFrameDecodesThroughTheRealPath() async throws {
    var driver = ScrollCaptureDriver()
    let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver)
    #expect(r.frames > 300, "expected a real frame stream, got \(r.frames)")
    #expect(r.decodeFailures == 0, "real BGRA decode path must handle every HEVC frame")
}
```

Apply the same `async` + `await VideoKeyframeSource.decodeCommittedKeyframes(...)` change to `captureIsNonEmptyWithSaneOverlaps` and `batchStitcherRecoversMonotonicOrder` (leave their assertions, including the `withKnownIssue` block, unchanged — full-rate default preserves the baseline).

- [ ] **Step 3: Add the throttled-cadence re-validation test**

Add to `CaptureVideoTests.swift`. This is the §"Video decode" re-validation gate: the throttled cadence must keep keyframe count and overlaps in the same healthy bands as full rate.

```swift
/// Re-validation gate: at the production sampling cadence (~12 fps by timestamp) the driver must
/// still bank the same handful of keyframes with sane overlaps as full-rate decode. If this ever
/// fails, the cadence is too coarse — raise targetFPS until it holds, then pin the new value here
/// and in VideoImportButton.
@Test func throttledCadenceKeepsKeyframesHealthy() async throws {
    var driver = ScrollCaptureDriver()
    let r = try await VideoKeyframeSource.decodeCommittedKeyframes(url: try fixtureURL(), driver: &driver, targetFPS: 12)
    #expect(r.decodeFailures == 0)
    try #require(r.keyframes.count >= 4, "throttled decode should still bank several keyframes, got \(r.keyframes.count)")
    #expect(r.keyframes.count <= 6, "throttled decode should not over-bank, got \(r.keyframes.count)")

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
        #expect(overlap > 0.35 && overlap < 0.65, "throttled overlap[\(i)] = \(overlap) outside sane band")
    }
}
```

- [ ] **Step 4: Run the video tier**

Run: `cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test --filter CaptureVideoTests`
Expected: PASS — the three baseline tests (2 real `#expect`s + the `withKnownIssue` xfail in the order test) and the new throttled test. If `throttledCadenceKeepsKeyframesHealthy` fails on keyframe count or overlap band, raise `targetFPS` (e.g. 15, 20) until it passes, then update the literal in the test comment and remember the chosen value for Task 7.

- [ ] **Step 5: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/StitchKit/Sources/StitchKit/VideoKeyframeSource.swift Longshot/StitchKit/Tests/StitchKitTests/CaptureVideoTests.swift
git rm Longshot/StitchKit/Tests/StitchKitTests/VideoFrameSource.swift
git commit -m "feat(stitchkit): VideoKeyframeSource — production video decode with timestamp throttle

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `OrderStrategy` + `resolveGeometry(strategy:)`

Generalize geometry resolution over three ordering policies and wire the existing broadcast import to the behaviour-preserving one.

**Files:**
- Modify: `Longshot/Longshot/Core/StitchAssembler.swift`
- Modify: `Longshot/Longshot/Core/LibraryModel.swift` (one call site)
- Test: `Longshot/LongshotTests/MediaImportTests.swift` (create in this task; extended in Task 5/6)

**Interfaces:**
- Produces:
  - `enum OrderStrategy { case recover; case recoverOrInputOrder; case inputOrder }`
  - `nonisolated static func resolveGeometry(_ session: StitchSession, in folder: URL, strategy: OrderStrategy = .recover, stitcher: BatchStitcher = BatchStitcher()) throws -> StitchSession`
  - `.recover` → today's behaviour (full recovery, `orderAssumed=false`). `.recoverOrInputOrder` → recover; if the recovered plan isn't one clean chain, re-plan `assumingOrder` input order and set `orderAssumed=true`. `.inputOrder` → plan `assumingOrder` input order, `orderAssumed=false`.
- Consumes: `BatchStitcher.plan`, `BatchStitcher.plan(_:assumingOrder:)` (Task 1); `StitchSession.orderAssumed` (Task 2).

- [ ] **Step 1: Write the failing test**

Create `LongshotTests/MediaImportTests.swift`:

```swift
import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Longshot

/// Shared synthetic-frame helpers + coverage for order resolution and media import.
@MainActor
struct MediaImportTests {

    /// A tall source with a monotonic vertical ramp plus horizontal structure that survives
    /// downscaling — scroll position is unambiguous. (Mirrors BatchAssemblyTests.makeSource.)
    static func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    static func slices(count: Int, width: Int, sliceH: Int, dy: Int) -> [CGImage] {
        let src = makeSource(width: width, height: sliceH + (count - 1) * dy)
        return (0..<count).map { src.cropping(to: CGRect(x: 0, y: $0 * dy, width: width, height: sliceH))! }
    }

    /// Writes `images` as raw keyframes + a base manifest into a fresh session folder, returning
    /// (store, id, folder). Used to drive resolveGeometry directly.
    private func writeBase(_ images: [CGImage], root: URL) throws -> (SessionStore, UUID, URL) {
        let store = SessionStore(containerURL: root)
        let id = UUID()
        let folder = try store.createFolder(for: id)
        var session = StitchSession(id: id, createdAt: Date(), status: .complete, deviceScale: 1, orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String)
        for (i, img) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(img, to: folder.appendingPathComponent(name))
            session.keyframes.append(Keyframe(filename: name, pixelWidth: img.width, pixelHeight: img.height, index: i))
        }
        try store.writeManifest(session)
        return (store, id, folder)
    }

    @Test func inputOrderStrategyTrustsOrderAndDoesNotBadge() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let imgs = Self.slices(count: 3, width: 120, sliceH: 360, dy: 140)  // in scroll order
        let (store, id, folder) = try writeBase(imgs, root: root)
        let session = try store.readManifest(for: id)
        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: .inputOrder)
        #expect(resolved.keyframes.map(\.index) == [0, 1, 2])
        #expect(resolved.segmentBreaks.isEmpty)
        #expect(resolved.orderAssumed == false)
    }

    @Test func recoverOrInputOrderBadgesWhenRecoveryCannotChain() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        // Two non-overlapping halves in pick order: recovery yields 2 segments → fallback + badge.
        let big = Self.makeSource(width: 120, height: 900)
        let a = big.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 300))!
        let b = big.cropping(to: CGRect(x: 0, y: 600, width: 120, height: 300))!
        let (store, id, folder) = try writeBase([a, b], root: root)
        let session = try store.readManifest(for: id)
        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: .recoverOrInputOrder)
        #expect(resolved.orderAssumed == true)
        #expect(resolved.keyframes.map(\.index) == [0, 1])   // kept pick order in the fallback
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LongshotTests/MediaImportTests`
Expected: FAIL — `resolveGeometry(_:in:strategy:)` has no `strategy:` parameter (compile error).

- [ ] **Step 3: Implement `OrderStrategy` + refactor `resolveGeometry`**

In `StitchAssembler.swift`, add above the enum body of `StitchAssembler` (top of file, after imports):

```swift
/// How `resolveGeometry` decides scroll order.
enum OrderStrategy {
    /// Recover order from pixel overlap; never fall back. Behaviour-preserving for broadcast.
    case recover
    /// Recover; if the result isn't one clean, confident chain, fall back to the input (pick)
    /// order and mark `orderAssumed`. Used by "From Photos".
    case recoverOrInputOrder
    /// Trust the input order verbatim (capture/temporal order). Used by "From Video".
    case inputOrder
}
```

Replace `resolveGeometry` with:

```swift
nonisolated static func resolveGeometry(_ session: StitchSession, in folder: URL, strategy: OrderStrategy = .recover, stitcher: BatchStitcher = BatchStitcher()) throws -> StitchSession {
    guard session.keyframes.count > 1 else { return session }
    let ordered = session.keyframes.sorted { $0.index < $1.index }
    let cs = colorSpace(for: session)
    let images = try ordered.map { try loadKeyframe($0, in: folder, colorSpace: cs) }
    let identity = Array(0..<images.count)

    let plan: BatchStitcher.Plan
    var orderAssumed = false
    switch strategy {
    case .recover:
        plan = try stitcher.plan(images)
    case .inputOrder:
        plan = try stitcher.plan(images, assumingOrder: identity)
    case .recoverOrInputOrder:
        let recovered = try stitcher.plan(images)
        let clean = recovered.session.segmentBreaks.isEmpty && recovered.session.seams.allSatisfy { !$0.isLowConfidence }
        if clean {
            plan = recovered
        } else {
            plan = try stitcher.plan(images, assumingOrder: identity)
            orderAssumed = true
        }
    }

    var resolved = session
    resolved.keyframes = plan.order.enumerated().map { slot, srcIndex in
        var kf = ordered[srcIndex]
        kf.index = slot
        return kf
    }
    resolved.seams = plan.session.seams
    resolved.segmentBreaks = plan.session.segmentBreaks
    resolved.contentBands = plan.session.contentBands
    resolved.orderAssumed = orderAssumed
    return resolved
}
```

Update the doc comment's first sentence to mention the strategy (keep the rest). In `LibraryModel.swift`, the one existing call site in `importFromGroup` stays behaviour-preserving — make the strategy explicit:

```swift
let resolved = try StitchAssembler.resolveGeometry(session, in: dest, strategy: .recover)
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LongshotTests/MediaImportTests -only-testing:LongshotTests/BatchAssemblyTests`
Expected: PASS — new `MediaImportTests` cases and the pre-existing `BatchAssemblyTests` (broadcast import still `.recover`, `orderAssumed` stays false).

- [ ] **Step 5: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/Longshot/Core/StitchAssembler.swift Longshot/Longshot/Core/LibraryModel.swift Longshot/LongshotTests/MediaImportTests.swift
git commit -m "feat(app): OrderStrategy + resolveGeometry(strategy:) with pick-order fallback

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `MediaImporter`

Write an ordered `[CGImage]` into a fresh app-storage session folder (raw BGRA keyframes + manifest), resolve geometry with the given strategy, and return the new session id. This is the shared backbone for both entries.

**Files:**
- Create: `Longshot/Longshot/Core/MediaImporter.swift`
- Test: `Longshot/LongshotTests/MediaImportTests.swift` (extend)

**Interfaces:**
- Produces:
  - `enum MediaImporter`
  - `enum Source: String { case photos, video }`
  - `enum ImportError: Error { case notEnoughContent }`
  - `nonisolated static func write(images: [CGImage], into store: SessionStore, strategy: OrderStrategy, source: Source) throws -> UUID`
  - Behaviour: throws `.notEnoughContent` when `images.count < 2`; writes `kf-%04d.bgra` per image; base manifest `status=.complete`, `deviceScale=1`, orientation from first image aspect, `colorSpaceName` from first image; then `resolveGeometry(strategy:)` and persist. Returns the new id.
- Consumes: `SessionStore`, `KeyframeIO.writeRaw`, `StitchAssembler.resolveGeometry`, `OrderStrategy`.

- [ ] **Step 1: Write the failing test**

Add to `MediaImportTests.swift`:

```swift
@Test func mediaImporterWritesResolvableSession() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let store = SessionStore(containerURL: root)
    let imgs = Self.slices(count: 3, width: 120, sliceH: 360, dy: 140)

    let id = try MediaImporter.write(images: imgs, into: store, strategy: .inputOrder, source: .video)
    let session = try store.readManifest(for: id)
    #expect(session.keyframes.count == 3)
    #expect(session.status == .complete)
    #expect(session.segmentBreaks.isEmpty)
    #expect(session.orderAssumed == false)
    // The raw files exist and are readable at the manifest's dims.
    let folder = store.folder(for: id)
    for kf in session.keyframes {
        let img = try KeyframeIO.readRaw(from: folder.appendingPathComponent(kf.filename), width: kf.pixelWidth, height: kf.pixelHeight)
        #expect(img.width == 120)
    }
}

@Test func mediaImporterRejectsSingleImage() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let store = SessionStore(containerURL: root)
    let one = Self.slices(count: 1, width: 120, sliceH: 360, dy: 140)
    #expect(throws: MediaImporter.ImportError.self) {
        try MediaImporter.write(images: one, into: store, strategy: .recoverOrInputOrder, source: .photos)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LongshotTests/MediaImportTests`
Expected: FAIL — no `MediaImporter`.

- [ ] **Step 3: Implement `MediaImporter`**

`MediaImporter.swift`:

```swift
import CoreGraphics
import Foundation
import StitchKit

/// Turns an ordered set of images (photo picks, or video-decoded keyframes) into a persisted
/// session in app storage — the shared path behind "From Photos" and "From Video". Mirrors the
/// broadcast import (write raw keyframes → base manifest → resolveGeometry) minus the App Group,
/// staleness, and per-session move logic that only the cross-process handoff needs. Pure and
/// off-actor: `nonisolated`, `Sendable` inputs/outputs.
enum MediaImporter {
    enum Source: String { case photos, video }
    enum ImportError: Error, Equatable { case notEnoughContent }

    /// Write `images` (in final display order) into `store` as a new session and resolve its
    /// geometry with `strategy`. Returns the new session id. Throws `.notEnoughContent` for
    /// fewer than two images (a single frame is not a stitch).
    nonisolated static func write(images: [CGImage], into store: SessionStore, strategy: OrderStrategy, source: Source) throws -> UUID {
        guard images.count >= 2 else { throw ImportError.notEnoughContent }
        let id = UUID()
        let folder = try store.createFolder(for: id)

        let first = images[0]
        var session = StitchSession(
            id: id,
            createdAt: Date(),
            status: .complete,
            deviceScale: 1,
            orientation: first.width > first.height ? .landscape : .portrait,
            colorSpaceName: first.colorSpace?.name as String?
        )
        for (i, image) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(image, to: folder.appendingPathComponent(name))
            session.keyframes.append(Keyframe(filename: name, pixelWidth: image.width, pixelHeight: image.height, index: i))
        }
        try store.writeManifest(session)

        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: strategy)
        try store.writeManifest(resolved)
        return id
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LongshotTests/MediaImportTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/Longshot/Core/MediaImporter.swift Longshot/LongshotTests/MediaImportTests.swift
git commit -m "feat(app): MediaImporter — persist ordered images as a resolvable session

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `LibraryModel` import entry points + progress + `Capture.orderAssumed`

Expose `importPhotos` / `importVideo` on the model (heavy work off-main, video progress observable), and surface `orderAssumed` on `Capture`.

**Files:**
- Modify: `Longshot/Longshot/Core/LibraryModel.swift`
- Test: `Longshot/LongshotTests/MediaImportTests.swift` (extend)

**Interfaces:**
- Produces (on `@MainActor final class LibraryModel`):
  - `private(set) var importProgress: Double?` (nil when idle; 0…1 during a video decode)
  - `func importPhotos(_ images: [CGImage]) async` — strategy `.recoverOrInputOrder`, source `.photos`; sets `importError` on failure.
  - `func importVideo(_ url: URL) async` — decode via `VideoKeyframeSource` (targetFPS 30 — the validated cadence from Task 3) with progress, then `MediaImporter` strategy `.inputOrder`, source `.video`.
  - `private(set) var importError: String?`
  - On `Capture`: `var orderAssumed: Bool { session.orderAssumed }`
- Consumes: `MediaImporter` (Task 5), `VideoKeyframeSource` (Task 3), existing `appStore`, `reload()`, `assemble(_:)`.

- [ ] **Step 1: Write the failing test**

Add to `MediaImportTests.swift`:

```swift
@Test func importPhotosProducesReadyCapture() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let app = root.appendingPathComponent("app")
    defer { try? fm.removeItem(at: root) }
    try fm.createDirectory(at: app, withIntermediateDirectories: true)

    let model = LibraryModel(appContainer: app, groupContainer: nil)
    // Pick order is the true scroll order → clean recovery, no badge.
    await model.importPhotos(Self.slices(count: 3, width: 120, sliceH: 360, dy: 140))

    #expect(model.captures.count == 1)
    let capture = try #require(model.captures.first)
    #expect(capture.phase == .ready)
    #expect(capture.orderAssumed == false)
    #expect(try #require(capture.proxy).width == 120)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LongshotTests/MediaImportTests/importPhotosProducesReadyCapture`
Expected: FAIL — no `importPhotos`.

- [ ] **Step 3: Implement the entry points**

In `LibraryModel.swift`, add stored properties near `lastPickupWasEmpty`:

```swift
/// 0…1 while a video import decodes; nil when idle. Drives a determinate progress view.
private(set) var importProgress: Double?
/// Set when the most recent import failed, for a user-visible message.
private(set) var importError: String?
```

Add the two methods (place after `refresh()`):

```swift
/// Import picked screenshots as a new capture. Recovers scroll order from overlap, falling back
/// to the pick order (badged) when recovery can't confidently chain them.
func importPhotos(_ images: [CGImage]) async {
    await runImport { store in
        try MediaImporter.write(images: images, into: store, strategy: .recoverOrInputOrder, source: .photos)
    }
}

/// Import one screen recording as a new capture: decode it into keyframes through the real
/// capture driver (sampled 30 fps — the validated cadence from Task 3), then stitch in capture order.
func importVideo(_ url: URL) async {
    importProgress = 0
    let diag = self.diag
    // A `@Sendable` sink that hops each fraction back to the main actor to update UI state.
    let sink: @Sendable (Double) -> Void = { [weak self] frac in
        Task { @MainActor in self?.importProgress = frac }
    }
    let decoded: Result<[CGImage], Error> = await Task.detached {
        do {
            var driver = ScrollCaptureDriver()
            let r = try await VideoKeyframeSource.decodeCommittedKeyframes(
                url: url, driver: &driver, targetFPS: 30, progress: sink
            )
            diag.log("importVideo: \(r.frames) frames, \(r.decodeFailures) decode failures, \(r.keyframes.count) keyframes")
            return .success(r.keyframes.map { $0.image })
        } catch {
            return .failure(error)
        }
    }.value
    importProgress = nil
    switch decoded {
    case .failure(let error):
        importError = error.localizedDescription
        diag.log("importVideo: decode FAILED: \(error.localizedDescription)")
    case .success(let images):
        await runImport { store in
            try MediaImporter.write(images: images, into: store, strategy: .inputOrder, source: .video)
        }
    }
}

/// Shared tail: run a `MediaImporter.write` off-main, then reload + assemble the new capture, or
/// record a user-visible error. `.notEnoughContent` maps to the friendly empty nudge.
private func runImport(_ body: @escaping @Sendable (SessionStore) throws -> UUID) async {
    let store = appStore
    let diag = self.diag
    let result: Result<UUID, Error> = await Task.detached {
        do { return .success(try body(store)) }
        catch { return .failure(error) }
    }.value
    switch result {
    case .success(let id):
        reload()
        await assemble(id)
    case .failure(let error):
        if case MediaImporter.ImportError.notEnoughContent = error {
            lastPickupWasEmpty = true
        } else {
            importError = error.localizedDescription
        }
        diag.log("import: FAILED: \(error.localizedDescription)")
    }
}
```

> The `sink` closure is `@Sendable` and hops each fraction back to the `@MainActor` model.
> `Task.detached` returning before all progress hops complete is fine — the final
> `importProgress = nil` after the `await` wins.

Also make `appStore` accessible to the detached closures: it is already a `let` on the actor; capture it into a local (`let store = appStore`) as shown, don't reference `self.appStore` inside `Task.detached`.

Add to `Capture` (in the struct, near the other computed props):

```swift
/// Scroll order was assumed from input order (pick-order fallback), not confidently recovered.
var orderAssumed: Bool { session.orderAssumed }
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:LongshotTests/MediaImportTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/Longshot/Core/LibraryModel.swift Longshot/LongshotTests/MediaImportTests.swift
git commit -m "feat(app): LibraryModel.importPhotos/importVideo + progress + Capture.orderAssumed

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: UI — three peer buttons, pickers, progress, error, badge

Wire the two picker front-ends into `CaptureStartView` as peers of Record, surface video progress + import errors, and badge assumed-order captures.

**Files:**
- Create: `Longshot/Longshot/Features/Capture/PhotoImportButton.swift`
- Create: `Longshot/Longshot/Features/Capture/VideoImportButton.swift`
- Modify: `Longshot/Longshot/Features/Capture/CaptureStartView.swift`
- Modify: `Longshot/Longshot/Features/Library/LibraryView.swift`

**Interfaces:**
- Consumes: `LibraryModel.importPhotos/importVideo/importProgress/importError` (Task 6), `Capture.orderAssumed` (Task 6). `CaptureStartView` gains a `model: LibraryModel` parameter (both call sites in `LibraryView` pass it).

- [ ] **Step 1: Photo picker front-end**

`PhotoImportButton.swift`:

```swift
import SwiftUI
import PhotosUI
import CoreGraphics
import ImageIO

/// "From Photos" entry: pick several overlapping screenshots; decode each to a CGImage and hand
/// them to the model in pick order. Requires at least two (a single image isn't a stitch).
struct PhotoImportButton: View {
    let model: LibraryModel
    var onStarted: () -> Void = {}
    @State private var selection: [PhotosPickerItem] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selection, maxSelectionCount: 20, matching: .images) {
                Label("From Photos", systemImage: "photo.on.rectangle.angled")
            }
            if let loadError { Text(loadError).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task { await load(items) }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        loadError = nil
        var images: [CGImage] = []
        for (i, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    loadError = "Couldn't read photo \(i + 1)."; return
                }
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                    loadError = "Photo \(i + 1) isn't a decodable image."; return
                }
                images.append(img)
            } catch {
                loadError = error.localizedDescription; return
            }
        }
        guard images.count >= 2 else { loadError = "Pick at least two overlapping screenshots."; return }
        selection = []
        onStarted()
        await model.importPhotos(images)
    }
}
```

- [ ] **Step 2: Video picker front-end**

`VideoImportButton.swift`:

```swift
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// A picked movie, copied out of the Photos sandbox into a temp URL for AVAssetReader.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            // Copy: the received file is a temporary the system reclaims after this closure.
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// "From Video" entry: pick one screen recording; hand its URL to the model, which decodes it
/// into keyframes and stitches in capture order.
struct VideoImportButton: View {
    let model: LibraryModel
    var onStarted: () -> Void = {}
    @State private var selection: PhotosPickerItem?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selection, matching: .videos) {
                Label("From Video", systemImage: "film")
            }
            if let loadError { Text(loadError).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        loadError = nil
        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                loadError = "Couldn't read that video."; return
            }
            selection = nil
            onStarted()
            await model.importVideo(movie.url)
        } catch {
            loadError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Three peer buttons in `CaptureStartView`**

Replace `CaptureStartView.swift` body to take `model` and show three peers:

```swift
import SwiftUI

/// The three ways to make a long screenshot: Record (live broadcast), From Video, From Photos.
struct CaptureStartView: View {
    let model: LibraryModel
    var showHelp: () -> Void
    var onStarted: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.tint.opacity(0.15)).frame(width: 96, height: 96)
                BroadcastPickerButton().frame(width: 80, height: 80)
            }
            Text("Record").font(.headline)
            Text("Pick Longshot, switch to the app you want, and scroll steadily.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)

            Divider().padding(.vertical, 4)

            VideoImportButton(model: model, onStarted: onStarted)
            PhotoImportButton(model: model, onStarted: onStarted)

            Button("How it works", action: showHelp).font(.footnote)
        }
        .padding()
    }
}
```

Update both `CaptureStartView(...)` call sites in `LibraryView.swift` to pass `model` and dismiss the sheet on start:
- Empty-library hero: `CaptureStartView(model: model, showHelp: { showOnboarding = true })`
- Capture sheet: `CaptureStartView(model: model, showHelp: { showOnboarding = true }, onStarted: { showCapture = false })`

- [ ] **Step 4: Progress + error surface, and the badge, in `LibraryView`**

In `LibraryView.body`, add a determinate progress overlay while a video decodes and an error alert. Add after the `.alert("Nothing to stitch", …)` modifier:

```swift
.overlay(alignment: .bottom) {
    if let p = model.importProgress {
        VStack(spacing: 6) {
            ProgressView(value: p) { Text("Reading video…") }
            Text("\(Int(p * 100))%").font(.caption).foregroundStyle(.secondary)
        }
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
    }
}
.alert("Import failed", isPresented: Binding(get: { model.importError != nil }, set: { if !$0 { model.clearImportError() } })) {
    Button("OK", role: .cancel) {}
} message: {
    Text(model.importError ?? "")
}
```

Add a tiny `clearImportError()` to `LibraryModel` (keeps `importError` `private(set)`):

```swift
func clearImportError() { importError = nil }
```

In `CaptureRow.statusLabel` (the `.ready` case `HStack`), add the badge before the "Ready" text:

```swift
if capture.orderAssumed { Label("Order assumed", systemImage: "arrow.up.arrow.down").foregroundStyle(.orange) }
```

- [ ] **Step 5: Build + run the app tests**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: BUILD SUCCEEDED; app + UI tests pass (no new UI tests required — model logic is covered in Tasks 4–6; this task is verified by a clean build and the existing suite staying green).

- [ ] **Step 6: Commit**

```bash
cd /Users/lili/Developer/Longshot
git add Longshot/Longshot/Features/Capture/PhotoImportButton.swift Longshot/Longshot/Features/Capture/VideoImportButton.swift Longshot/Longshot/Features/Capture/CaptureStartView.swift Longshot/Longshot/Features/Library/LibraryView.swift Longshot/Longshot/Core/LibraryModel.swift
git commit -m "feat(app): From Video / From Photos entries — pickers, progress, error, order badge

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> **Xcode project membership:** the three new app files (`MediaImporter.swift`, `PhotoImportButton.swift`, `VideoImportButton.swift`) and the new test (`MediaImportTests.swift`) must belong to the right targets. This project uses the modern file-system-synchronized group layout (files under `Longshot/Longshot/**` are picked up automatically), so placing them in the directories above should suffice. If a build reports "cannot find 'MediaImporter' in scope", open the project in Xcode once and confirm each new source is in the **Longshot** app target and the test is in **LongshotTests**.

---

### Task 8: Whole-project verification

**Files:** none (verification only).

- [ ] **Step 1: Full StitchKit suite**

Run: `cd /Users/lili/Developer/Longshot/Longshot/StitchKit && swift test`
Expected: all suites pass; the one pre-existing `withKnownIssue` xfail in `CaptureVideoTests` remains an expected known-issue (not a failure). Paste the summary line.

- [ ] **Step 2: App + extension build**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED (app + LongshotBroadcast), no warnings in new code.

- [ ] **Step 3: App + UI tests**

Run: `xcodebuild -project /Users/lili/Developer/Longshot/Longshot/Longshot.xcodeproj -scheme Longshot -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: TEST SUCCEEDED — `MediaImportTests`, `BatchAssemblyTests`, `BroadcastImportTests`, launch tests.

- [ ] **Step 4: Manual smoke (device or sim with media)**

Confirm on a simulator/device that the empty Library shows three peers (Record / From Video / From Photos), that picking ≥2 screenshots produces a Ready capture (and a shuffled/unrelated set shows the "Order assumed" badge), and that picking a scroll screen recording shows the progress bar then a Ready capture. Note results in the progress ledger.

- [ ] **Step 5: Update the progress ledger**

Append a "Video & Photo Import (spec 2026-07-24)" section to `.superpowers/sdd/progress.md` summarizing tasks, commits, and verification evidence.

```bash
cd /Users/lili/Developer/Longshot
git add .superpowers/sdd/progress.md
git commit -m "docs(log): video & photo import — verification evidence

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes

- **Spec coverage:** Three peer buttons (Task 7) ✓; From Photos recover+pick-order fallback+badge (Tasks 1,4,6,7) ✓; From Video decode+throttle+capture-order trust (Tasks 3,4,5,6) ✓; shared `MediaImporter` into existing pipeline (Task 5) ✓; `resolveGeometry` shared `orderTrust`/strategy (Task 4) ✓; timestamp-throttle + fixture re-validation gate (Task 3) ✓; error handling / no-silent-swallow (Tasks 5,6,7) ✓; processing/progress/empty states (Tasks 6,7) ✓; testing tiers (all tasks) ✓.
- **Deviation from spec §Testing:** photo import is tested with **synthetic** sliced images (Task 4/5/6) rather than a bundled screenshot fixture set — matches the established `BatchAssemblyTests`/`TestImages` pattern (deterministic, no new bundle resources) and is CI-friendlier. The real 3-image `Example` fixture already covers `assumingOrder` in StitchKit (Task 1).
- **`targetFPS = 30`** is the validated cadence (Task 3 arbitrated against the fixture: 12 and 20 fps produced out-of-band / degenerate keyframe sets by interacting with the deferred image-heavy matcher limitation; 30 fps reproduces the full-rate 5-keyframe set with ~2.7x less profiling). Kept in sync between `LibraryModel.importVideo` and the `throttledCadenceKeepsKeyframesHealthy` test.
- **Type consistency:** `resolveGeometry(_:in:strategy:stitcher:)`, `MediaImporter.write(images:into:strategy:source:)`, `OrderStrategy.{recover,recoverOrInputOrder,inputOrder}`, `VideoKeyframeSource.decodeCommittedKeyframes(url:driver:targetFPS:progress:)`, `StitchSession.orderAssumed`, `Capture.orderAssumed`, `LibraryModel.{importPhotos,importVideo,importProgress,importError,clearImportError}` used consistently across tasks.
