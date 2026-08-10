# One-Shot Capture Shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Seamly's test-harness UI with a one-shot product shell — record, get your long screenshot, save it, done.

**Architecture:** A single `NavigationStack` whose path is driven by the model rather than by tapping list rows: when an import finishes assembling, the model sets `pendingResult` and the shell pushes the result. All of `StitchKit` and all of `Seamly/Core/` survive; the work is confined to `Seamly/Features/` plus a new `Seamly/DesignSystem/`. The design system is *semantic*, not stylistic — one enum that owns the only translation from pipeline facts into user-facing language, plus two views.

**Tech Stack:** SwiftUI (iOS 26), Swift 6 language mode, Swift Testing, Core Graphics, PhotosUI. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-10-one-shot-capture-shell-design.md`

## Global Constraints

- **Deployment target is iOS 26.0.** Liquid Glass and all iOS 26 SwiftUI APIs are available.
- **Purely native.** System materials, SF Symbols, Dynamic Type, standard controls. **Do not create a spacing/radius/color token layer** — that is an explicit design decision, not an oversight. Use system values directly.
- **No pipeline vocabulary in user-facing copy.** The words "seam", "chrome", "segment", "confidence", "keyframe", "offset", and "profile" must never appear in a string a user can read. `CaptureCondition` is the only place pipeline facts become English.
- **Never swallow errors.** No bare `try?` that drops an error, no empty `catch {}`, no `?? someDefault` masking. Propagate with `throws`, or handle at the boundary (surface it, or log via `Diagnostics`). See `CLAUDE.md`.
- **No changes to `StitchKit`.** No behavioural change to capture, stitching, order recovery, or chrome measurement. No `StitchSession` schema change. The one permitted exception is a comment-only edit in Task 9.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) — not XCTest, except `SeamlyUITests` where `XCUIApplication` requires it.
- **Target membership follows the folder.** The project uses Xcode synchronized folder groups, so creating or deleting a file under `Seamly/Seamly/` needs **no `.pbxproj` edit**. A file under `Seamly/Seamly/` is app-only.
- **`#expect` over `contains(where:)` / `allSatisfy` will not compile** — the macro loses the `rethrows` conversion. Bind to a local first.
- Build check: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' build`
- App test check: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test`

## File Structure

**Create:**

| File | Responsibility |
|---|---|
| `Seamly/Seamly/DesignSystem/CaptureCondition.swift` | The only translation from pipeline facts to user-facing language. Pure values, no UI, no main actor. |
| `Seamly/Seamly/DesignSystem/ZoomState.swift` | Pinch-zoom accumulation maths. Pure, testable. |
| `Seamly/Seamly/DesignSystem/CaptureCanvas.swift` | Scrollable/zoomable proxy viewer. Thin view over `ZoomState`. |
| `Seamly/Seamly/DesignSystem/ConditionNotice.swift` | Renders a `CaptureCondition` inline, natively. |
| `Seamly/Seamly/Features/Home/HomeView.swift` | Record-first home + recents strip. |
| `Seamly/Seamly/Features/Result/ResultView.swift` | The finished capture, Save to Photos primary. |
| `Seamly/Seamly/Features/Result/OutcomeViews.swift` | Processing / NothingToStitch / Failure destinations. |
| `Seamly/SeamlyTests/CaptureConditionTests.swift` | Table-driven verdict + ranking tests. |
| `Seamly/SeamlyTests/ZoomStateTests.swift` | Zoom accumulation and clamping. |

**Modify:** `Core/LibraryModel.swift` (renamed to `Core/CaptureModel.swift`), `ContentView.swift`, `Features/Capture/PhotoImportButton.swift`, `Features/Capture/VideoImportButton.swift`, `Features/Onboarding/OnboardingView.swift`, `SeamlyBroadcast/SampleHandler.swift` (comment only), and the four `SeamlyTests` files that name `LibraryModel`.

**Delete:** `Features/Library/LibraryView.swift`, `Features/Preview/PreviewView.swift`, `Features/Preview/EditView.swift`, `Features/Export/ExportView.swift`, `Features/Capture/CaptureStartView.swift`.

**Task order keeps `main` building at every commit.** Additive work first (Tasks 1–4), then the model change with its call sites updated in the same task (Task 5), then new screens (6–7), then the switchover and deletion (8), then copy and tests (9–10).

---

### Task 1: `CaptureCondition` — the semantic core

The highest-value piece and the most testable. It is a pure function over plain values: no `Capture`, no main actor, no disk. This is deliberate — it is the one type that can silently tell a user something false about their capture, and a wrong fact-to-language mapping is invisible in code review.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/CaptureCondition.swift`
- Test: `Seamly/SeamlyTests/CaptureConditionTests.swift`

**Interfaces:**
- Consumes: `StitchKit.StitchSession` (read-only, for the `CaptureFacts` initialiser).
- Produces: `CaptureFacts`, `Imperfection`, `Imperfection.Kind`, `Severity`, `CaptureCondition`, `CaptureCondition.init(ready:)`, `CaptureFacts.init(_ session: StitchSession)`.

- [ ] **Step 1: Write the failing tests**

Create `Seamly/SeamlyTests/CaptureConditionTests.swift`:

