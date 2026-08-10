import Testing
import Foundation
@testable import StitchKit

@Suite struct StitchSessionTests {
    private let firstKeyframeID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let secondKeyframeID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let danglingKeyframeID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    private func sampleSession() -> StitchSession {
        StitchSession(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            status: .recording,
            deviceScale: 3.0,
            orientation: .portrait,
            colorSpaceName: "kCGColorSpaceDisplayP3",
            keyframes: [
                Keyframe(id: firstKeyframeID, filename: "kf-0000.heic", pixelWidth: 1290, pixelHeight: 2796, index: 0),
                Keyframe(id: secondKeyframeID, filename: "kf-0001.heic", pixelWidth: 1290, pixelHeight: 2796, index: 1),
            ],
            seams: [Seam(fromIndex: 0, provisionalDy: 1800, confidence: 0.92)],
            segmentBreaks: [],
            keyframeChrome: [
                KeyframeChrome(
                    keyframeID: firstKeyframeID,
                    automatic: ChromeMeasurement(
                        insets: ChromeInsets(top: 150, bottom: 120),
                        topConfidence: 0.95,
                        bottomConfidence: 0.92
                    )
                ),
                KeyframeChrome(
                    keyframeID: secondKeyframeID,
                    automatic: ChromeMeasurement(
                        insets: ChromeInsets(top: 140, bottom: 118),
                        topConfidence: 0.90,
                        bottomConfidence: 0.88
                    ),
                    userOverride: ChromeOverride(top: nil, bottom: 96)
                ),
            ]
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let original = sampleSession()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StitchSession.self, from: data)
        #expect(decoded == original)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["manifestFormat"] as? String == StitchSessionManifestFormat.keyframeChromePreRelease.rawValue)
        #expect(object["keyframeChrome"] != nil)
        #expect(object["contentBands"] == nil, "the prerelease migration must not dual-write the removed schema")
    }

    @Test func incrementalAppendGrowsManifest() {
        var session = sampleSession()
        #expect(session.keyframes.count == 2)
        session.keyframes.append(Keyframe(filename: "kf-0002.heic", pixelWidth: 1290, pixelHeight: 2796, index: 2))
        session.seams.append(Seam(fromIndex: 1, provisionalDy: 1750, confidence: 0.88))
        #expect(session.keyframes.count == 3)
        #expect(session.seams.count == 2)
    }

    @Test func statusTransitionsRecordingToComplete() {
        var session = sampleSession()
        #expect(session.status == .recording)
        session.status = .complete
        #expect(session.status == .complete)
    }

    @Test func needsTwoKeyframesToStitch() {
        var session = sampleSession()
        #expect(session.hasStitchableContent)
        session.keyframes.removeLast()
        #expect(!session.hasStitchableContent)
    }

    @Test func reportsSegmentBreakAfterIndex() {
        var session = sampleSession()
        #expect(!session.hasSegmentBreak(after: 0))
        session.segmentBreaks.append(SegmentBreak(afterKeyframeIndex: 0, reason: .lostLock))
        #expect(session.hasSegmentBreak(after: 0))
        #expect(!session.hasSegmentBreak(after: 1))
    }

