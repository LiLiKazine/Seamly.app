import Foundation

/// Why a segment was broken — content the tracker could not stitch across.
public enum SegmentBreakReason: String, Codable, Sendable {
    /// A fling with no frame-to-frame overlap that relocalization could not recover.
    case lostLock
    /// The frame dimensions changed mid-capture (device rotation).
    case rotation
    /// The locked content band changed shape sharply (a collapsing header, a keyboard) —
    /// the new steady state re-locks in the fresh segment.
    case contentChanged
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
/// *provisional* alignment. The app snaps `provisionalDy` to pixel-exact precision during
/// compositing; it never recomputes from scratch. Chrome to crop lives per-segment on
/// `StitchSession.contentBands`, not here.
public struct Seam: Codable, Sendable, Equatable {
    /// Index of the earlier keyframe in the pair.
    public var fromIndex: Int
    /// Provisional vertical offset in *source pixels* (profile rows scaled up).
    public var provisionalDy: Int
    /// Incidental horizontal offset in source pixels.
    public var provisionalDx: Int
    public var confidence: Double
    /// Flagged for review — low confidence or nonzero `dx`. (Chrome is no longer per-seam;
    /// it is a per-segment `ContentBand` on `StitchSession`.)
    public var isLowConfidence: Bool

    public init(
        fromIndex: Int,
        provisionalDy: Int,
        provisionalDx: Int = 0,
        confidence: Double,
        isLowConfidence: Bool = false
    ) {
        self.fromIndex = fromIndex
        self.provisionalDy = provisionalDy
        self.provisionalDx = provisionalDx
        self.confidence = confidence
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
    /// One content band per segment (segment order matches `splitIntoSegments`), locked by
    /// the extension's multi-frame consensus and used by the compositor's crop. A missing or
    /// short array means "no confident band" — segments beyond it are treated as `.unlocked`.
    public var contentBands: [ContentBand]
    /// User's global top/bottom trim (source pixels) applied to the final image — a
    /// non-destructive manifest edit, so it re-composites instantly from the keyframes.
    public var topTrim: Int
    public var bottomTrim: Int
    /// True when scroll order was *assumed* from input order because overlap recovery produced
    /// segment breaks. Drives an "order assumed" badge for Photos picks and broadcast imports that
    /// take that fallback. Never set for recovered order or authoritative `.inputOrder` sources
    /// such as decoded video.
    public var orderAssumed: Bool

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
        contentBands: [ContentBand] = [],
        topTrim: Int = 0,
        bottomTrim: Int = 0,
        orderAssumed: Bool = false
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
        self.contentBands = contentBands
        self.topTrim = topTrim
        self.bottomTrim = bottomTrim
        self.orderAssumed = orderAssumed
    }

    /// Custom decoding so fields added over time degrade gracefully. The manifest is written
    /// incrementally and read across app/extension builds that may differ; a missing key must
    /// default, not throw (which — via `SessionStore.loadAll`'s `try?` — would silently drop a
    /// whole capture). Required structural fields are still mandatory.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        status = try c.decode(SessionStatus.self, forKey: .status)
        deviceScale = try c.decode(Double.self, forKey: .deviceScale)
        orientation = try c.decode(CaptureOrientation.self, forKey: .orientation)
        colorSpaceName = try c.decodeIfPresent(String.self, forKey: .colorSpaceName)
        keyframes = try c.decode([Keyframe].self, forKey: .keyframes)
        seams = try c.decode([Seam].self, forKey: .seams)
        segmentBreaks = try c.decode([SegmentBreak].self, forKey: .segmentBreaks)
        contentBands = try c.decodeIfPresent([ContentBand].self, forKey: .contentBands) ?? []
        topTrim = try c.decodeIfPresent(Int.self, forKey: .topTrim) ?? 0
        bottomTrim = try c.decodeIfPresent(Int.self, forKey: .bottomTrim) ?? 0
        orderAssumed = try c.decodeIfPresent(Bool.self, forKey: .orderAssumed) ?? false
    }

    /// A session with fewer than two keyframes has nothing to stitch.
    public var hasStitchableContent: Bool { keyframes.count >= 2 }

    /// True when a segment break sits immediately after the given keyframe index.
    public func hasSegmentBreak(after index: Int) -> Bool {
        segmentBreaks.contains { $0.afterKeyframeIndex == index }
    }

    /// The content band for segment `index` (0-based, in `splitIntoSegments` order), or
    /// `.unlocked` when none was recorded — no confident band, so the whole frame is content.
    public func contentBand(forSegment index: Int) -> ContentBand {
        guard index >= 0, index < contentBands.count else { return .unlocked }
        return contentBands[index]
    }
}
