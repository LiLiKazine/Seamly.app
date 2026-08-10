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
/// *provisional* alignment. The app snaps `provisionalDy` to pixel-exact precision during
/// compositing; it never recomputes from scratch. Chrome to crop is keyed by `Keyframe.id`
/// in `StitchSession.keyframeChrome`, not stored on the seam.
public struct Seam: Codable, Sendable, Equatable {
    /// Index of the earlier keyframe in the pair.
    public var fromIndex: Int
    /// Provisional vertical offset in *source pixels* (profile rows scaled up).
    public var provisionalDy: Int
    /// Incidental horizontal offset in source pixels.
    public var provisionalDx: Int
    public var confidence: Double
    /// Flagged for review — low confidence or nonzero `dx`.
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

public enum StitchSessionManifestFormat: String, Codable, Sendable, Equatable {
    case keyframeChromePreRelease = "stitch-session.keyframe-chrome.v1"
}

/// The `Codable` manifest handed off from the extension to the app through the App
/// Group. Written incrementally: each keyframe/seam appended on commit, `status`
/// flipped to `.complete` in `broadcastFinished()`. A crash leaves it `.recording`,
/// and such a partial session is still stitchable and badged "incomplete."
public struct StitchSession: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public private(set) var manifestFormat: StitchSessionManifestFormat
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
    /// Per-keyframe chrome records keyed by `Keyframe.id`. Automatic measurement and user override
    /// are distinct persisted layers inside each record.
    public var keyframeChrome: [KeyframeChrome]
    /// User's global top/bottom trim (source pixels) applied to the final image — a
    /// non-destructive manifest edit, so it re-composites instantly from the keyframes.
    public var topTrim: Int
    public var bottomTrim: Int
    /// True when scroll order was *assumed* from input order because overlap recovery produced
    /// segment breaks. Drives an "order assumed" badge for Photos picks and broadcast imports that
    /// take that fallback. Never set for recovered order or authoritative `.inputOrder` sources
    /// such as decoded video.
    public var orderAssumed: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case manifestFormat
        case createdAt
        case status
        case deviceScale
        case orientation
        case colorSpaceName
        case keyframes
        case seams
        case segmentBreaks
        case keyframeChrome
        case topTrim
        case bottomTrim
        case orderAssumed
    }

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
        keyframeChrome: [KeyframeChrome] = [],
        topTrim: Int = 0,
        bottomTrim: Int = 0,
        orderAssumed: Bool = false
    ) {
        self.id = id
        self.manifestFormat = .keyframeChromePreRelease
        self.createdAt = createdAt
        self.status = status
        self.deviceScale = deviceScale
        self.orientation = orientation
        self.colorSpaceName = colorSpaceName
        self.keyframes = keyframes
        self.seams = seams
        self.segmentBreaks = segmentBreaks
        self.keyframeChrome = keyframeChrome
        self.topTrim = topTrim
        self.bottomTrim = bottomTrim
        self.orderAssumed = orderAssumed
    }

    /// Custom decoding for the unreleased keyframe-chrome manifest schema. Old manifests are
    /// rejected by the required `manifestFormat` marker rather than silently defaulted through
    /// compatibility logic.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        manifestFormat = try c.decode(StitchSessionManifestFormat.self, forKey: .manifestFormat)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        status = try c.decode(SessionStatus.self, forKey: .status)
        deviceScale = try c.decode(Double.self, forKey: .deviceScale)
        orientation = try c.decode(CaptureOrientation.self, forKey: .orientation)
        colorSpaceName = try c.decodeIfPresent(String.self, forKey: .colorSpaceName)
        keyframes = try c.decode([Keyframe].self, forKey: .keyframes)
        seams = try c.decode([Seam].self, forKey: .seams)
        segmentBreaks = try c.decode([SegmentBreak].self, forKey: .segmentBreaks)
        keyframeChrome = try c.decode([KeyframeChrome].self, forKey: .keyframeChrome)
        topTrim = try c.decode(Int.self, forKey: .topTrim)
        bottomTrim = try c.decode(Int.self, forKey: .bottomTrim)
        orderAssumed = try c.decode(Bool.self, forKey: .orderAssumed)
        try validateKeyframeChrome()
    }

    public func encode(to encoder: any Encoder) throws {
        try validateKeyframeChrome()
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(manifestFormat, forKey: .manifestFormat)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(status, forKey: .status)
        try c.encode(deviceScale, forKey: .deviceScale)
        try c.encode(orientation, forKey: .orientation)
        try c.encodeIfPresent(colorSpaceName, forKey: .colorSpaceName)
        try c.encode(keyframes, forKey: .keyframes)
        try c.encode(seams, forKey: .seams)
        try c.encode(segmentBreaks, forKey: .segmentBreaks)
        try c.encode(keyframeChrome.sortedForDeterministicEncoding(), forKey: .keyframeChrome)
        try c.encode(topTrim, forKey: .topTrim)
        try c.encode(bottomTrim, forKey: .bottomTrim)
        try c.encode(orderAssumed, forKey: .orderAssumed)
    }

    /// A session with fewer than two keyframes has nothing to stitch.
    public var hasStitchableContent: Bool { keyframes.count >= 2 }

    /// True when a segment break sits immediately after the given keyframe index.
    public func hasSegmentBreak(after index: Int) -> Bool {
        segmentBreaks.contains { $0.afterKeyframeIndex == index }
    }

    public func resolvedChrome(forKeyframeID keyframeID: UUID) -> ResolvedChrome {
        guard let keyframe = keyframes.first(where: { $0.id == keyframeID }) else { return .unlocked }
        return resolvedChrome(for: keyframe)
    }

    public func resolvedChrome(for keyframe: Keyframe) -> ResolvedChrome {
        guard let canonicalKeyframe = keyframes.first(where: { $0.id == keyframe.id }) else { return .unlocked }
        guard let record = uniqueChromeRecord(for: keyframe.id) else { return .unlocked }

        let (top, topSource) = resolvedEdge(.top, in: record)
        let (bottom, bottomSource) = resolvedEdge(.bottom, in: record)

        let insets = ChromeInsets(top: top, bottom: bottom)
        guard insets.isPlausible(forPixelHeight: canonicalKeyframe.pixelHeight) else { return .unlocked }

        return ResolvedChrome(
            insets: insets,
            topSource: topSource,
            bottomSource: bottomSource
        )
    }

    /// Edges with neither an explicit user value nor positive-confidence automatic evidence.
    /// Resolution remains lossless (zero crop), while the app can surface the uncertainty rather
    /// than treating an unobservable edge as a confidently measured absence of chrome.
    public func chromeEdgesNeedingReview(for keyframe: Keyframe) -> Set<ChromeEdge> {
        guard keyframes.contains(where: { $0.id == keyframe.id }),
              let record = uniqueChromeRecord(for: keyframe.id) else {
            return Set(ChromeEdge.allCases)
        }
        var result: Set<ChromeEdge> = []
        if record.userOverride?.top == nil,
           !(record.automatic.map { ChromeMeasurement.isValidConfidence($0.topConfidence) && $0.topConfidence > 0 } ?? false) {
            result.insert(.top)
        }
        if record.userOverride?.bottom == nil,
           !(record.automatic.map { ChromeMeasurement.isValidConfidence($0.bottomConfidence) && $0.bottomConfidence > 0 } ?? false) {
            result.insert(.bottom)
        }
        return result
    }

    /// Ensure the editable layer has one UUID-owned record for every keyframe. Missing automatic
    /// evidence remains `nil`; this creates ownership, not a synthetic measurement.
    public mutating func ensureChromeRecordsForKeyframes() {
        let recordedIDs = Set(keyframeChrome.map(\.keyframeID))
        keyframeChrome.append(contentsOf: keyframes
            .filter { !recordedIDs.contains($0.id) }
            .map { KeyframeChrome(keyframeID: $0.id) })
    }

    public func chromeValueForEditing(_ edge: ChromeEdge, keyframeID: UUID) -> Int {
        guard let record = uniqueChromeRecord(for: keyframeID) else { return 0 }
        return max(0, resolvedEdge(edge, in: record).value)
    }

    public func hasChromeOverride(_ edge: ChromeEdge, keyframeID: UUID) -> Bool {
        guard let override = uniqueChromeRecord(for: keyframeID)?.userOverride else { return false }
        return edge == .top ? override.top != nil : override.bottom != nil
    }

    /// Set or clear one manual edge. Values are clamped against the other effective edge so an
    /// editor cannot create a combined crop beyond the same plausibility ceiling the compositor
    /// enforces.
    public mutating func setChromeOverride(_ value: Int?, for edge: ChromeEdge, keyframeID: UUID) {
        guard let keyframe = keyframes.first(where: { $0.id == keyframeID }) else { return }
        ensureChromeRecordsForKeyframes()
        guard keyframeChrome.filter({ $0.keyframeID == keyframeID }).count == 1,
              let index = keyframeChrome.firstIndex(where: { $0.keyframeID == keyframeID }) else { return }

        var override = keyframeChrome[index].userOverride ?? ChromeOverride()
        let storedValue: Int?
        if let value {
            let other: ChromeEdge = edge == .top ? .bottom : .top
            let combinedLimit = Int(Double(keyframe.pixelHeight) * ChromeInsets.maxCombinedCropFraction)
            storedValue = min(max(0, value), max(0, combinedLimit - chromeValueForEditing(other, keyframeID: keyframeID)))
        } else {
            storedValue = nil
        }
        switch edge {
        case .top: override.top = storedValue
        case .bottom: override.bottom = storedValue
        }
        keyframeChrome[index].userOverride = override.hasAnyEdge ? override : nil
    }

    public func keyframeChromeValidationIssues() -> [KeyframeChromeValidationIssue] {
        let validKeyframeIDs = Set(keyframes.map(\.id))
        var counts: [UUID: Int] = [:]
        var invalidConfidenceEdgesByID: [UUID: Set<ChromeEdge>] = [:]
        for record in keyframeChrome {
            counts[record.keyframeID, default: 0] += 1
            guard let automatic = record.automatic else { continue }
            if !ChromeMeasurement.isValidConfidence(automatic.topConfidence) {
                invalidConfidenceEdgesByID[record.keyframeID, default: []].insert(.top)
            }
            if !ChromeMeasurement.isValidConfidence(automatic.bottomConfidence) {
                invalidConfidenceEdgesByID[record.keyframeID, default: []].insert(.bottom)
            }
        }

        let duplicateIssues = counts
            .filter { $0.value > 1 }
            .map(\.key)
            .sortedByUUIDString()
            .map { KeyframeChromeValidationIssue.duplicateRecord(keyframeID: $0) }

        let danglingIssues = counts.keys
            .filter { !validKeyframeIDs.contains($0) }
            .sortedByUUIDString()
            .map { KeyframeChromeValidationIssue.danglingRecord(keyframeID: $0) }

        let invalidConfidenceIssues = invalidConfidenceEdgesByID.keys
            .sortedByUUIDString()
            .flatMap { keyframeID in
                ChromeEdge.allCases
                    .filter { invalidConfidenceEdgesByID[keyframeID]?.contains($0) == true }
                    .map { KeyframeChromeValidationIssue.invalidAutomaticConfidence(keyframeID: keyframeID, edge: $0) }
            }

        return duplicateIssues + danglingIssues + invalidConfidenceIssues
    }

    public func validateKeyframeChrome() throws {
        let issues = keyframeChromeValidationIssues()
        guard issues.isEmpty else { throw KeyframeChromeValidationError(issues: issues) }
    }

    private func uniqueChromeRecord(for keyframeID: UUID) -> KeyframeChrome? {
        let matches = keyframeChrome.filter { $0.keyframeID == keyframeID }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private func resolvedEdge(
        _ edge: ChromeEdge,
        in record: KeyframeChrome
    ) -> (value: Int, source: ChromeResolutionSource) {
        let override = edge == .top ? record.userOverride?.top : record.userOverride?.bottom
        if let override { return (override, .userOverride) }
        guard let automatic = record.automatic else { return (0, .none) }
        let confidence = edge == .top ? automatic.topConfidence : automatic.bottomConfidence
        guard ChromeMeasurement.isValidConfidence(confidence) else { return (0, .none) }
        return (edge == .top ? automatic.insets.top : automatic.insets.bottom, .automatic)
    }
}

private extension Array where Element == KeyframeChrome {
    func sortedForDeterministicEncoding() -> [KeyframeChrome] {
        sorted { lhs, rhs in
            lhs.keyframeID.uuidString < rhs.keyframeID.uuidString
        }
    }
}

private extension Sequence where Element == UUID {
    func sortedByUUIDString() -> [UUID] {
        sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }
}
