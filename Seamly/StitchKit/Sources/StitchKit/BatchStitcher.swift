import CoreGraphics
import Foundation

/// Stitches a *fixed, unordered* set of overlapping screenshots into one long image.
///
/// `ScrollCaptureDriver` banks frames live and in order; this is the other half — assembly. It
/// receives the frames the user picked, possibly shuffled and possibly with gaps, recovers the
/// scroll order from pairwise vertical offsets, measures the repeated chrome (status/search bars,
/// nav bar), and hands a built `StitchSession` to `Compositor`. Frames that don't overlap fall into
/// separate segments rather than being forced together.
///
/// Every geometry decision in a finished capture is made here, not during capture: the extension's
/// only job is to bank overlapping keyframes.
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
        /// Keyframes (indexed by ordered position), seams, segment breaks, and per-keyframe chrome.
        public let session: StitchSession
    }

    /// How planning treats the order in which images arrived.
    ///
    /// Source policy is intentional: unordered diagnostic sets use `.recover`; Photos picks and
    /// committed broadcast keyframes use `.recoverOrInputOrder`; dense driver frames and decoded
    /// video keyframes use `.inputOrder` because their chronology is authoritative.
    public enum OrderStrategy: Sendable {
        /// Recover scroll order from pixel overlap and never fall back to arrival order.
        case recover
        /// Recover first; if and only if recovery contains a segment break, use input order and
        /// badge it as assumed. Low-confidence seams do not trigger the fallback: they describe
        /// alignment, not whether the recovered relative order is known.
        ///
        /// Falling back stops reordering; it never forces disconnected content together. Every
        /// consecutive input-order pair is measured again and non-overlapping neighbours remain
        /// separated by segment breaks.
        case recoverOrInputOrder
        /// Trust input order as chronology while still segmenting non-overlapping neighbours.
        /// This is not badged because the order is authoritative.
        case inputOrder
    }

    public enum StitchError: Error, Equatable { case empty }

    let profiler: VerticalProfile
    let matcher: OffsetMatcher
    /// Match confidence a pairwise offset must clear to count as an overlap edge.
    let edgeConfidence: Double
    /// Fewest profile rows of scroll for a pair to be an edge (rejects near-duplicate frames).
    let minEdgeDy: Int
    /// In the chain-joining pass only, a boundary pair counts as an overlap edge — even below
    /// `edgeConfidence` — when its scroll direction fits at most this fraction as badly as the
    /// opposite direction.
    ///
    /// The idea: two frames that don't overlap have no preferred direction, since neither
    /// alignment explains the other frame, so their two costs converge and the ratio approaches 1.
    /// A real edge, however weakly peaked, still fits better one way round.
    ///
    /// **Read the margins before touching this.** They are far tighter than the other measured
    /// constants here — `structureTolerance` next door separates its two populations by 8x, this
    /// separates them by about 1.1x — and each bound rests on a single observation.
    ///
    /// Measured on the video tier at both decode cadences (its pair 2-3 is a genuine `dy≈330`
    /// edge whose confidence, 0.27–0.34, sits well under `edgeConfidence`):
    ///
    /// | ratio | what it is | at 0.80 |
    /// |-------|------------|---------|
    /// | 0.658 | pair 2-3, full-rate decode — REAL | rescued |
    /// | 0.777 | pair 2-3, 30 fps (production) — REAL | rescued |
    /// | 0.803 | pair 3-4, 30 fps — real but unmatchable tail | rejected |
    /// | 0.953 | pair 3-4, full-rate — same tail | rejected |
    /// | >0.84 | first `wechat-*` false accept (verified safe at 0.84, over-merges at 0.88) | rejected |
    ///
    /// 0.80 is the highest value keeping a ≥5% margin below the false-accept zone. It is not
    /// pushed to ~0.81 to also capture pair 3-4, for two reasons: that would leave ~2% of margin
    /// on both sides, and it would not close the acceptance criterion anyway — the full-rate
    /// decode that `CaptureVideoTests` uses scores that same pair at 0.953, so its last break
    /// needs the fixture re-trimmed, not a bolder threshold.
    ///
    /// The asymmetry is why the bias is downward: rejecting a real edge leaves a segment break,
    /// which is visible and honest, while accepting a false one stitches unrelated screens
    /// together.
    ///
    /// Guards, all on real fixtures: `wechatNonOverlapStillBreaks` (over-merge),
    /// `baiduDownwardScrollStaysSane` (order inversion), `nonOverlappingFramesSplitIntoSegments`.
    /// Raising this without re-running them is how unrelated screens end up in one image.
    let directionalCostRatio: Double
    /// Max mean/variance delta (0...1 luminance) for a row to read as static chrome. The
    /// translucency (shape) term of that test keeps `ChromeStaticRowDetector`'s default — it is scaled
    /// to the signature width, not to this luminance tolerance.
    let chromeTolerance: Float
    /// How much of a candidate baseline chrome region must actually have held still for detection to
    /// believe it, rather than fall back to the conservative inward scan.
    ///
    /// A bar contains rows that change — a clock, signal bars — so the band is derived from where
    /// the *content* is (see `baselineChromeRows`) and can't require every row to be static. This is the
    /// guard on that inference: content mis-read as chrome shows up as a band that is mostly
    /// moving. Measured over every real fixture, the two populations are nowhere near each other:
    ///
    /// | candidate band | fraction | verdict |
    /// |----------------|----------|---------|
    /// | `RealDevice` youtube / baidu / wechat-bottom, `Screenshots`-bottom, `Example`-none | 1.000 | real, band unchanged |
    /// | `Screenshots2` bottom — toolbar with a 15 px moving strip | 0.923 | real, **the fix** |
    /// | `Screenshots2` top — 372 px bar with 39 px of live status icons | 0.892 | real, **the fix** |
    /// | `Example` bottom / top | 0.482 / 0.436 | content, rejected |
    /// | `Screenshots` top — would have cropped 1130 px of page | 0.303 | content, rejected |
    /// | `wechat` top — would have cropped 378 px | 0.232 | content, rejected |
    ///
    /// 0.75 sits in the middle of a 0.482–0.892 gap. The guard is doing real work, not decorating
    /// a safe inference: three of the six sets produce a candidate band that must be refused, and
    /// on `Screenshots` refusing it is the difference between the shipped stitch and losing a
    /// third of every page. The bias is deliberate — failing this test costs only the older,
    /// smaller band, while passing it wrongly crops content away for good.
    let minChromeStaticFraction: Double
    /// Match confidence below which a seam is stamped `isLowConfidence` — "this one offset is
    /// fuzzy", surfaced to the editor. It says nothing about ordering; `StitchAssembler` learned
    /// that the hard way (see `docs/logs/2026-07-25-08`).
    ///
    /// Configurable rather than a literal because the callers that must keep working *despite* a
    /// fuzzy seam can otherwise only be tested when some fixture happens to produce one. That was
    /// the arrangement until `Fixtures/Screenshots`' 0.368 seam — the only one in the repo — rose
    /// to 0.726 when the masked overlap floor was corrected, and two tests guarding a real,
    /// shipped bug went vacuous at once. Raising this reproduces the condition from the same real
    /// pixels instead of waiting for luck.
    let lowConfidenceSeam: Double
    /// ± source px searched around each provisional seam during compositing. Wider than the
    /// compositor's default because a downscaled provisional offset can be a few px off.
    let refinementDelta: Int

    public init(
        profiler: VerticalProfile = VerticalProfile(),
        // Planning runs in the app with the complete frame set, so it can afford the robust
        // spatial scorer. `KeyframeSelector` deliberately keeps `OffsetMatcher()`'s lightweight
        // weighted-mean default on the ReplayKit hot path.
        matcher: OffsetMatcher = OffsetMatcher(aggregation: .tileConsensus),
        edgeConfidence: Double = 0.45,
        minEdgeDy: Int = 2,
        directionalCostRatio: Double = 0.80,
        chromeTolerance: Float = 0.02,
        minChromeStaticFraction: Double = 0.75,
        lowConfidenceSeam: Double = 0.4,
        refinementDelta: Int = 16
    ) {
        self.profiler = profiler
        self.matcher = matcher
        self.edgeConfidence = edgeConfidence
        self.minEdgeDy = minEdgeDy
        self.directionalCostRatio = directionalCostRatio
        self.chromeTolerance = chromeTolerance
        self.minChromeStaticFraction = minChromeStaticFraction
        self.lowConfidenceSeam = lowConfidenceSeam
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

    /// Plan using a source-aware ordering policy. This preserves the two lower-level planning
    /// overloads above while providing one shared implementation for app and diagnostic callers.
    /// A fallback changes ordering policy only: `plan(_:assumingOrder:)` still detects genuine
    /// discontinuities and retains their segment breaks.
    public func plan(_ images: [CGImage], strategy: OrderStrategy) throws -> Plan {
        switch strategy {
        case .recover:
            return try plan(images)
        case .inputOrder:
            return try plan(images, assumingOrder: Array(images.indices))
        case .recoverOrInputOrder:
            let recovered = try plan(images)
            guard !recovered.session.segmentBreaks.isEmpty else { return recovered }

            let fallback = try plan(images, assumingOrder: Array(images.indices))
            var session = fallback.session
            session.orderAssumed = true
            return Plan(order: fallback.order, session: session)
        }
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
                // Which way round the pair goes is a question about *fit*, so it is settled on
                // cost. It used to be settled on confidence, which measures how sharply a match
                // beat its runner-up — and a spurious alignment can be sharp while fitting badly.
                // Measured on the video tier, that inversion discarded the real downward edge on
                // pairs 2-3 (dy=344, cost 0.177 vs the reverse's 0.269) and 3-4.
                let (above, below, m) = fwd.cost <= bwd.cost ? (i, j, fwd) : (j, i, bwd)
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
            case (let pa?, let pb?):
                // Both endpoints are already placed, in two different components (same-component
                // edges were skipped above). Positions are only meaningful *within* a component —
                // each starts its own frame of reference at 0 — so this edge is not a conflict,
                // it is the offset that finally relates the two frames. Slide the `below`
                // component so the edge is satisfied, then merge.
                //
                // This used to `continue`, silently discarding the edge and leaving a segment
                // break between two frames that overlap perfectly well. On `youtube-*` the
                // dropped edge was 1→2 at confidence 0.922 — the third-strongest edge in the
                // set — because 2-3 and 0-1 happened to be anchored first, which is purely an
                // artifact of confidence ordering, not evidence about the capture.
                let shift = (pa + Double(e.dy)) - pb
                let belowRoot = find(e.below)
                for k in 0..<n where find(k) == belowRoot { pos[k]? += shift }
            }
            parent[find(e.above)] = find(e.below)
        }
        for k in 0..<n where pos[k] == nil { pos[k] = 0 }   // isolated frame: its own component

        joinChainsAcrossComponents(profiles, n: n, pos: &pos, parent: &parent)

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
            // The order is fixed here, so there is no direction to choose — but the reverse match
            // is still needed, as the yardstick the forward one is judged against.
            let overlaps = qualifiesAsEdge(downwardMatch(a, b), against: downwardMatch(b, a))
            segmentOfSlot.append(overlaps ? segmentOfSlot[slot - 1] : segmentOfSlot[slot - 1] + 1)
        }
        return segmentOfSlot
    }

    /// Second pass: try to join components that the confidence floor left separate, by testing
    /// only their **boundary** frames — the bottom of one chain against the top of another.
    ///
    /// A weak-but-real edge can sit under `edgeConfidence` (video pair 2-3: a genuine dy=344 at
    /// confidence 0.341), and rescuing it needs a test other than sharpness. `qualifiesAsEdge`'s
    /// directional-cost comparison is that test — but it is only safe *here*, on a handful of
    /// boundary candidates.
    ///
    /// Offering it to all O(n²) pairs, which is what the first pass does, actively corrupts the
    /// order. Measured on the video tier: pairs 1-3 and 1-4 both pass the cost-ratio test in the
    /// *reverse* direction (0.762 and 0.781), and admitting them recovers `order=[4,0,1,2,3]` —
    /// the exact inversion issue #2 warns a lowered floor produces. Distant frames from one
    /// scroll share layout statistics, so "no overlap implies no preferred direction" simply
    /// isn't true for them. Restricting to chain extension removes those candidates entirely:
    /// a frame can only attach to the end of a chain, never into its middle.
    private func joinChainsAcrossComponents(
        _ profiles: [FrameProfile], n: Int,
        pos: inout [Int: Double], parent: inout [Int]
    ) {
        struct Join { let above: Int; let below: Int; let dy: Int; let ratio: Double }
        // Local, non-capturing root lookup: the caller's `find` closes over `parent`, and calling
        // it while `parent` is also bound `inout` here is an exclusive-access violation.
        func root(_ x: Int, _ p: [Int]) -> Int { var r = x; while p[r] != r { r = p[r] }; return r }

        while true {
            // Current chains, each ordered top→bottom by position.
            var chains: [Int: [Int]] = [:]
            for k in 0..<n { chains[root(k, parent), default: []].append(k) }
            guard chains.count > 1 else { return }
            let ordered = chains.values.map { $0.sorted { pos[$0]! < pos[$1]! } }

            var best: Join?
            for a in ordered {
                for b in ordered where b.first! != a.first! {
                    // Only `a`'s bottom frame against `b`'s top frame: append b's chain below a's.
                    let above = a.last!, below = b.first!
                    let fwd = downwardMatch(profiles[above], profiles[below])
                    let bwd = downwardMatch(profiles[below], profiles[above])
                    guard qualifiesAsEdge(fwd, against: bwd) else { continue }
                    let ratio = Double(fwd.cost / bwd.cost)
                    if best == nil || ratio < best!.ratio {
                        best = Join(above: above, below: below, dy: fwd.dy, ratio: ratio)
                    }
                }
            }
            guard let join = best else { return }

            let shift = (pos[join.above]! + Double(join.dy)) - pos[join.below]!
            let belowRoot = root(join.below, parent)
            for k in 0..<n where root(k, parent) == belowRoot { pos[k]? += shift }
            parent[root(join.above, parent)] = belowRoot
        }
    }

    /// Whether `chosen` is a real overlap edge, judged against the same pair's `opposite`
    /// direction. Shared by both the order-recovery and fixed-order paths so they cannot drift.
    ///
    /// Real scroll is required either way. Beyond that a match qualifies when it is sharply
    /// peaked (`edgeConfidence`), **or** when it fits decisively better than the other direction
    /// — see `directionalCostRatio` for why the second test separates a weak real edge from a
    /// non-overlap, which a confidence floor alone cannot do.
    private func qualifiesAsEdge(_ chosen: Match, against opposite: Match) -> Bool {
        guard chosen.dy >= minEdgeDy else { return false }
        if chosen.confidence >= edgeConfidence { return true }
        guard opposite.cost.isFinite, opposite.cost > 0, chosen.cost.isFinite else { return false }
        return Double(chosen.cost / opposite.cost) <= directionalCostRatio
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
        var consecutiveMatches = Array<Match?>(repeating: nil, count: max(0, order.count - 1))
        for slot in 0..<max(0, order.count - 1) {
            if segmentOfSlot[slot] == segmentOfSlot[slot + 1] {
                let a = profiles[order[slot]], b = profiles[order[slot + 1]]
                let m = downwardMatch(a, b)
                consecutiveMatches[slot] = m
                let dyPx = Int((Double(m.dy) * a.rowScale).rounded())
                session.seams.append(Seam(fromIndex: slot, provisionalDy: dyPx, confidence: m.confidence, isLowConfidence: m.confidence < lowConfidenceSeam))
            } else {
                session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: slot, reason: .lostLock))
            }
        }
        let segmentCount = (segmentOfSlot.max() ?? 0) + (order.isEmpty ? 0 : 1)
        let pairsBySegment = (0..<segmentCount).map { seg -> [(FrameProfile, FrameProfile)] in
            let slots = order.indices.filter { segmentOfSlot[$0] == seg }
            return zip(slots, slots.dropFirst()).map { (profiles[order[$0]], profiles[order[$1]]) }
        }
        // Only within-segment pairs contribute baseline evidence. A pair spanning a break compares
        // unrelated screens, so a singleton segment deliberately keeps an unmeasured UUID record
        // and resolves unlocked until the user supplies an override.
        var keyframeBaselineRows: [BaselineChromeRows] = []
        for seg in 0..<segmentCount {
            keyframeBaselineRows.append(baselineChromeRows(pairsBySegment[seg]))
        }
        session.keyframeChrome = automaticKeyframeChrome(
            profiles: profiles,
            order: order,
            segmentOfSlot: segmentOfSlot,
            keyframes: session.keyframes,
            baselineRowsBySegment: keyframeBaselineRows,
            consecutiveMatches: consecutiveMatches
        )
        return Plan(order: order, session: session)
    }

    // MARK: - Matching

    /// Best downward (positive-`dy`) alignment of `b` below `a`, taking whichever of the
    /// static-masked and plain matcher is more confident.
    ///
    /// The old rationale here — "the mask helps some real pairs and flips the sign on others, so
    /// neither wins alone" — does not survive measurement (issue #11), and could not have been
    /// literally true of this function anyway: it searches `1...bound`, so no sign is available
    /// to flip. Direction is chosen in `layout`, not here.
    ///
    /// Measured across every adjacent pair of `youtube-*`, `baidu-*` and `wechat-*`: masked and
    /// plain recover the **same `dy`** on all of them except baidu 4-5, where both are wrong. So
    /// this choice never changes the recovered offset on any real fixture — it only reports the
    /// better-scoring of two matches that already agree. It is kept because that reported
    /// confidence is load-bearing downstream (`edgeConfidence`, `isLowConfidence`), and masking
    /// genuinely improves it: `youtube` 3-4 scores 0.824 masked against 0.340 plain, baidu 3-4
    /// 0.387 against 0.032. Picking on confidence is right for that purpose; picking a *direction*
    /// on confidence was the bug, and `layout` now uses `cost` for it.
    /// Internal rather than private so tests can pin the offset a pair actually resolves to. A
    /// plan-level assertion cannot tell "the matcher found the offset" from "the ordering routed
    /// around a bad one", and a test-local reimplementation is exactly the drift `CaptureHarness`
    /// documents.
    func downwardMatch(_ a: FrameProfile, _ b: FrameProfile) -> Match {
        let bound = min(a.rowCount, b.rowCount) - matcher.minimumOverlap
        guard bound >= 1 else { return Match(dy: 0, confidence: 0) }
        let mask = ChromeStaticRowDetector(meanTolerance: chromeTolerance, varianceTolerance: chromeTolerance).staticMask(a, b)
        let masked = matcher.match(a, b, searchRange: 1...bound, rowMasks: RowMaskPair(shared: mask))
        let plain = matcher.match(a, b, searchRange: 1...bound)
        return masked.confidence >= plain.confidence ? masked : plain
    }

    // MARK: - Chrome

    /// The baseline chrome shared by every adjacent pair in a segment: rows static in *all* pairs.
    /// Intersection, not union, so a coincidentally-still content row in one pair can't over-crop.
    /// No pairs → `.unlocked`.
    ///
    /// The static test is `ChromeStaticRowDetector`'s, not a local copy: this used to inline its own
    /// mean+variance comparison, which is how the two drifted — the detector learned to recognize
    /// translucent chrome by shape while this path kept rejecting it, so a blurred tab bar produced
    /// a zero bottom inset here and got baked into the stitch once per keyframe.
    ///
    /// **A bar is not uniformly static, so the band is read as "everything outside the content"
    /// rather than "static rows counted inward from the edge."** A status bar carries a clock and
    /// signal indicators; screenshots taken seconds apart disagree there. The inward scan halted at
    /// the first such row, and on `Screenshots2` — where a 39 px strip of status icons sits inside a
    /// 372 px top bar, and a 15 px strip inside a 234 px bottom bar — it measured 81 px and 27 px,
    /// leaving the whole browser toolbar inside every keyframe's strip to be stamped through the
    /// middle of the page once per frame.
    ///
    /// The content is the longest run of rows that moved. That is a safe thing to key on precisely
    /// because it is the *longest* run: the scrolling region dwarfs any strip inside a bar (505 rows
    /// against 9 and 4 on `Screenshots2`). Its risk is the mirror image — a content row that happens
    /// to hold still splits the run, and the longer half is then mistaken for all of it — so each
    /// candidate band must itself be `minChromeStaticFraction` static to be believed, and falls back
    /// to the inward scan when it isn't. The fallback is never worse than the previous behaviour:
    /// the inward scan stops at the first row that moved, so it can only under-crop.
    private struct BaselineChromeRows {
        var top: Int
        var bottom: Int
        var isLowConfidence: Bool

        static let unlocked = BaselineChromeRows(top: 0, bottom: 0, isLowConfidence: true)
    }

    private func baselineChromeRows(_ pairs: [(FrameProfile, FrameProfile)]) -> BaselineChromeRows {
        guard !pairs.isEmpty else { return .unlocked }
        let n = pairs.map { min($0.0.rowCount, $0.1.rowCount) }.min()!
        let detector = ChromeStaticRowDetector(meanTolerance: chromeTolerance, varianceTolerance: chromeTolerance)
        let held = (0..<n).map { i in
            pairs.allSatisfy { detector.isStatic($0.0, $0.1, row: i, allowingTranslucency: true) }
        }

        var top = 0; while top < n, held[top] { top += 1 }
        var bottom = 0; while bottom < n - top, held[n - 1 - bottom] { bottom += 1 }

        if let content = longestMovingRun(held) {
            let overTop = content.lowerBound, underBottom = n - content.upperBound
            if readsAsChrome(held[0..<overTop]) { top = overTop }
            if readsAsChrome(held[(n - underBottom)...]) { bottom = underBottom }
        }
        // Insets that eat most of the frame mean the static test matched nearly every row —
        // "no content found anywhere", which is a measurement failure, not a very large bar.
        // Believing it collapses the stitch (every seam clamps to a 1px advance) while the
        // manifest still looks healthy, so degrade to unmeasured: crop nothing and let the editor
        // override. Checked in profile rows, the space it was measured
        // in, so no rounding can slip a rejected band back under the ceiling.
        guard Double(top + bottom) <= Double(n) * ChromeInsets.maxCombinedCropFraction else {
            return .unlocked
        }
        return BaselineChromeRows(top: top, bottom: bottom, isLowConfidence: false)
    }

    // MARK: - Per-keyframe chrome

    private struct ChromeRunObservation {
        let rows: Int
        let confidence: Double
    }

    private struct ResolvedChromeRows {
        let rows: Int
        let confidence: Double
    }

    /// Calibrated together against Screenshots3. Keep these as one policy: lowering a residual
    /// threshold without its run/content evidence floors turns isolated page changes into chrome.
    private enum ChromeResidualPolicy {
        static let highToleranceMultiplier: Float = 3
        static let contentToleranceMultiplier: Float = 2
        static let minimumRunRows = 8
        static let allowedGapRows = 1
        static let clusterToleranceRows = 2
        static let minimumClusterObservations = 2
    }

    private func automaticKeyframeChrome(
        profiles: [FrameProfile],
        order: [Int],
        segmentOfSlot: [Int],
        keyframes: [Keyframe],
        baselineRowsBySegment: [BaselineChromeRows],
        consecutiveMatches: [Match?]
    ) -> [KeyframeChrome] {
        guard !order.isEmpty else { return [] }

        var directTop = Array<ChromeRunObservation?>(repeating: nil, count: order.count)
        var directBottom = Array<ChromeRunObservation?>(repeating: nil, count: order.count)

        for slot in 0..<max(0, order.count - 1) where segmentOfSlot[slot] == segmentOfSlot[slot + 1] {
            guard let match = consecutiveMatches[slot] else { continue }
            let a = profiles[order[slot]]
            let b = profiles[order[slot + 1]]
            let observation = translationResidualChrome(above: a, below: b, dy: match.dy)
            directTop[slot + 1] = observation.topForBelow
            directBottom[slot] = observation.bottomForAbove
        }

        let segmentCount = (segmentOfSlot.max() ?? 0) + 1
        var records: [KeyframeChrome] = []
        records.reserveCapacity(keyframes.count)

        for seg in 0..<segmentCount {
            let slots = order.indices.filter { segmentOfSlot[$0] == seg }
            let baseline = baselineRowsBySegment.indices.contains(seg) ? baselineRowsBySegment[seg] : .unlocked
            let topCluster = agreeingCluster(slots.compactMap { directTop[$0] })
            let bottomCluster = agreeingCluster(slots.compactMap { directBottom[$0] })

            for slot in slots {
                var top = edgeRows(
                    baseline: baselineRows(edgeRows: baseline.top, baseline: baseline),
                    direct: directTop[slot],
                    cluster: topCluster
                )
                var bottom = edgeRows(
                    baseline: baselineRows(edgeRows: baseline.bottom, baseline: baseline),
                    direct: directBottom[slot],
                    cluster: bottomCluster
                )

                let profile = profiles[order[slot]]
                let topPx = sourcePixels(top.rows, rowScale: profile.rowScale)
                let bottomPx = sourcePixels(bottom.rows, rowScale: profile.rowScale)
                if !ChromeInsets(top: topPx, bottom: bottomPx).isPlausible(forPixelHeight: profile.sourceHeight) {
                    top = baselineRows(edgeRows: baseline.top, baseline: baseline)
                    bottom = baselineRows(edgeRows: baseline.bottom, baseline: baseline)
                }

                let insets = ChromeInsets(
                    top: sourcePixels(top.rows, rowScale: profile.rowScale),
                    bottom: sourcePixels(bottom.rows, rowScale: profile.rowScale)
                )
                // Keep the UUID-keyed record even for low-evidence keyframes so diagnostics can
                // distinguish "planned but unmeasured" from "record missing". But leave the
                // automatic layer nil when neither edge had evidence: `resolvedChrome` treats any
                // finite confidence as an automatic source, so encoding zero/zero there would hide
                // the UI's "no safe automatic measurement" warning for singleton/unknown frames.
                let automatic = top.confidence == 0 && bottom.confidence == 0
                    ? nil
                    : ChromeMeasurement(
                        insets: insets,
                        topConfidence: top.confidence,
                        bottomConfidence: bottom.confidence
                    )
                records.append(KeyframeChrome(keyframeID: keyframes[slot].id, automatic: automatic))
            }
        }

        return records.sorted { lhs, rhs in
            guard
                let left = keyframes.firstIndex(where: { $0.id == lhs.keyframeID }),
                let right = keyframes.firstIndex(where: { $0.id == rhs.keyframeID })
            else {
                return lhs.keyframeID.uuidString < rhs.keyframeID.uuidString
            }
            return left < right
        }
    }

    private func baselineRows(edgeRows: Int, baseline: BaselineChromeRows) -> ResolvedChromeRows {
        ResolvedChromeRows(rows: baseline.isLowConfidence ? 0 : edgeRows,
                           confidence: baseline.isLowConfidence ? 0 : minChromeStaticFraction)
    }

    private func edgeRows(
        baseline: ResolvedChromeRows,
        direct: ChromeRunObservation?,
        cluster: ResolvedChromeRows?
    ) -> ResolvedChromeRows {
        var candidates = [baseline]
        if let direct {
            candidates.append(ResolvedChromeRows(rows: direct.rows, confidence: direct.confidence))
        }
        if let cluster {
            candidates.append(cluster)
        }
        return candidates.max { lhs, rhs in
            lhs.rows != rhs.rows ? lhs.rows < rhs.rows : lhs.confidence < rhs.confidence
        }!
    }

    /// For a positive profile offset `dy`, `below[k]` aligns with `above[dy + k]`.
    /// A high residual at the start therefore observes the later frame's top chrome, while the
    /// same residual scanned from the end observes the earlier frame's bottom chrome.
    private func translationResidualChrome(
        above: FrameProfile,
        below: FrameProfile,
        dy: Int
    ) -> (topForBelow: ChromeRunObservation?, bottomForAbove: ChromeRunObservation?) {
        guard dy > 0, dy < above.rowCount else { return (nil, nil) }
        let overlap = min(above.rowCount - dy, below.rowCount)
        guard overlap > 0 else { return (nil, nil) }

        let residuals = (0..<overlap).map { k in
            rowDistance(below.rows[k], above.rows[dy + k])
        }
        return (
            topForBelow: directChromeRun(in: residuals),
            bottomForAbove: directChromeRun(in: Array(residuals.reversed()))
        )
    }

    private func rowDistance(_ a: [Float], _ b: [Float]) -> Float {
        let count = min(a.count, b.count)
        guard count > 0 else { return .greatestFiniteMagnitude }
        var sum: Float = 0
        for i in 0..<count { sum += abs(a[i] - b[i]) }
        return sum / Float(count)
    }

    /// Reads a direct seam-residual run at one frame edge. The edge must begin with at least
    /// eight high-residual rows (allowing one-row gaps, and with at least
    /// `minChromeStaticFraction` of the run high), followed immediately by at least eight rows
    /// that align as content. If either half is missing, the edge is unobservable and contributes
    /// no extra crop.
    private func directChromeRun(in values: [Float]) -> ChromeRunObservation? {
        let highThreshold = chromeTolerance * ChromeResidualPolicy.highToleranceMultiplier
        let lowThreshold = chromeTolerance * ChromeResidualPolicy.contentToleranceMultiplier

        guard let highRun = thresholdRun(
            values,
            from: values.startIndex,
            minRows: ChromeResidualPolicy.minimumRunRows,
            threshold: highThreshold,
            comparison: >=
        ) else {
            return nil
        }
        guard let contentRun = thresholdRun(
            values,
            from: highRun.range.upperBound,
            minRows: ChromeResidualPolicy.minimumRunRows,
            threshold: lowThreshold,
            comparison: <=
        ) else {
            return nil
        }

        let confidence = min(1, (highRun.fraction + contentRun.fraction) / 2)
        return ChromeRunObservation(rows: highRun.range.count, confidence: confidence)
    }

    private func thresholdRun(
        _ values: [Float],
        from start: Int,
        minRows: Int,
        threshold: Float,
        comparison: (Float, Float) -> Bool
    ) -> (range: Range<Int>, fraction: Double)? {
        guard start < values.count else { return nil }
        var end = start
        var passing = 0
        var gapRows = 0
        while end < values.count {
            if comparison(values[end], threshold) {
                passing += 1
                gapRows = 0
                end += 1
            } else if gapRows < ChromeResidualPolicy.allowedGapRows,
                      end + 1 < values.count,
                      comparison(values[end + 1], threshold) {
                gapRows += 1
                end += 1
            } else {
                break
            }
        }
        if end > start, !comparison(values[end - 1], threshold) {
            end -= 1
        }
        let count = end - start
        guard count >= minRows else { return nil }
        let fraction = Double(passing) / Double(count)
        guard fraction >= minChromeStaticFraction else { return nil }
        return (start..<end, fraction)
    }

    private func agreeingCluster(_ observations: [ChromeRunObservation]) -> ResolvedChromeRows? {
        guard observations.count >= ChromeResidualPolicy.minimumClusterObservations else { return nil }
        let sorted = observations.sorted { $0.rows < $1.rows }
        var best: ArraySlice<ChromeRunObservation>?
        for start in sorted.indices {
            var end = start
            while end < sorted.endIndex,
                  sorted[end].rows - sorted[start].rows <= ChromeResidualPolicy.clusterToleranceRows {
                end += 1
            }
            let cluster = sorted[start..<end]
            if cluster.count > (best?.count ?? 0) {
                best = cluster
            }
        }
        guard let cluster = best,
              cluster.count >= ChromeResidualPolicy.minimumClusterObservations else { return nil }
        let rows = cluster.map(\.rows).sorted()
        let confidence = min(1, cluster.map(\.confidence).reduce(0, +) / Double(cluster.count))
        return ResolvedChromeRows(rows: rows[rows.count / 2], confidence: confidence)
    }

    /// The longest run of rows that moved in at least one pair — the scrolling content — or `nil`
    /// when nothing moved anywhere (still frames; the caller's plausibility ceiling rejects that).
    private func longestMovingRun(_ held: [Bool]) -> Range<Int>? {
        var best: Range<Int>?
        var i = 0
        while i < held.count {
            guard !held[i] else { i += 1; continue }
            var j = i
            while j < held.count, !held[j] { j += 1 }
            if j - i > (best?.count ?? 0) { best = i..<j }
            i = j
        }
        return best
    }

    /// Whether a candidate band is static enough to be a bar rather than mis-classified content.
    /// An empty band is vacuously fine — there is nothing to disbelieve.
    private func readsAsChrome(_ rows: ArraySlice<Bool>) -> Bool {
        guard !rows.isEmpty else { return true }
        return Double(rows.filter { $0 }.count) / Double(rows.count) >= minChromeStaticFraction
    }

    /// Convert a count of static profile rows to source pixels, rounding **outward** by one row.
    ///
    /// A profile row aggregates `rowScale` source pixels, so the first row that reads as content is
    /// typically part chrome and part content — rounding to nearest leaves a sliver of the bar in
    /// every frame's strip, which the hard cut then bakes in as a thin line at each seam. Cropping
    /// a few extra *chrome* pixels is harmless; leaving a few behind is visible. A zero band stays
    /// zero — there is no chrome to round outward from, and widening it would eat content.
    private func sourcePixels(_ rows: Int, rowScale: Double) -> Int {
        rows == 0 ? 0 : Int((Double(rows + 1) * rowScale).rounded(.up))
    }
}