```swift
import Testing
@testable import Seamly

/// `CaptureCondition` is the only place pipeline facts become English. A wrong mapping here
/// is invisible in review and lands in front of a user, so every combination is pinned.
struct CaptureConditionTests {

    @Test func aCleanCaptureHasNoImperfections() {
        #expect(CaptureCondition(ready: CaptureFacts()) == .clean)
    }

    @Test func gapsAreReportedWithAPieceCount() throws {
        let condition = CaptureCondition(ready: CaptureFacts(segmentBreaks: 2))
        guard case .imperfect(let primary, let all) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.kind == .gaps)
        #expect(all.count == 1)
        // 2 breaks == 3 pieces.
        #expect(primary.headline == "Joined from 3 pieces")
    }

    @Test func aSingleFlaggedSeamReadsAsSingular() throws {
        let condition = CaptureCondition(ready: CaptureFacts(flaggedSeams: 1))
        guard case .imperfect(let primary, _) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.kind == .flaggedJoins)
        #expect(primary.detail == "1 join might be slightly off.")
    }

    @Test func severalFlaggedSeamsReadAsPlural() throws {
        let condition = CaptureCondition(ready: CaptureFacts(flaggedSeams: 3))
        guard case .imperfect(let primary, _) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.detail == "3 joins might be slightly off.")
    }

    /// Ranking is the whole point of `primary`: the user sees one line, so it must be the
    /// one that matters most. Missing content outranks a cosmetic misalignment.
    @Test func theMostSevereImperfectionIsPrimary() throws {
        let facts = CaptureFacts(
            segmentBreaks: 1,
            flaggedSeams: 5,
            unresolvedChrome: 2,
            isIncomplete: true,
            orderAssumed: true
        )
        guard case .imperfect(let primary, let all) = CaptureCondition(ready: facts) else {
            Issue.record("expected imperfect"); return
        }
        #expect(primary.kind == .endedEarly)
        #expect(all.count == 5)
        #expect(all.map(\.kind) == [.endedEarly, .gaps, .unresolvedBars, .flaggedJoins, .orderAssumed])
    }

    /// Re-recording is the only fix for missing content, but it will not help a join that is
    /// merely misaligned — that is what guided repair (Spec 2) is for. The result screen uses
    /// this to decide whether to push "Record again".
    @Test func onlyMissingContentRecommendsRecordingAgain() {
        #expect(CaptureCondition(ready: CaptureFacts(isIncomplete: true)).recommendsRecordingAgain)
        #expect(CaptureCondition(ready: CaptureFacts(segmentBreaks: 1)).recommendsRecordingAgain)
        #expect(!CaptureCondition(ready: CaptureFacts(flaggedSeams: 1)).recommendsRecordingAgain)
        #expect(!CaptureCondition(ready: CaptureFacts(unresolvedChrome: 1)).recommendsRecordingAgain)
        #expect(!CaptureCondition(ready: CaptureFacts()).recommendsRecordingAgain)
    }

    /// The hard rule from the spec: pipeline vocabulary never reaches a user.
    @Test func noUserFacingStringLeaksPipelineVocabulary() {
        let banned = ["seam", "chrome", "segment", "confidence", "keyframe", "offset", "profile"]
        let facts = CaptureFacts(
            segmentBreaks: 2, flaggedSeams: 2, unresolvedChrome: 2,
            isIncomplete: true, orderAssumed: true
        )
        guard case .imperfect(_, let all) = CaptureCondition(ready: facts) else {
            Issue.record("expected imperfect"); return
        }
        for imperfection in all {
            let text = (imperfection.headline + " " + imperfection.detail).lowercased()
            for word in banned {
                #expect(!text.contains(word), "\(imperfection.kind) leaks \"\(word)\": \(text)")
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SeamlyTests/CaptureConditionTests`

Expected: FAIL to compile — `cannot find 'CaptureCondition' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Seamly/Seamly/DesignSystem/CaptureCondition.swift`:

```swift
import Foundation
import StitchKit

/// The facts a finished capture can exhibit, reduced to plain values.
///
/// Deliberately *not* built from `Capture`: keeping this a plain struct keeps the verdict
/// below a pure function — off the main actor, off disk, and table-testable across every
/// combination.
struct CaptureFacts: Equatable {
    var segmentBreaks: Int = 0
    var flaggedSeams: Int = 0
    var unresolvedChrome: Int = 0
    var isIncomplete: Bool = false
    var orderAssumed: Bool = false
}

extension CaptureFacts {
    /// Read the facts off a stored session. This is the only place that touches `StitchKit`.
    init(_ session: StitchSession) {
        self.init(
            segmentBreaks: session.segmentBreaks.count,
            flaggedSeams: session.seams.filter(\.isLowConfidence).count,
            unresolvedChrome: session.keyframes.filter {
                !session.chromeEdgesNeedingReview(for: $0).isEmpty
            }.count,
            isIncomplete: session.status == .recording,
            orderAssumed: session.orderAssumed
        )
    }
}

/// How loudly to present an observation. Two levels only — a longer scale invites the
/// badge-dumping the harness UI did.
enum Severity {
    case guidance
    case warning
}

/// One plain-language observation about a capture.
struct Imperfection: Equatable, Identifiable {
    /// Declaration order **is** the ranking, most important first. The user sees one line,
    /// so this decides which. Missing content outranks cosmetic misalignment; an ordering
    /// note is the quietest thing we can say.
    enum Kind: Int, Comparable, CaseIterable {
        case endedEarly
        case gaps
        case unresolvedBars
        case flaggedJoins
        case orderAssumed

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: Kind
    let headline: String
    let detail: String
    let severity: Severity
    /// True when re-recording is the only available fix. False when the content is all
    /// present and merely imperfectly joined — guided repair (Spec 2) is the real answer
    /// there, and telling the user to record again would waste their time.
    let recommendsRecordingAgain: Bool

    var id: Kind { kind }
}

/// The single user-facing verdict on a capture. This type owns the *only* translation from
/// pipeline facts into language a user reads — "seam", "chrome", "segment", and "confidence"
/// never appear on the far side of it.
enum CaptureCondition: Equatable {
    case stitching
    case clean
    case imperfect(primary: Imperfection, all: [Imperfection])
    case nothingToStitch
    case failed(String)

    /// The verdict for a capture that stitched successfully. The other cases are decided by
    /// the caller from the capture's phase and import outcome.
    init(ready facts: CaptureFacts) {
        let all = Imperfection.Kind.allCases.compactMap { Imperfection(kind: $0, facts: facts) }
        guard let primary = all.first else { self = .clean; return }
        self = .imperfect(primary: primary, all: all)
    }

    /// Whether the result screen should offer "Record again" as a prominent action.
    var recommendsRecordingAgain: Bool {
        switch self {
        case .imperfect(let primary, _): primary.recommendsRecordingAgain
        case .nothingToStitch, .failed: true
        case .clean, .stitching: false
        }
    }
}

private extension Imperfection {
    /// Build the observation for one kind, or `nil` if the facts do not exhibit it.
    init?(kind: Kind, facts: CaptureFacts) {
        switch kind {
        case .endedEarly:
            guard facts.isIncomplete else { return nil }
            self.init(
                kind: kind,
                headline: "The recording ended early",
                detail: "This is everything that was saved before it stopped.",
                severity: .warning,
                recommendsRecordingAgain: true
            )

        case .gaps:
            guard facts.segmentBreaks > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "Joined from \(facts.segmentBreaks + 1) pieces",
                detail: "You scrolled too fast in places, so this couldn't be made continuous.",
                severity: .warning,
                recommendsRecordingAgain: true
            )

        case .unresolvedBars:
            guard facts.unresolvedChrome > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "Some bars may repeat",
                detail: "Couldn't tell which parts were the app's own bars on "
                    + Self.count(facts.unresolvedChrome, "screen", "screens") + ".",
                severity: .guidance,
                recommendsRecordingAgain: false
            )

        case .flaggedJoins:
            guard facts.flaggedSeams > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "A join may not line up",
                detail: Self.count(facts.flaggedSeams, "join", "joins") + " might be slightly off.",
                severity: .guidance,
                recommendsRecordingAgain: false
            )

        case .orderAssumed:
            guard facts.orderAssumed else { return nil }
            self.init(
                kind: kind,
                headline: "Kept in the order they were taken",
                detail: "These couldn't be put in order by their content, so the original order was used.",
                severity: .guidance,
                recommendsRecordingAgain: false
            )
        }
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SeamlyTests/CaptureConditionTests`

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/CaptureCondition.swift Seamly/SeamlyTests/CaptureConditionTests.swift
git commit -m "feat(app): add CaptureCondition, the one pipeline-to-English translation"
```

---

### Task 2: `ZoomState` — fix the zoom-does-not-accumulate bug

`PreviewView.swift:61` assigns `zoom = max(1, $0.magnification)`, but `MagnifyGesture.magnification` is relative to *gesture start*. Zoom to 3×, lift your fingers, pinch again, and the image snaps back to ~1×. Extracting the maths makes the bug testable instead of a thing you have to notice by hand.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/ZoomState.swift`
- Test: `Seamly/SeamlyTests/ZoomStateTests.swift`

