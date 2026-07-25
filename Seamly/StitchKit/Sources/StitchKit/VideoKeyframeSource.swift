import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

/// Decodes a real screen recording through the SAME path the broadcast extension uses on device —
/// `AVAssetReader` → 32BGRA `CVPixelBuffer` → `PixelBufferImage.makeCGImage` → `ScrollCaptureDriver`
/// — so "From Video" reuses the proven capture picking against real decode, scroll, chrome, codec.
///
/// Sampling: the driver commits based on overlap with the last *committed keyframe*, so we do not
/// need every source frame. When `targetFPS` is set, a frame is profiled only when at least
/// `1/targetFPS` seconds have elapsed (by presentation timestamp) since the last profiled frame —
/// far less work on a 60fps recording, with enough granularity to catch each commit point. The
/// coarsest healthy cadence is validated against the fixture (see CaptureVideoTests).
public struct VideoKeyframeSource: Sendable {
    public struct Result: Sendable {
        public let frames: Int
        public let decodeFailures: Int
        public let keyframes: [ScrollCaptureDriver.CapturedKeyframe]
    }

    public enum VideoError: Error { case noVideoTrack, readFailed(Error?) }

    /// Decode `url` into `driver`, collecting committed keyframes (including the trailing
    /// `finish()` commit). Throws if there is no video track or the reader can't start; an
    /// individual frame that yields no image buffer is counted, not thrown (mirrors the
    /// extension's per-frame skip).
    public static func decodeCommittedKeyframes(
        url: URL,
        driver: inout ScrollCaptureDriver,
        targetFPS: Double? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Result {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw VideoError.noVideoTrack }
        let duration = try await asset.load(.duration)
        let totalSeconds = max(CMTimeGetSeconds(duration), 0.0001)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()

        let minInterval = targetFPS.map { 1.0 / $0 }
        var lastProfiledSeconds = -Double.greatestFiniteMagnitude
        var frames = 0, decodeFailures = 0
        var committed: [ScrollCaptureDriver.CapturedKeyframe] = []

        while reader.status == .reading, let sample = output.copyNextSampleBuffer() {
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let seconds = CMTimeGetSeconds(pts)
            // Throttle: skip decoding/profiling this frame if it's too close to the last one we
            // profiled. Sample buffers are still pulled sequentially (inter-frame codec needs it);
            // the saving is skipping makeCGImage + VerticalProfile.
            if let minInterval, seconds - lastProfiledSeconds < minInterval { continue }
            // Intentional skip, deliberately not counted as a decode failure: the output is
            // configured for 32BGRA, so every video sample carries an image buffer and this is
            // effectively unreachable. A non-video sample that slipped through has no frame to
            // profile, so there is nothing to record — unlike `makeCGImage` returning nil below,
            // which *is* a real decode failure and is counted.
            guard let pb = CMSampleBufferGetImageBuffer(sample) else { continue }
            autoreleasepool {
                guard let image = PixelBufferImage.makeCGImage(from: pb) else { decodeFailures += 1; return }
                frames += 1
                lastProfiledSeconds = seconds
                if let kf = driver.ingest(image).keyframe { committed.append(kf) }
            }
            progress?(min(1, max(0, seconds / totalSeconds)))
        }
        if reader.status == .failed { throw VideoError.readFailed(reader.error) }
        if let tail = driver.finish() { committed.append(tail) }
        progress?(1)
        return Result(frames: frames, decodeFailures: decodeFailures, keyframes: committed)
    }
}
