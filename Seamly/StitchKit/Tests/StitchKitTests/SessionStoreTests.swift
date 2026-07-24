import Testing
import CoreGraphics
import Foundation
@testable import StitchKit

private func tempContainer() -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("seamly-store-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

private func session(_ id: UUID, created: TimeInterval, status: SessionStatus = .complete) -> StitchSession {
    StitchSession(id: id, createdAt: Date(timeIntervalSince1970: created), status: status, deviceScale: 3, orientation: .portrait,
                  keyframes: [Keyframe(filename: "kf-0000.bgra", pixelWidth: 100, pixelHeight: 200, index: 0),
                              Keyframe(filename: "kf-0001.bgra", pixelWidth: 100, pixelHeight: 200, index: 1)],
                  seams: [Seam(fromIndex: 0, provisionalDy: 120, confidence: 0.9)])
}

@Suite struct SessionStoreTests {
    @Test func writesAndReadsManifest() throws {
        let store = SessionStore(containerURL: tempContainer())
        let original = session(UUID(), created: 100)
        try store.writeManifest(original)
        let read = try store.readManifest(for: original.id)
        #expect(read == original)
    }

    @Test func incrementalManifestUpdatesOverwrite() throws {
        let store = SessionStore(containerURL: tempContainer())
        var s = session(UUID(), created: 100, status: .recording)
        try store.writeManifest(s)
        s.keyframes.append(Keyframe(filename: "kf-0002.bgra", pixelWidth: 100, pixelHeight: 200, index: 2))
        s.status = .complete
        try store.writeManifest(s)
        let read = try store.readManifest(for: s.id)
        #expect(read.keyframes.count == 3)
        #expect(read.status == .complete)
    }

    @Test func loadAllReturnsNewestFirstAndSkipsCorruptFolders() throws {
        let store = SessionStore(containerURL: tempContainer())
        try store.writeManifest(session(UUID(), created: 100))
        try store.writeManifest(session(UUID(), created: 300))
        try store.writeManifest(session(UUID(), created: 200))
        // A stray folder with no manifest must not break the scan.
        try FileManager.default.createDirectory(at: store.folder(for: UUID()), withIntermediateDirectories: true)
        let all = store.loadAll()
        #expect(all.count == 3)
        #expect(all.map(\.createdAt) == [300, 200, 100].map { Date(timeIntervalSince1970: $0) })
    }

    @Test func partialRecordingSessionStillLoads() throws {
        let store = SessionStore(containerURL: tempContainer())
        try store.writeManifest(session(UUID(), created: 100, status: .recording))
        let all = store.loadAll()
        #expect(all.count == 1)
        #expect(all[0].status == .recording)
    }

    @Test func deleteRemovesSession() throws {
        let store = SessionStore(containerURL: tempContainer())
        let s = session(UUID(), created: 100)
        try store.writeManifest(s)
        try store.delete(s.id)
        #expect(store.loadAll().isEmpty)
    }

    @Test func rawKeyframeRoundTripsExactly() throws {
        let img = makeGradient(width: 64, height: 96)
        let url = tempContainer().appendingPathComponent("kf.bgra")
        try KeyframeIO.writeRaw(img, to: url)
        let back = try KeyframeIO.readRaw(from: url, width: 64, height: 96)
        #expect(back.width == 64 && back.height == 96)
        let a = gray(img), b = gray(back)
        var maxDiff = 0
        for i in 0..<min(a.count, b.count) { maxDiff = max(maxDiff, abs(Int(a[i]) - Int(b[i]))) }
        #expect(maxDiff <= 1)
    }

    @Test func heicKeyframeRoundTripsDimensions() throws {
        let img = makeGradient(width: 48, height: 72)
        let url = tempContainer().appendingPathComponent("kf.heic")
        try KeyframeIO.writeHEIC(img, to: url)
        let back = try KeyframeIO.read(from: url)
        #expect(back.width == 48 && back.height == 72)
    }
}

private func makeGradient(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for y in 0..<height {
        ctx.setFillColor(gray: CGFloat(y) / CGFloat(height), alpha: 1)
        ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
    }
    return ctx.makeImage()!
}

private func gray(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    return Array(UnsafeBufferPointer(start: p, count: w * h))
}
