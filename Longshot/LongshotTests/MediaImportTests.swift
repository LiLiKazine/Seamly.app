import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Longshot

/// Shared synthetic-frame helpers + coverage for order resolution and media import.
@MainActor
struct MediaImportTests {

    /// A tall source with a monotonic vertical ramp plus horizontal structure that survives
    /// downscaling — scroll position is unambiguous. (Mirrors BatchAssemblyTests.makeSource.)
    static func makeSource(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35) + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    static func slices(count: Int, width: Int, sliceH: Int, dy: Int) -> [CGImage] {
        let src = makeSource(width: width, height: sliceH + (count - 1) * dy)
        return (0..<count).map { src.cropping(to: CGRect(x: 0, y: $0 * dy, width: width, height: sliceH))! }
    }

    /// Writes `images` as raw keyframes + a base manifest into a fresh session folder, returning
    /// (store, id, folder). Used to drive resolveGeometry directly.
    private func writeBase(_ images: [CGImage], root: URL) throws -> (SessionStore, UUID, URL) {
        let store = SessionStore(containerURL: root)
        let id = UUID()
        let folder = try store.createFolder(for: id)
        var session = StitchSession(id: id, createdAt: Date(), status: .complete, deviceScale: 1, orientation: .portrait, colorSpaceName: CGColorSpace.sRGB as String)
        for (i, img) in images.enumerated() {
            let name = String(format: "kf-%04d.bgra", i)
            try KeyframeIO.writeRaw(img, to: folder.appendingPathComponent(name))
            session.keyframes.append(Keyframe(filename: name, pixelWidth: img.width, pixelHeight: img.height, index: i))
        }
        try store.writeManifest(session)
        return (store, id, folder)
    }

    @Test func inputOrderStrategyTrustsOrderAndDoesNotBadge() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let imgs = Self.slices(count: 3, width: 120, sliceH: 360, dy: 140)  // in scroll order
        let (store, id, folder) = try writeBase(imgs, root: root)
        let session = try store.readManifest(for: id)
        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: .inputOrder)
        #expect(resolved.keyframes.map(\.index) == [0, 1, 2])
        #expect(resolved.segmentBreaks.isEmpty)
        #expect(resolved.orderAssumed == false)
    }

    @Test func recoverOrInputOrderBadgesWhenRecoveryCannotChain() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        // Two non-overlapping halves in pick order: recovery yields 2 segments → fallback + badge.
        let big = Self.makeSource(width: 120, height: 900)
        let a = big.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 300))!
        let b = big.cropping(to: CGRect(x: 0, y: 600, width: 120, height: 300))!
        let (store, id, folder) = try writeBase([a, b], root: root)
        let session = try store.readManifest(for: id)
        let resolved = try StitchAssembler.resolveGeometry(session, in: folder, strategy: .recoverOrInputOrder)
        #expect(resolved.orderAssumed == true)
        #expect(resolved.keyframes.map(\.index) == [0, 1])   // kept pick order in the fallback
    }
}
