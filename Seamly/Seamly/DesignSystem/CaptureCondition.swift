import Foundation
import StitchKit

/// The facts a finished capture can exhibit, reduced to plain values.
///
/// Deliberately *not* built from `Capture`: keeping this a plain struct keeps the verdict
/// below a pure function — off the main actor, off disk, and table-testable across every
/// combination.
///
/// `nonisolated` because this app target defaults new declarations to `@MainActor`
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); without it this type — and everything
/// below that touches it — would only be usable from the main actor, defeating the point.
nonisolated struct CaptureFacts: Equatable {
    var segmentBreaks: Int = 0
    var flaggedSeams: Int = 0
    var unresolvedChrome: Int = 0
    var isIncomplete: Bool = false
    var orderAssumed: Bool = false
}

nonisolated extension CaptureFacts {
    /// Read the facts off a stored session. This is the only place that touches `StitchKit`.
    init(_ session: StitchSession) {
        self.init(
            segmentBreaks: session.segmentBreaks.count,
            flaggedSeams: session.seams.filter(\.isLowConfidence).count,
            unresolvedChrome: session.keyframes.filter {
                !session.chromeEdgesNeedingReview(for: $0).isEmpty
            }.count,
            isIncomplete: session.status == .recording,
            orderAssumed: session.orderAssumed
        )
    }
}

/// How loudly to present an observation. Two levels only — a longer scale invites the
/// badge-dumping the harness UI did.
nonisolated enum Severity {
    case guidance
    case warning
}

/// One plain-language observation about a capture.
nonisolated struct Imperfection: Equatable, Identifiable {
    /// Declaration order **is** the ranking, most important first. The user sees one line,
    /// so this decides which. Missing content outranks cosmetic misalignment; an ordering
    /// note is the quietest thing we can say.
    enum Kind: Int, Comparable, CaseIterable {
        case endedEarly
        case gaps
        case unresolvedBars
        case flaggedJoins
        case orderAssumed

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    let kind: Kind
    let headline: String
    let detail: String
    let severity: Severity
    /// True when re-recording is the only available fix. False when the content is all
    /// present and merely imperfectly joined — guided repair (Spec 2) is the real answer
    /// there, and telling the user to record again would waste their time.
    let recommendsRecordingAgain: Bool

    var id: Kind { kind }
}

/// The single user-facing verdict on a capture. This type owns the *only* translation from
/// pipeline facts into language a user reads — "seam", "chrome", "segment", and "confidence"
/// never appear on the far side of it.
nonisolated enum CaptureCondition: Equatable {
    case stitching
    case clean
    case imperfect(primary: Imperfection, all: [Imperfection])
    case nothingToStitch
    case failed(String)

    /// The verdict for a capture that stitched successfully. The other cases are decided by
    /// the caller from the capture's phase and import outcome.
    init(ready facts: CaptureFacts) {
        let all = Imperfection.Kind.allCases.compactMap { Imperfection(kind: $0, facts: facts) }
        guard let primary = all.first else { self = .clean; return }
        self = .imperfect(primary: primary, all: all)
    }

    /// Whether the result screen should offer "Record again" as a prominent action.
    var recommendsRecordingAgain: Bool {
        switch self {
        case .imperfect(let primary, _): primary.recommendsRecordingAgain
        case .nothingToStitch, .failed: true
        case .clean, .stitching: false
        }
    }
}

nonisolated private extension Imperfection {
    /// Build the observation for one kind, or `nil` if the facts do not exhibit it.
    init?(kind: Kind, facts: CaptureFacts) {
        switch kind {
        case .endedEarly:
            guard facts.isIncomplete else { return nil }
            self.init(
                kind: kind,
                headline: "The recording ended early",
                detail: "This is everything that was saved before it stopped.",
                severity: .warning,
                recommendsRecordingAgain: true
            )

        case .gaps:
            guard facts.segmentBreaks > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "Joined from \(facts.segmentBreaks + 1) pieces",
                detail: "You scrolled too fast in places, so this couldn't be made continuous.",
                severity: .warning,
                recommendsRecordingAgain: true
            )

        case .unresolvedBars:
            guard facts.unresolvedChrome > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "Some bars may repeat",
                detail: "Couldn't tell which parts were the app's own bars on "
                    + Self.count(facts.unresolvedChrome, "screen", "screens") + ".",
                severity: .guidance,
                recommendsRecordingAgain: false
            )

        case .flaggedJoins:
            guard facts.flaggedSeams > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "A join may not line up",
                detail: Self.count(facts.flaggedSeams, "join", "joins") + " might be slightly off.",
                severity: .guidance,
                recommendsRecordingAgain: false
            )

        case .orderAssumed:
            guard facts.orderAssumed else { return nil }
            self.init(
                kind: kind,
                headline: "Kept in the order they were taken",
                detail: "These couldn't be put in order by their content, so the original order was used.",
                severity: .guidance,
                recommendsRecordingAgain: false
            )
        }
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}
