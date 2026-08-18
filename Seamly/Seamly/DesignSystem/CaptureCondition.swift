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
    /// True when the fix for this observation is lining the join up by hand, rather than recording
    /// again.
    ///
    /// Deliberately **not** the inverse of `recommendsRecordingAgain`: an assumed order is neither
    /// (dragging one join cannot reorder a capture), and "some bars may repeat" is both — no new
    /// recording helps, and lining up genuinely does, because the rows hidden behind an undetected
    /// bar come back once the two halves are continuous. The band itself stays; removing it is not
    /// this gesture's job, and cannot be folded into it (see the spec's "Out of scope").
    let canBeLinedUp: Bool

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

    /// Whether the result screen should offer the repair at all.
    ///
    /// Read over **every** observation, unlike `recommendsRecordingAgain`, which reads only the
    /// primary: a capture can have ended early *and* have a join worth fixing, and "record again"
    /// being the loudest advice does not make the image already on disk unfixable.
    ///
    /// A clean capture offers it too — quietly. This app's own history is that a green verdict has
    /// been confidently wrong, so flagged-only entry would leave a visibly bad stitch with no
    /// recourse but re-recording. Whether there is actually a join to drag is a question about the
    /// session, not about this verdict, and belongs to `RepairableJoins`.
    var offersLiningUp: Bool {
        switch self {
        case .clean: true
        case .imperfect(_, let all): all.contains(where: \.canBeLinedUp)
        case .stitching, .nothingToStitch, .failed: false
        }
    }

    /// The one label for the repair, wherever it appears. An imperfect capture shows it loudly and
    /// a clean one quietly, but the words are identical — so this stays the only place the string
    /// lives, which is the whole point of this type.
    static let liningUpActionTitle = "Line it up"
}

nonisolated extension CaptureCondition {
    /// Turn a thrown error into something a person can read.
    ///
    /// The pipeline's error types are plain `Error` enums with no `LocalizedError`
    /// conformance, so `localizedDescription` bridges them to *"The operation couldn't be
    /// completed. (StitchKit.Compositor.CompositorError error 1.)"* — which is what a user saw
    /// on the screen a failed capture navigates to automatically. `StitchKit` is the finished
    /// core and stays untouched, so the translation lives here, alongside the only other place
    /// that turns pipeline facts into user-facing language.
    ///
    /// Callers still log the raw error to `Diagnostics`: this is what the user reads, not what
    /// we keep.
    static func message(for error: Error) -> String {
        switch error {
        case Compositor.CompositorError.noKeyframes, BatchStitcher.StitchError.empty:
            "There was nothing saved to put together."
        case Compositor.CompositorError.contextFailure:
            "There wasn't enough memory to build an image this long."
        case KeyframeIO.IOError.decodeFailed:
            "Some of the saved screens couldn't be read back."
        case KeyframeIO.IOError.encodeFailed:
            "The screens couldn't be saved to this device."
        case KeyframeIO.IOError.sizeMismatch:
            "A saved screen isn't the size it was recorded at."
        case VideoKeyframeSource.VideoError.noVideoTrack:
            "That file doesn't have any video in it."
        case VideoKeyframeSource.VideoError.readFailed:
            "That video couldn't be read."
        case MediaImporter.ImportError.notEnoughContent:
            "There wasn't enough here to join together."
        case is KeyframeChromeValidationError:
            "What was saved about this capture doesn't add up, so it can't be rebuilt."
        default:
            unrecognizedMessage(for: error)
        }
    }

    /// An error we have no wording for. Prefer whatever the error itself says — a Foundation or
    /// AVFoundation failure carries a perfectly good sentence — and substitute a generic line
    /// only when the description would be the system's placeholder, which names the failing
    /// Swift type and tells a user nothing.
    private static func unrecognizedMessage(for error: Error) -> String {
        if let described = (error as? LocalizedError)?.errorDescription, !described.isEmpty {
            return described
        }
        let bridged = error as NSError
        let described = bridged.localizedDescription
        // The placeholder interpolates the domain — which for a bridged Swift error is the
        // type's own name — so a description containing its own domain carries no real message.
        guard !described.isEmpty, !described.contains(bridged.domain) else {
            return "Something went wrong and this couldn't be finished."
        }
        return described
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
                recommendsRecordingAgain: true,
                canBeLinedUp: false
            )

        case .gaps:
            guard facts.segmentBreaks > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "Joined from \(facts.segmentBreaks + 1) pieces",
                detail: "You scrolled too fast in places, so this couldn't be made continuous.",
                severity: .warning,
                recommendsRecordingAgain: true,
                canBeLinedUp: false
            )

        case .unresolvedBars:
            guard facts.unresolvedChrome > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "Some bars may repeat",
                detail: "Couldn't tell which parts were the app's own bars on "
                    + Self.count(facts.unresolvedChrome, "screen", "screens") + ".",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: true
            )

        case .flaggedJoins:
            guard facts.flaggedSeams > 0 else { return nil }
            self.init(
                kind: kind,
                headline: "A join may not line up",
                detail: Self.count(facts.flaggedSeams, "join", "joins") + " might be slightly off.",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: true
            )

        case .orderAssumed:
            guard facts.orderAssumed else { return nil }
            self.init(
                kind: kind,
                headline: "Kept in the order they were taken",
                detail: "These couldn't be put in order by their content, so the original order was used.",
                severity: .guidance,
                recommendsRecordingAgain: false,
                canBeLinedUp: false
            )
        }
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }
}
