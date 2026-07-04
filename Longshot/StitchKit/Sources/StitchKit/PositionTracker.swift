import Foundation

/// What happened to the capture when a frame was processed.
public enum TrackingDecision: Equatable, Sendable {
    /// New rows were revealed beyond the union and appended.
    case appended(rows: Int)
    /// The frame fell within the already-captured union (back-scroll, pause) — nothing new.
    case skipped
    /// Frame-to-frame lock was lost but the frame was re-found in the accumulated map;
    /// `rows` is any new content appended after re-locking (often 0).
    case relocalized(rows: Int)
    /// Lock was lost and could not be recovered — the current segment closed and a new one
    /// started at a labeled break, seeded by this frame.
    case segmentBreak(reason: SegmentBreakReason)
}

/// The outcome of processing one frame.
public struct TrackingResult: Equatable, Sendable {
    public let decision: TrackingDecision
    /// True when overlap has dropped low enough to warn the user (drives the sound/haptic cue).
    public let needsSafetyCue: Bool
    /// Content-space row of the current frame's top within its segment.
    public let position: Int
    /// Furthest content row captured in the current segment.
    public let maxY: Int
    /// Match confidence for this frame.
    public let confidence: Double
    /// Index of the segment this frame belongs to (bumped on every break).
    public let segmentIndex: Int
    /// The current segment's content band (source pixels), once consensus has locked it;
    /// `.unlocked` (whole frame is content, flagged) until then. One band governs the whole
    /// segment — the caller records the last value per segment.
    public let contentBand: ContentBand

    public init(decision: TrackingDecision, needsSafetyCue: Bool, position: Int, maxY: Int, confidence: Double, segmentIndex: Int, contentBand: ContentBand = .unlocked) {
        self.decision = decision
        self.needsSafetyCue = needsSafetyCue
        self.position = position
        self.maxY = maxY
        self.confidence = confidence
        self.segmentIndex = segmentIndex
        self.contentBand = contentBand
    }
}

/// Tracks the user's absolute scroll position in content-space and decides, per frame,
/// what to append. Implements the design's "capture the union" core model: hold a captured
/// interval `[0 … maxY]`, match each frame against the previous one (tracking) or against
/// the accumulated 1-D map (relocalize), and append only content revealed beyond `maxY`.
///
/// A value type used serially on the extension's frame-processing path — no shared mutable
/// state across tasks, so no actor is needed; state lives in the struct and mutates in place.
public struct PositionTracker: Sendable {
    private let matcher: OffsetMatcher
    /// Pristine detector config, copied into `detector` at the start of each segment.
    private let detectorTemplate: ContentBandDetector
    /// Overlap fraction below which the safety cue should fire (before content is lost).
    private let safetyMargin: Double
    /// Tracking-match confidence below which we treat the lock as lost and relocalize.
    private let minTrackingConfidence: Double
    /// Relocalize-match confidence required to re-lock rather than break the segment.
    private let relocalizeConfidence: Double
    /// Relocalize search half-window, in multiples of the frame height, around the last
    /// known position — biases toward where we were and bounds the search cost.
    private let relocalizeWindowFrames: Int
    /// Consecutive moving pairs that must all show a sharp band change before the segment
    /// breaks — persistence guards against a single unreliable pair.
    private let sharpChangeToBreak: Int

    // Mutable capture state (current segment).
    private var started = false
    private var segmentIndex = 0
    private var segmentWidth = 0
    private var segmentRowScale: Double = 1
    private var previous: FrameProfile?
    private var position = 0
    private var maxY = 0
    private var mapMeans: [Float] = []
    private var mapVariances: [Float] = []
    /// Per-segment content-band consensus; reset from `detectorTemplate` at each segment start.
    private var detector: ContentBandDetector
    /// Consecutive moving pairs showing a sharp band change (reset on any non-sharp pair).
    private var sharpChangeStreak = 0

    public init(
        matcher: OffsetMatcher = OffsetMatcher(),
        bandDetector: ContentBandDetector = ContentBandDetector(),
        safetyMargin: Double = 0.4,
        minTrackingConfidence: Double = 0.3,
        relocalizeConfidence: Double = 0.5,
        relocalizeWindowFrames: Int = 4,
        sharpChangeToBreak: Int = 2
    ) {
        self.matcher = matcher
        self.detectorTemplate = bandDetector
        self.detector = bandDetector
        self.safetyMargin = safetyMargin
        self.minTrackingConfidence = minTrackingConfidence
        self.relocalizeConfidence = relocalizeConfidence
        self.relocalizeWindowFrames = relocalizeWindowFrames
        self.sharpChangeToBreak = sharpChangeToBreak
    }

