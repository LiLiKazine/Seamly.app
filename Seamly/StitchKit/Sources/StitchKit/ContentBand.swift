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

    /// The most of a frame that static chrome may plausibly occupy before the measurement is
    /// treated as failed rather than believed.
    ///
    /// Real chrome is small — the `youtube-*` and baidu fixtures land around 2–8% per edge, and
    /// even a status bar plus nav bar plus tab bar plus home indicator stays far under half a
    /// screen. So this ceiling is deliberately loose: it is not tuned to reject *slightly* wrong
    /// bands (it can't — nothing here knows the true answer), only to catch measurements that
    /// cannot be chrome at all. A band at or past this fraction means the detector found no
    /// content, which is a different statement from "found a big bar".
    public static let maxChromeFraction = 0.5

    /// Whether this band leaves a plausible content region in a frame `height` px tall.
    ///
    /// Exists because an implausible band is not a recoverable edge case to clamp — clamping
    /// converts a detectable measurement failure into a plausible-looking wrong image. See
    /// `Compositor.plan` and `BatchStitcher.chromeBand`, which both degrade to `.unlocked`
    /// instead: chrome repeating is ugly and honest, content vanishing is neither.
    public func isPlausible(forFrameHeight height: Int) -> Bool {
        guard height > 0 else { return false }
        let chrome = max(0, topChrome) + max(0, bottomChrome)
        return Double(chrome) <= Double(height) * Self.maxChromeFraction
    }
}
