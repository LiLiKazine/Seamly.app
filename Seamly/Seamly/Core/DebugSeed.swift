#if DEBUG
import CoreGraphics
import Foundation
import StitchKit

/// Writes one deliberately misaligned capture into app storage, so a UI test can reach the repair
/// screen without driving the system photo picker.
///
/// **Debug builds only, and only when asked.** Spec 1 deferred UI-test seeding rather than adding
/// test-only hooks; this reverses that for the repair screen specifically, because the picker's
/// cells carry no distinguishing labels — a test that taps them is exactly the test that keeps
/// passing while the screen is broken, which this project has already shipped once (an invisible
/// record button survived 42 unit tests, 4 UI tests and eleven reviews).
///
/// The frames are synthesized rather than bundled: no binary asset, deterministic, and the stored
/// offset can be made wrong on purpose so there is genuinely something to fix.
enum DebugSeed {
    static let launchArgument = "-SeamlySeedMisalignedCapture"

    /// A fixed id, so repeated launches replace the seed instead of piling up captures.
    private static let id = UUID(uuidString: "5EED0000-0000-0000-0000-00000000C0DE")!

    private static let frameWidth = 300
    private static let frameHeight = 700
    /// What the frames were actually cropped at.
    private static let trueDy = 360
    /// What the manifest claims, which is what the user has to drag away. 60 px past the truth —
    /// far enough to duplicate a visible band of rows, and far outside the ±16 px the old draw
    /// path would have quietly fixed.
    private static let storedDy = 420

    /// `@MainActor` names the actual requirement (`CaptureModel.appContainerURL()` reads/creates a
    /// directory and is declared on a `@MainActor` type); it does not depend on this app target's
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` default holding for a debug-only file. Called
    /// from `SeamlyApp.init()`, which the same default (or this annotation, if that ever changes)
    /// makes MainActor too.
    @MainActor
    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        do {
            try seed()
        } catch {
            // A failed seed must be loud: the UI test that depends on it would otherwise fail
            // somewhere far away, looking like a bug in the repair screen.
            print("Seamly: DebugSeed FAILED: \(error)")
        }
    }

    @MainActor
    private static func seed() throws {
        let store = SessionStore(containerURL: CaptureModel.appContainerURL())
        try? store.delete(id)   // best-effort: nothing to remove on a clean install
        let folder = try store.createFolder(for: id)

        let source = makeSource(width: frameWidth, height: frameHeight + trueDy)
        var session = StitchSession(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait,
            colorSpaceName: source.colorSpace?.name as String?
        )
        for index in 0..<2 {
            let name = String(format: "kf-%04d.bgra", index)
            let crop = source.cropping(to: CGRect(
                x: 0, y: index * trueDy, width: frameWidth, height: frameHeight
            ))!
            try KeyframeIO.writeRaw(crop, to: folder.appendingPathComponent(name))
            session.keyframes.append(
                Keyframe(filename: name, pixelWidth: frameWidth, pixelHeight: frameHeight, index: index)
            )
        }
        // Wrong on purpose, and flagged — so the result screen shows the loud entry ("A join may
        // not line up") and the notice has something to stop saying once the join is lined up.
        session.seams = [
            Seam(fromIndex: 0, provisionalDy: storedDy, confidence: 0.2, isLowConfidence: true)
        ]
        // Every edge gets a confident, zero-inset automatic measurement rather than an unresolved
        // (`automatic == nil`) record from `ensureChromeRecordsForKeyframes()`. With `automatic ==
        // nil`, both edges would need review, `unresolvedChrome == 2`, and `unresolvedBars`
        // (`Imperfection.Kind` rank 2) would outrank `flaggedJoins` (rank 3) as the primary
        // imperfection — the result screen would show "Some bars may repeat" instead, and the text
        // this seed exists to exercise ("A join may not line up") would be sitting unseen inside a
        // collapsed disclosure.
        session.keyframeChrome = session.keyframes.map {
            KeyframeChrome(keyframeID: $0.id, automatic: ChromeMeasurement(insets: .zero, confidence: 0.9))
        }
        // Deliberately *not* frozen: freezing happens at import, and this capture never goes
        // through one. That is what leaves the wrong offset in place for the test (and a human) to
        // drag away.
        try store.writeManifest(session)
    }

    /// A monotonic vertical ramp so vertical position is unambiguous, plus horizontal structure so
    /// a misalignment is visible to a human looking at the screen.
    private static func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let stripe = (y % 40 < 6) ? 90.0 : 0
                let v = 50.0 + Double(y) * (120.0 / Double(height)) + stripe
                    + 40 * sin(Double(x) * 0.3)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }
}
#endif
