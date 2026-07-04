import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads and writes keyframe images.
///
/// The pixel-exact / hard-cut design depends on byte-faithful keyframes, so the default is
/// raw BGRA-to-disk — guaranteed lossless and allocation-free (a memcpy, no encoder spike),
/// which also side-steps the extension's ~50 MB encode-memory ceiling. Lossless HEIC is
/// offered for space once the on-device memory peak is verified.
public enum KeyframeIO {
    public enum IOError: Error { case encodeFailed, decodeFailed, sizeMismatch }

    /// Write `image` as raw 8-bit BGRA (premultiplied), tightly packed (no row padding).
    public static func writeRaw(_ image: CGImage, to url: URL) throws {
        let width = image.width, height = image.height
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        try buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { throw IOError.encodeFailed }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        try Data(buffer).write(to: url, options: .atomic)
    }

    /// Read a raw BGRA keyframe previously written by `writeRaw`, using the manifest's
    /// dimensions and (optionally) its color space.
    public static func readRaw(from url: URL, width: Int, height: Int, colorSpace: CGColorSpace? = nil) throws -> CGImage {
        let data = try Data(contentsOf: url)
        let bytesPerRow = width * 4
        guard data.count == bytesPerRow * height else { throw IOError.sizeMismatch }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { throw IOError.decodeFailed }
        return image
    }

    /// Write `image` as HEIC. `lossless` requests maximum quality (a space optimization over
    /// the raw path, pending on-device memory verification).
    public static func writeHEIC(_ image: CGImage, to url: URL, lossless: Bool = true) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw IOError.encodeFailed
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: lossless ? 1.0 : 0.85]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw IOError.encodeFailed }
    }

    /// Read any image file (HEIC/PNG/…) via ImageIO.
    public static func read(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw IOError.decodeFailed
        }
        return image
    }
}
