# 2026-08-22-03 — The broadcast picker kept the pre-Paper icon

## The report

"The icon in broadcast is still the old icon, not updated to current app icon." The Home Screen
showed the new mark ("Ruled, three uneven", `2026-08-22-app-icon.md`); both broadcast surfaces —
the `RPSystemBroadcastPickerView` sheet inside the app *and* the Control Center screen-recording
list — showed the pre-Paper spike artefact, the cyan-to-blue gradient behind stacked cards.

The device screenshot listed exactly **one** row, "Seamly", so this was never two installs fighting
over the bundle id.

## What was ruled out first

Nothing stale existed anywhere in the build. Verified rather than assumed:

- **The repo** holds only the new icon. `git log` confirms 69ad1c1 replaced both PNGs and deleted
  `icon_tinted.png`; no other PNG exists outside `Fixtures/`.
- **The built app**, simulator *and* device, is current: `assetutil` shows exactly two renditions
  (default → `icon_light`, `UIAppearanceDark` → `icon_dark`), and the flattened
  `AppIcon60x60@2x.png` at the bundle root renders as the ink field with three joins.
- **One genuinely stale install** turned up — the iPad Pro 13-inch simulator, an Aug 20 build with
  a 670 KB `Assets.car`. Irrelevant: the report was from a real device.

So the old pixels were not coming from anything this repo produces.

## Root cause

`SeamlyBroadcast.appex` shipped **no icon at all**, and never had in any commit: no
`Assets.xcassets` in the target folder, no `ASSETCATALOG_COMPILER_APPICON_NAME`, and no
`CFBundleIcons` in its built `Info.plist`.

The picker's row is the *extension's* row. With nothing in the appex to draw, iOS resolves a
fallback to the containing app's icon — and that resolution is cached per extension bundle id. The
appex then has nothing that could ever invalidate it: no icon bytes of its own, and
`CURRENT_PROJECT_VERSION = 1` / `MARKETING_VERSION = 1.0` hardcoded and never bumped. The rendition
baked at the first install — back when the app icon *was* the gradient — is frozen. Reinstalling
re-renders the app's icon, which is why the Home Screen was right, and never touches the
extension's.

The app icon was verified on the springboard when it shipped. The picker was never looked at, and
it is the one surface that does not read the app's icon.

## The fix

The extension gets its own icon, and the generator writes both so they cannot drift.

1. `scripts/make-app-icon.swift` now writes into a list of appiconsets, adding
   `Seamly/SeamlyBroadcast/Assets.xcassets/AppIcon.appiconset`. It still fails loudly if any
   destination is missing, and the app's PNGs came out **byte-identical** after the refactor —
   `git diff` on the app's asset catalog is empty.
2. `Seamly/SeamlyBroadcast/Assets.xcassets/` created, mirroring the app's catalog exactly: the same
   two appearances at 1024, no tinted asset.
3. `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` on both extension build configurations.

An asset catalog cannot be *shared* between the two: target membership follows the folder
(synchronized folder groups), and there is no shared app-level folder. Duplicating the pixels from
one generator run is the option that keeps them derivable from the design tokens; adding an
explicit cross-target file reference would fight the project's own convention.

Cost to the appex is ~48 KB of bundle size — `Assets.car` plus three flattened PNGs. That is bundle
size, not resident memory: the extension never loads its own icon, SpringBoard does. The ~50 MB
footprint ceiling is untouched.

## Verified, not assumed

`SeamlyBroadcast/Info.plist` is hand-written with `GENERATE_INFOPLIST_FILE = NO`, so it was an open
question whether the icon keys would arrive at all. They do — actool's partial plist merges
regardless — and the merge is **additive**: `NSExtensionPointIdentifier`,
`NSExtensionPrincipalClass` and `RPBroadcastProcessMode` all survive intact. Clobbering those would
have stopped the bundle being a broadcast extension, which no icon test would have caught.

The appex's flattened `AppIcon60x60@2x.png` is byte-identical to the app's.

## The suite lied once on the way

`SeamlyTests/BroadcastExtensionIconTests.swift` asserts the appex carries `Assets.car`, declares
`CFBundleIcons` with `NSExtension` intact, and ships the same flattened icon as the app.

Checking that these actually fail without the fix, **they passed anyway.** Xcode does not prune
resources it has already copied into a bundle, so `Assets.car` and the PNGs stayed in the appex
after `ASSETCATALOG_COMPILER_APPICON_NAME` was removed. A clean `-derivedDataPath` produced an
appex with no icon files at all and all three went red; restoring the setting turned them green
again on another clean build. The caveat is recorded in the test file: an incremental run of these
is a false green.

Full `SeamlyTests` suite green afterwards.

## Clearing the poisoned rendition: a reboot, not a reinstall

The first prediction here was that a delete + reinstall would clear the frozen rendition. **That
was wrong, and the device disproved it:** the app was removed from the Home Screen, rebuilt and
reinstalled, and the picker still showed the gradient.

What settled it was proving where the pixels could *not* be coming from. `BroadcastExtensionIconTests`
was run against the physical device (`-destination 'platform=iOS,id=…'`), and all three passed there:
the installed appex carries `Assets.car`, declares `CFBundleIcons → AppIcon`, and its flattened icon
is byte-identical to the app's. The gradient therefore existed in no installed bundle on that phone,
which leaves a system-held rendition as the only possibility — measured, not inferred.

**A reboot cleared it.** The picker now shows the new mark.

The asymmetry that made this confusing is worth keeping: the Home Screen icon updated on every
install, because SpringBoard's own icon store is rebuilt then. The picker's list-row variant comes
through `com.apple.iconservices`, a system-wide cache that survives deleting the app — so a
same-version reinstall lands back on the same entry. `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
have been `1.0` / `1` for every build ever made, so that key has never once changed.

Bumping the build number would also have changed the key, and was the next planned single variable.
It was never needed, so it stays **untested** — do not write it up as a known remedy.

This only bites devices that carried the iconless appex and cached a fallback for it. A device
installing the current build for the first time has real icon bytes to render, and those bytes now
change whenever the mark does.
