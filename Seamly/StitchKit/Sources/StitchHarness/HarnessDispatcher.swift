import CoreGraphics
import Foundation
import ImageIO
import StitchKit
import UniformTypeIdentifiers

/// In-process command dispatcher for component diagnostics. It never prints or exits.
public struct HarnessDispatcher: Sendable {
    public static let schemaVersion = "stitch-harness.v1"

    public init() {}

    /// Runs one command and returns its single pretty-printed, sorted JSON success envelope.
    public func run(_ arguments: [String]) async throws -> Data {
        guard let command = arguments.first else { throw HarnessError.missingCommand }

        let result: [String: Any]
        switch command {
        case "profile":
            result = try profile(Array(arguments.dropFirst()))
        case "match":
            result = try match(Array(arguments.dropFirst()))
        case "capture":
            result = try await capture(Array(arguments.dropFirst()))
        case "pipeline":
            result = try await pipeline(Array(arguments.dropFirst()))
        case "plan":
            result = try plan(Array(arguments.dropFirst()))
        case "session":
            result = try session(Array(arguments.dropFirst()))
        case "compose":
            result = try compose(Array(arguments.dropFirst()))
        default:
            throw HarnessError.unknownCommand(command)
        }
        return try Self.jsonData([
            "schemaVersion": Self.schemaVersion,
            "command": command,
            "ok": true,
            "result": result,
        ])
    }

