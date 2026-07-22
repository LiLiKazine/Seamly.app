import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@testable import StitchKit

/// Decodes a real screen recording through the SAME path the extension uses on device —
/// `AVAssetReader` → 32BGRA `CVPixelBuffer` → `PixelBufferImage.makeCGImage` → `ScrollCaptureDriver`
/// — so the video tier exercises the real decode path, real scroll dynamics, real chrome, and the
/// real codec. This is the only tier that touches `PixelBufferImage`/`AVAssetReader`.
enum VideoFrameSource {
    struct Result {
        let frames: Int
        let decodeFailures: Int
        let keyframes: [ScrollCaptureDriver.CapturedKeyframe]
    }

    /// Decode every frame of `url` into the driver and collect the committed keyframes (including
    /// the trailing `finish()` commit). Throws if the asset has no video track or the reader can't
    /// start — a decode failure of an individual frame is counted, not thrown (mirrors the
    /// extension's per-frame skip).
    static func decodeCommittedKeyframes(url: URL, driver: inout ScrollCaptureDriver) throws -> Result {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw VideoError.noVideoTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        var frames = 0, decodeFailures = 0
        var committed: [ScrollCaptureDriver.CapturedKeyframe] = []
        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            autoreleasepool {
                guard let image = PixelBufferImage.makeCGImage(from: pb) else { decodeFailures += 1; return }
                frames += 1
                if let kf = driver.ingest(image).keyframe { committed.append(kf) }
            }
        }
        if reader.status == .failed {
            throw VideoError.readFailed(reader.error)
        }
        if let tail = driver.finish() { committed.append(tail) }
        return Result(frames: frames, decodeFailures: decodeFailures, keyframes: committed)
    }

    enum VideoError: Error { case noVideoTrack, readFailed(Error?) }
}
