import Foundation
import Observation
import ReplayKit

/// Reads the facts `LiveCaptureAvailability` is decided from, and keeps them current.
///
/// ReplayKit's availability is a live value, not a launch-time constant: AirPlay mirroring can
/// take it away and give it back while the app is on screen. So this listens for
/// `screenRecorderDidChangeAvailability(_:)` and re-decides on each change. The decision itself
/// stays in `LiveCaptureAvailability`, where it is tested; this class only supplies inputs.
///
/// Owned by `AppShell` for the life of the app, because `RPScreenRecorder.delegate` is weak.
@MainActor @Observable
final class LiveCaptureMonitor: NSObject, RPScreenRecorderDelegate {
    private(set) var availability: LiveCaptureAvailability

    #if DEBUG
    /// Forces the unavailable branch. The simulator has no recording service and is deliberately
    /// treated as available so the dock UI tests keep touching the real picker, which leaves the
    /// explanatory branch unreachable there without this. Debug builds only, and only when asked
    /// — the same narrow shape as `DebugSeed`'s arguments.
    static let unavailableLaunchArgument = "-SeamlyLiveCaptureUnavailable"
    #endif

    override init() {
        availability = Self.decide(recorderAvailable: RPScreenRecorder.shared().isAvailable)
        super.init()
        RPScreenRecorder.shared().delegate = self
    }

    /// ReplayKit does not say which queue this arrives on, and the recorder is not `Sendable`, so
    /// nothing is read here: the re-read happens on the main actor.
    nonisolated func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        Task { @MainActor in
            self.availability = Self.decide(recorderAvailable: RPScreenRecorder.shared().isAvailable)
        }
    }

    private static func decide(recorderAvailable: Bool) -> LiveCaptureAvailability {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(unavailableLaunchArgument) {
            return .recorderUnavailable
        }
        #endif
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return LiveCaptureAvailability(
            isiOSAppOnMac: ProcessInfo.processInfo.isiOSAppOnMac,
            recorderAvailable: recorderAvailable,
            isSimulator: isSimulator
        )
    }
}
