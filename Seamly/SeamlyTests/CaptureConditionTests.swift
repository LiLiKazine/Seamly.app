import Testing
import Foundation
import StitchKit
@testable import Seamly

/// `CaptureCondition` is the only place pipeline facts become English. A wrong mapping here
/// is invisible in review and lands in front of a user, so every combination is pinned.
struct CaptureConditionTests {

    @Test func aCleanCaptureHasNoImperfections() {
        #expect(CaptureCondition(ready: CaptureFacts()) == .clean)
    }

    @Test func gapsAreReportedWithAPieceCount() throws {
        let condition = CaptureCondition(ready: CaptureFacts(segmentBreaks: 2))
        guard case .imperfect(let primary, let all) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.kind == .gaps)
        #expect(all.count == 1)
        // 2 breaks == 3 pieces.
        #expect(primary.headline == "Joined from 3 pieces")
    }

    @Test func aSingleFlaggedSeamReadsAsSingular() throws {
        let condition = CaptureCondition(ready: CaptureFacts(flaggedSeams: 1))
        guard case .imperfect(let primary, _) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.kind == .flaggedJoins)
        #expect(primary.detail == "1 join might be slightly off.")
    }

    @Test func severalFlaggedSeamsReadAsPlural() throws {
        let condition = CaptureCondition(ready: CaptureFacts(flaggedSeams: 3))
        guard case .imperfect(let primary, _) = condition else {
            Issue.record("expected imperfect, got \(condition)"); return
        }
        #expect(primary.detail == "3 joins might be slightly off.")
    }

    /// Ranking is the whole point of `primary`: the user sees one line, so it must be the
    /// one that matters most. Missing content outranks a cosmetic misalignment.
    @Test func theMostSevereImperfectionIsPrimary() throws {
        let facts = CaptureFacts(
            segmentBreaks: 1,
            flaggedSeams: 5,
            unresolvedChrome: 2,
            isIncomplete: true,
            orderAssumed: true
        )
        guard case .imperfect(let primary, let all) = CaptureCondition(ready: facts) else {
            Issue.record("expected imperfect"); return
        }
        #expect(primary.kind == .endedEarly)
        #expect(all.count == 5)
        #expect(all.map(\.kind) == [.endedEarly, .gaps, .unresolvedBars, .flaggedJoins, .orderAssumed])
    }

    /// Re-recording is the only fix for missing content, but it will not help a join that is
    /// merely misaligned — that is what guided repair (Spec 2) is for. The result screen uses
    /// this to decide whether to push "Record again".
    @Test func onlyMissingContentRecommendsRecordingAgain() {
        #expect(CaptureCondition(ready: CaptureFacts(isIncomplete: true)).recommendsRecordingAgain)
        #expect(CaptureCondition(ready: CaptureFacts(segmentBreaks: 1)).recommendsRecordingAgain)
        #expect(!CaptureCondition(ready: CaptureFacts(flaggedSeams: 1)).recommendsRecordingAgain)
        #expect(!CaptureCondition(ready: CaptureFacts(unresolvedChrome: 1)).recommendsRecordingAgain)
        #expect(!CaptureCondition(ready: CaptureFacts()).recommendsRecordingAgain)
    }

    /// The hard rule from the spec: pipeline vocabulary never reaches a user.
    @Test func noUserFacingStringLeaksPipelineVocabulary() {
        let facts = CaptureFacts(
            segmentBreaks: 2, flaggedSeams: 2, unresolvedChrome: 2,
            isIncomplete: true, orderAssumed: true
        )
        guard case .imperfect(_, let all) = CaptureCondition(ready: facts) else {
            Issue.record("expected imperfect"); return
        }
        for imperfection in all {
            let text = imperfection.headline + " " + imperfection.detail
            for word in Self.bannedVocabulary {
                #expect(!text.lowercased().contains(word), "\(imperfection.kind) leaks \"\(word)\": \(text)")
            }
        }
    }

    // MARK: - Error messages

    /// Every error the pipeline can hand us is a plain `Error` enum with no `LocalizedError`
    /// conformance, so `localizedDescription` bridges it to "The operation couldn't be
    /// completed. (StitchKit.Compositor.CompositorError error 1.)" — which is what a user saw
    /// on the screen a failed capture navigates to *automatically*. Every known case must read
    /// as a sentence, and none of them may leak a type name or pipeline vocabulary.
    @Test func knownPipelineErrorsReadAsPlainEnglish() {
        let errors: [Error] = [
            Compositor.CompositorError.noKeyframes,
            Compositor.CompositorError.contextFailure,
            BatchStitcher.StitchError.empty,
            KeyframeIO.IOError.decodeFailed,
            KeyframeIO.IOError.encodeFailed,
            KeyframeIO.IOError.sizeMismatch,
            VideoKeyframeSource.VideoError.noVideoTrack,
            VideoKeyframeSource.VideoError.readFailed(nil),
            MediaImporter.ImportError.notEnoughContent,
            KeyframeChromeValidationError(issues: [.duplicateRecord(keyframeID: UUID())])
        ]
        for error in errors {
            let message = CaptureCondition.message(for: error)
            #expect(!message.isEmpty)
            #expect(message != error.localizedDescription, "\(error) still shows its bridged description")
            #expect(!message.contains("StitchKit"), "\(error) leaks a module name: \(message)")
            #expect(!message.contains("Error"), "\(error) leaks a type name: \(message)")
            for word in Self.bannedVocabulary {
                #expect(!message.lowercased().contains(word), "\(error) leaks \"\(word)\": \(message)")
            }
        }
    }

    /// An error we have no wording for must not degrade into the bridged placeholder either —
    /// that string names the failing Swift type and means nothing to a user.
    @Test func anUnrecognizedSwiftErrorDoesNotLeakItsTypeName() {
        enum Unforeseen: Error { case somethingNew }
        let message = CaptureCondition.message(for: Unforeseen.somethingNew)
        #expect(!message.contains("Unforeseen"))
        #expect(!message.contains("error 0"))
        #expect(message == "Something went wrong and this couldn't be finished.")
    }

    /// …but an error that *does* carry a real sentence keeps it. Throwing away a specific,
    /// actionable message ("the file doesn't exist", "the disk is full") in favour of a generic
    /// one would be its own regression.
    @Test func anErrorWithARealMessageKeepsIt() {
        let localized = CaptureModel.CaptureError.notFound
        #expect(CaptureCondition.message(for: localized) == "That capture is no longer available.")

        let cocoa = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileNoSuchFileError,
            userInfo: [NSLocalizedDescriptionKey: "The file “kf-0000.bgra” couldn’t be opened."]
        )
        #expect(CaptureCondition.message(for: cocoa) == "The file “kf-0000.bgra” couldn’t be opened.")
    }

    private static let bannedVocabulary = [
        "seam", "chrome", "segment", "confidence", "keyframe", "offset", "profile"
    ]
}
