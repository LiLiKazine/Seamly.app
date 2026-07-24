import CoreGraphics
import Foundation
import StitchKit

/// Turns an ordered set of images (photo picks, or video-decoded keyframes) into a persisted
/// session in app storage — the shared path behind "From Photos" and "From Video". Mirrors the
/// broadcast import (write raw keyframes → base manifest → resolveGeometry) minus the App Group,
/// staleness, and per-session move logic that only the cross-process handoff needs. Pure and
/// off-actor: `nonisolated`, `Sendable` inputs/outputs.
enum MediaImporter {
    enum Source: String { case photos, video }
    enum ImportError: Error, Equatable { case notEnoughContent }

    /// Write `images` (in final display order) into `store` as a new session and resolve its
    /// geometry with `strategy`. Returns the new session id. Throws `.notEnoughContent` for
    /// fewer than two images (a single frame is not a stitch).
    nonisolated static func write(images: [CGImage], into store: SessionStore, strategy: OrderStrategy, source: Source) throws -> UUID {
        guard images.count >= 2 else { throw ImportError.notEnoughContent }
        let id = UUID()
        let folder = try store.createFolder(for: id)

        let first = images[0]
        var session = StitchSession(
            id: id,
            createdAt: Date(),
            status: .complete,
            deviceScale: 1,
            orientation: first.width > first.height ? .landscape : .portrait,
            colorSpaceName: first.colorSpace?.name as String?
        )
        for (i, image) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(image, to: folder.appendingPathComponent(name))
            session.keyframes.append(Keyframe(filename: name, pixelWidth: image.width, pixelHeight: image.height, index: i))
        }
        try store.writeManifest(session)

        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: strategy)
        try store.writeManifest(resolved)
        return id
    }
}
