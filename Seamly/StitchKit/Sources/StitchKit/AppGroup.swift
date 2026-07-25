import Foundation

/// The identifiers the app and the `SeamlyBroadcast` extension must agree on to hand a capture
/// across the process boundary.
///
/// These live in `StitchKit` because it is the only compilation unit **both** targets share. The
/// Xcode project uses synchronized folder groups, one per target folder, so a file under
/// `Seamly/` is app-only and a file under `SeamlyBroadcast/` is extension-only — there is no
/// third app-level folder to put shared code in. Before this existed, the group identifier was
/// repeated as a literal in five places (two of them inside `SampleHandler`) and the Darwin
/// notification name in two more; a typo in any of them silently produces a capture that goes
/// nowhere, because a wrong group id just yields `nil` for the container.
///
/// The package already knows about shared containers — `SessionStore` and `Diagnostics` are both
/// built around a `containerURL` — so this is configuration for machinery that is already here,
/// not app logic leaking into the core.
///
/// The two `.entitlements` files still repeat the group identifier literally; entitlements are
/// build configuration and cannot reference Swift. Those are the only remaining copies.
public enum AppGroup {
    /// Must match `com.apple.security.application-groups` in **both** targets' entitlements.
    public static let identifier = "group.io.github.lilikazine.Seamly"

    /// Darwin notification the extension posts when it finalizes a session, so a foregrounded
    /// app can pick it up instantly. A launch/foreground scan remains the source of truth —
    /// this only removes the wait.
    public static let sessionFinishedNotification = "io.github.lilikazine.Seamly.sessionFinished"

    /// The shared container, or `nil` if the App Group isn't provisioned (e.g. a misconfigured
    /// build, or a mismatch between the two targets' entitlements). Callers degrade gracefully
    /// rather than crash: the app reports that no capture could be imported, and the extension
    /// fails the broadcast loudly instead of recording into nowhere.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
