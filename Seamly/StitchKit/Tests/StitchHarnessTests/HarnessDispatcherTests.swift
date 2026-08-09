import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import StitchKit
@testable import StitchHarness

struct HarnessDispatcherTests {
    @Test func profileReturnsSemanticJSONEnvelope() async throws {
        try await withTemporaryDirectory { directory in
            let imageURL = directory.appendingPathComponent("frame.png")
            try writePNG(makeImage(width: 16, height: 24), to: imageURL)

            let data = try await HarnessDispatcher().run(["profile", imageURL.path])
            let root = try object(data)
            let result = try #require(root["result"] as? [String: Any])

            #expect(root["schemaVersion"] as? String == "stitch-harness.v1")
            #expect(root["command"] as? String == "profile")
            #expect(root["ok"] as? Bool == true)
            #expect(result["sourceWidth"] as? Int == 16)
            #expect(result["sourceHeight"] as? Int == 24)
            #expect(result["rowCount"] as? Int == 24)
            let means = try #require(result["means"] as? [String: Any])
            let variances = try #require(result["variances"] as? [String: Any])
            #expect(means["min"] is Double)
            #expect(means["max"] is Double)
            #expect(means["average"] is Double)
            #expect(variances["min"] is Double)
            #expect(result["means"] as? [Double] == nil)
            #expect(data.last == 0x0A)
        }
    }

