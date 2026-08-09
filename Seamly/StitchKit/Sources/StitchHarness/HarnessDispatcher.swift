import CoreGraphics
import Foundation
import ImageIO
import StitchKit
import UniformTypeIdentifiers

/// In-process command dispatcher for component diagnostics. It never prints or exits.
package struct HarnessDispatcher: Sendable {
    package static let schemaVersion = "stitch-harness.v1"

    package init() {}

    /// Runs one command and returns its single pretty-printed, sorted JSON success envelope.
    /// The executable boundary must serialize every thrown error through `errorData`.
    package func run(_ arguments: [String]) async throws -> Data {
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
    package static func errorData(for error: any Error, arguments: [String]) -> Data {
        let command = arguments.first ?? ""
        let cause: String?
        if let wrapped = error as? HarnessFailure {
            cause = wrapped.cause
        } else if error is HarnessError {
            cause = nil
        } else {
            cause = Self.causeDescription(error)
        }
        var serializedError: [String: Any] = [
            "code": (error as? HarnessFailure)?.error.code
                ?? (error as? HarnessError)?.code
                ?? "internal_error",
            "message": error.localizedDescription,
        ]
        if let cause { serializedError["cause"] = cause }
        let object: [String: Any] = [
            "schemaVersion": schemaVersion,
            "command": command,
            "ok": false,
            "error": serializedError,
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
        let geometricOverlapFraction = commonRows == 0
            ? 0
            : min(1, max(0, Double(commonRows - abs(matched.dy)) / Double(commonRows)))
        let matcherOverlap: Any = matched.overlap.map { overlap in
            [
                "countedRows": overlap.countedRows,
                "countableRows": overlap.countableRows,
                "minimumRequiredRows": overlap.minimumRequiredRows,
                "fraction": overlap.fraction,
                "passesMinimum": overlap.passedMinimumOverlap,
            ] as [String: Any]
        } ?? NSNull()
        return [
            "a": arguments[0],
            "b": arguments[1],
            "dy": matched.dy,
            "sourceDy": sourceDy,
            "confidence": matched.confidence,
            "cost": matched.cost.isFinite ? Double(matched.cost) : NSNull(),
            "maskChrome": maskChrome,
            "maskedRows": mask?.filter { !$0 }.count ?? 0,
            // This is geometric row overlap, not the matcher's mask-aware overlap floor.
            "geometricOverlapFraction": geometricOverlapFraction,
            "matcherOverlap": matcherOverlap,
        ]
    }

    private func summary(_ values: [Float]) -> [String: Double] {
        guard let minimum = values.min(), let maximum = values.max() else {
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

    private struct KeyframeReport: Encodable {
        let index: Int
        let pixelWidth: Int
        let pixelHeight: Int
    }

    private struct IngestionReport: Encodable {
        let source: String?
        let input: String
        let processedFrameCount: Int
        let decodeFailureCount: Int?
        let keyframeCount: Int
        let safetyCueCount: Int?
        let keyframes: [KeyframeReport]
        let outDirectory: String?
        let files: [String]?
        let fps: Double?
    }

    private struct PlanStage: Encodable {
        let orderMode: String
        let orderAssumed: Bool
        let order: [Int]
        let seamCount: Int
        let segmentBreakCount: Int
        let contentBandCount: Int
    }

    private struct SessionStage: Encodable {
        let sessionID: String
        let folder: String
        let manifest: String
        let keyframeCount: Int
    }

    private struct CompositionStage: Encodable {
        let width: Int
        let height: Int
        let path: String
    }

    private struct PipelineStages: Encodable {
        let ingestion: IngestionReport
        let plan: PlanStage
        let session: SessionStage
        let composition: CompositionStage
    }

    private struct PipelineResult: Encodable {
        let source: String
        let stages: PipelineStages
    }

    private enum CaptureSource: Equatable {
        case frames
        case video

        init?(argument: String) {
            switch argument {
            case "frames": self = .frames
            case "video": self = .video
            default: return nil
            }
        }

        var name: String {
            switch self {
            case .frames: "frames"
            case .video: "video"
            }
        }
    }

    private func capture(_ arguments: [String]) async throws -> [String: Any] {
        guard let requestedSource = arguments.first else {
            throw HarnessError.usage("capture frames <dir> [--prefix P] [--out DIR] | capture video <file> [--fps N] [--out DIR]")
        }
        guard let source = CaptureSource(argument: requestedSource) else {
            throw HarnessError.unsupportedSource(requestedSource)
        }
        guard arguments.count >= 2 else {
            throw HarnessError.usage("capture \(source.name) <source> [options]")
        }
        switch source {
        case .frames:
            let options = try parseOptions(Array(arguments.dropFirst(2)), allowed: ["--prefix", "--out"])
            let discovered = try discoverImages(in: arguments[1], prefix: options["--prefix"])
            let captured = try selectKeyframes(fromRawFrames: discovered.urls)
            try dumpKeyframes(captured.keyframes, to: options["--out"])
            return try Self.dictionary(for: captureReport(
                captured,
                source: .frames,
                includeSource: true,
                input: arguments[1],
                files: discovered.names,
                outDirectory: options["--out"],
                fps: nil
            ))
        case .video:
            let options = try parseOptions(Array(arguments.dropFirst(2)), allowed: ["--fps", "--out"])
            let fps = try parseFPS(options["--fps"])
            let captured = try await captureVideo(path: arguments[1], fps: fps)
            try dumpKeyframes(captured.keyframes, to: options["--out"])
            let report = captureReport(
                captured,
                source: .video,
                includeSource: true,
                input: arguments[1],
                files: nil,
                outDirectory: options["--out"],
                fps: fps
            )
            return try Self.dictionary(for: report)
        }
    }

    private func selectKeyframes(fromRawFrames imageURLs: [URL]) throws -> CaptureResult {
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
            throw HarnessFailure(
                error: .videoReadFailed(path),
                cause: Self.causeDescription(error)
            )
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
        source: CaptureSource,
        includeSource: Bool,
        input: String,
        files: [String]?,
        outDirectory: String?,
        fps: Double?
    ) -> IngestionReport {
        IngestionReport(
            source: includeSource ? source.name : nil,
            input: input,
            processedFrameCount: capture.processedFrameCount,
            decodeFailureCount: source == .video ? capture.decodeFailureCount : nil,
            keyframeCount: capture.keyframes.count,
            safetyCueCount: source == .frames ? capture.safetyCueCount : nil,
            keyframes: capture.keyframes.map { keyframe in
                KeyframeReport(
                    index: keyframe.metadata.index,
                    pixelWidth: keyframe.metadata.pixelWidth,
                    pixelHeight: keyframe.metadata.pixelHeight
                )
            },
            outDirectory: outDirectory,
            files: files,
            fps: fps
        )
    }

    private enum PipelineSource {
        case photos
        case committed
        case frames
        case video

        init?(argument: String) {
            switch argument {
            case "photos": self = .photos
            case "committed": self = .committed
            case "frames": self = .frames
            case "video": self = .video
            default: return nil
            }
        }

        var name: String {
            switch self {
            case .photos: "photos"
            case .committed: "committed"
            case .frames: "frames"
            case .video: "video"
            }
        }

        var allowedOptions: Set<String> {
            switch self {
            case .photos, .committed, .frames: ["--out", "--prefix", "--order"]
            case .video: ["--out", "--fps", "--order"]
            }
        }

        var defaultOrderMode: String {
            switch self {
            case .photos, .committed: "recover-or-input"
            case .frames, .video: "input"
            }
        }
    }

    private func pipeline(_ arguments: [String]) async throws -> [String: Any] {
        guard let requestedSource = arguments.first else {
            throw HarnessError.usage("pipeline photos|committed|frames <dir> --out <dir> [--prefix P] [--order recover|recover-or-input|input] | pipeline video <file> --out <dir> [--fps N] [--order recover|recover-or-input|input]")
        }
        guard let source = PipelineSource(argument: requestedSource) else {
            throw HarnessError.unsupportedSource(requestedSource)
        }
        guard arguments.count >= 2 else {
            throw HarnessError.usage("pipeline \(source.name) <source> --out <dir> [options]")
        }

        let options = try parseOptions(Array(arguments.dropFirst(2)), allowed: source.allowedOptions)
        guard let outputPath = options["--out"] else { throw HarnessError.missingValue("--out") }
        let order = try parseOrder(options["--order"], defaultMode: source.defaultOrderMode)

        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let prepared = try await preparePipeline(
            source: source,
            input: arguments[1],
            options: options,
            order: order,
            output: output
        )
        // Preparation owns the captured images. At this point they are out of scope: final
        // composition deliberately exercises the persisted manifest and keyframe files.
        let composed = try compositePersistedSession(folder: prepared.folder)
        let stitchedURL = output.appendingPathComponent("stitched.png")
        try autoreleasepool { try writePNG(composed.image, to: stitchedURL) }

        let sessionStage = SessionStage(
            sessionID: prepared.session.id.uuidString,
            folder: prepared.folder.path,
            manifest: prepared.folder.appendingPathComponent("manifest.json").path,
            keyframeCount: prepared.session.keyframes.count
        )
        let compositionStage = CompositionStage(
            width: composed.image.width,
            height: composed.image.height,
            path: stitchedURL.path
        )
        return try Self.dictionary(for: PipelineResult(
            source: source.name,
            stages: PipelineStages(
                ingestion: prepared.ingestionStage,
                plan: prepared.planStage,
                session: sessionStage,
                composition: compositionStage
            )
        ))
    }

    private struct PipelinePreparation {
        let ingestionStage: IngestionReport
        let planStage: PlanStage
        let session: StitchSession
        let folder: URL
    }

    private func preparePipeline(
        source: PipelineSource,
        input: String,
        options: [String: String],
        order: ParsedOrder,
        output: URL
    ) async throws -> PipelinePreparation {
        let images: [CGImage]
        let ingestionStage: IngestionReport
        switch source {
        case .photos, .committed:
            let loaded = try loadImages(in: input, prefix: options["--prefix"])
            images = loaded.images
            ingestionStage = directInputReport(
                images: images,
                input: input,
                files: loaded.names
            )
        case .frames:
            let discovered = try discoverImages(in: input, prefix: options["--prefix"])
            let captured = try selectKeyframes(fromRawFrames: discovered.urls)
            images = captured.keyframes.map(\.image)
            ingestionStage = captureReport(
                captured,
                source: .frames,
                includeSource: false,
                input: input,
                files: discovered.names,
                outDirectory: nil,
                fps: nil
            )
        case .video:
            let parsedFPS = try parseFPS(options["--fps"])
            let captured = try await captureVideo(path: input, fps: parsedFPS)
            images = captured.keyframes.map(\.image)
            ingestionStage = captureReport(
                captured,
                source: .video,
                includeSource: false,
                input: input,
                files: nil,
                outDirectory: nil,
                fps: parsedFPS
            )
        }
        guard images.count >= 2 else {
            throw HarnessError.insufficientPipelineImages(images.count)
        }

        let plan = try BatchStitcher().plan(images, strategy: order.strategy)
        let stored = try persist(
            plan: plan,
            images: images,
            container: output.appendingPathComponent("store")
        )
        let planStage = PlanStage(
            orderMode: order.mode,
            orderAssumed: stored.session.orderAssumed,
            order: plan.order,
            seamCount: plan.session.seams.count,
            segmentBreakCount: plan.session.segmentBreaks.count,
            contentBandCount: plan.session.contentBands.count
        )
        return PipelinePreparation(
            ingestionStage: ingestionStage,
            planStage: planStage,
            session: stored.session,
            folder: stored.folder
        )
    }

    private func directInputReport(
        images: [CGImage],
        input: String,
        files: [String]
    ) -> IngestionReport {
        IngestionReport(
            source: nil,
            input: input,
            processedFrameCount: images.count,
            decodeFailureCount: nil,
            keyframeCount: images.count,
            safetyCueCount: nil,
            keyframes: images.enumerated().map { index, image in
                KeyframeReport(index: index, pixelWidth: image.width, pixelHeight: image.height)
            },
            outDirectory: nil,
            files: files,
            fps: nil
        )
    }

    private struct ParsedOrder {
        let mode: String
        let strategy: BatchStitcher.OrderStrategy
    }

    private func parseOrder(_ value: String?, defaultMode: String) throws -> ParsedOrder {
        let mode = value ?? defaultMode
        let strategy: BatchStitcher.OrderStrategy
        switch mode {
        case "recover": strategy = .recover
        case "recover-or-input": strategy = .recoverOrInputOrder
        case "input": strategy = .inputOrder
        default: throw HarnessError.invalidValue(option: "--order", value: mode)
        }
        return ParsedOrder(mode: mode, strategy: strategy)
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
            catch {
                throw HarnessFailure(
                    error: .keyframeWriteFailed(url.path),
                    cause: Self.causeDescription(error)
                )
            }
        }
        do { try store.writeManifest(session) }
        catch {
            throw HarnessFailure(
                error: .manifestWriteFailed(store.manifestURL(in: folder).path),
                cause: Self.causeDescription(error)
            )
        }
        return (session, folder)
    }

    private func plan(_ arguments: [String]) throws -> [String: Any] {
        guard let directory = arguments.first else {
            throw HarnessError.usage("plan <dir> [--prefix P] [--order recover|recover-or-input|input] [--out DIR]")
        }
        let options = try parseOptions(
            Array(arguments.dropFirst()),
            allowed: ["--prefix", "--order", "--out"]
        )
        let order = try parseOrder(options["--order"], defaultMode: "recover")
        let loaded = try loadImages(in: directory, prefix: options["--prefix"])
        let plan = try BatchStitcher().plan(loaded.images, strategy: order.strategy)
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
            "orderMode": order.mode,
            "orderAssumed": plan.session.orderAssumed,
            "order": plan.order,
            "manifest": manifest,
            "outDirectory": options["--out"] ?? NSNull(),
        ]
    }

    private func session(_ arguments: [String]) throws -> [String: Any] {
        guard let subcommand = arguments.first else {
            throw HarnessError.usage("session create <images-dir> --out <container> [--prefix P] [--order recover|recover-or-input|input] | session inspect <session-folder>")
        }
        switch subcommand {
        case "create": return try createSession(Array(arguments.dropFirst()))
        case "inspect": return try inspectSession(Array(arguments.dropFirst()))
        default: throw HarnessError.unknownSessionCommand(subcommand)
        }
    }

    private func createSession(_ arguments: [String]) throws -> [String: Any] {
        guard let directory = arguments.first else {
            throw HarnessError.usage("session create <images-dir> --out <container> [--prefix P] [--order recover|recover-or-input|input]")
        }
        let options = try parseOptions(Array(arguments.dropFirst()), allowed: ["--out", "--prefix", "--order"])
        guard let containerPath = options["--out"] else { throw HarnessError.missingValue("--out") }
        let order = try parseOrder(options["--order"], defaultMode: "recover")

        let loaded = try loadImages(in: directory, prefix: options["--prefix"])
        let plan = try BatchStitcher().plan(loaded.images, strategy: order.strategy)
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
            "orderMode": order.mode,
            "orderAssumed": readBack.orderAssumed,
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
            throw HarnessFailure(
                error: .manifestReadFailed(manifestURL.path),
                cause: Self.causeDescription(error)
            )
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

    private struct ValidatedKeyframeFile {
        let keyframe: Keyframe
        let url: URL
    }

    private func validateKeyframeFiles(
        _ session: StitchSession,
        folder: URL,
        decodeEncodedImages: Bool = true
    ) throws {
        let files = try resolvedKeyframeFiles(session, folder: folder)
        for file in files {
            do {
                if file.url.pathExtension.lowercased() == "bgra" {
                    try validateRawKeyframe(
                        file.url,
                        width: file.keyframe.pixelWidth,
                        height: file.keyframe.pixelHeight
                    )
                } else if decodeEncodedImages {
                    try autoreleasepool { _ = try KeyframeIO.read(from: file.url) }
                }
            } catch let failure as HarnessFailure {
                throw failure
            } catch let error as HarnessError {
                throw error
            } catch {
                throw HarnessFailure(
                    error: .keyframeDecodeFailed(file.url.path),
                    cause: Self.causeDescription(error)
                )
            }
        }
    }

    /// Resolves every path before any keyframe content is accessed.
    private func resolvedKeyframeFiles(
        _ session: StitchSession,
        folder: URL
    ) throws -> [ValidatedKeyframeFile] {
        let resolvedFolder = folder.resolvingSymlinksInPath().standardizedFileURL
        return try session.keyframes.map { keyframe in
            let url = folder.appendingPathComponent(keyframe.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw HarnessError.keyframeMissing(url.path)
            }
            let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolvedURL.deletingLastPathComponent().path == resolvedFolder.path else {
                throw HarnessError.invalidSession(
                    "keyframe must resolve directly inside session folder: \(keyframe.filename)"
                )
            }
            return ValidatedKeyframeFile(keyframe: keyframe, url: url)
        }
    }

    private func validateRawKeyframe(_ url: URL, width: Int, height: Int) throws {
        let (bytesPerRow, rowOverflow) = width.multipliedReportingOverflow(by: 4)
        let (expectedSize, sizeOverflow) = bytesPerRow.multipliedReportingOverflow(by: height)
        guard !rowOverflow, !sizeOverflow else {
            throw HarnessFailure(
                error: .keyframeDecodeFailed(url.path),
                cause: "raw keyframe expected byte count overflow for \(width)x\(height) pixels"
            )
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw HarnessFailure(
                error: .keyframeDecodeFailed(url.path),
                cause: Self.causeDescription(error)
            )
        }
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw HarnessFailure(
                error: .keyframeDecodeFailed(url.path),
                cause: "raw keyframe file size attribute is unavailable"
            )
        }
        let actualSize = fileSize.uint64Value
        guard actualSize == UInt64(expectedSize) else {
            throw HarnessFailure(
                error: .keyframeDecodeFailed(url.path),
                cause: "raw keyframe size mismatch: expected \(expectedSize) bytes, actual \(actualSize) bytes"
            )
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
            throw HarnessFailure(
                error: .keyframeDecodeFailed(url.path),
                cause: Self.causeDescription(error)
            )
        }
    }

    private func compositePersistedSession(
        folder: URL
    ) throws -> (session: StitchSession, image: CGImage) {
        let session = try readAndValidateManifest(folder: folder)
        try validateKeyframeFiles(session, folder: folder, decodeEncodedImages: false)
        guard session.hasStitchableContent else {
            throw HarnessError.insufficientKeyframes(session.keyframes.count)
        }
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
            "orderAssumed": session.orderAssumed,
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
            throw HarnessFailure(
                error: .imageReadFailed(path),
                cause: Self.causeDescription(error)
            )
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
            throw HarnessFailure(
                error: .directoryReadFailed(path),
                cause: Self.causeDescription(error)
            )
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

    private static func causeDescription(_ error: any Error) -> String {
        func path(_ codingPath: [any CodingKey]) -> String {
            let value = codingPath.map(\.stringValue).joined(separator: ".")
            return value.isEmpty ? "<root>" : value
        }

        switch error {
        case DecodingError.dataCorrupted(let context):
            return "dataCorrupted at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.keyNotFound(let key, let context):
            return "keyNotFound at \(path(context.codingPath + [key])): \(context.debugDescription)"
        case DecodingError.typeMismatch(_, let context):
            return "typeMismatch at \(path(context.codingPath)): \(context.debugDescription)"
        case DecodingError.valueNotFound(_, let context):
            return "valueNotFound at \(path(context.codingPath)): \(context.debugDescription)"
        default:
            return error.localizedDescription
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

    private static func dictionary<T: Encodable>(for value: T) throws -> [String: Any] {
        let object = try jsonObject(for: value)
        guard let dictionary = object as? [String: Any] else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "top-level harness result must encode as a JSON object"
                )
            )
        }
        return dictionary
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

private struct HarnessFailure: LocalizedError {
    let error: HarnessError
    let cause: String

    var errorDescription: String? { error.errorDescription }
}

package enum HarnessError: LocalizedError, Equatable {
    case missingCommand
    case unknownCommand(String)
    case usage(String)
    case unknownOption(String)
    case duplicateOption(String)
    case missingValue(String)
    case invalidValue(option: String, value: String)
    case invalidFPS(String)
    case unsupportedSource(String)
    case insufficientPipelineImages(Int)
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

    package var code: String {
        switch self {
        case .missingCommand: "missing_command"
        case .unknownCommand: "unknown_command"
        case .usage: "usage"
        case .unknownOption: "unknown_option"
        case .duplicateOption: "duplicate_option"
        case .missingValue: "missing_value"
        case .invalidValue: "invalid_value"
        case .invalidFPS: "invalid_fps"
        case .unsupportedSource: "unsupported_source"
        case .insufficientPipelineImages: "insufficient_pipeline_images"
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

    package var errorDescription: String? {
        switch self {
        case .missingCommand: "missing command"
        case .unknownCommand(let command): "unknown command: \(command)"
        case .usage(let usage): "usage: stitch-harness \(usage)"
        case .unknownOption(let option): "unknown option: \(option)"
        case .duplicateOption(let option): "duplicate option: \(option)"
        case .missingValue(let option): "missing value for option: \(option)"
        case .invalidValue(let option, let value): "invalid value for \(option): \(value)"
        case .invalidFPS(let value): "fps must be a finite number greater than 0; got \(value)"
        case .unsupportedSource(let source): "unsupported source: \(source)"
        case .insufficientPipelineImages(let count):
            "pipeline requires at least 2 images after ingestion; available \(count)"
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
