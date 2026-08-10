import Testing
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
        let banned = ["seam", "chrome", "segment", "confidence", "keyframe", "offset", "profile"]
        let facts = CaptureFacts(
            segmentBreaks: 2, flaggedSeams: 2, unresolvedChrome: 2,
            isIncomplete: true, orderAssumed: true
        )
        guard case .imperfect(_, let all) = CaptureCondition(ready: facts) else {
            Issue.record("expected imperfect"); return
        }
        for imperfection in all {
            let text = (imperfection.headline + " " + imperfection.detail).lowercased()
            for word in banned {
                #expect(!text.contains(word), "\(imperfection.kind) leaks \"\(word)\": \(text)")
            }
        }
    }
}
