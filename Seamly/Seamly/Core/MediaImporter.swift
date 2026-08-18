import CoreGraphics
import Foundation
import StitchKit

/// Turns a set of images in source arrival order (Photos pick order or video decode order) into a
/// persisted session in app storage — the shared path behind "From Photos" and "From Video". Mirrors the
/// broadcast import (write raw keyframes → base manifest → resolveGeometry) minus the App Group,
/// staleness, and per-session move logic that only the cross-process handoff needs. Pure and
/// off-actor: `nonisolated`, `Sendable` inputs/outputs.
enum MediaImporter {
    enum Source: String { case photos, video }
    enum ImportError: Error, Equatable { case notEnoughContent }

    /// Write `images` in their source arrival order into `store`, then resolve geometry with
    /// `strategy`. Photos arrive in user pick order and may be reordered; decoded video arrives in
    /// authoritative chronology. Returns the new session id. Throws `.notEnoughContent` for fewer
    /// than two images (a single frame is not a stitch).
    ///
    /// `source` is recorded in the diagnostic trace: a capture's origin is otherwise
    /// indistinguishable after import, and photo picks and video decodes fail differently.
    nonisolated static func write(images: [CGImage], into store: SessionStore, strategy: BatchStitcher.OrderStrategy, source: Source, diag: Diagnostics) throws -> UUID {
        guard images.count >= 2 else {
            diag.log("import[\(source.rawValue)]: rejected, \(images.count) image(s) — need at least two")
            throw ImportError.notEnoughContent
        }
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
        // Freeze here, next to where geometry is derived — never on the draw path. From this point
        // the manifest is the authority on where every join sits.
        let frozen = try StitchAssembler.freezeGeometry(resolved, in: folder)
        try store.writeManifest(frozen)
        diag.log("import[\(source.rawValue)]: \(id.uuidString.prefix(8)) wrote \(images.count) kf, resolved \(frozen.seams.count) seams, \(frozen.segmentBreaks.count) breaks, orderAssumed=\(frozen.orderAssumed)")
        return id
    }
}
