import Testing
import CoreGraphics
import Foundation
import StitchKit
@testable import Seamly

/// The queue holds answers and writes them once. What matters is that every kind of answer
/// reaches the manifest, and that an answered finding stops being a finding — otherwise the
/// queue would re-raise a question the user just answered.
@MainActor
struct RepairQueueModelTests {

    /// A real capture on disk, so `CaptureModel` can load, assemble and re-assemble it.
    private func makeCapture(
        chromeUncertainOn: Set<Int> = [], flagged: Set<Int> = [],
        chromeMeasurements: [Int: ChromeMeasurement] = [:]
    ) async throws -> (CaptureModel, UUID) {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let store = SessionStore(containerURL: container)

        let id = UUID()
        let folder = try store.createFolder(for: id)
        let width = 120, height = 300, dy = 180, count = 3
        let source = ramp(width: width, height: height + dy * count)

        var session = StitchSession(
            id: id, createdAt: Date(timeIntervalSince1970: 0), status: .complete,
            deviceScale: 1, orientation: .portrait,
            colorSpaceName: source.colorSpace?.name as String?
        )
        for index in 0..<count {
            let name = String(format: "kf-%04d.bgra", index)
            let crop = source.cropping(to: CGRect(x: 0, y: index * dy, width: width, height: height))!
            try KeyframeIO.writeRaw(crop, to: folder.appendingPathComponent(name))
            session.keyframes.append(
                Keyframe(filename: name, pixelWidth: width, pixelHeight: height, index: index)
            )
        }
        session.seams = (0..<(count - 1)).map {
            Seam(fromIndex: $0, provisionalDy: dy,
                 confidence: flagged.contains($0) ? 0.2 : 0.9,
                 isLowConfidence: flagged.contains($0))
        }
        session.keyframeChrome = session.keyframes.map { kf in
            if let measurement = chromeMeasurements[kf.index] {
                return KeyframeChrome(keyframeID: kf.id, automatic: measurement)
            }
            return chromeUncertainOn.contains(kf.index)
                ? KeyframeChrome(keyframeID: kf.id)
                : KeyframeChrome(keyframeID: kf.id,
                                 automatic: ChromeMeasurement(insets: .zero, confidence: 0.9))
        }
        try store.writeManifest(session)

        let model = CaptureModel(appContainer: container, groupContainer: nil)
        await model.refresh()
        return (model, id)
    }

