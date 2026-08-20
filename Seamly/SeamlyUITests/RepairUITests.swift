import XCTest

/// The end-to-end gate on the repair queue — see `testAnsweringAJoinClearsTheFinding` below for
/// what "gate" means here. Both tests drive the queue open through Home's margin marker, the
/// design's own entry, rather than a route through Review.
final class RepairUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The end-to-end gate for the repair queue: a seeded, deliberately misaligned capture is
    /// opened from Home's margin marker, its join is dragged, and the answer is committed. The
    /// assertion is that the finding is *gone* — which can only happen if the drag registered,
    /// the manifest was rewritten, and the capture re-composited from it.
    @MainActor
    func testAnsweringAJoinClearsTheFinding() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Return-home: the seeded capture IS Home, and its margin marker is numbered 1 — the
        // seed has exactly one finding, a flagged join. But the marker is only IN the
        // accessibility tree once its ring is actually on screen (`CaptureGeometry.isVisible`,
        // gating `CaptureView.marginRail`'s `ForEach`), and the seed's join sits at destY 700 of
        // an 1120 px-tall capture — below Home's initial viewport. So this scrolls the stage
        // rather than waiting for a marker that a static wait would never see.
        let sheet = app.descendants(matching: .any).matching(identifier: "capture-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30), "the seeded capture never appeared")

        let marker = app.descendants(matching: .any).matching(identifier: "margin-marker-1").firstMatch
        XCTAssertTrue(
            scrollUntilHittable(marker, on: sheet),
            "the seeded capture's join was never reachable by scrolling — it may not be flagged"
        )

        // Visual evidence for something XCUITest's tree cannot assert directly: the numbered
        // ring in the margin and the flagged rule drawn ON the sheet are placed from the same
        // `CaptureGeometry`, but `SeamMark` is `.accessibilityHidden` on purpose (quiet by
        // design — see its doc comment), so there is no accessibility-tree query that can check
        // the two still line up after a scroll. A screenshot, taken the moment the ring is
        // hittable, is the only artifact that can show it.
        let ringAndRule = XCTAttachment(screenshot: app.screenshot())
        ringAndRule.name = "margin-ring-and-sheet-rule-after-scroll"
        ringAndRule.lifetime = .keepAlways
        add(ringAndRule)

        marker.tap()

        let canvas = app.descendants(matching: .any).matching(identifier: "repair-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "the repair queue never loaded the join")

        // Drag the lower half up. The seed stores an offset 60 px past the truth (420 vs a
        // true 360), and dragging up *lowers* dy, so this converges rather than moving further
        // away. The assertion below is about the commit reaching disk, not pixel perfection.
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.2, thenDragTo: to)

        app.buttons["queue-accept"].tap()

        // The marker disappearing proves almost nothing on its own: while the queue's cover is
        // up, Home is not in the accessibility tree at all, so the marker is already absent the
        // moment it was tapped. The hittability gate below does the real work — it waits until
        // Home is genuinely back and interactive (which needs a .ready capture with a proxy),
        // and only then asserts the marker is gone, i.e. that the condition recomputed clean
        // from what was actually written.
        let sheetAfterCommit = app.descendants(matching: .any).matching(identifier: "capture-sheet").firstMatch
        XCTAssertTrue(sheetAfterCommit.waitForExistence(timeout: 60), "Home never came back")
        XCTAssertTrue(
            waitUntilHittable(sheetAfterCommit, timeout: 60),
            "the capture never became interactive again — the post-commit re-composite did not finish"
        )
        XCTAssertFalse(
            marker.exists,
            "the join is still flagged now that Home is back and interactive — the answer did not reach the manifest"
        )
    }

    /// The queue's shape, not its arithmetic: it opens on the finding that was tapped, counts
    /// its answers, and the manual path is reachable but not the default.
    @MainActor
    func testTheQueueOffersTheManualPathBehindAdjustManually() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Same reason as `testAnsweringAJoinClearsTheFinding`: the marker does not exist in the
        // tree until it is scrolled into view.
        let sheet = app.descendants(matching: .any).matching(identifier: "capture-sheet").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 30))
        let marker = app.descendants(matching: .any).matching(identifier: "margin-marker-1").firstMatch
        XCTAssertTrue(scrollUntilHittable(marker, on: sheet))
        marker.tap()

        XCTAssertTrue(app.staticTexts["1 of 1"].waitForExistence(timeout: 20),
                      "the queue never showed its position")
        XCTAssertTrue(app.buttons["queue-accept"].isHittable,
                      "the affirmative answer must be the wide, primary one")
        XCTAssertFalse(app.buttons["Increase Offset"].exists,
                       "the steppers are the advanced path, not the default")

        app.buttons["Adjust manually"].tap()
        XCTAssertTrue(app.buttons["Increase Offset"].waitForExistence(timeout: 5))
    }

    /// Drags `sheet` upward until `marker` is hittable, or gives up after `maxSwipes`.
    ///
    /// Bounded rather than a `while true`: a marker that never appears — a broken seed, or a
    /// real positioning regression — must fail loudly here with a clear message, not hang the
    /// run pretending to scroll forever.
    @MainActor
    @discardableResult
    private func scrollUntilHittable(_ marker: XCUIElement, on sheet: XCUIElement, maxSwipes: Int = 12) -> Bool {
        for _ in 0..<maxSwipes {
            if marker.exists && marker.isHittable { return true }
            let from = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let to = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return marker.exists && marker.isHittable
    }

    /// Polls until `element` is hittable, rather than trusting a one-shot `.isHittable` read taken
    /// the moment `waitForExistence` returns — existing and being hittable are not the same thing,
    /// and the recomposite this waits out can still be running for a beat after the button appears.
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists && element.isHittable
    }

    /// Same conditional dance as `SeamlyUITests`: onboarding shows only on a fresh install, and its
    /// button reads "Next" until the last page.
    @MainActor
    private func dismissOnboardingIfPresented(_ app: XCUIApplication) {
        let next = app.buttons["Next"]
        let getStarted = app.buttons["Get Started"]
        guard next.waitForExistence(timeout: 5) || getStarted.exists else { return }
        while next.exists { next.tap() }
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "onboarding never offered a way out")
        getStarted.tap()
    }
}