    /// Builds the one JSON error object emitted by the executable boundary.
    public static func errorData(for error: any Error, arguments: [String]) -> Data {
        let command = arguments.first ?? ""
        let object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "command": command,
            "ok": false,
            "error": [
                "code": (error as? HarnessError)?.code ?? "internal_error",
                "message": error.localizedDescription,
            ],
        ]
        // This object contains JSON primitives only; failure would indicate a programmer error.
        return (try? jsonData(object)) ?? Data("{\"ok\":false}\n".utf8)
    }

    private func profile(_ arguments: [String]) throws -> [String: Any] {
        guard arguments.count == 1 else {
            throw HarnessError.usage("profile <image>")
        }
        let image = try loadImage(arguments[0])
        let profile = VerticalProfile().profile(image)
        return [
            "image": arguments[0],
            "sourceWidth": profile.sourceWidth,
            "sourceHeight": profile.sourceHeight,
            "rowCount": profile.rowCount,
            "rowScale": profile.rowScale,
            "signatureWidth": profile.rows.first?.count ?? 0,
            "means": summary(profile.means),
            "variances": summary(profile.variances),
        ]
    }

    private func match(_ arguments: [String]) throws -> [String: Any] {
        guard arguments.count == 2 || (arguments.count == 3 && arguments[2] == "--mask-chrome") else {
            throw HarnessError.usage("match <a> <b> [--mask-chrome]")
        }
        let imageA = try loadImage(arguments[0])
        let imageB = try loadImage(arguments[1])
        let profiler = VerticalProfile()
        let a = profiler.profile(imageA)
        let b = profiler.profile(imageB)
        let matcher = OffsetMatcher()
        let bound = max(0, min(a.rowCount, b.rowCount) - matcher.minimumOverlap)
        let maskChrome = arguments.count == 3
        let mask = maskChrome ? ContentBandDetector().staticMask(a, b) : nil
        let matched = matcher.match(a, b, searchRange: (-bound)...bound, rowMask: mask)
        let sourceDy = Int((Double(matched.dy) * a.rowScale).rounded())
        let commonRows = min(a.rowCount, b.rowCount)
        let overlapFraction = commonRows == 0
            ? 0
            : min(1, max(0, Double(commonRows - abs(matched.dy)) / Double(commonRows)))
        return [
            "a": arguments[0],
            "b": arguments[1],
            "dy": matched.dy,
            "sourceDy": sourceDy,
            "confidence": matched.confidence,
            "cost": matched.cost.isFinite ? Double(matched.cost) : NSNull(),
            "maskChrome": maskChrome,
            "maskedRows": mask?.filter { !$0 }.count ?? 0,
            "overlapFraction": overlapFraction,
        ]
    }

    private func summary(_ values: [Float]) -> [String: Double] {
        guard let minimum = values.min(), let maximum = values.max(), !values.isEmpty else {
            return ["min": 0, "max": 0, "average": 0]
        }
        return [
            "min": Double(minimum),
            "max": Double(maximum),
            "average": values.reduce(0.0) { $0 + Double($1) } / Double(values.count),
        ]
    }

    private struct CaptureResult {
        let keyframes: [ScrollCaptureDriver.CapturedKeyframe]
        let processedFrameCount: Int
        let decodeFailureCount: Int
        let safetyCueCount: Int?
    }

    private func capture(_ arguments: [String]) async throws -> [String: Any] {
        guard let source = arguments.first else {
            throw HarnessError.usage("capture images <dir> [--prefix P] [--out DIR] | capture video <file> [--fps N] [--out DIR]")
        }
        guard arguments.count >= 2 else {
            throw HarnessError.usage("capture \(source) <source> [options]")
        }
        switch source {
        case "images":
            let options = try parseOptions(Array(arguments.dropFirst(2)), allowed: ["--prefix", "--out"])
            let discovered = try discoverImages(in: arguments[1], prefix: options["--prefix"])
            let captured = try captureImages(discovered.urls)
            try dumpKeyframes(captured.keyframes, to: options["--out"])
            return captureReport(
                captured,
                source: "images",
                input: arguments[1],
                files: discovered.names,
                outDirectory: options["--out"]
            )
        case "video":
            let options = try parseOptions(Array(arguments.dropFirst(2)), allowed: ["--fps", "--out"])
            let fps = try parseFPS(options["--fps"])
            let captured = try await captureVideo(path: arguments[1], fps: fps)
            try dumpKeyframes(captured.keyframes, to: options["--out"])
            var report = captureReport(
                captured,
                source: "video",
                input: arguments[1],
                files: nil,
                outDirectory: options["--out"]
            )
            report["fps"] = fps
            return report
        default:
            throw HarnessError.unsupportedCaptureSource(source)
        }
    }

    private func captureImages(_ imageURLs: [URL]) throws -> CaptureResult {
        var driver = ScrollCaptureDriver()
        var keyframes: [ScrollCaptureDriver.CapturedKeyframe] = []
        var safetyCueCount = 0
        for url in imageURLs {
            let step = try autoreleasepool {
                let image = try loadImage(url.path)
                return driver.ingest(image)
            }
            if step.fireSafetyCue { safetyCueCount += 1 }
            if let keyframe = step.keyframe { keyframes.append(keyframe) }
        }
        if let trailing = driver.finish() { keyframes.append(trailing) }
        return CaptureResult(
            keyframes: keyframes,
            processedFrameCount: imageURLs.count,
            decodeFailureCount: 0,
            safetyCueCount: safetyCueCount
        )
    }

    private func captureVideo(path: String, fps: Double) async throws -> CaptureResult {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HarnessError.videoReadFailed(path)
        }
        var driver = ScrollCaptureDriver()
        do {
            let decoded = try await VideoKeyframeSource.decodeCommittedKeyframes(
                url: URL(fileURLWithPath: path), driver: &driver, targetFPS: fps
            )
            return CaptureResult(
                keyframes: decoded.keyframes,
                processedFrameCount: decoded.frames,
                decodeFailureCount: decoded.decodeFailures,
                safetyCueCount: nil
            )
        } catch {
            throw HarnessError.videoReadFailed(path)
        }
    }

    private func dumpKeyframes(_ keyframes: [ScrollCaptureDriver.CapturedKeyframe], to path: String?) throws {
        if let path {
            let out = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            for (index, keyframe) in keyframes.enumerated() {
                let name = String(format: "kf-%04d.png", index)
                try autoreleasepool {
                    try writePNG(keyframe.image, to: out.appendingPathComponent(name))
                }
            }
        }
    }

    private func captureReport(
        _ capture: CaptureResult,
        source: String,
        input: String,
        files: [String]?,
        outDirectory: String?
    ) -> [String: Any] {
        var report: [String: Any] = [
            "source": source,
            "input": input,
            "processedFrameCount": capture.processedFrameCount,
            "decodeFailureCount": capture.decodeFailureCount,
            "inputCount": capture.processedFrameCount,
            "keyframeCount": capture.keyframes.count,
            "safetyCueCount": capture.safetyCueCount.map { $0 as Any } ?? NSNull(),
            "keyframes": capture.keyframes.map { keyframe in
                [
                    "index": keyframe.metadata.index,
                    "pixelWidth": keyframe.metadata.pixelWidth,
                    "pixelHeight": keyframe.metadata.pixelHeight,
                ]
            },
            "outDirectory": outDirectory ?? NSNull(),
        ]
        if source == "images" { report["directory"] = input }
        if let files { report["files"] = files }
        return report
    }

    private func pipeline(_ arguments: [String]) async throws -> [String: Any] {
        guard let source = arguments.first else {
            throw HarnessError.usage("pipeline images <dir> --out <dir> [--prefix P] [--order recover|input] | pipeline video <file> --out <dir> [--fps N] [--order recover|input]")
        }
        guard arguments.count >= 2 else {
            throw HarnessError.usage("pipeline \(source) <source> --out <dir> [options]")
        }

        let allowed: Set<String>
        switch source {
        case "images": allowed = ["--out", "--prefix", "--order"]
        case "video": allowed = ["--out", "--fps", "--order"]
        default: throw HarnessError.unsupportedCaptureSource(source)
        }
        let options = try parseOptions(Array(arguments.dropFirst(2)), allowed: allowed)
        guard let outputPath = options["--out"] else { throw HarnessError.missingValue("--out") }
        let defaultOrder = source == "video" ? "input" : "recover"
        let orderMode = options["--order"] ?? defaultOrder
        guard orderMode == "recover" || orderMode == "input" else {
            throw HarnessError.invalidValue(option: "--order", value: orderMode)
        }

        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let prepared = try await preparePipeline(
            source: source,
            input: arguments[1],
            options: options,
            orderMode: orderMode,
            output: output
        )
        // Preparation owns the captured images. At this point they are out of scope: final
        // composition deliberately exercises the persisted manifest and keyframe files.
        let composed = try compositePersistedSession(folder: prepared.folder)
        let stitchedURL = output.appendingPathComponent("stitched.png")
        try autoreleasepool { try writePNG(composed.image, to: stitchedURL) }

        let sessionStage: [String: Any] = [
            "sessionID": prepared.session.id.uuidString,
            "folder": prepared.folder.path,
            "manifest": prepared.folder.appendingPathComponent("manifest.json").path,
            "keyframeCount": prepared.session.keyframes.count,
        ]
        let compositionStage: [String: Any] = [
            "width": composed.image.width,
            "height": composed.image.height,
            "path": stitchedURL.path,
        ]
        return [
            "source": source,
            "orderMode": orderMode,
            "sessionID": prepared.session.id.uuidString,
            "folder": prepared.folder.path,
            "plan": prepared.planStage,
            "composition": compositionStage,
            "stages": [
                "capture": prepared.captureStage,
                "plan": prepared.planStage,
                "session": sessionStage,
                "composition": compositionStage,
            ],
        ]
    }

    private struct PipelinePreparation {
        let captureStage: [String: Any]
        let planStage: [String: Any]
        let session: StitchSession
        let folder: URL
    }

    private func preparePipeline(
        source: String,
        input: String,
        options: [String: String],
        orderMode: String,
        output: URL
    ) async throws -> PipelinePreparation {
        let captured: CaptureResult
        var files: [String]?
        var fps: Double?
        if source == "images" {
            let discovered = try discoverImages(in: input, prefix: options["--prefix"])
            files = discovered.names
            captured = try captureImages(discovered.urls)
        } else {
            let parsedFPS = try parseFPS(options["--fps"])
            fps = parsedFPS
            captured = try await captureVideo(path: input, fps: parsedFPS)
        }
        guard captured.keyframes.count >= 2 else {
            throw HarnessError.underCapturedPipeline(captured.keyframes.count)
        }

        let images = captured.keyframes.map(\.image)
        let stitcher = BatchStitcher()
        let plan = try orderMode == "input"
            ? stitcher.plan(images, assumingOrder: Array(images.indices))
            : stitcher.plan(images)
        let stored = try persist(
            plan: plan,
            images: images,
            container: output.appendingPathComponent("store")
        )
        var captureStage = captureReport(
            captured,
            source: source,
            input: input,
            files: files,
            outDirectory: nil
        )
        if let fps { captureStage["fps"] = fps }
        let planStage: [String: Any] = [
            "orderMode": orderMode,
            "order": plan.order,
            "seamCount": plan.session.seams.count,
            "segmentBreakCount": plan.session.segmentBreaks.count,
            "contentBandCount": plan.session.contentBands.count,
        ]
        return PipelinePreparation(
            captureStage: captureStage,
            planStage: planStage,
            session: stored.session,
            folder: stored.folder
        )
    }

    private func parseFPS(_ value: String?) throws -> Double {
        let raw = value ?? "30"
        guard let fps = Double(raw), fps.isFinite, fps > 0 else {
            throw HarnessError.invalidFPS(raw)
        }
        return fps
    }

    private func persist(
        plan: BatchStitcher.Plan,
        images: [CGImage],
        container: URL
    ) throws -> (session: StitchSession, folder: URL) {
        var session = plan.session
        if let firstSource = plan.order.first {
            let first = images[firstSource]
            session.orientation = first.width > first.height ? .landscape : .portrait
            session.colorSpaceName = first.colorSpace?.name as String?
        }
        for slot in session.keyframes.indices {
            let image = images[plan.order[slot]]
            session.keyframes[slot].filename = String(format: "kf-%04d.bgra", slot)
            session.keyframes[slot].pixelWidth = image.width
            session.keyframes[slot].pixelHeight = image.height
            session.keyframes[slot].index = slot
        }
        let store = SessionStore(containerURL: container)
        let folder = try store.createFolder(for: session.id)
        for (slot, keyframe) in session.keyframes.enumerated() {
            let url = store.keyframeURL(keyframe, in: folder)
            do {
                try autoreleasepool {
                    try KeyframeIO.writeRaw(images[plan.order[slot]], to: url)
                }
            }
            catch { throw HarnessError.keyframeWriteFailed(url.path) }
        }
        do { try store.writeManifest(session) }
        catch { throw HarnessError.manifestWriteFailed(store.manifestURL(in: folder).path) }
        return (session, folder)
    }

    private func plan(_ arguments: [String]) throws -> [String: Any] {
        guard let directory = arguments.first else {
            throw HarnessError.usage("plan <dir> [--prefix P] [--order recover|input] [--out DIR]")
        }
        let options = try parseOptions(
            Array(arguments.dropFirst()),
            allowed: ["--prefix", "--order", "--out"]
        )
        let orderMode = options["--order"] ?? "recover"
        guard orderMode == "recover" || orderMode == "input" else {
            throw HarnessError.invalidValue(option: "--order", value: orderMode)
        }
        let loaded = try loadImages(in: directory, prefix: options["--prefix"])
        let stitcher = BatchStitcher()
        let plan = try orderMode == "input"
            ? stitcher.plan(loaded.images, assumingOrder: Array(loaded.images.indices))
            : stitcher.plan(loaded.images)
        let manifest = try Self.jsonObject(for: plan.session)

        if let path = options["--out"] {
            let out = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let data = try Self.encoded(plan.session)
            try data.write(to: out.appendingPathComponent("manifest.json"), options: .atomic)
        }

        return [
            "directory": directory,
            "files": loaded.names,
            "orderMode": orderMode,
            "order": plan.order,
            "manifest": manifest,
            "outDirectory": options["--out"] ?? NSNull(),
        ]
    }

    private func session(_ arguments: [String]) throws -> [String: Any] {
        guard let subcommand = arguments.first else {
            throw HarnessError.usage("session create <images-dir> --out <container> [--prefix P] [--order recover|input] | session inspect <session-folder>")
        }
        switch subcommand {
        case "create": return try createSession(Array(arguments.dropFirst()))
        case "inspect": return try inspectSession(Array(arguments.dropFirst()))
        default: throw HarnessError.unknownSessionCommand(subcommand)
        }
    }

    private func createSession(_ arguments: [String]) throws -> [String: Any] {
        guard let directory = arguments.first else {
            throw HarnessError.usage("session create <images-dir> --out <container> [--prefix P] [--order recover|input]")
        }
        let options = try parseOptions(Array(arguments.dropFirst()), allowed: ["--out", "--prefix", "--order"])
        guard let containerPath = options["--out"] else { throw HarnessError.missingValue("--out") }
        let orderMode = options["--order"] ?? "recover"
        guard orderMode == "recover" || orderMode == "input" else {
            throw HarnessError.invalidValue(option: "--order", value: orderMode)
        }

        let loaded = try loadImages(in: directory, prefix: options["--prefix"])
        let stitcher = BatchStitcher()
        let plan = try orderMode == "input"
            ? stitcher.plan(loaded.images, assumingOrder: Array(loaded.images.indices))
            : stitcher.plan(loaded.images)
        let container = URL(fileURLWithPath: containerPath, isDirectory: true)
        let stored = try persist(plan: plan, images: loaded.images, container: container)
        let store = SessionStore(containerURL: container)
        let folder = stored.folder
        let readBack = try readAndValidateManifest(folder: folder)
        try validateKeyframeFiles(readBack, folder: folder)
        return [
            "sessionID": readBack.id.uuidString,
            "folder": folder.path,
            "manifest": store.manifestURL(in: folder).path,
            "keyframeCount": readBack.keyframes.count,
            "orderMode": orderMode,
        ]
    }

    private func inspectSession(_ arguments: [String]) throws -> [String: Any] {
        guard arguments.count == 1 else {
            throw HarnessError.usage("session inspect <session-folder>")
        }
        let folder = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let session = try readAndValidateManifest(folder: folder)
        try validateKeyframeFiles(session, folder: folder)
        return inspectionResult(session, folder: folder)
    }

    private func compose(_ arguments: [String]) throws -> [String: Any] {
        guard let folderPath = arguments.first else {
            throw HarnessError.usage("compose <session-folder> --out <image.png>")
        }
        let options = try parseOptions(Array(arguments.dropFirst()), allowed: ["--out"])
        guard let outputPath = options["--out"] else { throw HarnessError.missingValue("--out") }
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        let composed = try compositePersistedSession(folder: folder)
        let output = URL(fileURLWithPath: outputPath)
        try autoreleasepool { try writePNG(composed.image, to: output) }
        return [
            "width": composed.image.width,
            "height": composed.image.height,
            "path": output.path,
            "frameCount": composed.session.keyframes.count,
        ]
    }

    private func readAndValidateManifest(folder: URL) throws -> StitchSession {
        let manifestURL = folder.appendingPathComponent("manifest.json")
        let session: StitchSession
        do {
            session = try SessionStore(containerURL: folder).readManifest(at: manifestURL)
        } catch {
            throw HarnessError.manifestReadFailed(manifestURL.path)
        }
        try validateManifest(session)
        return session
    }

    private func validateManifest(_ session: StitchSession) throws {
        let keyframeCount = session.keyframes.count
        guard session.keyframes.allSatisfy({ $0.pixelWidth > 0 && $0.pixelHeight > 0 }) else {
            throw HarnessError.invalidSession("keyframe dimensions must be positive")
        }
        guard Set(session.keyframes.map(\.id)).count == keyframeCount else {
            throw HarnessError.invalidSession("keyframe IDs must be unique")
        }
        guard session.keyframes.map(\.index).sorted() == Array(0..<keyframeCount) else {
            throw HarnessError.invalidSession(
                "keyframe indices must be unique and exactly 0..<\(keyframeCount)"
            )
        }

        var filenames: Set<String> = []
        for keyframe in session.keyframes {
            let filename = keyframe.filename
            guard !filename.isEmpty,
                  filename != ".",
                  filename != "..",
                  !(filename as NSString).isAbsolutePath,
                  !filename.contains("/"),
                  !filename.contains("\\") else {
                throw HarnessError.invalidSession("unsafe keyframe filename: \(filename)")
            }
            guard filenames.insert(filename).inserted else {
                throw HarnessError.invalidSession("keyframe filenames must be unique")
            }
        }

        let boundaryCount = max(0, keyframeCount - 1)
        let seamIndices = session.seams.map(\.fromIndex)
        guard seamIndices.allSatisfy({ $0 >= 0 && $0 < boundaryCount }),
              Set(seamIndices).count == seamIndices.count else {
            throw HarnessError.invalidSession(
                "seam fromIndex must be in 0..<\(boundaryCount) and unique"
            )
        }
        let breakIndices = session.segmentBreaks.map(\.afterKeyframeIndex)
        guard breakIndices.allSatisfy({ $0 >= 0 && $0 < boundaryCount }),
              Set(breakIndices).count == breakIndices.count else {
            throw HarnessError.invalidSession(
                "segment break index must be in 0..<\(boundaryCount) and unique"
            )
        }
        if let shared = Set(seamIndices).intersection(breakIndices).sorted().first {
            throw HarnessError.invalidSession("seam and segment break cannot share index \(shared)")
        }
    }

    private func validateKeyframeFiles(_ session: StitchSession, folder: URL) throws {
        let resolvedFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        for keyframe in session.keyframes {
            let url = folder.appendingPathComponent(keyframe.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw HarnessError.keyframeMissing(url.path)
            }
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.deletingLastPathComponent() == resolvedFolder else {
                throw HarnessError.invalidSession(
                    "keyframe must resolve directly inside session folder: \(keyframe.filename)"
                )
            }
            do {
                if url.pathExtension.lowercased() == "bgra" {
                    try validateRawKeyframe(url, width: keyframe.pixelWidth, height: keyframe.pixelHeight)
                } else {
                    try autoreleasepool { _ = try KeyframeIO.read(from: url) }
                }
            } catch let error as HarnessError {
                throw error
            } catch {
                throw HarnessError.keyframeDecodeFailed(url.path)
            }
        }
    }

    private func validateRawKeyframe(_ url: URL, width: Int, height: Int) throws {
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (expectedSize, sizeOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !sizeOverflow,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              fileSize.uint64Value == UInt64(expectedSize) else {
            throw HarnessError.keyframeDecodeFailed(url.path)
        }
    }

    private func loadPersistedImage(
        _ keyframe: Keyframe,
        session: StitchSession,
        folder: URL
    ) throws -> CGImage {
        let url = folder.appendingPathComponent(keyframe.filename)
        do {
            return try autoreleasepool {
                if url.pathExtension.lowercased() == "bgra" {
                    let colorSpace = session.colorSpaceName.flatMap {
                        CGColorSpace(name: $0 as CFString)
                    }
                    return try KeyframeIO.readRaw(
                        from: url,
                        width: keyframe.pixelWidth,
                        height: keyframe.pixelHeight,
                        colorSpace: colorSpace
                    )
                }
                return try KeyframeIO.read(from: url)
            }
        } catch {
            throw HarnessError.keyframeDecodeFailed(url.path)
        }
    }

    private func compositePersistedSession(
        folder: URL
    ) throws -> (session: StitchSession, image: CGImage) {
        let session = try readAndValidateManifest(folder: folder)
        guard session.hasStitchableContent else {
            throw HarnessError.insufficientKeyframes(session.keyframes.count)
        }
        try validateKeyframeFiles(session, folder: folder)
        let image = try Compositor(refinementDelta: 16).composite(session) { keyframe in
            try loadPersistedImage(keyframe, session: session, folder: folder)
        }
        return (session, image)
    }

    private func inspectionResult(_ session: StitchSession, folder: URL) -> [String: Any] {
        [
            "sessionID": session.id.uuidString,
            "folder": folder.path,
            "status": session.status.rawValue,
            "orientation": session.orientation.rawValue,
            "keyframeCount": session.keyframes.count,
            "seamCount": session.seams.count,
            "segmentBreakCount": session.segmentBreaks.count,
            "stitchable": session.hasStitchableContent,
            "counts": [
                "keyframes": session.keyframes.count,
                "seams": session.seams.count,
                "segmentBreaks": session.segmentBreaks.count,
            ],
            "topology": [
                "segmentCount": session.segmentBreaks.count + 1,
                "seamFromIndices": session.seams.map(\.fromIndex),
                "breakAfterIndices": session.segmentBreaks.map(\.afterKeyframeIndex),
            ],
            "valid": true,
        ]
    }

    private func parseOptions(_ arguments: [String], allowed: Set<String>) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard allowed.contains(option) else { throw HarnessError.unknownOption(option) }
            guard result[option] == nil else { throw HarnessError.duplicateOption(option) }
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw HarnessError.missingValue(option)
            }
            result[option] = arguments[index + 1]
            index += 2
        }
        return result
    }

    private func loadImage(_ path: String) throws -> CGImage {
        do {
            return try KeyframeIO.read(from: URL(fileURLWithPath: path))
        } catch {
            throw HarnessError.imageReadFailed(path)
        }
    }

    private func discoverImages(in path: String, prefix: String?) throws -> (names: [String], urls: [URL]) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let supported = Set(["png", "jpg", "jpeg", "heic", "heif"])
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: url.path)
                .filter { supported.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
                .filter { prefix.map($0.hasPrefix) ?? true }
                .sorted()
        } catch {
            throw HarnessError.directoryReadFailed(path)
        }
        guard !names.isEmpty else { throw HarnessError.noImages(path, prefix) }
        return (names, names.map { url.appendingPathComponent($0) })
    }

    private func loadImages(in path: String, prefix: String?) throws -> (names: [String], images: [CGImage]) {
        let discovered = try discoverImages(in: path, prefix: prefix)
        // Planning and explicit session creation intentionally retain the complete frame set.
        let images = try discovered.urls.map { url in
            try autoreleasepool { try loadImage(url.path) }
        }
        return (discovered.names, images)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw HarnessError.imageWriteFailed(url.path) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.imageWriteFailed(url.path)
        }
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func jsonObject<T: Encodable>(for value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: encoded(value))
    }

    private static func jsonData(_ object: Any) throws -> Data {
        var data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        data.append(0x0A)
        return data
    }
}

