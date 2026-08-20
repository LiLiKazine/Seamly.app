import Foundation
import StitchKit

/// One thing about a capture that is worth asking the user about, located in the finished
/// image and paired with its fix.
///
/// This is the per-item companion to `CaptureCondition`'s aggregate verdict, and it lives
/// beside it deliberately: `CaptureCondition` is the only place pipeline facts become English,
/// and that rule still holds. What changed is the vocabulary — the design puts the pipeline's
/// own words on screen ("seam", "bars", "gap"), reversing the ban in
/// `docs/superpowers/specs/2026-08-17-guided-repair-design.md`. So the strings here are
/// different from `Imperfection`'s, but they are written in the same file's spirit and in the
/// same one place.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`.
nonisolated struct Finding: Identifiable, Equatable {
    /// Declaration order **is** the ranking, most important first — the same order
    /// `Imperfection.Kind` already uses. Missing content outranks uncertain bars, which
    /// outranks a join that might be a pixel off.
    enum Kind: Int, Comparable, CaseIterable {
        case gap
        case bars
        case seam

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    /// What answering this finding actually changes.
    enum Target: Equatable {
        /// Nothing to change — the content was never captured.
        case gap(afterKeyframeIndex: Int)
        /// `StitchSession.setChromeOverride(_:for:keyframeID:)`.
        case chrome(keyframeID: UUID, edges: Set<ChromeEdge>)
        /// `Seam.provisionalDy` for the join between this index and the next.
        case join(Int)
    }

    /// Stable across rebuilds, so a `ForEach` and a queue position survive a re-derive.
    let id: String
    /// The number the margin marker shows and the queue counts by.
    let n: Int
    let kind: Kind
    /// Where this sits in the whole capture, 0…1.
    let atPct: Double
    let target: Target
    let title: String
    let question: String
    let detail: String
    /// The offset under the finger, for a seam. `nil` where there is no offset to state.
    let dy: Int?
    let confidence: Double?
}

/// A join drawn on the sheet. Every join gets one, confident ones included and unnumbered —
/// principle 1 says a good capture must look like one image, so only doubt draws attention.
nonisolated struct CaptureMark: Identifiable, Equatable {
    enum Kind { case confident, flagged, gap }

    let id: String
    let kind: Kind
    let atPct: Double
    /// Present only when this mark has a finding, and then it is that finding's number.
    let n: Int?
    /// A gap always says what was lost. `nil` for everything else.
    let lostLabel: String?
}

nonisolated enum CaptureFindings {

    /// Everything this capture wants to ask about, ranked and numbered.
    ///
    /// Numbering is by rank then position, which is why a capture's gaps are 1…k before its
    /// flagged joins — the queue walks the most important thing first, and the margin marker
    /// carries the same number so the two are never out of step.
    static func all(in session: StitchSession, placement: Placement) -> [Finding] {
        guard placement.totalHeight > 0 else { return [] }
        let height = Double(placement.totalHeight)

        struct Draft {
            let id: String
            let kind: Finding.Kind
            let atPct: Double
            let target: Finding.Target
            let title: String
            let question: String
            let detail: String
            let dy: Int?
            let confidence: Double?
        }

        var drafts: [Draft] = []

        // Gaps — content the scroll outran. Nothing overlaps across one, so there is no offset.
        for span in session.segmentBreaks.sorted(by: { $0.afterKeyframeIndex < $1.afterKeyframeIndex }) {
            guard let destY = placement.destY(forBreakAfter: span.afterKeyframeIndex) else { continue }
            drafts.append(Draft(
                id: "gap-\(span.afterKeyframeIndex)",
                kind: .gap,
                atPct: Double(destY) / height,
                target: .gap(afterKeyframeIndex: span.afterKeyframeIndex),
                title: "Gap after frame \(span.afterKeyframeIndex + 1)",
                question: "Nothing was captured here",
                detail: "You scrolled past this stretch too fast — recording that part again is the only way to get it.",
                dy: nil,
                confidence: nil
            ))
        }

        // Bars — an edge with neither a user value nor positive-confidence automatic evidence.
        // Resolution stays lossless, so the crop is zero and the app's bars may repeat.
        for keyframe in session.keyframes.sorted(by: { $0.index < $1.index }) {
            let edges = session.chromeEdgesNeedingReview(for: keyframe)
            guard !edges.isEmpty, let span = placement.firstSpan(forKeyframeIndex: keyframe.index) else { continue }
            drafts.append(Draft(
                id: "bars-\(keyframe.index)",
                kind: .bars,
                atPct: Double(span.destY) / height,
                target: .chrome(keyframeID: keyframe.id, edges: edges),
                title: "Bars uncertain — frame \(keyframe.index + 1)",
                question: "Where do the bars end?",
                detail: "Bars weren't detected confidently here — set the crop.",
                dy: nil,
                confidence: nil
            ))
        }

        // Seams the engine wasn't sure about. `destY(forJoin:)` is `nil` across a segment
        // break, which is the same exclusion `RepairableJoins.walkable` makes and for the same
        // reason: nothing overlaps there, so dragging it would move nothing.
        for seam in session.seams.filter(\.isLowConfidence).sorted(by: { $0.fromIndex < $1.fromIndex }) {
            guard let destY = placement.destY(forJoin: seam.fromIndex) else { continue }
            drafts.append(Draft(
                id: "seam-\(seam.fromIndex)",
                kind: .seam,
                atPct: Double(destY) / height,
                target: .join(seam.fromIndex),
                title: "Seam after frame \(seam.fromIndex + 1)",
                question: "Does this line up?",
                detail: "Drag the lower half until the two halves meet.",
                dy: seam.provisionalDy,
                confidence: seam.confidence
            ))
        }

        return drafts
            .sorted { a, b in a.kind == b.kind ? a.atPct < b.atPct : a.kind < b.kind }
            .enumerated()
            .map { index, d in
                Finding(
                    id: d.id, n: index + 1, kind: d.kind, atPct: d.atPct, target: d.target,
                    title: d.title, question: d.question, detail: d.detail,
                    dy: d.dy, confidence: d.confidence
                )
            }
    }
}

nonisolated enum CaptureMarks {

    /// Every join in the capture, with the numbered ones carrying their finding's number so
    /// the mark on the sheet and the row in the queue are the same thing.
    static func all(in session: StitchSession, placement: Placement, findings: [Finding]) -> [CaptureMark] {
        guard placement.totalHeight > 0 else { return [] }
        let height = Double(placement.totalHeight)
        let byTarget = Dictionary(findings.map { ($0.target, $0) }, uniquingKeysWith: { first, _ in first })

        var marks: [CaptureMark] = []

        for seam in session.seams.sorted(by: { $0.fromIndex < $1.fromIndex }) {
            guard let destY = placement.destY(forJoin: seam.fromIndex) else { continue }
            let finding = byTarget[.join(seam.fromIndex)]
            marks.append(CaptureMark(
                id: "join-\(seam.fromIndex)",
                kind: finding == nil ? .confident : .flagged,
                atPct: Double(destY) / height,
                n: finding?.n,
                lostLabel: nil
            ))
        }

        for span in session.segmentBreaks.sorted(by: { $0.afterKeyframeIndex < $1.afterKeyframeIndex }) {
            guard let destY = placement.destY(forBreakAfter: span.afterKeyframeIndex) else { continue }
            marks.append(CaptureMark(
                id: "break-\(span.afterKeyframeIndex)",
                kind: .gap,
                atPct: Double(destY) / height,
                n: byTarget[.gap(afterKeyframeIndex: span.afterKeyframeIndex)]?.n,
                // The engine cannot know how much was never revealed — that is what a break
                // is. Naming a pixel count here would be inventing a number.
                lostLabel: "lost lock"
            ))
        }

        // A bars finding is about a whole frame rather than a join, so it gets a margin marker
        // (from `findings`) but no rule on the sheet — there is no line to draw.
        return marks.sorted { $0.atPct < $1.atPct }
    }
}

nonisolated extension Finding.Target: Hashable {}
