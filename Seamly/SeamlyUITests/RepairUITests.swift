import XCTest

/// The end-to-end gate for guided repair: a seeded, deliberately misaligned capture is opened, its
/// join is dragged, and the change is committed. The assertion is that the notice which said the
/// join might not line up is *gone* — which can only happen if the drag registered, the manifest
/// was rewritten, and the capture re-composited from it.
final class RepairUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLiningUpAJoinClearsTheNotice() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Return-home: a seeded capture is the newest one, so Home is already showing it —
        // there is no recents strip to tap any more. Fully rewritten in Task 19 once the
        // repair queue replaces this screen; for now it just reaches the same place.
        let review = app.buttons["review-capture"]
        XCTAssertTrue(review.waitForExistence(timeout: 30), "the seeded capture never appeared")
        review.tap()

        let notice = app.staticTexts["A join may not line up"]
        XCTAssertTrue(notice.waitForExistence(timeout: 30), "the seeded capture was not flagged")

        app.buttons["Line it up"].tap()

        let canvas = app.descendants(matching: .any).matching(identifier: "repair-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20), "the repair screen never loaded")

        // Drag the lower half up. The seed stores an offset 60 px past the truth (420 vs. a true
        // 360), and dragging up *lowers* `dy` (`JoinAlignment.dy(draggedBy:...)`), so this
        // genuinely converges rather than moving further away — roughly 105 pt of drag at ~0.75
        // source px/pt lands near 342, close enough that the join no longer reads as flagged once
        // committed. The assertion below is about the commit reaching disk, not pixel perfection.
        let from = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        let to = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        from.press(forDuration: 0.2, thenDragTo: to)

        app.buttons["Done"].tap()

        XCTAssertTrue(
            notice.waitForNonExistence(timeout: 60),
            "the join was still flagged after being lined up — the edit did not reach the manifest"
        )

        // `waitForNonExistence` above proves almost nothing on its own, and not for the reason it
        // might appear to. It is satisfied by *the cover itself*: while `RepairView` is up,
        // `ResultView` (notice included) is not in the accessibility tree at all, so the notice is
        // already absent the moment "Line it up" is tapped, before anything is written. Nor does
        // this catch a `.processing` flip on the way back: `commit()` awaits `model.update(_:)` —
        // which persists the manifest *and* runs `assemble` to completion — *before* it calls
        // `dismiss()`, so by the time the cover drops the capture is already back to `.ready`.
        //
        // So the hittability-gated re-assertion below is doing all the real work: it waits until
        // `ResultView` is genuinely back on screen and interactive (the primary action existing
        // *and* hittable, which needs a `.ready` capture with a proxy), and only then asserts the
        // notice is absent — i.e. that the condition recomputed clean from what was actually
        // written, rather than the notice merely being off-screen behind the cover.
        let saveButton = app.buttons["Save to Photos"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 30), "the result screen never came back")
        XCTAssertTrue(
            waitUntilHittable(saveButton, timeout: 30),
            "Save to Photos never became hittable again — the post-commit re-composite did not finish"
        )
        XCTAssertFalse(
            notice.exists,
            "the join is still flagged now that the result screen is back and interactive — the earlier disappearance was only the repair cover covering it"
        )
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
