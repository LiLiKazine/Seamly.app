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

        // A seeded capture is not a new arrival, so nothing pushes to it — it appears in recents.
        // SwiftUI's choice of accessibility element type for this button is not guaranteed (it has
        // shown up as a button and as a generic element depending on its content), so match by
        // identifier against `.any` rather than assuming `.buttons`.
        let thumbnail = app.descendants(matching: .any).matching(identifier: "recent-capture").firstMatch
        XCTAssertTrue(thumbnail.waitForExistence(timeout: 30), "the seeded capture never appeared")
        thumbnail.tap()

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

        // `waitForNonExistence` above is satisfied the instant the capture flips to `.processing`
        // (`ResultView`'s `.stitching` case renders `ProcessingView`, which has no `ConditionNotice`
        // at all) — that proves nothing about whether the write that triggered it was correct. A
        // commit that flipped to processing without truly persisting the fix (or without writing
        // anything at all before some other side effect re-triggered assembly) would make the
        // notice vanish transiently and then reappear once the capture settles back to `.ready`
        // with its still-flagged condition. So: wait for the primary action to become hittable
        // again — which only happens once `assemble` finishes and the capture is `.ready` with a
        // proxy — and only then assert the notice is *still* absent.
        let saveButton = app.buttons["Save to Photos"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 30), "the result screen never came back")
        XCTAssertTrue(
            waitUntilHittable(saveButton, timeout: 30),
            "Save to Photos never became hittable again — the post-commit re-composite did not finish"
        )
        XCTAssertFalse(
            notice.exists,
            "the join was flagged again once the re-composite settled — the earlier disappearance was just the processing flip"
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