**Interfaces:**
- Produces: `ZoomState`, `.scale`, `.update(magnification:)`, `.end()`, `.reset()`, `ZoomState.minScale`, `ZoomState.maxScale`.

- [ ] **Step 1: Write the failing tests**

Create `Seamly/SeamlyTests/ZoomStateTests.swift`:

```swift
import Testing
import CoreGraphics
@testable import Seamly

/// `MagnifyGesture.magnification` is relative to the start of the *current* gesture. The
/// harness UI assigned it directly, so lifting your fingers reset the zoom. These pin the
/// accumulating behaviour a tall-image viewer needs.
struct ZoomStateTests {

    @Test func startsUnzoomed() {
        #expect(ZoomState().scale == 1)
    }

    @Test func tracksMagnificationDuringAGesture() {
        var zoom = ZoomState()
        zoom.update(magnification: 2)
        #expect(zoom.scale == 2)
    }

    /// The regression: a second gesture must build on the first, not replace it.
    @Test func accumulatesAcrossGestures() {
        var zoom = ZoomState()
        zoom.update(magnification: 3)
        zoom.end()
        #expect(zoom.scale == 3)

        zoom.update(magnification: 1.5)
        #expect(zoom.scale == 4.5)
        zoom.end()
        #expect(zoom.scale == 4.5)
    }

    @Test func clampsToMaximum() {
        var zoom = ZoomState()
        zoom.update(magnification: 100)
        #expect(zoom.scale == ZoomState.maxScale)
        zoom.end()
        zoom.update(magnification: 100)
        #expect(zoom.scale == ZoomState.maxScale)
    }

    /// Pinching in past 1× must not let the image shrink below fit, and must not bank a
    /// sub-1 committed scale that a later gesture would multiply from.
    @Test func clampsToMinimum() {
        var zoom = ZoomState()
        zoom.update(magnification: 0.1)
        #expect(zoom.scale == ZoomState.minScale)
        zoom.end()
        zoom.update(magnification: 2)
        #expect(zoom.scale == 2)
    }

    @Test func resetReturnsToFit() {
        var zoom = ZoomState()
        zoom.update(magnification: 4)
        zoom.end()
        zoom.reset()
        #expect(zoom.scale == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SeamlyTests/ZoomStateTests`

Expected: FAIL to compile — `cannot find 'ZoomState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Seamly/Seamly/DesignSystem/ZoomState.swift`:

```swift
import CoreGraphics

/// Pinch-zoom that accumulates across gestures.
///
/// `MagnifyGesture.magnification` is relative to the *start of the current gesture*, so
/// assigning it to the scale directly resets the zoom every time the user lifts their
/// fingers. The committed scale is multiplied by the in-flight magnification instead, and
/// only the clamped product is banked on `end()` — otherwise a hard pinch would store a
/// scale far outside the range and the next gesture would start from it.
struct ZoomState: Equatable {
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 6

    private var committed: CGFloat = ZoomState.minScale
    private var gesture: CGFloat = 1

    var scale: CGFloat { Self.clamp(committed * gesture) }

    mutating func update(magnification: CGFloat) {
        gesture = magnification
    }

    mutating func end() {
        committed = Self.clamp(committed * gesture)
        gesture = 1
    }

    mutating func reset() {
        committed = Self.minScale
        gesture = 1
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SeamlyTests/ZoomStateTests`

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Seamly/Seamly/DesignSystem/ZoomState.swift Seamly/SeamlyTests/ZoomStateTests.swift
git commit -m "fix(app): make pinch zoom accumulate across gestures"
```

---

### Task 3: `CaptureCanvas` and `ConditionNotice`

Two small views, committed together: neither is unit-testable on its own, both are verified by build plus `#Preview`, and they are the entire view half of the design system.

**Files:**
- Create: `Seamly/Seamly/DesignSystem/CaptureCanvas.swift`
- Create: `Seamly/Seamly/DesignSystem/ConditionNotice.swift`

