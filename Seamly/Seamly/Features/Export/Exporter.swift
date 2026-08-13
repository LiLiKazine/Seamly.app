import CoreGraphics
import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers
import StitchKit

/// Turns a composited capture into shareable artifacts: PNG for Photos/Share/Copy and a
/// PDF for Share/Files. Photos write access is requested only here, at export time.
///
/// PNG, not JPEG. A long screenshot is text and sharp UI edges end to end — exactly what
/// JPEG's ringing artifacts damage most, and why iOS screenshots are PNG in the first place.
/// A `jpegURL` helper lived here unused from the beginning; it was removed rather than wired
/// up. If long stitches ever produce PNGs too large to share, add a smaller-file option then,
/// with measured sizes behind the decision.
enum Exporter {
    enum ExportError: LocalizedError {
        case encodeFailed
        case photosDenied
        var errorDescription: String? {
            switch self {
            case .encodeFailed: "Couldn't encode the image."
            case .photosDenied: "Seamly needs permission to add photos. Enable it in Settings."
            }
        }
    }

    /// No lossy-quality parameter: every path here encodes PNG, where it would be a no-op.
    /// It existed only for the removed JPEG helper — reintroduce it with that, if ever.
    static func encode(_ image: CGImage, as type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ExportError.encodeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodeFailed }
        return data as Data
    }

    /// Write an artifact into a temp file for `ShareLink` / Save to Files.
    static func writeTemp(_ data: Data, name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func pngURL(_ image: CGImage, name: String) throws -> URL {
        try writeTemp(try encode(image, as: .png), name: "\(name).png")
    }

    static func saveToPhotos(_ image: CGImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.photosDenied }
        // Encode here (on the caller's actor) to a `Data`, then hand PhotoKit a **`@Sendable`**
        // change block. The module defaults to `@MainActor` isolation, so a plain closure would
        // inherit main-actor isolation — but `performChanges` runs the block on its own private
        // queue, and the injected main-actor executor check then traps (EXC_BREAKPOINT on
        // com.apple.PHPhotoLibrary.changes). A `@Sendable` closure is non-isolated, so it runs
        // safely off-main; capturing `Data` (Sendable) keeps the non-Sendable image out of it.
        let data = try encode(image, as: .png)
        try await PHPhotoLibrary.shared().performChanges { @Sendable in
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    static func copyToPasteboard(_ image: CGImage) {
        UIPasteboard.general.image = UIImage(cgImage: image)
    }
}
