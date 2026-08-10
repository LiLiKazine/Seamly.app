import Foundation

/// Static chrome to crop from a keyframe, expressed in source pixels.
public struct ChromeInsets: Codable, Sendable, Equatable {
    /// Static top chrome to crop, in source pixels.
    public var top: Int
    /// Static bottom chrome to crop, in source pixels.
    public var bottom: Int

    public init(top: Int = 0, bottom: Int = 0) {
        self.top = top
        self.bottom = bottom
    }

    public static let zero = ChromeInsets()

    /// The most of a keyframe that chrome may plausibly occupy before the measurement is
    /// treated as unsafe. Matching the legacy segment-band ceiling keeps the same safety
    /// posture without using segment bands as a fallback.
    public static let maxCombinedCropFraction = 0.5

    public func isPlausible(forPixelHeight pixelHeight: Int) -> Bool {
        guard pixelHeight > 0, top >= 0, bottom >= 0 else { return false }
        return Double(top + bottom) <= Double(pixelHeight) * Self.maxCombinedCropFraction
    }
}

/// Automatic chrome measurement for one keyframe. Insets and confidence are persisted
/// together, with confidence modeled independently per edge.
public struct ChromeMeasurement: Codable, Sendable, Equatable {
    public var insets: ChromeInsets
    public var topConfidence: Double
    public var bottomConfidence: Double

    public init(insets: ChromeInsets, topConfidence: Double, bottomConfidence: Double) {
        self.insets = insets
        self.topConfidence = topConfidence
        self.bottomConfidence = bottomConfidence
    }

    public init(insets: ChromeInsets, confidence: Double) {
        self.init(insets: insets, topConfidence: confidence, bottomConfidence: confidence)
    }

    public var hasValidConfidence: Bool {
        Self.isValidConfidence(topConfidence) && Self.isValidConfidence(bottomConfidence)
    }

    public static func isValidConfidence(_ confidence: Double) -> Bool {
        confidence.isFinite && (0...1).contains(confidence)
    }

    private enum CodingKeys: String, CodingKey {
        case insets
        case topConfidence
        case bottomConfidence
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        insets = try c.decode(ChromeInsets.self, forKey: .insets)
        topConfidence = try c.decode(Double.self, forKey: .topConfidence)
        bottomConfidence = try c.decode(Double.self, forKey: .bottomConfidence)

        guard Self.isValidConfidence(topConfidence) else {
            throw DecodingError.dataCorruptedError(
                forKey: .topConfidence,
                in: c,
                debugDescription: "topConfidence must be finite and within 0...1"
            )
        }
        guard Self.isValidConfidence(bottomConfidence) else {
            throw DecodingError.dataCorruptedError(
                forKey: .bottomConfidence,
                in: c,
                debugDescription: "bottomConfidence must be finite and within 0...1"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        guard Self.isValidConfidence(topConfidence) else {
            throw EncodingError.invalidValue(
                topConfidence,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "topConfidence must be finite and within 0...1"
                )
            )
        }
        guard Self.isValidConfidence(bottomConfidence) else {
            throw EncodingError.invalidValue(
                bottomConfidence,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "bottomConfidence must be finite and within 0...1"
                )
            )
        }

        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(insets, forKey: .insets)
        try c.encode(topConfidence, forKey: .topConfidence)
        try c.encode(bottomConfidence, forKey: .bottomConfidence)
    }
}

/// User-authored chrome override. Each edge is optional so a user can override top while
/// leaving bottom on the automatic measurement, or vice versa.
public struct ChromeOverride: Codable, Sendable, Equatable {
    public var top: Int?
    public var bottom: Int?

    public init(top: Int? = nil, bottom: Int? = nil) {
        self.top = top
        self.bottom = bottom
    }

    public var hasAnyEdge: Bool {
        top != nil || bottom != nil
    }
}

/// The persisted chrome layers for one keyframe, keyed by `Keyframe.id`.
public struct KeyframeChrome: Codable, Sendable, Equatable {
    public let keyframeID: UUID
    public var automatic: ChromeMeasurement?
    public var userOverride: ChromeOverride?

    public init(
        keyframeID: UUID,
        automatic: ChromeMeasurement? = nil,
        userOverride: ChromeOverride? = nil
    ) {
        self.keyframeID = keyframeID
        self.automatic = automatic
        self.userOverride = userOverride
    }
}

public enum ChromeResolutionSource: String, Codable, Sendable, Equatable {
    case none
    case automatic
    case userOverride
}

/// A resolved per-keyframe chrome crop. `.unlocked` means there is no safe crop to apply:
/// callers should treat the whole keyframe as content rather than clamping an unsafe value.
public struct ResolvedChrome: Sendable, Equatable {
    public let insets: ChromeInsets
    public let topSource: ChromeResolutionSource
    public let bottomSource: ChromeResolutionSource
    public var isUnlocked: Bool { topSource == .none && bottomSource == .none }

    init(
        insets: ChromeInsets,
        topSource: ChromeResolutionSource,
        bottomSource: ChromeResolutionSource
    ) {
        self.insets = insets
        self.topSource = topSource
        self.bottomSource = bottomSource
    }

    public static let unlocked = ResolvedChrome(
        insets: .zero,
        topSource: .none,
        bottomSource: .none
    )
}

public enum ChromeEdge: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case top
    case bottom
}

public enum KeyframeChromeValidationIssue: Sendable, Equatable {
    case duplicateRecord(keyframeID: UUID)
    case danglingRecord(keyframeID: UUID)
    case invalidAutomaticConfidence(keyframeID: UUID, edge: ChromeEdge)
}

public struct KeyframeChromeValidationError: Error, Sendable, Equatable {
    public var issues: [KeyframeChromeValidationIssue]

    public init(issues: [KeyframeChromeValidationIssue]) {
        self.issues = issues
    }
}
