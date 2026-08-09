import CoreGraphics
import Foundation
import ImageIO
import Testing

private final class HarnessProcessBundleToken: NSObject {}

struct HarnessProcessTests {
    @Test func executableWritesSuccessEnvelopeOnlyToStandardOutput() throws {
        try withTemporaryDirectory { directory in
            let imageURL = directory.appendingPathComponent("frame.png")
            try writePNG(makeImage(width: 16, height: 24), to: imageURL)

            let result = try runHarness(["profile", imageURL.path])

            #expect(result.terminationStatus == 0)
            #expect(result.standardError.isEmpty)
            let envelope = try jsonObject(result.standardOutput)
            #expect(envelope["schemaVersion"] as? String == "stitch-harness.v1")
            #expect(envelope["command"] as? String == "profile")
            #expect(envelope["ok"] as? Bool == true)
            #expect(envelope["result"] is [String: Any])
        }
    }

    @Test func executableWritesFailureEnvelopeOnlyToStandardError() throws {
        let result = try runHarness(["capture", "audio", "unused-source"])

        #expect(result.terminationStatus == 1)
        #expect(result.standardOutput.isEmpty)
        let envelope = try jsonObject(result.standardError)
        let error = try #require(envelope["error"] as? [String: Any])
        #expect(envelope["schemaVersion"] as? String == "stitch-harness.v1")
        #expect(envelope["command"] as? String == "capture")
        #expect(envelope["ok"] as? Bool == false)
        #expect(error["code"] as? String == "unsupported_source")
        #expect(error["message"] as? String == "unsupported source: audio")
    }

    @Test func executablePreservesWrappedImageReadCauseOnStandardError() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-profile-\(UUID().uuidString).png")
        let result = try runHarness(["profile", missing.path])

        #expect(result.terminationStatus == 1)
        #expect(result.standardOutput.isEmpty)
        let envelope = try jsonObject(result.standardError)
        let error = try #require(envelope["error"] as? [String: Any])
        #expect(envelope["command"] as? String == "profile")
        #expect(envelope["ok"] as? Bool == false)
        #expect(error["code"] as? String == "image_read_failed")
        #expect((error["cause"] as? String)?.isEmpty == false)
    }

    private struct ProcessResult {
        let terminationStatus: Int32
        let standardOutput: Data
        let standardError: Data
    }

    private func runHarness(_ arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = try harnessExecutableURL()
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        return ProcessResult(
            terminationStatus: process.terminationStatus,
            standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
            standardError: standardError.fileHandleForReading.readDataToEndOfFile()
        )
    }

    private func harnessExecutableURL() throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        let launchLocations = [
            Bundle(for: HarnessProcessBundleToken.self).bundleURL,
            Bundle.main.executableURL,
            Bundle.main.bundleURL,
            URL(fileURLWithPath: CommandLine.arguments[0]),
        ].compactMap { $0 }
        for location in launchLocations {
            var ancestor = location.standardizedFileURL.deletingLastPathComponent()
            while ancestor.path != "/" {
                if ancestor.lastPathComponent == "debug" || ancestor.lastPathComponent == "release" {
                    candidates.append(ancestor.appendingPathComponent("stitch-harness"))
                    break
                }
                ancestor.deleteLastPathComponent()
            }
        }

        if let builtProductsDirectory = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            candidates.append(
                URL(fileURLWithPath: builtProductsDirectory, isDirectory: true)
                    .appendingPathComponent("stitch-harness")
            )
        }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(packageRoot.appendingPathComponent(".build/debug/stitch-harness"))

        let buildDirectory = packageRoot.appendingPathComponent(".build", isDirectory: true)
        if let entries = try? fileManager.contentsOfDirectory(
            at: buildDirectory,
            includingPropertiesForKeys: nil
        ) {
            for entry in entries {
                candidates.append(entry.appendingPathComponent("debug/stitch-harness"))
            }
        }

        for candidate in candidates {
            let path = candidate.standardizedFileURL.path
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw ProcessTestError.executableNotFound(candidates.map(\.standardizedFileURL.path))
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarnessProcessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private enum ProcessTestError: Error, CustomStringConvertible {
        case executableNotFound([String])

        var description: String {
            switch self {
            case .executableNotFound(let paths):
                "stitch-harness was not built alongside the test products; checked:\n"
                    + paths.map { "  \($0)" }.joined(separator: "\n")
            }
        }
    }
}
