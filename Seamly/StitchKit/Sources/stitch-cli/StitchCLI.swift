import CoreGraphics
import Foundation
import ImageIO
import StitchKit
import UniformTypeIdentifiers

/// Runs the real stitching pipeline over an arbitrary clip or screenshot set and writes the result
/// where you can look at it.
///
/// This exists because the failure modes that matter here are *visual*. A stitch can pass every
/// structural gate the test suite has — right scroll order, no segment breaks, high seam confidence,
/// sane overlaps — and still be wrong in a way only pixels reveal: the translucent-tab-bar bug
/// (`TranslucentChromeTests`) produced exactly that, a clean-looking plan with the bar baked in six
/// times. Tests can't take a path off the user's disk and can't be eyeballed; this can. Use it to
/// triage a real capture, then pin whatever it turns up as a fixture-backed test.
///
///     swift run stitch-cli video ~/Pictures/scroll.mp4 --out /tmp/stitch
///     swift run stitch-cli images ./Fixtures/RealDevice --out /tmp/stitch --prefix youtube
///
/// `video` mirrors the app's "From Video" import (30fps sampling, capture order trusted); `images`
/// mirrors batch assembly over a directory of PNGs, recovering scroll order from the pixels.
@main
struct StitchCLI {
    static func main() async {
        do { try await run(Array(CommandLine.arguments.dropFirst())) }
        catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static let usage = """
        usage: stitch-cli video  <clip.mp4>  [--out <dir>] [--fps <n>]
               stitch-cli images <directory> [--out <dir>] [--prefix <name>]

          --out     where to write stitched.png (default: alongside the input)
          --fps     frame sampling rate for video (default 30, the app's cadence)
          --prefix  only load PNGs whose name starts with this
        """

    static func run(_ args: [String]) async throws {
        guard let mode = args.first, args.count >= 2, mode == "video" || mode == "images" else {
            print(usage)
            exit(2)
        }
        let input = URL(fileURLWithPath: args[1])
        let options = Options(args.dropFirst(2))
        let outDir = options.out.map { URL(fileURLWithPath: $0) }
            ?? input.deletingLastPathComponent().appendingPathComponent("stitch-out")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let images: [CGImage]
        let order: [Int]?
        switch mode {
        case "video":
            images = try await decodeVideo(input, fps: options.fps, into: outDir)
            // Capture order is temporal and therefore trustworthy — same as `.inputOrder`.
            order = Array(0..<images.count)
        default:
            images = try loadImages(input, prefix: options.prefix)
            order = nil
        }
        guard images.count >= 2 else {
            throw CLIError.notEnoughFrames(images.count)
        }

        let stitcher = BatchStitcher()
        let plan = try order.map { try stitcher.plan(images, assumingOrder: $0) }
            ?? stitcher.plan(images)
        report(plan, count: images.count)

        let stitched = try Compositor(refinementDelta: 16)
            .composite(plan.session) { images[plan.order[$0.index]] }
        let out = outDir.appendingPathComponent("stitched.png")
        try writePNG(stitched, to: out)
        print("stitched \(stitched.width)x\(stitched.height) -> \(out.path)")
    }

    // MARK: - Reporting

    /// Print the manifest the compositor will assemble from. Seam confidence, segment breaks and the
    /// content band are the three things worth reading before opening the PNG: a zero band means
    /// chrome will repeat, and a break means the frames didn't overlap.
    static func report(_ plan: BatchStitcher.Plan, count: Int) {
        print("order: \(plan.order)\(plan.order == Array(0..<count) ? " (monotonic)" : " (recovered)")")
        for seam in plan.session.seams {
            print(String(format: "  seam %d->%d  dy=%-5d conf=%.3f%@",
                         seam.fromIndex, seam.fromIndex + 1, seam.provisionalDy, seam.confidence,
                         seam.isLowConfidence ? "  LOW CONFIDENCE" : ""))
        }
        if plan.session.segmentBreaks.isEmpty {
            print("  segments: 1 (continuous)")
        } else {
            print("  segment breaks after: \(plan.session.segmentBreaks.map { $0.afterKeyframeIndex })")
        }
        for (i, band) in plan.session.contentBands.enumerated() {
            let warning = band.bottomChrome == 0 ? "  <- no bottom chrome; a bottom bar would repeat" : ""
            print("  band[\(i)] topChrome=\(band.topChrome) bottomChrome=\(band.bottomChrome)\(warning)")
        }
    }

    // MARK: - Input

    static func decodeVideo(_ url: URL, fps: Double, into outDir: URL) async throws -> [CGImage] {
        var driver = ScrollCaptureDriver()
        let result = try await VideoKeyframeSource.decodeCommittedKeyframes(url: url, driver: &driver, targetFPS: fps)
        print("decoded \(result.frames) frames at \(Int(fps))fps, \(result.decodeFailures) failures, "
              + "\(result.keyframes.count) keyframes banked")
        // Dump the keyframes: when a stitch looks wrong the first question is always whether capture
        // or assembly is at fault, and that needs the inputs.
        let kfDir = outDir.appendingPathComponent("keyframes")
        try FileManager.default.createDirectory(at: kfDir, withIntermediateDirectories: true)
        for (i, kf) in result.keyframes.enumerated() {
            try writePNG(kf.image, to: kfDir.appendingPathComponent(String(format: "kf-%02d.png", i)))
        }
        return result.keyframes.map { $0.image }
    }

    static func loadImages(_ dir: URL, prefix: String?) throws -> [CGImage] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.lowercased().hasSuffix(".png") }
            .filter { prefix.map($0.hasPrefix) ?? true }
            .sorted()
        guard !names.isEmpty else { throw CLIError.noImages(dir.path, prefix) }
        print("loading \(names.count) image(s): \(names.joined(separator: ", "))")
        return try names.map { try KeyframeIO.read(from: dir.appendingPathComponent($0)) }
    }

    // MARK: - Output

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw CLIError.pngFailed(url.path) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CLIError.pngFailed(url.path) }
    }

    // MARK: - Support

    struct Options {
        var out: String?
        var fps: Double = 30
        var prefix: String?

        init(_ args: some Sequence<String>) {
            var it = Array(args), i = 0
            while i < it.count {
                switch it[i] {
                case "--out" where i + 1 < it.count: out = it[i + 1]; i += 2
                case "--fps" where i + 1 < it.count: fps = Double(it[i + 1]) ?? 30; i += 2
                case "--prefix" where i + 1 < it.count: prefix = it[i + 1]; i += 2
                default: i += 1
                }
            }
        }
    }

    enum CLIError: LocalizedError {
        case notEnoughFrames(Int)
        case noImages(String, String?)
        case pngFailed(String)

        var errorDescription: String? {
            switch self {
            case .notEnoughFrames(let n):
                return "need at least 2 frames to stitch, got \(n)"
            case .noImages(let path, let prefix):
                return "no PNGs\(prefix.map { " starting with '\($0)'" } ?? "") in \(path)"
            case .pngFailed(let path):
                return "could not write PNG at \(path)"
            }
        }
    }
}
