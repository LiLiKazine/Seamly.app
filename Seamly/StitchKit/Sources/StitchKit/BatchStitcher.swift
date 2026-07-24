import CoreGraphics
import Foundation

/// Stitches a *fixed, unordered* set of overlapping screenshots into one long image.
///
/// `PositionTracker` tracks a live, in-order broadcast stream; the batch case instead receives
/// the frames the user picked — possibly shuffled, possibly with gaps. `BatchStitcher` recovers
/// the scroll order from pairwise vertical offsets, measures the repeated chrome (status/search
/// bars, nav bar), and hands a built `StitchSession` to `Compositor`. Frames that don't overlap
/// fall into separate segments rather than being forced together.
///
/// Ordering is a 1-D layout problem: for each overlapping pair the matcher gives how far the
/// lower frame sits below the upper one, so anchoring the highest-confidence edges and reading
/// off positions sorts the frames top→bottom. A pair is only an "edge" when the match clears a
/// confidence floor and shows real scroll — non-overlapping frames simply produce no edge.
public struct BatchStitcher: Sendable {

    /// The recovered ordering plus the manifest to composite. `session.keyframes[k]` corresponds
    /// to `images[order[k]]`.
    public struct Plan: Sendable {
        /// Input indices in scroll order, top→bottom.
        public let order: [Int]
        /// Keyframes (indexed by ordered position), seams, segment breaks, and per-segment bands.
        public let session: StitchSession
    }

    public enum StitchError: Error, Equatable { case empty }

    let profiler: VerticalProfile
    let matcher: OffsetMatcher
    /// Match confidence a pairwise offset must clear to count as an overlap edge.
    let edgeConfidence: Double
    /// Fewest profile rows of scroll for a pair to be an edge (rejects near-duplicate frames).
    let minEdgeDy: Int
    /// Max mean/variance delta (0...1 luminance) for a row to read as static chrome.
    let chromeTolerance: Float
    /// ± source px searched around each provisional seam during compositing. Wider than the
    /// compositor's default because a downscaled provisional offset can be a few px off.
    let refinementDelta: Int

    public init(
        profiler: VerticalProfile = VerticalProfile(),
        matcher: OffsetMatcher = OffsetMatcher(),
        edgeConfidence: Double = 0.45,
        minEdgeDy: Int = 2,
        chromeTolerance: Float = 0.02,
        refinementDelta: Int = 16
    ) {
        self.profiler = profiler
        self.matcher = matcher
        self.edgeConfidence = edgeConfidence
        self.minEdgeDy = minEdgeDy
        self.chromeTolerance = chromeTolerance
        self.refinementDelta = refinementDelta
    }

    // MARK: - Public API

    /// Recover scroll order and build the stitch manifest without touching pixels.
    public func plan(_ images: [CGImage]) throws -> Plan {
        guard !images.isEmpty else { throw StitchError.empty }
        let profiles = images.map { profiler.profile($0) }
        let (order, segmentOfSlot) = layout(profiles)
        return buildPlan(profiles: profiles, order: order, segmentOfSlot: segmentOfSlot)
    }

    /// Build the stitch manifest assembling along `order` verbatim (no re-sort). Consecutive
    /// frames stay in one segment while they overlap; the first non-overlapping neighbour starts
    /// a new segment. Used when the caller's order is trusted (video capture order) or assumed
    /// (photos pick-order fallback).
    public func plan(_ images: [CGImage], assumingOrder order: [Int]) throws -> Plan {
        guard !images.isEmpty else { throw StitchError.empty }
        precondition(order.count == images.count && Set(order) == Set(0..<images.count),
                     "assumingOrder must be a permutation of 0..<images.count")
        let profiles = images.map { profiler.profile($0) }
        let segmentOfSlot = segmentsAlong(order, profiles)
        return buildPlan(profiles: profiles, order: order, segmentOfSlot: segmentOfSlot)
    }

