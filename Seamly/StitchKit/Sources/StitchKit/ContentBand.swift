import Foundation

/// The scrolling content region of a segment, expressed as the static chrome cropped from
/// each edge in **source pixels**. The content is rows `[topChrome, height − bottomChrome)`.
///
/// One `ContentBand` is locked per segment via multi-frame consensus (`ContentBandDetector`)
/// and drives both the compositor's crop and — post-lock — the matcher's row restriction.
/// When no confident band locks, the band is `{0, 0}` with `isLowConfidence == true`: the
/// whole frame is treated as content (chrome merely repeats rather than content being lost),
/// and the editor override is the fallback. That is the meaning of `.unlocked`.
public struct ContentBand: Codable, Sendable, Equatable {
    /// Static top chrome to crop, in source pixels.
    public var topChrome: Int
    /// Static bottom chrome to crop, in source pixels.
    public var bottomChrome: Int
    /// True when no confident band locked for the segment — the segment is flagged for the
    /// editor rather than silently mis-cropped. (A sharp mid-segment change is handled by a
    /// segment break, not by flagging a locked band.)
    public var isLowConfidence: Bool

    public init(topChrome: Int = 0, bottomChrome: Int = 0, isLowConfidence: Bool = false) {
        self.topChrome = topChrome
        self.bottomChrome = bottomChrome
        self.isLowConfidence = isLowConfidence
    }

    /// No confident band: whole frame is content, flagged low-confidence for editor override.
    public static let unlocked = ContentBand(topChrome: 0, bottomChrome: 0, isLowConfidence: true)
}
