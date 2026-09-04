import Foundation

/// Whether the dock's Record slab can do anything on this device, and if not, what to say instead.
///
/// The picker is the system `RPSystemBroadcastPickerView`, and there are devices where it is a
/// button with nothing behind it: an iPad app running on an Apple silicon Mac (macOS has ReplayKit
/// for in-app recording, but broadcast upload extensions do not exist there), and any iPhone or
/// iPad where ReplayKit reports itself unavailable — Screen Time or an MDM profile disallowing
/// screen recording, the screen mirrored over AirPlay or TV-out, another app holding the recorder.
/// App Review met one of those and read the silent button as "features intentionally hidden
/// during review" (guideline 5.6, 2026-08-27). A control that cannot work is replaced by a
/// sentence, never left to swallow the tap.
///
/// A pure function of three facts, so every branch is table-testable off-device.
/// `LiveCaptureMonitor` is what reads the facts from ReplayKit.
///
/// `nonisolated` because the app target defaults declarations to `@MainActor`, and this is a plain
/// value the tests and the monitor's delegate callback both want to build freely.
nonisolated enum LiveCaptureAvailability: Equatable {
    case available
    /// The iOS binary is running on a Mac. Wins over the recorder flag, because macOS's own
    /// ReplayKit can report available while the broadcast picker still has nothing to offer.
    case unavailableOnMac
    /// ReplayKit says no. The reasons are indistinguishable from here and some are transient.
    case recorderUnavailable

    /// - Parameter isSimulator: the simulator has no recording service, so the recorder is always
    ///   unavailable there. Treating that as unavailable would swap the picker out from under
    ///   every dock UI test, so the simulator keeps the real control.
    init(isiOSAppOnMac: Bool, recorderAvailable: Bool, isSimulator: Bool) {
        if isiOSAppOnMac {
            self = .unavailableOnMac
        } else if isSimulator || recorderAvailable {
            self = .available
        } else {
            self = .recorderUnavailable
        }
    }

    var isAvailable: Bool { self == .available }

    /// The sentence that takes the slab's place. Always ends by naming the two paths that still
    /// work, because those are the buttons either side of it.
    var explanation: String? {
        switch self {
        case .available:
            nil
        case .unavailableOnMac:
            "Live capture needs an iPhone or iPad. Import a screen recording or screenshots instead."
        case .recorderUnavailable:
            "Screen recording isn't available right now. Import a screen recording or screenshots instead."
        }
    }
}
