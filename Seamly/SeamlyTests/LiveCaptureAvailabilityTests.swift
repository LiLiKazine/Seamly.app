import Testing
@testable import Seamly

/// The Record slab is the dock's hero. On a device where ReplayKit broadcast cannot work it must
/// say so, never sit there as a button that swallows the tap — App Review read exactly that
/// silence as "features intentionally hidden during review" (guideline 5.6, 2026-08-27).
///
/// The rule is a pure function of three facts so every branch is pinned here, off-device; the
/// ReplayKit-backed monitor only feeds it.
struct LiveCaptureAvailabilityTests {

    @Test func anIPhoneWithReplayKitCanRecord() {
        let availability = LiveCaptureAvailability(
            isiOSAppOnMac: false, recorderAvailable: true, isSimulator: false
        )
        #expect(availability == .available)
        #expect(availability.isAvailable)
        #expect(availability.explanation == nil)
    }

    /// macOS has its own ReplayKit with in-app recording, so the recorder can report available
    /// while the broadcast picker still has nothing behind it — broadcast upload extensions do
    /// not exist there. Mac wins over the recorder flag.
    @Test func aMacIsNeverLiveEvenWhenItsOwnRecorderReportsAvailable() throws {
        let availability = LiveCaptureAvailability(
            isiOSAppOnMac: true, recorderAvailable: true, isSimulator: false
        )
        #expect(availability == .unavailableOnMac)
        #expect(!availability.isAvailable)
        let explanation = try #require(availability.explanation)
        #expect(explanation.contains("iPhone or iPad"))
    }

    /// Screen Time restrictions, an MDM profile, AirPlay mirroring or another recorder all make
    /// ReplayKit report unavailable, and nothing distinguishes them, so the words stay generic
    /// and say it may be temporary.
    @Test func anUnavailableRecorderExplainsInsteadOfShowingADeadButton() throws {
        let availability = LiveCaptureAvailability(
            isiOSAppOnMac: false, recorderAvailable: false, isSimulator: false
        )
        #expect(availability == .recorderUnavailable)
        #expect(!availability.isAvailable)
        let explanation = try #require(availability.explanation)
        #expect(explanation.contains("right now"))
    }

    /// The simulator has no recording service, so the recorder is always unavailable there. If
    /// that hid the picker, every dock UI test would silently stop exercising the real control.
    @Test func theSimulatorKeepsThePickerSoTheDockTestsStillTouchIt() {
        let availability = LiveCaptureAvailability(
            isiOSAppOnMac: false, recorderAvailable: false, isSimulator: true
        )
        #expect(availability == .available)
    }

    /// Whatever the reason, the sentence must point at the two paths that still work, because
    /// they are the buttons sitting either side of it.
    @Test func everyExplanationNamesTheImportAlternatives() throws {
        let unavailable: [LiveCaptureAvailability] = [.unavailableOnMac, .recorderUnavailable]
        for availability in unavailable {
            let explanation = try #require(availability.explanation)
            let namesAlternatives = explanation.contains("screen recording or screenshots")
            #expect(namesAlternatives, "\(availability): \(explanation)")
        }
    }
}
