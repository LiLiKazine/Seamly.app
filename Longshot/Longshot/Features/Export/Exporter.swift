import CoreGraphics
import Foundation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers
import StitchKit

/// Turns a composited capture into shareable artifacts: PNG/JPEG for Photos/Share/Copy and a
/// PDF for Share/Files. Photos write access is requested only here, at export time.
enum Exporter {
    enum ExportError: LocalizedError {
        case encodeFailed
        case photosDenied
        var errorDescription: String? {
            switch self {
            case .encodeFailed: "Couldn't encode the image."
            case .photosDenied: "Longshot needs permission to add photos. Enable it in Settings."
            }
        }
    }

    static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw ExportError.encodeFailed
        }
        var options: [CFString: Any] = [:]
        if let quality { options[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
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

    static func jpegURL(_ image: CGImage, name: String) throws -> URL {
        try writeTemp(try encode(image, as: .jpeg, quality: 0.9), name: "\(name).jpg")
    }

    static func saveToPhotos(_ image: CGImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw ExportError.photosDenied }
        let uiImage = UIImage(cgImage: image)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
        }
    }

    static func copyToPasteboard(_ image: CGImage) {
        UIPasteboard.general.image = UIImage(cgImage: image)
    }
}