    @Test func rejectsManifestMissingRequiredFormatMarker() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","createdAt":1000000,
         "status":"complete","deviceScale":3,"orientation":"portrait",
         "keyframes":[],"seams":[],"segmentBreaks":[],
         "keyframeChrome":[],"topTrim":0,"bottomTrim":0,"orderAssumed":false}
        """
        let error = try #require(sessionDecodeFailure(json))
        guard case let .keyNotFound(key, _) = error else {
            Issue.record("Expected missing manifestFormat to produce DecodingError.keyNotFound")
            return
        }
        #expect(key.stringValue == "manifestFormat")
    }

    @Test func rejectsManifestWithOldFormatMarker() throws {
        let json = """
        {"manifestFormat":"stitch-session-v1","id":"11111111-1111-1111-1111-111111111111","createdAt":1000000,
         "status":"complete","deviceScale":3,"orientation":"portrait",
         "keyframes":[],"seams":[],"segmentBreaks":[],
         "keyframeChrome":[],"topTrim":0,"bottomTrim":0,"orderAssumed":false}
        """
        #expect(sessionDecodeFailure(json) != nil)
    }

    @Test func rejectsCurrentFormatManifestMissingKeyframeChrome() throws {
        let json = """
        {"manifestFormat":"stitch-session.keyframe-chrome.v1","id":"11111111-1111-1111-1111-111111111111","createdAt":1000000,
         "status":"complete","deviceScale":3,"orientation":"portrait",
         "keyframes":[],"seams":[],"segmentBreaks":[],
         "topTrim":0,"bottomTrim":0,"orderAssumed":false}
        """
        let error = try #require(sessionDecodeFailure(json))
        guard case let .keyNotFound(key, _) = error else {
            Issue.record("Expected missing keyframeChrome to produce DecodingError.keyNotFound")
            return
        }
        #expect(key.stringValue == "keyframeChrome")
    }

    @Test func resolvesChromeByKeyframeUUIDNotMutableIndex() {
        var session = sampleSession()
        session.keyframes[0].index = 17
        session.keyframes[1].index = 0

        let resolved = session.resolvedChrome(forKeyframeID: secondKeyframeID)

        #expect(resolved.insets == ChromeInsets(top: 140, bottom: 96))
        #expect(resolved.topSource == .automatic)
        #expect(resolved.bottomSource == .userOverride)
        #expect(!resolved.isUnlocked)
    }

    @Test func resolvesChromePerEdgeOverrideThenAutomaticThenZero() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: 100, bottom: 80),
                    topConfidence: 0.8,
                    bottomConfidence: 0.7
                ),
                userOverride: ChromeOverride(top: 64, bottom: nil)
            ),
            KeyframeChrome(
                keyframeID: secondKeyframeID,
                userOverride: ChromeOverride(top: nil, bottom: 44)
            ),
        ]

        let mixed = session.resolvedChrome(forKeyframeID: firstKeyframeID)
        #expect(mixed.insets == ChromeInsets(top: 64, bottom: 80))
        #expect(mixed.topSource == .userOverride)
        #expect(mixed.bottomSource == .automatic)

        let partialOverride = session.resolvedChrome(forKeyframeID: secondKeyframeID)
        #expect(partialOverride.insets == ChromeInsets(top: 0, bottom: 44))
        #expect(partialOverride.topSource == .none)
        #expect(partialOverride.bottomSource == .userOverride)
        #expect(!partialOverride.isUnlocked)
    }

    @Test func absentChromeDataResolvesToZeroUnlocked() {
        var session = sampleSession()
        session.keyframeChrome = []

        #expect(session.resolvedChrome(forKeyframeID: firstKeyframeID) == .unlocked)
        #expect(session.resolvedChrome(forKeyframeID: danglingKeyframeID) == .unlocked)
    }

    @Test func invalidCombinedCropResolvesToZeroUnlocked() {
        var session = sampleSession()
        session.keyframes[0].pixelHeight = 100
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: 40, bottom: 40),
                    topConfidence: 0.9,
                    bottomConfidence: 0.9
                ),
                userOverride: ChromeOverride(top: 20, bottom: nil)
            )
        ]

        #expect(session.resolvedChrome(forKeyframeID: firstKeyframeID) == .unlocked)
    }

    @Test func negativeChromeInsetsResolveToZeroUnlocked() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(insets: ChromeInsets(top: -1, bottom: 10), confidence: 0.9)
            )
        ]

        #expect(session.resolvedChrome(forKeyframeID: firstKeyframeID) == .unlocked)
    }

    @Test func detachedKeyframeCannotSupplyStaleChromeGeometry() {
        var session = sampleSession()
        session.keyframes[0].pixelHeight = 100
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(insets: ChromeInsets(top: 30, bottom: 30), confidence: 0.9)
            )
        ]
        var detached = session.keyframes[0]
        detached.pixelHeight = 1_000

        #expect(session.resolvedChrome(for: detached) == .unlocked)
    }

    @Test func chromeMeasurementConfidenceAcceptsFiniteUnitIntervalBoundaries() {
        let measurement = ChromeMeasurement(
            insets: ChromeInsets(top: 0, bottom: 0),
            topConfidence: 0,
            bottomConfidence: 1
        )

        #expect(measurement.hasValidConfidence)
    }

    @Test func invalidAutomaticConfidenceIsRejectedByValidationAndResolver() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: 10, bottom: 10),
                    topConfidence: 1.01,
                    bottomConfidence: 0.5
                )
            )
        ]

        #expect(session.keyframeChromeValidationIssues() == [
            .invalidAutomaticConfidence(keyframeID: firstKeyframeID, edge: .top)
        ])
        let resolved = session.resolvedChrome(forKeyframeID: firstKeyframeID)
        #expect(resolved.insets == ChromeInsets(top: 0, bottom: 10))
        #expect(resolved.topSource == .none)
        #expect(resolved.bottomSource == .automatic)
        #expect(!resolved.isUnlocked)
    }

    @Test func zeroConfidenceAutomaticEdgeRemainsVisibleForReviewUntilOverridden() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: 0, bottom: 18),
                    topConfidence: 0,
                    bottomConfidence: 0.9
                )
            )
        ]

        #expect(session.chromeEdgesNeedingReview(for: session.keyframes[0]) == [.top])
        session.keyframeChrome[0].userOverride = ChromeOverride(top: 12)
        #expect(session.chromeEdgesNeedingReview(for: session.keyframes[0]).isEmpty)
    }

    @Test func chromeEditingSeedsByUUIDClampsCombinedCropAndCanReturnToAutomatic() {
        var session = sampleSession()
        session.keyframeChrome.removeAll()
        session.ensureChromeRecordsForKeyframes()
        #expect(session.keyframeChrome.map(\.keyframeID) == session.keyframes.map(\.id))

        session.keyframeChrome[0].automatic = ChromeMeasurement(
            insets: ChromeInsets(top: 100, bottom: 120), confidence: 0.9
        )
        session.setChromeOverride(2_000, for: .top, keyframeID: firstKeyframeID)
        #expect(session.chromeValueForEditing(.top, keyframeID: firstKeyframeID) == 1_278)
        #expect(session.resolvedChrome(forKeyframeID: firstKeyframeID).insets == ChromeInsets(top: 1_278, bottom: 120))
        #expect(!session.hasChromeOverride(.bottom, keyframeID: firstKeyframeID))
        #expect(session.chromeValueForEditing(.top, keyframeID: secondKeyframeID) == 0,
                "editing one UUID must not affect another")

        session.setChromeOverride(nil, for: .top, keyframeID: firstKeyframeID)
        #expect(!session.hasChromeOverride(.top, keyframeID: firstKeyframeID))
        #expect(session.chromeValueForEditing(.top, keyframeID: firstKeyframeID) == 100)
    }

    @Test func fullUserOverrideWinsOverInvalidAutomaticConfidence() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: 10, bottom: 10),
                    topConfidence: .nan,
                    bottomConfidence: 2
                ),
                userOverride: ChromeOverride(top: 14, bottom: 16)
            )
        ]

        let resolved = session.resolvedChrome(forKeyframeID: firstKeyframeID)
        #expect(resolved.insets == ChromeInsets(top: 14, bottom: 16))
        #expect(resolved.topSource == .userOverride)
        #expect(resolved.bottomSource == .userOverride)
        #expect(!resolved.isUnlocked)
    }

    @Test func perEdgeUserOverrideWinsOverInvalidAutomaticConfidence() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(
                    insets: ChromeInsets(top: 10, bottom: 18),
                    topConfidence: .infinity,
                    bottomConfidence: 0.8
                ),
                userOverride: ChromeOverride(top: 12, bottom: nil)
            )
        ]

        let resolved = session.resolvedChrome(forKeyframeID: firstKeyframeID)
        #expect(resolved.insets == ChromeInsets(top: 12, bottom: 18))
        #expect(resolved.topSource == .userOverride)
        #expect(resolved.bottomSource == .automatic)
        #expect(!resolved.isUnlocked)
    }

    @Test func decodingInvalidAutomaticConfidenceFails() throws {
        let json = """
        {"manifestFormat":"stitch-session.keyframe-chrome.v1","id":"11111111-1111-1111-1111-111111111111","createdAt":1000000,
         "status":"complete","deviceScale":3,"orientation":"portrait",
         "keyframes":[{"id":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","filename":"kf-0000.heic","pixelWidth":1290,"pixelHeight":2796,"index":0}],
         "seams":[],"segmentBreaks":[],
         "keyframeChrome":[{"keyframeID":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA",
           "automatic":{"insets":{"top":10,"bottom":10},"topConfidence":1.01,"bottomConfidence":0.5}}],
         "topTrim":0,"bottomTrim":0,"orderAssumed":false}
        """

        let error = try #require(sessionDecodeFailure(json))
        guard case .dataCorrupted = error else {
            Issue.record("Expected invalid automatic confidence to produce DecodingError.dataCorrupted")
            return
        }
    }

    @Test func validatesDuplicateAndDanglingChromeRecordsDeterministically() throws {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(keyframeID: danglingKeyframeID),
            KeyframeChrome(keyframeID: firstKeyframeID),
            KeyframeChrome(keyframeID: firstKeyframeID, userOverride: ChromeOverride(top: 8, bottom: nil)),
        ]

        let expectedIssues: [KeyframeChromeValidationIssue] = [
            .duplicateRecord(keyframeID: firstKeyframeID),
            .danglingRecord(keyframeID: danglingKeyframeID),
        ]
        #expect(session.keyframeChromeValidationIssues() == expectedIssues)

        do {
            try session.validateKeyframeChrome()
            Issue.record("Expected duplicate and dangling keyframe chrome records to be rejected")
        } catch let error as KeyframeChromeValidationError {
            #expect(error.issues == expectedIssues)
        }
        #expect(throws: KeyframeChromeValidationError.self) {
            try JSONEncoder().encode(session)
        }
    }

    @Test func duplicateChromeRecordsDoNotResolveByLastWins() {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(insets: ChromeInsets(top: 10, bottom: 10), confidence: 0.9)
            ),
            KeyframeChrome(
                keyframeID: firstKeyframeID,
                automatic: ChromeMeasurement(insets: ChromeInsets(top: 20, bottom: 20), confidence: 0.9)
            ),
        ]

        #expect(session.resolvedChrome(forKeyframeID: firstKeyframeID) == .unlocked)
    }

    @Test func encodesKeyframeChromeRecordsDeterministically() throws {
        var session = sampleSession()
        session.keyframeChrome = [
            KeyframeChrome(keyframeID: secondKeyframeID),
            KeyframeChrome(keyframeID: firstKeyframeID),
        ]

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(StitchSession.self, from: data)

        #expect(decoded.keyframeChrome.map(\.keyframeID) == [firstKeyframeID, secondKeyframeID])
    }

    @Test func frameProfileExposesRowGeometry() {
        let profile = FrameProfile(means: [0.1, 0.2, 0.3, 0.4], variances: [0, 0, 0, 0], sourceWidth: 100, sourceHeight: 800)
        #expect(profile.rowCount == 4)
        #expect(profile.rowScale == 200)
    }

    private func sessionDecodeFailure(_ json: String) -> DecodingError? {
        do {
            _ = try JSONDecoder().decode(StitchSession.self, from: Data(json.utf8))
            Issue.record("Expected StitchSession decoding to fail")
            return nil
        } catch let error as DecodingError {
            return error
        } catch {
            Issue.record("Expected DecodingError but got \(error)")
            return nil
        }
    }
}