**Interfaces:**
- Consumes: `ZoomState` (Task 2), `CaptureCondition` / `Imperfection` / `Severity` (Task 1).
- Produces: `CaptureCanvas(proxy:)`, `ConditionNotice(condition:)`.

- [ ] **Step 1: Write `CaptureCanvas`**

Create `Seamly/Seamly/DesignSystem/CaptureCanvas.swift`:

```swift
import SwiftUI
import CoreGraphics

/// The scrollable, zoomable viewer for a stitched capture.
///
/// Takes a **display proxy**, never a full-resolution composite: a GPU texture tops out around
/// 16,384 px per side and a full-res stitch routinely exceeds that, so binding one to an
/// `Image` fails to render. `StitchAssembler.makeProxy` caps the height at 4096 px.
struct CaptureCanvas: View {
    let proxy: CGImage

    @State private var zoom = ZoomState()

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Image(decorative: proxy, scale: 1)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoom.scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { zoom.update(magnification: $0.magnification) }
                        .onEnded { _ in withAnimation(.snappy) { zoom.end() } }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) { zoom.reset() }
                }
                .accessibilityLabel("Stitched screenshot")
                .accessibilityHint("Pinch to zoom. Double-tap to fit.")
        }
    }
}
```

- [ ] **Step 2: Write `ConditionNotice`**

Create `Seamly/Seamly/DesignSystem/ConditionNotice.swift`:

```swift
import SwiftUI

/// Renders a `CaptureCondition` inline. One implementation and one severity scale, so the
/// same underlying state can never read two different ways in two different places — which
/// is exactly what the harness UI did.
///
/// Shows the **primary** observation only. A disclosure reveals the rest; presenting four
/// badges to someone who wanted a screenshot is what made the old UI read as a tool.
struct ConditionNotice: View {
    let condition: CaptureCondition

    @State private var expanded = false

    var body: some View {
        switch condition {
        case .clean, .stitching:
            EmptyView()
        case .imperfect(let primary, let all):
            imperfect(primary: primary, all: all)
        case .nothingToStitch:
            row(
                symbol: "arrow.up.and.down",
                headline: "Nothing to stitch",
                detail: "This recording didn't scroll, so there was nothing to join together.",
                severity: .guidance
            )
        case .failed(let message):
            row(
                symbol: "exclamationmark.triangle",
                headline: "Couldn't finish this one",
                detail: message,
                severity: .warning
            )
        }
    }

    @ViewBuilder
    private func imperfect(primary: Imperfection, all: [Imperfection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                symbol: symbol(for: primary.kind),
                headline: primary.headline,
                detail: primary.detail,
                severity: primary.severity
            )
            if all.count > 1 {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(all.dropFirst()) { item in
                            row(
                                symbol: symbol(for: item.kind),
                                headline: item.headline,
                                detail: item.detail,
                                severity: item.severity
                            )
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("\(all.count - 1) more").font(.caption)
                }
            }
        }
    }

    private func row(symbol: String, headline: String, detail: String, severity: Severity) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(severity == .warning ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func symbol(for kind: Imperfection.Kind) -> String {
        switch kind {
        case .endedEarly: "exclamationmark.circle"
        case .gaps: "rectangle.split.1x2"
        case .unresolvedBars: "rectangle.dashed"
        case .flaggedJoins: "arrow.left.and.right"
        case .orderAssumed: "arrow.up.arrow.down"
        }
    }
}

#Preview("Imperfect") {
    ConditionNotice(
        condition: CaptureCondition(
            ready: CaptureFacts(segmentBreaks: 2, flaggedSeams: 1, orderAssumed: true)
        )
    )
    .padding()
}

#Preview("Nothing to stitch") {
    ConditionNotice(condition: .nothingToStitch).padding()
}
```

- [ ] **Step 3: Build to verify both compile**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Seamly/Seamly/DesignSystem/CaptureCanvas.swift Seamly/Seamly/DesignSystem/ConditionNotice.swift
git commit -m "feat(app): add CaptureCanvas and ConditionNotice"
```

---

### Task 4: `CaptureModel` — rename, `pendingResult`, throwing export

`LibraryModel` is misnamed rather than misdesigned: only `captures` and `delete` are library concepts, and the other ~300 lines are capture lifecycle that survives untouched. This task renames it, adds the navigation trigger, and stops export masking its errors.

**Files:**
- Modify → rename: `Seamly/Seamly/Core/LibraryModel.swift` → `Seamly/Seamly/Core/CaptureModel.swift`
- Modify: `Seamly/Seamly/Features/Capture/PhotoImportButton.swift:9`, `Seamly/Seamly/Features/Capture/VideoImportButton.swift:25`, `Seamly/Seamly/Features/Capture/CaptureStartView.swift:5`, `Seamly/Seamly/Features/Library/LibraryView.swift:7`, `Seamly/Seamly/Features/Preview/PreviewView.swift:9`, `Seamly/Seamly/Features/Preview/EditView.swift:9`, `Seamly/Seamly/Features/Export/ExportView.swift:9`
- Modify (tests): every `SeamlyTests` file naming `LibraryModel`

**Interfaces:**
- Produces: `CaptureModel` (replacing `LibraryModel`), `CaptureModel.pendingResult: UUID?`, `CaptureModel.consumePendingResult()`, `CaptureModel.fullComposite(_:) async throws -> CGImage`, `CaptureModel.exportPDF(_:) async throws -> URL`.

- [ ] **Step 1: Rename the type and its file**

```bash
git mv Seamly/Seamly/Core/LibraryModel.swift Seamly/Seamly/Core/CaptureModel.swift
```

Then rename every occurrence of `LibraryModel` to `CaptureModel` across the app and tests:

```bash
grep -rl 'LibraryModel' Seamly/Seamly Seamly/SeamlyTests \
  | xargs sed -i '' 's/LibraryModel/CaptureModel/g'
