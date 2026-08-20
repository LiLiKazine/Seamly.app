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

    /// Verifies the empty-home state: the dock is present with all three ways in, and the
    /// empty state is capture-first. This only exercises the no-captures branch, so it asks
    /// for a known-empty store explicitly (`-SeamlyResetCaptures`) rather than assuming one.
    ///
    /// XCTest runs test classes alphabetically, so `RepairUITests` runs before this one and
    /// launches with `-SeamlySeedMisalignedCapture`, which writes a capture straight into app
    /// storage — and that capture used to stay there for every launch after. This test would
    /// then find a non-empty Home and fail, but only on a simulator that had already run the
    /// suite once; a freshly erased one stayed green. That "green here, red there" split is
    /// exactly what `CLAUDE.md` calls a lie, so the reset is the real fix, not the erase.
    @MainActor
    func testHomeShowsRecordFirst() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlyResetCaptures"]
        app.launch()
        dismissOnboardingIfPresented(app)

        // Home is *behind* the onboarding sheet, so its elements exist even while the sheet is
        // covering them — these assertions are only worth something because they also check the
        // elements can be reached.
        let headline = app.staticTexts["Nothing captured yet"]
        XCTAssertTrue(headline.waitForExistence(timeout: 5))
        XCTAssertTrue(headline.isHittable, "home is covered — onboarding was not dismissed")

        // The dock's hero wraps `RPSystemBroadcastPickerView` (`BroadcastPickerButton`), a
        // `UIViewRepresentable`. That surfaces as an `Other` carrying our identifier and label,
        // not a `Button` — SwiftUI's choice of accessibility element type for wrapped UIKit
        // content is not guaranteed, so match by identifier against `.any` rather than assuming
        // `.buttons`, the same fix `RepairUITests` already needed for this exact class of problem.
        let record = app.descendants(matching: .any).matching(identifier: "record-button").firstMatch
        XCTAssertTrue(record.isHittable, "the dock's hero is missing")
        XCTAssertTrue(app.buttons["From a screen recording"].isHittable)
        XCTAssertTrue(app.buttons["From screenshots"].isHittable)
    }

    /// Library is reachable from Home and lists the capture Home is showing.
    @MainActor
    func testLibraryListsTheCapture() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-SeamlySeedMisalignedCapture"]
        app.launch()
        dismissOnboardingIfPresented(app)

        let library = app.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 30), "Home never offered Library")
        library.tap()

        let row = app.descendants(matching: .any).matching(identifier: "library-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the capture is not listed")

        // Same fix `testHomeShowsRecordFirst` already needed: the dock's hero wraps
        // `RPSystemBroadcastPickerView` in a `UIViewRepresentable`, which surfaces as an
        // `Other` carrying the "Record" label, not a `Button` — matching `app.buttons["Record"]`
        // finds nothing and reads as "the dock is gone" even though it is sitting right there.
        let record = app.descendants(matching: .any).matching(identifier: "record-button").firstMatch
        XCTAssertTrue(record.isHittable, "the dock must stay on Library")
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
