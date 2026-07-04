import Foundation

/// Shared identifiers and container access for the App Group that bridges the app and the
/// `LongshotBroadcast` extension. Both targets compile this file.
enum AppGroup {
    /// Must match `com.apple.security.application-groups` in both targets' entitlements.
    static let identifier = "group.io.github.lilikazine.Longshot"

    /// Darwin notification the extension posts when it finalizes a session, so a
    /// foregrounded app can pick it up instantly (a launch/foreground scan is the source of
    /// truth regardless).
    static let sessionFinishedNotification = "io.github.lilikazine.Longshot.sessionFinished"

    /// The shared container URL, or `nil` if the App Group isn't provisioned (e.g. a
    /// misconfigured build). Callers degrade gracefully rather than crash.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    private static var isObservingFinish = false

    /// Bridge the extension's Darwin "session finished" notification to a normal
    /// `NotificationCenter` post, so a foregrounded app can refresh instantly (a scenePhase
    /// change won't fire when the broadcast is stopped from Control Center). Idempotent.
    static func startBroadcastFinishObserver() {
        guard !isObservingFinish else { return }
        isObservingFinish = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), nil,
            { _, _, _, _, _ in NotificationCenter.default.post(name: .longshotBroadcastFinished, object: nil) },
            sessionFinishedNotification as CFString, nil, .deliverImmediately
        )
    }
}

extension Notification.Name {
    static let longshotBroadcastFinished = Notification.Name(AppGroup.sessionFinishedNotification)
}