    @Test func matchUsesDisplacedRealFramesAndChromeMaskImprovesConfidence() async throws {
        let fixtures = photosFixtureDirectory()
        let a = fixtures.appendingPathComponent("IMG_1757.PNG")
        let b = fixtures.appendingPathComponent("IMG_1758.PNG")

        let plain = try result(try await HarnessDispatcher().run(["match", a.path, b.path]))
        let masked = try result(try await HarnessDispatcher().run([
            "match", a.path, b.path, "--mask-chrome",
        ]))

        #expect(plain["dy"] as? Int == 296)
        #expect(plain["sourceDy"] as? Int == 1326)
        #expect(masked["dy"] as? Int == 296)
        #expect(masked["sourceDy"] as? Int == 1326)
        #expect(masked["maskChrome"] as? Bool == true)
        #expect((masked["maskedRows"] as? Int ?? 0) > 0)
        #expect(masked["geometricOverlapFraction"] as? Double == 0.5375)
        #expect(masked["overlapFraction"] == nil)
        let matcherOverlap = try #require(masked["matcherOverlap"] as? [String: Any])
        #expect(Set(matcherOverlap.keys) == [
            "countedRows", "countableRows", "minimumRequiredRows", "fraction", "passesMinimum",
        ])
        #expect((matcherOverlap["countedRows"] as? Int ?? 0) > 0)
        #expect((matcherOverlap["countableRows"] as? Int ?? 0) > 0)
        #expect((matcherOverlap["minimumRequiredRows"] as? Int ?? 0) > 0)
        #expect(matcherOverlap["passesMinimum"] as? Bool == true)
        let countedRows = try #require(matcherOverlap["countedRows"] as? Int)
        let countableRows = try #require(matcherOverlap["countableRows"] as? Int)
        let minimumRequiredRows = try #require(matcherOverlap["minimumRequiredRows"] as? Int)
        let matcherFraction = try #require(matcherOverlap["fraction"] as? Double)
        #expect(countedRows <= countableRows)
        #expect(minimumRequiredRows <= countedRows)
        #expect(matcherFraction == Double(countedRows) / Double(countableRows))
        #expect(matcherFraction != 0.5375)
        let plainConfidence = try #require(plain["confidence"] as? Double)
        let maskedConfidence = try #require(masked["confidence"] as? Double)
        #expect(maskedConfidence > plainConfidence)
    }

    @Test func errorEnvelopeHasStableCodeAndSortedKeys() throws {
        let data = HarnessDispatcher.errorData(
            for: HarnessError.missingValue("--out"),
            arguments: ["session", "create"]
        )
        let root = try object(data)
        let error = try #require(root["error"] as? [String: Any])
        #expect(error["code"] as? String == "missing_value")
        #expect(error["message"] as? String == "missing value for option: --out")
        #expect(String(decoding: data, as: UTF8.self).hasPrefix("{\n  \"command\""))
        #expect(HarnessError.invalidSession("bad topology").code == "invalid_session")
    }

    @Test func sessionRoundTripInspectAndCompose() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let container = directory.appendingPathComponent("container")
            let output = directory.appendingPathComponent("stitched.png")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let source = makeImage(width: 32, height: 112)
            try writePNG(try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 32, height: 72))),
                         to: input.appendingPathComponent("scroll-01.png"))
            try writePNG(try #require(source.cropping(to: CGRect(x: 0, y: 40, width: 32, height: 72))),
                         to: input.appendingPathComponent("scroll-02.png"))

            let created = try result(try await HarnessDispatcher().run([
                "session", "create", input.path, "--out", container.path,
                "--prefix", "scroll-", "--order", "input",
            ]))
            #expect(created["keyframeCount"] as? Int == 2)
            #expect(created["orderMode"] as? String == "input")
            let folder = try #require(created["folder"] as? String)
            let manifest = try #require(created["manifest"] as? String)
            #expect(FileManager.default.fileExists(atPath: manifest))
            #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: folder).appendingPathComponent("kf-0000.bgra").path))

            let inspected = try result(try await HarnessDispatcher().run(["session", "inspect", folder]))
            #expect(inspected["valid"] as? Bool == true)
            #expect(inspected["keyframeCount"] as? Int == 2)
            #expect(inspected["seamCount"] as? Int == 1)

            let composed = try result(try await HarnessDispatcher().run(["compose", folder, "--out", output.path]))
            #expect(composed["frameCount"] as? Int == 2)
            #expect(composed["path"] as? String == output.path)
            let image = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(CGImageSourceCreateImageAtIndex(image, 0, nil) != nil)
        }
    }

    @Test func inspectReportsTypedMissingKeyframeError() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let container = directory.appendingPathComponent("container")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let image = makeImage(width: 32, height: 64)
            try writePNG(image, to: input.appendingPathComponent("01.png"))
            try writePNG(image, to: input.appendingPathComponent("02.png"))
            let created = try result(try await HarnessDispatcher().run([
                "session", "create", input.path, "--out", container.path, "--order", "input",
            ]))
            let folder = URL(fileURLWithPath: try #require(created["folder"] as? String))
            try FileManager.default.removeItem(at: folder.appendingPathComponent("kf-0001.bgra"))
            await #expect(throws: HarnessError.keyframeMissing(folder.appendingPathComponent("kf-0001.bgra").path)) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }
        }
    }

    @Test func malformedManifestErrorEnvelopeRetainsDecodingCauseAndCodingPath() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            try mutateManifest(at: folder.appendingPathComponent("manifest.json")) { manifest in
                manifest["id"] = 7
            }

            do {
                _ = try await HarnessDispatcher().run(["session", "inspect", folder.path])
                Issue.record("expected malformed manifest to fail")
            } catch {
                let envelope = try object(HarnessDispatcher.errorData(
                    for: error,
                    arguments: ["session", "inspect", folder.path]
                ))
                let serialized = try #require(envelope["error"] as? [String: Any])
                #expect(serialized["code"] as? String == "manifest_read_failed")
                let cause = try #require(serialized["cause"] as? String)
                #expect(cause.contains("id"), "cause must retain the decoder coding path: \(cause)")
            }
        }
    }

    @Test func corruptRawKeyframeErrorRetainsExpectedAndActualByteCounts() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 1)
            try Data(repeating: 0, count: 7).write(
                to: folder.appendingPathComponent("kf-0000.bgra"),
                options: .atomic
            )

            do {
                _ = try await HarnessDispatcher().run(["session", "inspect", folder.path])
                Issue.record("expected corrupt raw keyframe to fail validation")
            } catch {
                let envelope = try object(HarnessDispatcher.errorData(
                    for: error,
                    arguments: ["session", "inspect", folder.path]
                ))
                let serialized = try #require(envelope["error"] as? [String: Any])
                #expect(serialized["code"] as? String == "keyframe_decode_failed")
                let cause = try #require(serialized["cause"] as? String)
                #expect(cause.contains("expected 4608 bytes"))
                #expect(cause.contains("actual 7 bytes"))
            }
        }
    }

    @Test func inspectRejectsDuplicateKeyframeIndexAndID() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            let manifestURL = folder.appendingPathComponent("manifest.json")
            let original = try Data(contentsOf: manifestURL)

            try mutateManifest(at: manifestURL) { manifest in
                var keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
                keyframes[1]["index"] = keyframes[0]["index"]
                manifest["keyframes"] = keyframes
            }
            await #expect(throws: HarnessError.invalidSession("keyframe indices must be unique and exactly 0..<2")) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }

            try original.write(to: manifestURL, options: .atomic)
            try mutateManifest(at: manifestURL) { manifest in
                var keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
                keyframes[1]["id"] = keyframes[0]["id"]
                manifest["keyframes"] = keyframes
            }
            await #expect(throws: HarnessError.invalidSession("keyframe IDs must be unique")) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }
        }
    }

    @Test func inspectRejectsTraversalBeforeLoadingKeyframe() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            let escaped = directory.appendingPathComponent("escaped.bgra")
            try Data().write(to: escaped)
            try mutateManifest(at: folder.appendingPathComponent("manifest.json")) { manifest in
                var keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
                keyframes[0]["filename"] = "../escaped.bgra"
                manifest["keyframes"] = keyframes
            }

            await #expect(throws: HarnessError.invalidSession("unsafe keyframe filename: ../escaped.bgra")) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }
            await #expect(throws: HarnessError.invalidSession("unsafe keyframe filename: ../escaped.bgra")) {
                try await HarnessDispatcher().run([
                    "compose", folder.path, "--out", directory.appendingPathComponent("out.png").path,
                ])
            }
        }
    }

    @Test func inspectRejectsKeyframeSymlinkEscapingSessionFolder() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 1)
            let keyframe = folder.appendingPathComponent("kf-0000.bgra")
            let external = directory.appendingPathComponent("external.bgra")
            try FileManager.default.moveItem(at: keyframe, to: external)
            try FileManager.default.createSymbolicLink(at: keyframe, withDestinationURL: external)

            await #expect(throws: HarnessError.invalidSession(
                "keyframe must resolve directly inside session folder: kf-0000.bgra"
            )) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }
            await #expect(throws: HarnessError.invalidSession(
                "keyframe must resolve directly inside session folder: kf-0000.bgra"
            )) {
                try await HarnessDispatcher().run([
                    "compose", folder.path, "--out", directory.appendingPathComponent("out.png").path,
                ])
            }
        }
    }

    @Test func canonicalSessionPathValidationAcceptsSymlinkedSessionFolder() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            let alias = directory.appendingPathComponent("session-alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder)

            let inspected = try result(try await HarnessDispatcher().run([
                "session", "inspect", alias.path,
            ]))
            #expect(inspected["valid"] as? Bool == true)

            let output = directory.appendingPathComponent("symlinked-session.png")
            let composed = try result(try await HarnessDispatcher().run([
                "compose", alias.path, "--out", output.path,
            ]))
            #expect(composed["frameCount"] as? Int == 2)
            #expect(FileManager.default.fileExists(atPath: output.path))
        }
    }

    @Test func composeAcceptsCompressedKeyframes() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            try replaceRawKeyframesWithPNGs(in: folder, count: 2)

            let output = directory.appendingPathComponent("compressed.png")
            let composed = try result(try await HarnessDispatcher().run([
                "compose", folder.path, "--out", output.path,
            ]))
            #expect(composed["frameCount"] as? Int == 2)
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(composed["width"] as? Int == image.width)
            #expect(composed["height"] as? Int == image.height)
        }
    }

    @Test func inspectAndComposeCorruptCompressedKeyframeRetainDecodeCause() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            try replaceRawKeyframesWithPNGs(in: folder, count: 2)
            try Data("not an image".utf8).write(
                to: folder.appendingPathComponent("kf-0001.png"), options: .atomic
            )

            for arguments in [
                ["session", "inspect", folder.path],
                ["compose", folder.path, "--out", directory.appendingPathComponent("out.png").path],
            ] {
                do {
                    _ = try await HarnessDispatcher().run(arguments)
                    Issue.record("expected corrupt compressed keyframe to fail: \(arguments)")
                } catch {
                    let serialized = try #require(try object(HarnessDispatcher.errorData(
                        for: error, arguments: arguments
                    ))["error"] as? [String: Any])
                    #expect(serialized["code"] as? String == "keyframe_decode_failed")
                    #expect((serialized["cause"] as? String)?.isEmpty == false)
                }
            }
        }
    }

    @Test func inspectRejectsInvalidSeamAndSegmentBreakTopology() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 2)
            let manifestURL = folder.appendingPathComponent("manifest.json")
            let original = try Data(contentsOf: manifestURL)

            try mutateManifest(at: manifestURL) { manifest in
                var seams = try #require(manifest["seams"] as? [[String: Any]])
                seams[0]["fromIndex"] = 1
                manifest["seams"] = seams
            }
            await #expect(throws: HarnessError.invalidSession("seam fromIndex must be in 0..<1 and unique")) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }

            try original.write(to: manifestURL, options: .atomic)
            try mutateManifest(at: manifestURL) { manifest in
                manifest["segmentBreaks"] = [["afterKeyframeIndex": 1, "reason": "lostLock"]]
            }
            await #expect(throws: HarnessError.invalidSession("segment break index must be in 0..<1 and unique")) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }

            try original.write(to: manifestURL, options: .atomic)
            try mutateManifest(at: manifestURL) { manifest in
                manifest["segmentBreaks"] = [["afterKeyframeIndex": 0, "reason": "lostLock"]]
            }
            await #expect(throws: HarnessError.invalidSession("seam and segment break cannot share index 0")) {
                try await HarnessDispatcher().run(["session", "inspect", folder.path])
            }
        }
    }

    @Test func validManifestInspectsAndOneKeyframeIsNotStitchable() async throws {
        try await withTemporaryDirectory { directory in
            let folder = try await makeSession(in: directory, imageCount: 1)
            let inspected = try result(try await HarnessDispatcher().run(["session", "inspect", folder.path]))
            #expect(inspected["valid"] as? Bool == true)
            #expect(inspected["stitchable"] as? Bool == false)
            #expect(inspected["keyframeCount"] as? Int == 1)

            await #expect(throws: HarnessError.insufficientKeyframes(1)) {
                try await HarnessDispatcher().run([
                    "compose", folder.path, "--out", directory.appendingPathComponent("out.png").path,
                ])
            }
        }
    }

    @Test func recoveredSessionStoresPixelsAndSeamsByOrderedSlot() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let container = directory.appendingPathComponent("container")
            let reference = directory.appendingPathComponent("top.bgra")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let source = makeImage(width: 48, height: 128)
            let top = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 80)))
            let bottom = try #require(source.cropping(to: CGRect(x: 0, y: 40, width: 48, height: 80)))
            try writePNG(bottom, to: input.appendingPathComponent("01-bottom.png"))
            try writePNG(top, to: input.appendingPathComponent("02-top.png"))
            try KeyframeIO.writeRaw(top, to: reference)

            let created = try result(try await HarnessDispatcher().run([
                "session", "create", input.path, "--out", container.path, "--order", "recover",
            ]))
            let folder = URL(fileURLWithPath: try #require(created["folder"] as? String))
            #expect(try Data(contentsOf: folder.appendingPathComponent("kf-0000.bgra")) == Data(contentsOf: reference))

            let manifestData = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
            let manifest = try #require(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            let keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
            let seams = try #require(manifest["seams"] as? [[String: Any]])
            #expect(keyframes.compactMap { $0["filename"] as? String } == ["kf-0000.bgra", "kf-0001.bgra"])
            #expect(keyframes.compactMap { $0["index"] as? Int } == [0, 1])
            #expect(seams.compactMap { $0["fromIndex"] as? Int } == [0])
        }
    }

    @Test func captureFramesLoadsLexicallyAndReportsCanonicalShape() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let output = directory.appendingPathComponent("output")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            try writePNG(makeImage(width: 24, height: 48), to: input.appendingPathComponent("p-02.jpg"))
            try writePNG(makeImage(width: 24, height: 48), to: input.appendingPathComponent("p-01.png"))
            try writePNG(makeImage(width: 24, height: 48), to: input.appendingPathComponent("skip.png"))

            let data = try await HarnessDispatcher().run([
                "capture", "frames", input.path, "--prefix", "p-", "--out", output.path,
            ])
            let result = try #require(try object(data)["result"] as? [String: Any])
            #expect(Set(result.keys) == [
                "source", "input", "processedFrameCount", "keyframeCount", "safetyCueCount",
                "keyframes", "outDirectory", "files",
            ])
            #expect(result["source"] as? String == "frames")
            #expect(result["files"] as? [String] == ["p-01.png", "p-02.jpg"])
            #expect(result["processedFrameCount"] as? Int == 2)
            #expect(result["keyframeCount"] as? Int == 1)
            #expect(result["safetyCueCount"] is Int)
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("kf-0000.png").path))
        }
    }

    @Test func planInputOrderWritesManifest() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let output = directory.appendingPathComponent("output")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            try writePNG(makeImage(width: 20, height: 40), to: input.appendingPathComponent("one.png"))

            let data = try await HarnessDispatcher().run([
                "plan", input.path, "--order", "input", "--out", output.path,
            ])
            let result = try #require(try object(data)["result"] as? [String: Any])
            #expect(result["order"] as? [Int] == [0])
            #expect(result["orderMode"] as? String == "input")
            #expect(result["manifest"] is [String: Any])
            #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("manifest.json").path))
        }
    }

    @Test func rejectsUnknownMissingAndDuplicateOptions() async throws {
        let dispatcher = HarnessDispatcher()
        await #expect(throws: HarnessError.unknownOption("--wat")) {
            try await dispatcher.run(["plan", "/tmp", "--wat", "x"])
        }
        await #expect(throws: HarnessError.missingValue("--prefix")) {
            try await dispatcher.run(["capture", "frames", "/tmp", "--prefix"])
        }
        await #expect(throws: HarnessError.duplicateOption("--out")) {
            try await dispatcher.run(["plan", "/tmp", "--out", "a", "--out", "b"])
        }
        await #expect(throws: HarnessError.usage("match <a> <b> [--mask-chrome]")) {
            try await dispatcher.run(["match", "a", "b", "--other"])
        }
        await #expect(throws: HarnessError.missingValue("--out")) {
            try await dispatcher.run(["compose", "/tmp/session"])
        }
        await #expect(throws: HarnessError.usage("session inspect <session-folder>")) {
            try await dispatcher.run(["session", "inspect", "/tmp/session", "extra"])
        }
    }

    @Test func rejectsRemovedImagesAliases() async throws {
        let dispatcher = HarnessDispatcher()
        await #expect(throws: HarnessError.unsupportedSource("images")) {
            try await dispatcher.run(["capture", "images", "/tmp"])
        }
        await #expect(throws: HarnessError.unsupportedSource("images")) {
            try await dispatcher.run(["pipeline", "images", "/tmp", "--out", "/tmp/out"])
        }
    }

    @Test func videoCaptureRejectsInvalidFPSAndMissingFile() async throws {
        let dispatcher = HarnessDispatcher()
        await #expect(throws: HarnessError.invalidFPS("0")) {
            try await dispatcher.run(["capture", "video", "/tmp/missing.mp4", "--fps", "0"])
        }
        await #expect(throws: HarnessError.videoReadFailed("/tmp/missing.mp4")) {
            try await dispatcher.run(["capture", "video", "/tmp/missing.mp4"])
        }
        await #expect(throws: HarnessError.unsupportedSource("audio")) {
            try await dispatcher.run(["capture", "audio", "/tmp/input.wav"])
        }
        await #expect(throws: HarnessError.unsupportedSource("audio")) {
            try await dispatcher.run(["capture", "audio"])
        }
    }

    @Test func captureVideoOmitsInapplicableFieldsAndWritesKeyframePNGs() async throws {
        try await withTemporaryDirectory { directory in
            let video = directory.appendingPathComponent("scroll.mp4")
            let output = directory.appendingPathComponent("keyframes")
            try await writeMP4(frames: try scrollingFrames(), to: video)

            let capture = try result(try await HarnessDispatcher().run([
                "capture", "video", video.path, "--fps", "30", "--out", output.path,
            ]))

            #expect(Set(capture.keys) == [
                "source", "input", "processedFrameCount", "decodeFailureCount", "keyframeCount",
                "keyframes", "outDirectory", "fps",
            ])
            #expect(capture["source"] as? String == "video")
            #expect(capture["input"] as? String == video.path)
            #expect(capture["fps"] as? Double == 30)
            #expect(capture["processedFrameCount"] as? Int == 9)
            #expect(capture["decodeFailureCount"] as? Int == 0)
            #expect(capture["safetyCueCount"] == nil)
            let keyframeCount = try #require(capture["keyframeCount"] as? Int)
            #expect(keyframeCount >= 2)
            for index in 0..<keyframeCount {
                let url = output.appendingPathComponent(String(format: "kf-%04d.png", index))
                let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
                #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
            }
        }
    }

    @Test func pipelineRejectsInsufficientImagesAfterIngestion() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            try writePNG(makeImage(width: 32, height: 64), to: input.appendingPathComponent("only.png"))
            #expect(HarnessError.insufficientPipelineImages(1).code == "insufficient_pipeline_images")
            #expect(
                HarnessError.insufficientPipelineImages(1).errorDescription
                    == "pipeline requires at least 2 images after ingestion; available 1"
            )
            await #expect(throws: HarnessError.insufficientPipelineImages(1)) {
                try await HarnessDispatcher().run([
                    "pipeline", "photos", input.path, "--out", directory.appendingPathComponent("out").path,
                ])
            }
        }
    }

    @Test func pipelineVideoDefaultsToInputOrderPersistsAndComposes() async throws {
        try await withTemporaryDirectory { directory in
            let video = directory.appendingPathComponent("scroll.mp4")
            let output = directory.appendingPathComponent("output")
            try await writeMP4(frames: try scrollingFrames(), to: video)

            let pipeline = try result(try await HarnessDispatcher().run([
                "pipeline", "video", video.path, "--out", output.path, "--fps", "30",
            ]))

            #expect(Set(pipeline.keys) == ["source", "stages"])
            #expect(pipeline["source"] as? String == "video")
            let stages = try #require(pipeline["stages"] as? [String: Any])
            #expect(Set(stages.keys) == ["ingestion", "plan", "session", "composition"])
            let ingestion = try #require(stages["ingestion"] as? [String: Any])
            #expect(Set(ingestion.keys) == [
                "input", "processedFrameCount", "decodeFailureCount", "keyframeCount",
                "keyframes", "fps",
            ])
            #expect(ingestion["source"] == nil)
            #expect(ingestion["fps"] as? Double == 30)
            #expect(ingestion["processedFrameCount"] as? Int == 9)
            #expect(ingestion["decodeFailureCount"] as? Int == 0)
            #expect(ingestion["safetyCueCount"] == nil)

            let plan = try #require(stages["plan"] as? [String: Any])
            #expect(plan["orderMode"] as? String == "input")
            let order = try #require(plan["order"] as? [Int])
            let expectedOrder = Array(0..<order.count)
            #expect(order == expectedOrder)
            #expect(order.count >= 2)

            let session = try #require(stages["session"] as? [String: Any])
            #expect(Set(session.keys) == ["sessionID", "folder", "manifest", "keyframeCount"])
            let folder = URL(fileURLWithPath: try #require(session["folder"] as? String))
            #expect(folder.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "store")
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path))
            let manifestData = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
            let manifest = try #require(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            let keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
            #expect(keyframes.count == order.count)
            let allRawKeyframes = keyframes.allSatisfy { ($0["filename"] as? String)?.hasSuffix(".bgra") == true }
            #expect(allRawKeyframes)
            for index in keyframes.indices {
                #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(String(format: "kf-%04d.bgra", index)).path))
            }

            let stitched = output.appendingPathComponent("stitched.png")
            let imageSource = try #require(CGImageSourceCreateWithURL(stitched as CFURL, nil))
            let stitchedImage = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            let composition = try #require(stages["composition"] as? [String: Any])
            #expect(Set(composition.keys) == ["width", "height", "path"])
            #expect(composition["path"] as? String == stitched.path)
            #expect(composition["width"] as? Int == stitchedImage.width)
            #expect(composition["height"] as? Int == stitchedImage.height)
        }
    }

    @Test func pipelineFramesDrivesCaptureAndDefaultsToTrustedInputOrder() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let output = directory.appendingPathComponent("output")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let source = makeImage(width: 48, height: 240)
            for (index, y) in [0, 12, 24, 36, 48, 60, 72, 84, 96].enumerated() {
                let frame = try #require(source.cropping(to: CGRect(x: 0, y: y, width: 48, height: 96)))
                try writePNG(frame, to: input.appendingPathComponent(String(format: "frame-%02d.png", index)))
            }

            let pipeline = try result(try await HarnessDispatcher().run([
                "pipeline", "frames", input.path, "--out", output.path,
            ]))
            #expect(Set(pipeline.keys) == ["source", "stages"])
            #expect(pipeline["source"] as? String == "frames")
            let stages = try #require(pipeline["stages"] as? [String: Any])
            #expect(Set(stages.keys) == ["ingestion", "plan", "session", "composition"])
            let ingestion = try #require(stages["ingestion"] as? [String: Any])
            #expect(Set(ingestion.keys) == [
                "input", "processedFrameCount", "keyframeCount", "safetyCueCount",
                "keyframes", "files",
            ])
            #expect(ingestion["source"] == nil)
            #expect(ingestion["processedFrameCount"] as? Int == 9)
            let committedCount = try #require(ingestion["keyframeCount"] as? Int)
            #expect(committedCount >= 2)
            #expect(committedCount < 9, "dense raw frames should be reduced to committed keyframes")
            #expect(ingestion["safetyCueCount"] is Int)
            let plan = try #require(stages["plan"] as? [String: Any])
            #expect(Set(plan.keys) == [
                "orderMode", "orderAssumed", "order", "seamCount", "segmentBreakCount",
                "contentBandCount",
            ])
            #expect(plan["orderMode"] as? String == "input")
            #expect(plan["orderAssumed"] as? Bool == false)
            #expect((plan["order"] as? [Int])?.count == committedCount)
            let session = try #require(stages["session"] as? [String: Any])
            let folder = URL(fileURLWithPath: try #require(session["folder"] as? String))
            let stitched = output.appendingPathComponent("stitched.png")
            #expect(folder.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "store")
            #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("manifest.json").path))
            let inspected = try result(try await HarnessDispatcher().run(["session", "inspect", folder.path]))
            #expect((inspected["keyframeCount"] as? Int ?? 0) >= 2)
            let imageSource = try #require(CGImageSourceCreateWithURL(stitched as CFURL, nil))
            let stitchedImage = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
            let composition = try #require(stages["composition"] as? [String: Any])
            #expect(composition["width"] as? Int == stitchedImage.width)
            #expect(composition["height"] as? Int == stitchedImage.height)
            let manifestData = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
            let manifest = try #require(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            let keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
            #expect(keyframes.allSatisfy { ($0["filename"] as? String)?.hasSuffix(".bgra") == true })
        }
    }

    @Test func pipelineCommittedPlansEveryKeyframeAndDefaultsToRecoverOrInput() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            let output = directory.appendingPathComponent("output")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let source = makeImage(width: 48, height: 240)
            for (index, y) in [0, 12, 24, 36, 48, 60, 72, 84, 96].enumerated() {
                let frame = try #require(source.cropping(to: CGRect(x: 0, y: y, width: 48, height: 96)))
                try writePNG(frame, to: input.appendingPathComponent(String(format: "frame-%02d.png", index)))
            }

            let pipeline = try result(try await HarnessDispatcher().run([
                "pipeline", "committed", input.path, "--out", output.path,
            ]))

            #expect(Set(pipeline.keys) == ["source", "stages"])
            #expect(pipeline["source"] as? String == "committed")
            let stages = try #require(pipeline["stages"] as? [String: Any])
            #expect(Set(stages.keys) == ["ingestion", "plan", "session", "composition"])
            let ingestion = try #require(stages["ingestion"] as? [String: Any])
            #expect(Set(ingestion.keys) == [
                "input", "processedFrameCount", "keyframeCount", "keyframes", "files",
            ])
            #expect(ingestion["source"] == nil)
            #expect(ingestion["files"] as? [String] == (0..<9).map { String(format: "frame-%02d.png", $0) })
            #expect(ingestion["processedFrameCount"] as? Int == 9)
            #expect(ingestion["keyframeCount"] as? Int == 9)
            #expect(ingestion["safetyCueCount"] == nil)

            let plan = try #require(stages["plan"] as? [String: Any])
            #expect(plan["orderMode"] as? String == "recover-or-input")
            #expect((plan["order"] as? [Int])?.count == 9)
            let session = try #require(stages["session"] as? [String: Any])
            #expect(session["keyframeCount"] as? Int == 9)
        }
    }

    @Test func pipelinePhotosUsesEveryGroundTruthScreenshotAndCanonicalSchema() async throws {
        let fixtures = photosFixtureDirectory()
        try await withTemporaryDirectory { directory in
            let output = directory.appendingPathComponent("photos")
            let pipeline = try result(try await HarnessDispatcher().run([
                "pipeline", "photos", fixtures.path, "--out", output.path,
            ]))

            #expect(Set(pipeline.keys) == ["source", "stages"])
            #expect(pipeline["source"] as? String == "photos")
            let stages = try #require(pipeline["stages"] as? [String: Any])
            #expect(Set(stages.keys) == ["ingestion", "plan", "session", "composition"])
            let ingestion = try #require(stages["ingestion"] as? [String: Any])
            #expect(Set(ingestion.keys) == [
                "input", "processedFrameCount", "keyframeCount", "keyframes", "files",
            ])
            #expect(ingestion["source"] == nil)
            #expect(ingestion["processedFrameCount"] as? Int == 6)
            #expect(ingestion["keyframeCount"] as? Int == 6)

            let plan = try #require(stages["plan"] as? [String: Any])
            #expect(plan["orderMode"] as? String == "recover-or-input")
            #expect(plan["orderAssumed"] as? Bool == false)
            #expect(plan["order"] as? [Int] == Array(0..<6))
            #expect(plan["seamCount"] as? Int == 5)
            #expect(plan["segmentBreakCount"] as? Int == 0)

            let session = try #require(stages["session"] as? [String: Any])
            #expect(session["keyframeCount"] as? Int == 6)
            let composition = try #require(stages["composition"] as? [String: Any])
            #expect(composition["width"] as? Int == 1320)
            #expect(composition["height"] as? Int == 10316)
        }
    }

    @Test func recoverOrInputOrderIsAcceptedAndBadgesDisconnectedFallback() async throws {
        try await withTemporaryDirectory { directory in
            let input = directory.appendingPathComponent("input")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let source = makeScrollSource(width: 120, height: 900)
            try writePNG(
                try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 300))),
                to: input.appendingPathComponent("01-top.png")
            )
            try writePNG(
                try #require(source.cropping(to: CGRect(x: 0, y: 600, width: 120, height: 300))),
                to: input.appendingPathComponent("02-bottom.png")
            )

            let planned = try result(try await HarnessDispatcher().run([
                "plan", input.path, "--out", directory.appendingPathComponent("plan").path,
                "--order", "recover-or-input",
            ]))
            #expect(planned["orderMode"] as? String == "recover-or-input")
            #expect(planned["order"] as? [Int] == [0, 1])
            #expect(planned["orderAssumed"] as? Bool == true)

            let created = try result(try await HarnessDispatcher().run([
                "session", "create", input.path,
                "--out", directory.appendingPathComponent("session").path,
                "--order", "recover-or-input",
            ]))
            #expect(created["orderMode"] as? String == "recover-or-input")
            #expect(created["orderAssumed"] as? Bool == true)
            let folder = try #require(created["folder"] as? String)
            let inspected = try result(try await HarnessDispatcher().run(["session", "inspect", folder]))
            #expect(inspected["orderAssumed"] as? Bool == true)

            let pipeline = try result(try await HarnessDispatcher().run([
                "pipeline", "photos", input.path,
                "--out", directory.appendingPathComponent("pipeline").path,
                "--order", "recover-or-input",
            ]))
            let stages = try #require(pipeline["stages"] as? [String: Any])
            let plan = try #require(stages["plan"] as? [String: Any])
            #expect(plan["order"] as? [Int] == [0, 1])
            #expect(plan["orderAssumed"] as? Bool == true)
        }
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func result(_ data: Data) throws -> [String: Any] {
        try #require(try object(data)["result"] as? [String: Any])
    }

    private func makeSession(in directory: URL, imageCount: Int) async throws -> URL {
        let input = directory.appendingPathComponent("input")
        let container = directory.appendingPathComponent("container")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        for index in 0..<imageCount {
            try writePNG(
                makeImage(width: 24, height: 48),
                to: input.appendingPathComponent(String(format: "%02d.png", index))
            )
        }
        let created = try result(try await HarnessDispatcher().run([
            "session", "create", input.path, "--out", container.path, "--order", "input",
        ]))
        return URL(fileURLWithPath: try #require(created["folder"] as? String), isDirectory: true)
    }

    private func mutateManifest(
        at url: URL,
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws {
        var manifest = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        try mutation(&manifest)
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func replaceRawKeyframesWithPNGs(in folder: URL, count: Int) throws {
        for index in 0..<count {
            let raw = folder.appendingPathComponent(String(format: "kf-%04d.bgra", index))
            let png = folder.appendingPathComponent(String(format: "kf-%04d.png", index))
            try writePNG(makeImage(width: 24, height: 48), to: png)
            try FileManager.default.removeItem(at: raw)
        }
        try mutateManifest(at: folder.appendingPathComponent("manifest.json")) { manifest in
            var keyframes = try #require(manifest["keyframes"] as? [[String: Any]])
            for index in keyframes.indices {
                keyframes[index]["filename"] = String(format: "kf-%04d.png", index)
            }
            manifest["keyframes"] = keyframes
        }
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        for y in 0..<height {
            let red = CGFloat((y * 37) % 255) / 255
            let green = CGFloat((y * 17 + 31) % 255) / 255
            context.setFillColor(red: red, green: green, blue: 1 - red, alpha: 1)
            context.fill(CGRect(x: 0, y: y, width: width / 2, height: 1))
            context.setFillColor(red: green, green: 1 - green, blue: red, alpha: 1)
            context.fill(CGRect(x: width / 2, y: y, width: width - width / 2, height: 1))
        }
        return context.makeImage()!
    }

    private func makeScrollSource(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<width {
                let value = 60.0 + Double(y) * (120.0 / Double(height))
                    + 50 * sin(Double(x) * 0.35)
                    + 25 * sin(Double(y) * 0.2 + Double(x) * 0.15)
                let byte = UInt8(max(0, min(255, value)))
                let offset = y * bytesPerRow + x * 4
                pixels[offset] = byte
                pixels[offset + 1] = byte
                pixels[offset + 2] = byte
                pixels[offset + 3] = 255
            }
        }
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func photosFixtureDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("StitchKitTests/Fixtures/Screenshots", isDirectory: true)
    }

    private func scrollingFrames() throws -> [CGImage] {
        let source = makeImage(width: 64, height: 240)
        return try stride(from: 0, through: 96, by: 12).map { y in
            try #require(source.cropping(to: CGRect(x: 0, y: y, width: 64, height: 96)))
        }
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let type = url.pathExtension.lowercased() == "jpg" ? UTType.jpeg : UTType.png
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    private func writeMP4(frames: [CGImage], to url: URL, fps: Int = 10) async throws {
        guard let first = frames.first else { throw VideoFixtureError.emptyFrames }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: first.width,
            AVVideoHeightKey: first.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: 1,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw VideoFixtureError.writerRejectedInput }
        writer.add(input)
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: first.width,
            kCVPixelBufferHeightKey as String: first.height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.startWriting() else { throw VideoFixtureError.writeFailed(writer.error) }
        writer.startSession(atSourceTime: .zero)
        for (index, frame) in frames.enumerated() {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            let buffer = try pixelBuffer(for: frame, using: adaptor)
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))) else {
                throw VideoFixtureError.writeFailed(writer.error)
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw VideoFixtureError.writeFailed(writer.error) }
    }

    private func pixelBuffer(
        for image: CGImage,
        using adaptor: AVAssetWriterInputPixelBufferAdaptor
    ) throws -> CVPixelBuffer {
        let pool = try #require(adaptor.pixelBufferPool)
        var rawBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &rawBuffer)
        guard status == kCVReturnSuccess, let buffer = rawBuffer else {
            throw VideoFixtureError.pixelBufferCreationFailed(status)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw VideoFixtureError.contextCreationFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    private enum VideoFixtureError: Error {
        case emptyFrames
        case writerRejectedInput
        case pixelBufferCreationFailed(CVReturn)
        case contextCreationFailed
        case writeFailed(Error?)
    }

    private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StitchHarnessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { /* Test cleanup is best-effort; assertions already completed. */ }
        }
        try await body(directory)
    }
}