public enum HarnessError: LocalizedError, Equatable {
    case missingCommand
    case unknownCommand(String)
    case usage(String)
    case unknownOption(String)
    case duplicateOption(String)
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case invalidFPS(String)
    case unsupportedCaptureSource(String)
    case underCapturedPipeline(Int)
    case videoReadFailed(String)
    case directoryReadFailed(String)
    case noImages(String, String?)
    case imageReadFailed(String)
    case imageWriteFailed(String)
    case unknownSessionCommand(String)
    case manifestReadFailed(String)
    case manifestWriteFailed(String)
    case invalidSession(String)
    case insufficientKeyframes(Int)
    case keyframeMissing(String)
    case keyframeDecodeFailed(String)
    case keyframeWriteFailed(String)

    public var code: String {
        switch self {
        case .missingCommand: "missing_command"
        case .unknownCommand: "unknown_command"
        case .usage: "usage"
        case .unknownOption: "unknown_option"
        case .duplicateOption: "duplicate_option"
        case .missingValue: "missing_value"
        case .invalidValue: "invalid_value"
        case .invalidFPS: "invalid_fps"
        case .unsupportedCaptureSource: "unsupported_capture_source"
        case .underCapturedPipeline: "under_captured_pipeline"
        case .videoReadFailed: "video_read_failed"
        case .directoryReadFailed: "directory_read_failed"
        case .noImages: "no_images"
        case .imageReadFailed: "image_read_failed"
        case .imageWriteFailed: "image_write_failed"
        case .unknownSessionCommand: "unknown_session_command"
        case .manifestReadFailed: "manifest_read_failed"
        case .manifestWriteFailed: "manifest_write_failed"
        case .invalidSession: "invalid_session"
        case .insufficientKeyframes: "insufficient_keyframes"
        case .keyframeMissing: "keyframe_missing"
        case .keyframeDecodeFailed: "keyframe_decode_failed"
        case .keyframeWriteFailed: "keyframe_write_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .missingCommand: "missing command"
        case .unknownCommand(let command): "unknown command: \(command)"
        case .usage(let usage): "usage: stitch-harness \(usage)"
        case .unknownOption(let option): "unknown option: \(option)"
        case .duplicateOption(let option): "duplicate option: \(option)"
        case .missingValue(let option): "missing value for option: \(option)"
        case .invalidValue(let option, let value): "invalid value for \(option): \(value)"
        case .invalidFPS(let value): "fps must be a finite number greater than 0; got \(value)"
        case .unsupportedCaptureSource(let source): "unsupported capture source: \(source)"
        case .underCapturedPipeline(let count): "pipeline requires at least 2 committed keyframes; captured \(count)"
        case .videoReadFailed(let path): "could not read video: \(path)"
        case .directoryReadFailed(let path): "could not read directory: \(path)"
        case .noImages(let path, let prefix):
            "no supported images\(prefix.map { " starting with '\($0)'" } ?? "") in \(path)"
        case .imageReadFailed(let path): "could not read image: \(path)"
        case .imageWriteFailed(let path): "could not write PNG: \(path)"
        case .unknownSessionCommand(let command): "unknown session command: \(command)"
        case .manifestReadFailed(let path): "could not read session manifest: \(path)"
        case .manifestWriteFailed(let path): "could not write session manifest: \(path)"
        case .invalidSession(let message): "invalid session: \(message)"
        case .insufficientKeyframes(let count): "session requires at least 2 keyframes; found \(count)"
        case .keyframeMissing(let path): "keyframe file is missing: \(path)"
        case .keyframeDecodeFailed(let path): "could not decode keyframe: \(path)"
        case .keyframeWriteFailed(let path): "could not write keyframe: \(path)"
        }
    }
}