    private func ramp(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let bpr = width * 4
        var buf = [UInt8](repeating: 0, count: bpr * height)
        for y in 0..<height {
            for x in 0..<width {
                let v = 40.0 + Double(y) * (150.0 / Double(height)) + 40 * sin(Double(x) * 0.4)
                let b = UInt8(max(0, min(255, v)))
                let o = y * bpr + x * 4
                buf[o] = b; buf[o + 1] = b; buf[o + 2] = b; buf[o + 3] = 255
            }
        }
        let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bpr,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    @Test func answeringNoBarsClearsTheFinding() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .bars })

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.acceptNoBars(for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id })
        #expect(after.findings.filter { $0.kind == .bars }.isEmpty,
                "an answered finding must stop being a finding, or the queue re-asks it")
    }

    /// A finding's `edges` can name one edge alone — the other may already carry a confident
    /// automatic measurement. "No bars here" must answer only the edge actually in doubt: a
    /// blanket zero on both would un-crop a bar the pipeline had measured correctly, which is
    /// the precise regression this feature exists to prevent.
    @Test func acceptNoBarsPreservesTheConfidentEdge() async throws {
        let (model, id) = try await makeCapture(chromeMeasurements: [
            1: ChromeMeasurement(insets: ChromeInsets(top: 0, bottom: 34), topConfidence: 0, bottomConfidence: 0.9)
        ])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .bars })
        guard case .chrome(let keyframeID, let edges) = finding.target else {
            Issue.record("expected a chrome target")
            return
        }
        #expect(edges == [.top], "the bottom edge already has a confident measurement")

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.acceptNoBars(for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id })
        #expect(after.session.chromeValueForEditing(.bottom, keyframeID: keyframeID) == 34,
                "the pipeline's confident bottom measurement must survive an answer about the top")
        #expect(after.session.chromeValueForEditing(.top, keyframeID: keyframeID) == 0)
    }

    @Test func aBarsAnswerReachesTheManifest() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .bars })
        guard case .chrome(let keyframeID, _) = finding.target else {
            Issue.record("expected a chrome target")
            return
        }

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.setChrome(44, edge: .top, for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id })
        #expect(after.session.chromeValueForEditing(.top, keyframeID: keyframeID) == 44)
        #expect(after.session.hasChromeOverride(.top, keyframeID: keyframeID))
    }

    /// Chrome moves every position below it, so the composite must actually change height.
    ///
    /// A crop on an interior keyframe only shifts which of two overlapping frames supplies the
    /// boundary rows — the compositor's overlap math cancels a modest crop exactly, so the
    /// total height is provably invariant until the crop is large enough to push the seam
    /// search past its clamp. 150 is `chromeRange(for:)`'s own ceiling for this fixture (half of
    /// a 300 px frame), so it is guaranteed to cross that point without exceeding what the
    /// stepper itself would ever let the user dial in.
    @Test func aBarsAnswerChangesTheCompositesHeight() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let before = try #require(model.captures.first { $0.id == id }).pixelSize.height
        let finding = try #require(model.captures.first { $0.id == id }?.findings.first { $0.kind == .bars })

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.setChrome(150, edge: .bottom, for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id }).pixelSize.height
        #expect(after != before)
    }

    /// A queue the user walked without changing anything must close cleanly. Committing
    /// nothing is a success, not a failure — otherwise "Skip all" would raise a save error.
    /// The gap that let two versions of the same bug through: the suite tested `setChrome` →
    /// `commit` and `acceptNoBars` → `commit`, but never `setChrome` → **accept**, which is the
    /// only route a user actually has. The affirmative is the sole way to advance a bars finding.
    @Test func acceptKeepsTheCropTheUserTypedAndZeroesOnlyTheRest() async throws {
        let (model, id) = try await makeCapture(chromeUncertainOn: [1])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .bars })
        guard case .chrome(let keyframeID, let edges) = finding.target else {
            Issue.record("expected a chrome target")
            return
        }
        #expect(edges.contains(.top) && edges.contains(.bottom), "both edges start in doubt")

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        queue.setChrome(44, edge: .top, for: finding)
        queue.acceptNoBars(for: finding)
        #expect(await queue.commit())

        let after = try #require(model.captures.first { $0.id == id })
        #expect(after.session.chromeValueForEditing(.top, keyframeID: keyframeID) == 44,
                "the tap that submits an answer must not destroy it")
        #expect(after.session.chromeValueForEditing(.bottom, keyframeID: keyframeID) == 0,
                "the edge the user did not answer is still answered 'none'")
        #expect(after.findings.filter { $0.kind == .bars }.isEmpty,
                "and the finding is done being asked")
    }

    @Test func committingNothingSucceeds() async throws {
        let (model, id) = try await makeCapture()
        let queue = RepairQueueModel(captureID: id, model: model, startAt: 1)
        #expect(!queue.hasPendingEdits)
        #expect(await queue.commit())
    }

    @Test func answeringTheLastFindingCommitsAndFinishes() async throws {
        let (model, id) = try await makeCapture(flagged: [0])
        let capture = try #require(model.captures.first { $0.id == id })
        let finding = try #require(capture.findings.first { $0.kind == .seam })

        let queue = RepairQueueModel(captureID: id, model: model, startAt: finding.n)
        await queue.load()
        queue.setDy(150)
        #expect(await queue.answer(), "the last answer commits and tells the caller to close")

        let after = try #require(model.captures.first { $0.id == id })
        let seam = try #require(after.session.seams.first { $0.fromIndex == 0 })
        #expect(seam.provisionalDy == 150)
        #expect(!seam.isLowConfidence, "a join the user has looked at must stop being flagged")
    }
}