    public mutating func process(_ frame: FrameProfile) -> TrackingResult {
        if !started {
            startSegment(frame)
            return result(.appended(rows: frame.rowCount), cue: false, confidence: 1)
        }

        // Orientation change closes the segment rather than stitching across rotations.
        if frame.sourceWidth != segmentWidth {
            segmentIndex += 1
            startSegment(frame)
            return result(.segmentBreak(reason: .rotation), cue: false, confidence: 1)
        }

        let n = frame.rowCount
        let bound = max(0, n - matcher.minimumOverlap)
        // Restrict matching to content rows so static chrome can't pin the offset to dy=0:
        // the locked band once consensus is confident, else the adaptive per-pair static
        // mask (bootstrap). A nil mask (pre-scroll / still frames) matches every row.
        let mask: [Bool]?
        if let locked = detector.lockedBand {
            mask = contentMask(rowCount: n, top: locked.top, bottom: locked.bottom)
        } else {
            mask = detector.staticMask(previous!, frame)
        }
        let m = matcher.match(previous!, frame, searchRange: -bound...bound, rowMask: mask)
        let overlapRows = n - abs(m.dy)
        let lostLock = m.confidence < minTrackingConfidence || overlapRows < matcher.minimumOverlap

        if lostLock {
            return relocalize(frame)
        }

        // A locked band that changes shape sharply (collapsing header, keyboard) closes the
        // segment. Require the change to *persist* across consecutive moving pairs before
        // breaking — a single pair is unreliable (a slow/uniform row just inside the chrome
        // edge can momentarily read static), the same reason the band lock needs consensus.
        if detector.lockedBand != nil, detector.bandChangedSharply(previous!, frame) {
            sharpChangeStreak += 1
        } else {
            sharpChangeStreak = 0
        }
        if sharpChangeStreak >= sharpChangeToBreak {
            segmentIndex += 1
            startSegment(frame)
            return result(.segmentBreak(reason: .contentChanged), cue: true, confidence: m.confidence)
        }

        // Fold this pair into the band consensus (only moving pairs vote, inside observe).
        detector.observe(previous!, frame, dy: m.dy)

        let newPosition = position + m.dy
        let overlapFraction = Double(overlapRows) / Double(n)
        let appended = commit(position: newPosition, frame: frame)
        position = newPosition
        previous = frame
        let decision: TrackingDecision = appended > 0 ? .appended(rows: appended) : .skipped
        return result(decision, cue: overlapFraction < safetyMargin, confidence: m.confidence)
    }

    // MARK: - Relocalize

    private mutating func relocalize(_ frame: FrameProfile) -> TrackingResult {
        let window = relocalizeWindowFrames * frame.rowCount
        let lo = max(0, position - window)
        let hi = min(maxY - matcher.minimumOverlap, position + window)

        if hi >= lo, !mapMeans.isEmpty {
            let map = FrameProfile(means: mapMeans, variances: mapVariances, sourceWidth: segmentWidth, sourceHeight: maxY)
            let m = matcher.match(map, frame, searchRange: lo...hi)
            if m.confidence >= relocalizeConfidence {
                let newPosition = m.dy   // absolute position: the map starts at content row 0
                let appended = commit(position: newPosition, frame: frame)
                position = newPosition
                previous = frame
                return result(.relocalized(rows: appended), cue: true, confidence: m.confidence)
            }
        }

        // Genuinely new, never-seen content: a real gap.
        segmentIndex += 1
        startSegment(frame)
        return result(.segmentBreak(reason: .lostLock), cue: true, confidence: 0)
    }

    // MARK: - State helpers

    private mutating func startSegment(_ frame: FrameProfile) {
        started = true
        segmentWidth = frame.sourceWidth
        segmentRowScale = frame.rowScale
        previous = frame
        position = 0
        maxY = frame.rowCount
        mapMeans = frame.means
        mapVariances = frame.variances
        detector = detectorTemplate
        sharpChangeStreak = 0
    }

    /// A content mask (screen-row indexed) for the locked band: `true` for content rows
    /// `[top, n − bottom)`, `false` for the chrome edges.
    private func contentMask(rowCount n: Int, top: Int, bottom: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: n)
        let lo = min(max(0, top), n)
        let hi = max(lo, n - max(0, bottom))
        for i in lo..<hi { mask[i] = true }
        return mask
    }

    /// Extends the union/map with any rows the frame reveals beyond `maxY`; returns the
    /// count appended (0 when the frame lies within the captured range).
    private mutating func commit(position: Int, frame: FrameProfile) -> Int {
        let frameBottom = position + frame.rowCount
        guard frameBottom > maxY else { return 0 }
        let startRow = max(0, maxY - position)
        guard startRow < frame.rowCount else { return 0 }
        mapMeans.append(contentsOf: frame.means[startRow...])
        mapVariances.append(contentsOf: frame.variances[startRow...])
        let appended = frameBottom - maxY
        maxY = frameBottom
        return appended
    }

    private func result(_ decision: TrackingDecision, cue: Bool, confidence: Double) -> TrackingResult {
        let band: ContentBand
        if let locked = detector.lockedBand {
            band = ContentBand(
                topChrome: Int((Double(locked.top) * segmentRowScale).rounded()),
                bottomChrome: Int((Double(locked.bottom) * segmentRowScale).rounded()),
                isLowConfidence: false
            )
        } else {
            band = .unlocked
        }
        return TrackingResult(decision: decision, needsSafetyCue: cue, position: position, maxY: maxY, confidence: confidence, segmentIndex: segmentIndex, contentBand: band)
    }
}
