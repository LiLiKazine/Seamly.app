import Foundation

/// Why a segment was broken — content the tracker could not stitch across.
public enum SegmentBreakReason: String, Codable, Sendable {
    /// A fling with no frame-to-frame overlap that relocalization could not recover.
    case lostLock
    /// The frame dimensions changed mid-capture (device rotation).
    case rotation
}

/// The interface orientation of a segment. A rotation closes the current segment and
/// opens a new one rather than stitching across orientations.
public enum CaptureOrientation: String, Codable, Sendable {
    case portrait
    case landscape
}

/// One saved keyframe: a lossless full-resolution frame committed by the extension,
/// referenced by a filename relative to the session folder.
public struct Keyframe: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// File name within `sessions/<id>/`, e.g. `kf-0003.heic` or `kf-0003.bgra`.
    public var filename: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// Order of this keyframe within the capture, from 0.
    public var index: Int

    public init(id: UUID = UUID(), filename: String, pixelWidth: Int, pixelHeight: Int, index: Int) {
        self.id = id
        self.filename = filename
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.index = index
    }
}

/// The seam between keyframe `index` and keyframe `index + 1`: the extension's
/// *provisional* alignment plus the chrome bands to crop. The app snaps `provisionalDy`
/// to pixel-exact precision during compositing; it never recomputes from scratch.
public struct Seam: Codable, Sendable, Equatable {
    /// Index of the earlier keyframe in the pair.
    public var fromIndex: Int
    /// Provisional vertical offset in *source pixels* (profile rows scaled up).
    public var provisionalDy: Int
    /// Incidental horizontal offset in source pixels.
    public var provisionalDx: Int
    public var confidence: Double
    /// Static chrome to crop, in source pixels.
    public var chromeTopPixels: Int
    public var chromeBottomPixels: Int
    /// Flagged for review — low confidence, ambiguous chrome, or nonzero `dx`.
    public var isLowConfidence: Bool

    public init(
        fromIndex: Int,
        provisionalDy: Int,
        provisionalDx: Int = 0,
        confidence: Double,
        chromeTopPixels: Int = 0,
        chromeBottomPixels: Int = 0,
        isLowConfidence: Bool = false
    ) {
        self.fromIndex = fromIndex
        self.provisionalDy = provisionalDy
        self.provisionalDx = provisionalDx
        self.confidence = confidence
        self.chromeTopPixels = chromeTopPixels
        self.chromeBottomPixels = chromeBottomPixels
        self.isLowConfidence = isLowConfidence
    }
}

/// A labeled break in the capture — everything before and after is preserved; the app
/// can offer targeted "recapture this stretch."
public struct SegmentBreak: Codable, Sendable, Equatable {
    /// The break sits after this keyframe index.
    public var afterKeyframeIndex: Int
    public var reason: SegmentBreakReason

    public init(afterKeyframeIndex: Int, reason: SegmentBreakReason) {
        self.afterKeyframeIndex = afterKeyframeIndex
        self.reason = reason
    }
}

public enum SessionStatus: String, Codable, Sendable {
    /// Broadcast in progress, or ended without a clean `broadcastFinished()`.
    case recording
    /// Cleanly finalized.
    case complete
}

/// The `Codable` manifest handed off from the extension to the app through the App
/// Group. Written incrementally: each keyframe/seam appended on commit, `status`
/// flipped to `.complete` in `broadcastFinished()`. A crash leaves it `.recording`,
/// and such a partial session is still stitchable and badged "incomplete."
public struct StitchSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var createdAt: Date
    public var status: SessionStatus
    /// Device screen scale (`UIScreen.scale`) so the app can map points to pixels.
    public var deviceScale: Double
    public var orientation: CaptureOrientation
    /// Core Graphics color space name of the captured frames, preserved end-to-end.
    /// `nil` means "unknown — fall back to the frame's own tagging."
    public var colorSpaceName: String?
    public var keyframes: [Keyframe]
    public var seams: [Seam]
    public var segmentBreaks: [SegmentBreak]
    /// User's global top/bottom trim (source pixels) applied to the final image — a
    /// non-destructive manifest edit, so it re-composites instantly from the keyframes.
    public var topTrim: Int
    public var bottomTrim: Int

    public init(
        id: UUID = UUID(),
        createdAt: Date,
        status: SessionStatus = .recording,
        deviceScale: Double,
        orientation: CaptureOrientation,
        colorSpaceName: String? = nil,
        keyframes: [Keyframe] = [],
        seams: [Seam] = [],
        segmentBreaks: [SegmentBreak] = [],
        topTrim: Int = 0,
        bottomTrim: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.status = status
        self.deviceScale = deviceScale
        self.orientation = orientation
        self.colorSpaceName = colorSpaceName
        self.keyframes = keyframes
        self.seams = seams
        self.segmentBreaks = segmentBreaks
        self.topTrim = topTrim
        self.bottomTrim = bottomTrim
    }

    /// A session with fewer than two keyframes has nothing to stitch.
    public var hasStitchableContent: Bool { keyframes.count >= 2 }

    /// True when a segment break sits immediately after the given keyframe index.
    public func hasSegmentBreak(after index: Int) -> Bool {
        segmentBreaks.contains { $0.afterKeyframeIndex == index }
    }
}