```

Update the type's doc comment in `Core/CaptureModel.swift` — it currently opens "The Library is the app's home surface and the source of truth for captures." Replace with:

```swift
/// The source of truth for captures. Scans the App Group on launch and foreground, imports
/// finished sessions into app storage, drives assembly, and composites for export.
///
/// Named for what it owns rather than where it is shown: the app is one-shot, so there is no
/// library surface. `CaptureStore` was avoided deliberately — it would read as a sibling of
/// `StitchKit.SessionStore`, which it is not. `@MainActor` (UI state) with heavy work
/// delegated off-actor.
```

- [ ] **Step 2: Verify the rename builds and the existing tests still pass**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test`

Expected: BUILD SUCCEEDED and all existing `SeamlyTests` pass. A pure rename must not change behaviour.

- [ ] **Step 3: Commit the rename on its own**

A rename mixed with behaviour changes is unreviewable. Keep it separate.

```bash
git add -u
git commit -m "refactor(app): rename LibraryModel to CaptureModel"
```

- [ ] **Step 4: Add `pendingResult` and make export throw**

In `Seamly/Seamly/Core/CaptureModel.swift`, add the navigation trigger next to the other published state (beside `importError`):

```swift
    /// Set when an imported capture has finished assembling, so the shell can navigate
    /// straight to it. **Must** be cleared via `consumePendingResult()` once consumed —
    /// otherwise navigating back re-pushes the same destination and the user is trapped.
    private(set) var pendingResult: UUID?

    func consumePendingResult() {
        pendingResult = nil
    }
```

Set it at the end of `assemble(_:)` on **both** branches:

```swift
        case .success(let proxy):
            captures[index].proxy = proxy
            captures[index].phase = .ready
            pendingResult = id
        case .failure(let error):
            diag.log("assemble: \(id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
            captures[index].phase = .failed(error.localizedDescription)
            // Navigate on failure too. Setting this only on success is how "coming back from
            // a broadcast does nothing" ships: the capture fails, nothing is pushed, and the
            // user is left on home with no indication anything happened. See DECISIONS.md [B4].
            pendingResult = id
```

Replace `fullComposite` and `exportPDF` with throwing versions. Both currently log the real cause to `Diagnostics` and hand back `nil`, which `ExportView` turns into `"Nothing to export."` — the masking-fallback pattern `CLAUDE.md` prohibits:

```swift
    enum CaptureError: LocalizedError {
        case notFound
        var errorDescription: String? {
            switch self {
            case .notFound: "That capture is no longer available."
            }
        }
    }

    /// Composite the full-resolution image on demand (for export, not display).
    func fullComposite(_ id: UUID) async throws -> CGImage {
        guard let capture = captures.first(where: { $0.id == id }) else { throw CaptureError.notFound }
        let session = capture.session, folder = capture.folder
        let diag = self.diag
        let result: Result<CGImage, Error> = await Task.detached {
            do { return .success(try StitchAssembler.composite(session, in: folder)) }
            catch { return .failure(error) }
        }.value
        // Log *and* rethrow: Diagnostics is the only window into a device failure, but the
        // user must still be told what actually went wrong.
        if case .failure(let error) = result {
            diag.log("fullComposite: \(session.id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
        }
        return try result.get()
    }

    /// Render the capture to a PDF in a temp file for sharing.
    func exportPDF(_ id: UUID) async throws -> URL {
        guard let capture = captures.first(where: { $0.id == id }) else { throw CaptureError.notFound }
        let session = capture.session, folder = capture.folder
        let diag = self.diag
        let result: Result<URL, Error> = await Task.detached {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Seamly-\(session.id.uuidString).pdf")
            do {
                try StitchAssembler.writePDF(session, in: folder, to: url)
                return .success(url)
            } catch {
                return .failure(error)
            }
        }.value
        if case .failure(let error) = result {
            diag.log("exportPDF: \(session.id.uuidString.prefix(8)) FAILED: \(error.localizedDescription)")
        }
        return try result.get()
    }
```

- [ ] **Step 5: Update `ExportView` to the throwing signatures**

`ExportView` is deleted in Task 8, but `main` must build now. In `Seamly/Seamly/Features/Export/ExportView.swift`, change each of the four action methods to catch and surface the real error instead of the generic string. For example `save()`:

```swift
    private func save() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let image = try await model.fullComposite(captureID)
                try await Exporter.saveToPhotos(image)
                status = "Saved to Photos."
            } catch {
                status = error.localizedDescription
            }
        }
    }
```

And the other three:

```swift
    private func prepareImage() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let image = try await model.fullComposite(captureID)
                pngURL = try Exporter.pngURL(image, name: "Seamly-\(captureID.uuidString)")
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func preparePDF() {
        busy = true
        Task {
            defer { busy = false }
            do { pdfURL = try await model.exportPDF(captureID) }
            catch { status = error.localizedDescription }
        }
    }

    private func copy() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let image = try await model.fullComposite(captureID)
                Exporter.copyToPasteboard(image)
                status = "Copied."
            } catch {
                status = error.localizedDescription
            }
        }
    }
```

- [ ] **Step 6: Run the full app test suite**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test`

Expected: BUILD SUCCEEDED, all `SeamlyTests` pass.

- [ ] **Step 7: Commit**

```bash
git add -u
git commit -m "feat(app): add pendingResult and stop export masking its errors"
```

---

### Task 5: Result screen

The most important surface in a one-shot app: what you came back for. Save to Photos is the primary action; everything else is secondary.

**Files:**
- Create: `Seamly/Seamly/Features/Result/ResultView.swift`

**Interfaces:**
- Consumes: `CaptureModel` (Task 4), `CaptureCanvas` (Task 3), `ConditionNotice` (Task 3), `CaptureCondition`/`CaptureFacts` (Task 1), `Exporter`.
- Produces: `ResultView(captureID:model:onRecordAgain:)`.

- [ ] **Step 1: Write the view**

Create `Seamly/Seamly/Features/Result/ResultView.swift`:

```swift
import SwiftUI
import StitchKit

/// The finished capture. In a one-shot app this is the destination, not a waypoint: saving
/// is the primary action, and once saved the user is offered a way to clear it out.
struct ResultView: View {
    let captureID: UUID
    let model: CaptureModel
    var onRecordAgain: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var status: String?
    @State private var busy = false
    @State private var savedToPhotos = false

