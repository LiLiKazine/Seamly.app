import Testing
import Foundation

/// The broadcast picker's row is the *extension's* row, so it renders the extension's own icon.
/// `SeamlyBroadcast.appex` shipped with no icon at all for its entire history, and an appex with
/// no icon does not simply borrow the app's current one: iOS resolves a fallback once, caches it
/// per extension bundle id, and the appex carries nothing whose bytes ever change to invalidate
/// it. So the picker kept showing the pre-Paper gradient icon long after the app icon was
/// replaced — the Home Screen updated and the picker did not.
///
/// These assertions are about the built *bundle*, not about Swift code, which is exactly why they
/// are worth writing down: the fix is three lines of build configuration and an asset catalog,
/// all of which are invisible at the call site and none of which any other test would notice
/// disappearing. See `docs/logs/2026-08-22-03-broadcast-extension-icon.md`.
///
/// **These only tell the truth on a clean build.** Verifying that they actually fail without the
/// fix, they passed anyway on an incremental build: Xcode does not prune resources it has already
/// copied into a bundle, so `Assets.car` and the flattened PNGs survived in the appex after
/// `ASSETCATALOG_COMPILER_APPICON_NAME` was removed. A fresh `-derivedDataPath` produced an appex
/// with no icon files at all and all three went red. If you are ever checking whether these still
/// bite, wipe DerivedData first — an incremental run here is a false green.
struct BroadcastExtensionIconTests {

    /// The appex as it actually sits inside the host app that is running these tests.
    private func broadcastExtensionURL() throws -> URL {
        let plugIns = try #require(
            Bundle.main.builtInPlugInsURL,
            "the test host has no PlugIns directory — is this running in the app?"
        )
        let appex = plugIns.appendingPathComponent("SeamlyBroadcast.appex")
        try #require(
            FileManager.default.fileExists(atPath: appex.path),
            "SeamlyBroadcast.appex is not embedded in the app at \(appex.path)"
        )
        return appex
    }

    /// The compiled asset catalog must be in the appex. Without `Assets.car` the appex has no
    /// icon of its own and the picker is back on the frozen fallback.
    @Test func extensionBundleCarriesACompiledAssetCatalog() throws {
        let appex = try broadcastExtensionURL()
        let assets = appex.appendingPathComponent("Assets.car")
        #expect(
            FileManager.default.fileExists(atPath: assets.path),
            """
            SeamlyBroadcast.appex has no Assets.car. Its ASSETCATALOG_COMPILER_APPICON_NAME or its \
            Assets.xcassets is gone, and the broadcast picker will show a stale cached icon.
            """
        )
    }

    /// `SeamlyBroadcast/Info.plist` is hand-written with `GENERATE_INFOPLIST_FILE = NO`, so the
    /// icon keys arrive only via actool's partial-plist merge. That merge is the load-bearing and
    /// non-obvious part of the fix — assert it happened rather than trusting it.
    @Test func extensionInfoPlistDeclaresTheIcon() throws {
        let appex = try broadcastExtensionURL()
        let data = try Data(contentsOf: appex.appendingPathComponent("Info.plist"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        let icons = try #require(
            plist["CFBundleIcons"] as? [String: Any],
            "no CFBundleIcons in the appex Info.plist — actool's partial plist did not merge"
        )
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")

        // The hand-written keys must survive the merge — clobbering these would stop the bundle
        // being a broadcast upload extension at all, which no icon test would otherwise catch.
        let ext = try #require(plist["NSExtension"] as? [String: Any])
        #expect(ext["NSExtensionPointIdentifier"] as? String == "com.apple.broadcast-services-upload")
    }

    /// The picker should show *the* Seamly mark, not a second drifting copy of it. One generator
    /// run writes both appiconsets (`scripts/make-app-icon.swift`), so the flattened icons the
    /// two bundles ship must be identical byte for byte.
    @Test func extensionIconIsTheSameMarkAsTheApp() throws {
        let appex = try broadcastExtensionURL()
        let name = "AppIcon60x60@2x.png"

        let appIcon = Bundle.main.bundleURL.appendingPathComponent(name)
        let extIcon = appex.appendingPathComponent(name)
        try #require(
            FileManager.default.fileExists(atPath: extIcon.path),
            "the appex has no flattened \(name) — legacy icon consumers get nothing"
        )

        let app = try Data(contentsOf: appIcon)
        let ext = try Data(contentsOf: extIcon)
        #expect(app == ext, "the extension's icon has drifted from the app's — re-run scripts/make-app-icon.swift")
    }
}
