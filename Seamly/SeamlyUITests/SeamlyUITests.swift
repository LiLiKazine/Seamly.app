//
//  SeamlyUITests.swift
//  SeamlyUITests
//
//  Created by Leo Sheng on 2026/7/4.
//

import XCTest

final class SeamlyUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // No `testExample` here on purpose. XCTest runs methods alphabetically, so the template
    // stub — which asserted nothing — launched the app before `testHomeShowsRecordFirst` and
    // let `HomeView.task` set `hasSeenOnboarding`. Onboarding was then never on screen for the
    // test that exists to walk through and dismiss it, so its dismissal path went unexercised
    // and a deliberate break in it would not have reproduced.

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Verifies the empty-home state: the record affordance and both import entries
    /// ("From Video", "From Photos") are present. This never seeds a capture, so it
    /// only exercises the no-captures branch — it does not assert that the recents
    /// strip (shown once captures exist) stays free of anything list-like.
    @MainActor
    func testHomeShowsRecordFirst() throws {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfPresented(app)

        // Home is *behind* the onboarding sheet, so its elements exist even while the sheet is
        // covering them — these assertions are only worth something because they also check the
        // elements can be reached. An earlier version guarded on "Get Started" (which onboarding
        // only shows on its last page), so it never dismissed anything and asserted straight
        // through the sheet.
        let headline = app.staticTexts["Record a long screenshot"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertTrue(headline.isHittable, "home is covered — onboarding was not dismissed")
        XCTAssertTrue(app.buttons["From Video"].isHittable)
        XCTAssertTrue(app.buttons["From Photos"].isHittable)
    }

    /// First launch presents onboarding as a sheet over home. Its button reads "Next" on every
    /// page but the last, where it becomes "Get Started" — so reaching home means paging all the
    /// way through. Later launches on the same install skip onboarding entirely
    /// (`hasSeenOnboarding` persists), which is why every step here is conditional.
    @MainActor
    private func dismissOnboardingIfPresented(_ app: XCUIApplication) {
        let next = app.buttons["Next"]
        let getStarted = app.buttons["Get Started"]
        guard next.waitForExistence(timeout: 5) || getStarted.exists else { return }
        while next.exists { next.tap() }
        XCTAssertTrue(getStarted.waitForExistence(timeout: 5), "onboarding never offered a way out")
        getStarted.tap()
        XCTAssertTrue(
            getStarted.waitForNonExistence(timeout: 5),
            "onboarding stayed on screen after Get Started"
        )
    }
}