    private var capture: Capture? { model.captures.first { $0.id == captureID } }

    private var condition: CaptureCondition {
        guard let capture else { return .failed("That capture is no longer available.") }
        switch capture.phase {
        case .processing: return .stitching
        case .failed(let message): return .failed(message)
        case .ready: return CaptureCondition(ready: CaptureFacts(capture.session))
        }
    }

    var body: some View {
        Group {
            switch condition {
            case .stitching:
                ProcessingView(progress: model.importProgress)
            case .failed(let message):
                CaptureFailureView(message: message, onRecordAgain: onRecordAgain)
            case .clean, .imperfect, .nothingToStitch:
                if let proxy = capture?.proxy {
                    VStack(spacing: 0) {
                        ConditionNotice(condition: condition)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        CaptureCanvas(proxy: proxy)
                    }
                } else {
                    ContentUnavailableView(
                        "Capture removed",
                        systemImage: "photo.badge.exclamationmark"
                    )
                }
            }
        }
        .navigationTitle("Your screenshot")
        .navigationBarTitleDisplayMode(.inline)
        // Export actions are meaningless while stitching or after a failure — there is
        // nothing to export — so the bar only appears once there is an image.
        .safeAreaInset(edge: .bottom) {
            if capture?.proxy != nil { actions }
        }
        .alert(
            "Export",
            isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(status ?? "")
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if busy { ProgressView() }

            Button {
                save()
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || capture?.proxy == nil)

            HStack(spacing: 16) {
                if let pngURL {
                    ShareLink(item: pngURL) { Label("Share", systemImage: "square.and.arrow.up") }
                } else {
                    Button { prepareImage() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button { copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label("PDF", systemImage: "doc.richtext") }
                } else {
                    Button { preparePDF() } label: { Label("PDF", systemImage: "doc.richtext") }
                }
            }
            .font(.subheadline)
            .disabled(busy)

            // Re-recording is offered only when it is actually the fix. A merely misaligned
            // join is not improved by recording again — that is what guided repair is for.
            if condition.recommendsRecordingAgain {
                Button("Record again", action: onRecordAgain).font(.subheadline)
            }

            if savedToPhotos {
                Button("Done — remove from Seamly", role: .destructive) {
                    model.delete(captureID)
                    dismiss()
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(.bar)
    }

    private func save() {
        run {
            let image = try await model.fullComposite(captureID)
            try await Exporter.saveToPhotos(image)
            savedToPhotos = true
            status = "Saved to Photos."
        }
    }

    private func prepareImage() {
        run {
            let image = try await model.fullComposite(captureID)
            pngURL = try Exporter.pngURL(image, name: "Seamly-\(captureID.uuidString)")
        }
    }

    private func preparePDF() {
        run { pdfURL = try await model.exportPDF(captureID) }
    }

    private func copy() {
        run {
            let image = try await model.fullComposite(captureID)
            Exporter.copyToPasteboard(image)
            status = "Copied."
        }
    }

    /// Shared tail: every export path surfaces its real error rather than a generic string.
    private func run(_ body: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await body() }
            catch { status = error.localizedDescription }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Seamly/Seamly/Features/Result/ResultView.swift
git commit -m "feat(app): add the one-shot result screen"
```

---

### Task 6: Processing, nothing-to-stitch, and failure destinations

Three small sibling views that change together.

**Files:**
- Create: `Seamly/Seamly/Features/Result/OutcomeViews.swift`

**Interfaces:**
- Consumes: `ConditionNotice` (Task 3).
- Produces: `ProcessingView(progress:)`, `NothingToStitchView(onRecordAgain:)`, `CaptureFailureView(message:onRecordAgain:)`.

- [ ] **Step 1: Write the views**

Create `Seamly/Seamly/Features/Result/OutcomeViews.swift`:

```swift
import SwiftUI

/// Shown while a capture is being read and stitched.
///
/// Video *decode* reports real progress, so it gets a determinate bar. Stitching does not —
/// `StitchAssembler.composite` has no progress callback — and inventing a bar for it would
/// be a lie about how far along the work is.
struct ProcessingView: View {
    /// 0…1 while a video decodes; `nil` while stitching.
    let progress: Double?

    var body: some View {
        VStack(spacing: 16) {
            if let progress {
                ProgressView(value: progress) { Text("Reading video…") }
                    .frame(maxWidth: 260)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Putting it together…").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The capture contained no scrolling. This is not an error — the user simply did not scroll
/// the app they recorded — so it reads as coaching, not failure.
struct NothingToStitchView: View {
    var onRecordAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Nothing to stitch", systemImage: "arrow.up.and.down")
        } description: {
            Text("This recording didn't scroll, so there was nothing to join together. Start the recording, switch to the app you want, then scroll down steadily.")
        } actions: {
            Button("Record again", action: onRecordAgain)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// The stitch genuinely failed. Shows the real underlying message — never a generic one.
struct CaptureFailureView: View {
    let message: String
    var onRecordAgain: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't finish this one", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Record again", action: onRecordAgain)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Stitching") { ProcessingView(progress: nil) }
#Preview("Decoding") { ProcessingView(progress: 0.42) }
#Preview("Nothing to stitch") { NothingToStitchView(onRecordAgain: {}) }
#Preview("Failed") { CaptureFailureView(message: "The saved frames could not be read.", onRecordAgain: {}) }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Seamly/Seamly/Features/Result/OutcomeViews.swift
git commit -m "feat(app): add processing, empty, and failure destinations"
```

---

### Task 7: `HomeView` — the record-first home

**Files:**
- Create: `Seamly/Seamly/Features/Home/HomeView.swift`

**Interfaces:**
- Consumes: `CaptureModel` (Task 4), `BroadcastPickerButton`, `VideoImportButton`, `PhotoImportButton`, `OnboardingView`, `DiagnosticsView`, `ResultView` (Task 5), `ProcessingView`/`NothingToStitchView` (Task 6).
- Produces: `HomeView()`.

- [ ] **Step 1: Write the view**

Create `Seamly/Seamly/Features/Home/HomeView.swift`:

```swift
import SwiftUI
import StitchKit

/// The app's home: a record affordance, not a list.
///
/// Seamly is one-shot — you record, you get your screenshot, you save it. A finished capture
/// navigates to *itself* via `CaptureModel.pendingResult` rather than appearing as a row the
/// user has to notice and tap.
struct HomeView: View {
    @State private var model = CaptureModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    @State private var path: [UUID] = []
    @State private var showOnboarding = false
    @State private var showDiagnostics = false
    @State private var showNothingToStitch = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 32) {
                    recordSection
                    Divider()
                    importSection
                    if !model.captures.isEmpty { recents }
                }
                .padding()
            }
            .navigationTitle("Seamly")
            .navigationDestination(for: UUID.self) { id in
                ResultView(captureID: id, model: model, onRecordAgain: { path.removeAll() })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("How it works", systemImage: "questionmark.circle") { showOnboarding = true }
                }
                // Diagnostics is a developer surface, not a feature — tucked behind a menu
                // rather than given a top-level button. It stays reachable because the
                // extension cannot draw UI and its container is not reliably pullable over
                // USB, so this log is the only window into a failed capture on a device.
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Diagnostics", systemImage: "stethoscope") { showDiagnostics = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if model.importProgress != nil || isStitching {
                    ProcessingView(progress: model.importProgress)
                        .background(.regularMaterial)
                }
            }
        }
        .task {
            if !hasSeenOnboarding { showOnboarding = true; hasSeenOnboarding = true }
            AppGroup.startBroadcastFinishObserver()
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .seamlyBroadcastFinished)) { _ in
            Task { await model.refresh() }
        }
        // The model finished assembling an import: go straight to it, then clear the trigger
        // so navigating back doesn't re-push the same destination.
        .onChange(of: model.pendingResult) { _, id in
            guard let id else { return }
            path = [id]
            model.consumePendingResult()
        }
        .onChange(of: model.lastPickupWasEmpty) { _, empty in
            showNothingToStitch = empty
        }
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showNothingToStitch) {
            NothingToStitchView(onRecordAgain: { showNothingToStitch = false })
                .presentationDetents([.medium])
        }
        .alert(
            "Import failed",
            isPresented: Binding(
                get: { model.importError != nil },
                set: { if !$0 { model.clearImportError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
    }

    private var isStitching: Bool {
        let processing = model.captures.filter { $0.phase == .processing }
        return !processing.isEmpty
    }

    private var recordSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.tint.opacity(0.15)).frame(width: 120, height: 120)
                BroadcastPickerButton().frame(width: 100, height: 100)
            }
            Text("Record a long screenshot").font(.headline)
            Text("Pick Seamly, switch to the app you want, and scroll down steadily. One buzz means ease up.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private var importSection: some View {
        VStack(spacing: 12) {
            Text("Already have it?").font(.caption).foregroundStyle(.secondary)
            VideoImportButton(model: model)
            PhotoImportButton(model: model)
        }
    }

    /// Recent captures — a way back to something you just made and haven't saved, not a
    /// library. Every stored capture appears: capping the strip would strand older captures
    /// on disk with no way to reach or delete them. Long-press deletes; nothing is ever
    /// removed without a tap.
    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(model.captures) { capture in
                        Button {
                            path = [capture.id]
                        } label: {
                            thumbnail(capture)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                model.delete(capture.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func thumbnail(_ capture: Capture) -> some View {
        Group {
            if let proxy = capture.proxy {
                // A long screenshot is very tall; a centred crop shows a confusing middle
                // slice that reads as "not stitched". Anchor to the top so the recognizable
                // start of the capture is what shows.
                Image(decorative: proxy, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 72, height: 96, alignment: .top)
                    .clipped()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
                    .frame(width: 72, height: 96)
            }
        }
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(Text(capture.session.createdAt, style: .date))
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' build`

Expected: BUILD SUCCEEDED. (`HomeView` is not yet reachable — `ContentView` still shows `LibraryView`.)

- [ ] **Step 3: Commit**

```bash
git add Seamly/Seamly/Features/Home/HomeView.swift
git commit -m "feat(app): add the record-first home"
```

---

### Task 8: Switch over and delete the harness UI

**Files:**
- Modify: `Seamly/Seamly/ContentView.swift`
- Delete: `Seamly/Seamly/Features/Library/LibraryView.swift`, `Seamly/Seamly/Features/Preview/PreviewView.swift`, `Seamly/Seamly/Features/Preview/EditView.swift`, `Seamly/Seamly/Features/Export/ExportView.swift`, `Seamly/Seamly/Features/Capture/CaptureStartView.swift`
- Modify: `Seamly/Seamly/Core/CaptureModel.swift` (comment on `update(_:)`)

- [ ] **Step 1: Point `ContentView` at `HomeView`**

Replace the body of `Seamly/Seamly/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
}
```

- [ ] **Step 2: Delete the harness surfaces**

```bash
git rm Seamly/Seamly/Features/Library/LibraryView.swift \
       Seamly/Seamly/Features/Preview/PreviewView.swift \
       Seamly/Seamly/Features/Preview/EditView.swift \
       Seamly/Seamly/Features/Export/ExportView.swift \
       Seamly/Seamly/Features/Capture/CaptureStartView.swift
```

No `.pbxproj` edit is needed — the project uses synchronized folder groups.

`EditView` is removed rather than restyled: it is the surface guided repair (Spec 2) replaces, and keeping a pixel-offset stepper form alive would contradict the no-pipeline-vocabulary rule. **The resulting gap — no way to fix a bad stitch until Spec 2 — was raised and explicitly accepted.**

- [ ] **Step 3: Mark `update(_:)` as deliberately caller-less**

Deleting `EditView` leaves `CaptureModel.update(_:)` with no caller. It is the persist-and-reassemble path guided repair needs; removing it now only to re-add it in Spec 2 is churn. Without a comment the next reader will correctly read it as dead code and delete it. Prepend to its doc comment in `Seamly/Seamly/Core/CaptureModel.swift`:

```swift
    /// Persist an edited manifest and re-assemble the proxy.
    ///
    /// **Intentionally has no caller in the shipped shell.** `EditView` was removed with the
    /// harness UI; this is the path guided repair (Spec 2,
    /// `docs/superpowers/specs/2026-08-10-one-shot-capture-shell-design.md`) reconnects to.
    /// Do not delete as dead code.
```

- [ ] **Step 4: Build and run the full app suite**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test`

Expected: BUILD SUCCEEDED, all `SeamlyTests` pass. If a test referenced a deleted view, it was testing the harness rather than behaviour — check `git log` for its intent before deleting it, and port it to the new surface if it covered real behaviour.

- [ ] **Step 5: Commit**

```bash
git add -u && git add Seamly/Seamly/ContentView.swift
git commit -m "feat(app): switch to the one-shot shell and delete the harness UI"
```

---

### Task 9: Onboarding copy and the settled haptic caveat

The safety cue was verified by hand on a physical device on 2026-08-10 — it fires and is felt mid-broadcast. Onboarding's existing promise of a buzz is therefore honest, and gets upgraded from a parenthetical to an explicitly taught signal.

**Files:**
- Modify: `Seamly/Seamly/Features/Onboarding/OnboardingView.swift:16-26`
- Modify: `Seamly/SeamlyBroadcast/SampleHandler.swift:217-219` (comment only)

- [ ] **Step 1: Revise the onboarding steps**

Replace the `steps` array in `Seamly/Seamly/Features/Onboarding/OnboardingView.swift`:

```swift
    private let steps = [
        Step(symbol: "record.circle",
             title: "Tap Record, choose Seamly",
             body: "Seamly records your screen while you scroll another app. Tap Record, pick Seamly in the sheet, and wait for the countdown."),
        Step(symbol: "hand.draw",
             title: "Switch over and scroll steadily",
             body: "Open the app you want and scroll down at a steady, moderate pace."),
        Step(symbol: "iphone.radiowaves.left.and.right",
             title: "One buzz means ease up",
             body: "If you feel a single buzz, you're scrolling too fast to keep everything joined up. Slow down, or scroll back a little and continue."),
        Step(symbol: "checkmark.seal",
             title: "Stop and come back",
             body: "Stop the recording from the red indicator at the top of the screen, then return to Seamly. Your long screenshot will be waiting."),
    ]
```

- [ ] **Step 2: Replace the settled caveat in `SampleHandler`**

The comment at `Seamly/SeamlyBroadcast/SampleHandler.swift:217-219` still describes the haptic as an open question. **Comment only — do not touch the code.** Replace:

```swift
    /// Fire a sound + haptic when overlap drops toward the loss threshold.
    ///
    /// Verified by hand on a physical device 2026-08-10: the vibration fires and is felt
    /// mid-broadcast, so this is a real feedback channel and the only one that reaches a user
    /// who is inside another app. Onboarding teaches it as "one buzz means ease up".
    ///
    /// The *threshold* is not here — `ScrollCaptureDriver.ingest()` decides it purely as
    /// `overlapFraction < safetyMargin` (default 0.4), which the off-device
    /// `CaptureSimulationTests` tier exercises. This adapter only throttles and plays.
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add -u
git commit -m "docs(capture): teach the verified safety cue, settle its caveat"
```

---

### Task 10: UI test for the one-shot flow

The hero path cannot be automated — the broadcast flow needs a device, the system picker, and a human scrolling a third-party app. The Photos path is the only entry a UI test can drive, and it exercises the same shell: import → assemble → `pendingResult` → result screen.

**Files:**
- Modify: `Seamly/SeamlyUITests/SeamlyUITests.swift`

- [ ] **Step 1: Read the existing UI test file**

Read `Seamly/SeamlyUITests/SeamlyUITests.swift` to match its existing setup conventions (launch arguments, `continueAfterFailure`) before adding to it.

- [ ] **Step 2: Add the home-surface test**

`SeamlyUITests` uses **XCTest**, not Swift Testing — `XCUIApplication` requires it. Add:

```swift
    /// The shell is record-first: home shows the record affordance and the two import
    /// entries, and never a capture list.
    @MainActor
    func testHomeShowsRecordFirst() throws {
        let app = XCUIApplication()
        app.launch()

        // First launch presents onboarding; dismiss it to reach home.
        if app.buttons["Get Started"].waitForExistence(timeout: 5) {
            while app.buttons["Next"].exists { app.buttons["Next"].tap() }
            app.buttons["Get Started"].tap()
        }

        XCTAssertTrue(app.staticTexts["Record a long screenshot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["From Video"].exists)
        XCTAssertTrue(app.buttons["From Photos"].exists)
    }
```

- [ ] **Step 3: Run the UI test**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:SeamlyUITests/SeamlyUITests/testHomeShowsRecordFirst`

Expected: PASS.

- [ ] **Step 4: Run everything**

Run: `xcodebuild -project Seamly/Seamly.xcodeproj -scheme Seamly -destination 'platform=iOS Simulator,name=iPhone 17' test`

Then confirm the core is untouched:

Run: `swift test --package-path Seamly/StitchKit`

Expected: 180 tests in 28 suites pass with 1 known issue — **unchanged**. If this number moved, something in this plan touched `StitchKit`, which it must not.

- [ ] **Step 5: Commit**

```bash
git add -u
git commit -m "test(app): cover the record-first home in UI tests"
```

---

## Manual verification (not automatable)

After Task 10, on a **physical device** with the extension installed:

1. Record a scroll through a third-party app, stop, return to Seamly → lands directly on the result, no list.
2. Save to Photos → "Done — remove from Seamly" appears and clears the capture.
3. Start a broadcast and do not scroll → "Nothing to stitch" reads as guidance, not failure.
4. Scroll fast enough to trip the cue → one buzz, matching what onboarding taught.
5. Pinch to zoom, lift, pinch again → zoom accumulates rather than resetting.

## Out of scope

Guided repair (Spec 2). Between this shell shipping and Spec 2 landing there is no way to fix a bad stitch — only to record again. Raised and accepted 2026-08-10.