    /// Recover order and composite to a single long image.
    public func stitch(_ images: [CGImage]) throws -> CGImage {
        let plan = try plan(images)
        return try compositor.composite(plan.session) { images[plan.order[$0.index]] }
    }

    /// Recover order and write the stitch as a PDF — same recovered order as `stitch`.
    public func writePDF(_ images: [CGImage], to url: URL) throws {
        let plan = try plan(images)
        try compositor.writePDF(plan.session, images: { images[plan.order[$0.index]] }, to: url)
    }

    /// Compositor tuned with this stitcher's matcher/profiler and a wider refinement window.
    private var compositor: Compositor {
        Compositor(matcher: matcher, profiler: profiler, refinementDelta: refinementDelta)
    }

    // MARK: - Ordering

    /// Recover scroll order (input indices, top→bottom) and the segment index of each ordered
    /// slot. Non-overlapping groups become distinct segments.
    private func layout(_ profiles: [FrameProfile]) -> (order: [Int], segmentOfSlot: [Int]) {
        let n = profiles.count
        if n == 1 { return ([0], [0]) }

        // Directed overlap edges: `above → below`, weighted by scroll distance (rows).
        struct Edge { let above: Int; let below: Int; let dy: Int; let conf: Double }
        var edges: [Edge] = []
        for i in 0..<n {
            for j in (i + 1)..<n {
                let fwd = downwardMatch(profiles[i], profiles[j])   // i above j
                let bwd = downwardMatch(profiles[j], profiles[i])   // j above i
                let (above, below, m) = fwd.confidence >= bwd.confidence ? (i, j, fwd) : (j, i, bwd)
                if m.confidence >= edgeConfidence, m.dy >= minEdgeDy {
                    edges.append(Edge(above: above, below: below, dy: m.dy, conf: m.confidence))
                }
            }
        }

        // Anchor the highest-confidence edges first, reading off a position per frame. A frame's
        // component is the set it's connected to; frames in the same component are ordered by
        // position, and separate components are separate segments.
        var parent = Array(0..<n)
        func find(_ x: Int) -> Int { var r = x; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        var pos = [Int: Double]()
        for e in edges.sorted(by: { $0.conf > $1.conf }) {
            if find(e.above) == find(e.below) { continue }
            switch (pos[e.above], pos[e.below]) {
            case (nil, nil): pos[e.above] = 0; pos[e.below] = Double(e.dy)
            case (let pa?, nil): pos[e.below] = pa + Double(e.dy)
            case (nil, let pb?): pos[e.above] = pb - Double(e.dy)
            case (.some, .some): continue   // both already placed in different components: skip
            }
            parent[find(e.above)] = find(e.below)
        }
        for k in 0..<n where pos[k] == nil { pos[k] = 0 }   // isolated frame: its own component

        // Group into components, order each by position, order components by lowest input index.
        var comps: [Int: [Int]] = [:]
        for k in 0..<n { comps[find(k), default: []].append(k) }
        let orderedComps = comps.values
            .map { $0.sorted { pos[$0]! != pos[$1]! ? pos[$0]! < pos[$1]! : $0 < $1 } }
            .sorted { $0.min()! < $1.min()! }

        var order: [Int] = []
        var segmentOfSlot: [Int] = []
        for (seg, comp) in orderedComps.enumerated() {
            for src in comp { order.append(src); segmentOfSlot.append(seg) }
        }
        return (order, segmentOfSlot)
    }

    /// Segment index per ordered slot when the order is fixed: increment at the first consecutive
    /// pair that does not clear the overlap gate.
    private func segmentsAlong(_ order: [Int], _ profiles: [FrameProfile]) -> [Int] {
        guard !order.isEmpty else { return [] }
        var segmentOfSlot = [0]
        for slot in 1..<order.count {
            let a = profiles[order[slot - 1]], b = profiles[order[slot]]
            let m = downwardMatch(a, b)
            let overlaps = m.confidence >= edgeConfidence && m.dy >= minEdgeDy
            segmentOfSlot.append(overlaps ? segmentOfSlot[slot - 1] : segmentOfSlot[slot - 1] + 1)
        }
        return segmentOfSlot
    }

    /// Shared manifest assembly from a resolved (order, segmentOfSlot). Extracted verbatim from the
    /// original `plan` body so recovered and assumed-order paths build identical structures.
    private func buildPlan(profiles: [FrameProfile], order: [Int], segmentOfSlot: [Int]) -> Plan {
        var session = StitchSession(
            createdAt: Date(timeIntervalSince1970: 0),
            status: .complete,
            deviceScale: 1,
            orientation: .portrait
        )
        for (slot, src) in order.enumerated() {
            session.keyframes.append(Keyframe(filename: "kf-\(slot)", pixelWidth: profiles[src].sourceWidth, pixelHeight: profiles[src].sourceHeight, index: slot))
        }
        for slot in 0..<max(0, order.count - 1) {
            if segmentOfSlot[slot] == segmentOfSlot[slot + 1] {
                let a = profiles[order[slot]], b = profiles[order[slot + 1]]
                let m = downwardMatch(a, b)
                let dyPx = Int((Double(m.dy) * a.rowScale).rounded())
                session.seams.append(Seam(fromIndex: slot, provisionalDy: dyPx, confidence: m.confidence, isLowConfidence: m.confidence < 0.4))
            } else {
                session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: slot, reason: .lostLock))
            }
        }
        let segmentCount = (segmentOfSlot.max() ?? 0) + (order.isEmpty ? 0 : 1)
        for seg in 0..<segmentCount {
            let slots = order.indices.filter { segmentOfSlot[$0] == seg }
            let pairs = zip(slots, slots.dropFirst()).map { (profiles[order[$0]], profiles[order[$1]]) }
            session.contentBands.append(chromeBand(pairs, rowScale: profiles[order[slots[0]]].rowScale))
        }
        return Plan(order: order, session: session)
    }

    // MARK: - Matching

    /// Best downward (positive-`dy`) alignment of `b` below `a`, taking whichever of the
    /// static-masked and plain matcher is more confident — the mask helps some real pairs and
    /// flips the sign on others, so neither wins alone.
    private func downwardMatch(_ a: FrameProfile, _ b: FrameProfile) -> Match {
        let bound = min(a.rowCount, b.rowCount) - matcher.minimumOverlap
        guard bound >= 1 else { return Match(dy: 0, confidence: 0) }
        let mask = ContentBandDetector(meanTolerance: chromeTolerance, varianceTolerance: chromeTolerance).staticMask(a, b)
        let masked = matcher.match(a, b, searchRange: 1...bound, rowMask: mask)
        let plain = matcher.match(a, b, searchRange: 1...bound)
        return masked.confidence >= plain.confidence ? masked : plain
    }

    // MARK: - Chrome

    /// The chrome shared by every adjacent pair in a segment: rows static (mean+variance within
    /// tolerance) in *all* pairs, counted inward from each edge. Intersection, not union, so a
    /// coincidentally-still content row in one pair can't over-crop. No pairs → `.unlocked`.
    private func chromeBand(_ pairs: [(FrameProfile, FrameProfile)], rowScale: Double) -> ContentBand {
        guard !pairs.isEmpty else { return .unlocked }
        let n = pairs.map { min($0.0.rowCount, $0.1.rowCount) }.min()!
        func staticAll(_ i: Int) -> Bool {
            pairs.allSatisfy { abs($0.0.means[i] - $0.1.means[i]) <= chromeTolerance && abs($0.0.variances[i] - $0.1.variances[i]) <= chromeTolerance }
        }
        var top = 0; while top < n, staticAll(top) { top += 1 }
        var bottom = 0; while bottom < n - top, staticAll(n - 1 - bottom) { bottom += 1 }
        return ContentBand(
            topChrome: Int((Double(top) * rowScale).rounded()),
            bottomChrome: Int((Double(bottom) * rowScale).rounded()),
            isLowConfidence: false
        )
    }
}
