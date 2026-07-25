import Foundation
import StitchKit

/// App-side bridging for the App Group handoff. The identifiers themselves live in
/// `StitchKit.AppGroup` because the extension needs them too; this observer is app-only —
/// the extension posts the notification, it never listens for it.
extension AppGroup {
    private static var isObservingFinish = false

    /// Bridge the extension's Darwin "session finished" notification to a normal
    /// `NotificationCenter` post, so a foregrounded app can refresh instantly (a scenePhase
    /// change won't fire when the broadcast is stopped from Control Center). Idempotent.
    static func startBroadcastFinishObserver() {
        guard !isObservingFinish else { return }
        isObservingFinish = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in NotificationCenter.default.post(name: .seamlyBroadcastFinished, object: nil) },
            sessionFinishedNotification as CFString, nil, .deliverImmediately
        )
    }
}

extension Notification.Name {
    static let seamlyBroadcastFinished = Notification.Name(AppGroup.sessionFinishedNotification)
}
