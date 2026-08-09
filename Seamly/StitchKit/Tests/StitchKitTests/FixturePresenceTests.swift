import Testing
import Foundation
@testable import StitchKit

/// The binary fixtures are hosted as GitHub Release assets rather than committed, so the one thing
/// that must never happen is a fixture-backed test quietly *not running* because its pixels are
/// absent.
///
/// This suite is the single, actionable failure for that: it reads `Fixtures/manifest.json` — which
/// is checked in, alongside every set's `README.md` — and fails naming the command to run. Without
/// it the first symptom of an unfetched checkout is a scatter of "missing fixture IMG_1863" errors
/// across a dozen unrelated suites.
///
/// **This must fail, never skip.** A green suite here has lied three times (see `CLAUDE.md`), and a
/// real-pixel test that silently turns into a no-op is that same failure in a new costume. There is
/// deliberately no `withKnownIssue` and no early `return` in this file.
@Suite struct FixturePresenceTests {

    struct Manifest: Decodable {
        struct File: Decodable {
            let name: String
            let sha256: String
            let bytes: Int
        }
        struct FixtureSet: Decodable {
            let name: String
            let asset: String
            let sha256: String
            let bytes: Int
            let files: [File]
        }
        let repo: String
        let release: String
        let root: String
        let sets: [FixtureSet]
    }

    /// Source-relative rather than `Bundle.module`: the manifest is not a declared SwiftPM
    /// resource, and it describes the fixture tree from the repo's point of view, not the bundle's.
    static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func manifest() throws -> Manifest {
        let url = fixturesDirectory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    /// Every file the manifest promises is on disk, at the size it promises.
    ///
    /// Size rather than SHA-256 because this runs on every test invocation and hashing 105 MB to
    /// answer "did the download finish" is a poor trade — a truncated or empty file, which is what
    /// an interrupted fetch actually leaves behind, differs in length. `scripts/fetch-fixtures.sh`
    /// does verify the full hash of every file, and is the gate that matters for content.
    @Test func everyFixtureTheManifestPromisesIsPresent() throws {
        let manifest = try Self.manifest()
        var wrong: [String] = []
        for set in manifest.sets {
            let directory = Self.fixturesDirectory.appendingPathComponent(set.name)
            for file in set.files {
                let path = directory.appendingPathComponent(file.name)
                guard let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                    wrong.append("\(set.name)/\(file.name) (missing)")
                    continue
                }
                if size != file.bytes {
                    wrong.append("\(set.name)/\(file.name) (\(size) bytes, expected \(file.bytes))")
                }
            }
        }
        let detail = """
            \(wrong.count) fixture file(s) missing or truncated, first few: \(wrong.prefix(5).joined(separator: ", ")).
            Binary fixtures are not committed — run:  scripts/fetch-fixtures.sh
            """
        #expect(wrong.isEmpty, "\(detail)")
    }

    /// The manifest describes the tree that actually exists — a set added to `Fixtures/` without a
    /// manifest entry would never be uploaded, so a fresh clone would silently lack it while this
    /// machine kept passing.
    @Test func everyFixtureSetOnDiskIsInTheManifest() throws {
        let manifest = try Self.manifest()
        let described = Set(manifest.sets.map(\.name))

        let contents = try FileManager.default.contentsOfDirectory(
            at: Self.fixturesDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        let directories = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.map { $0.lastPathComponent }

        let undescribed = directories.filter { !described.contains($0) }
        #expect(undescribed.isEmpty,
                "fixture set(s) \(undescribed) exist on disk but are not in manifest.json, so they are not published and a fresh clone will not have them")
    }

    /// Each set keeps its `README.md` **in the repo**. The ground truth is the part worth reading
    /// before measuring anything (`CLAUDE.md` says so), and it must survive the pixels being absent.
    @Test func everyFixtureSetKeepsItsGroundTruthInTheRepo() throws {
        let manifest = try Self.manifest()
        for set in manifest.sets {
            let readme = Self.fixturesDirectory
                .appendingPathComponent(set.name)
                .appendingPathComponent("README.md")
            #expect(FileManager.default.fileExists(atPath: readme.path),
                    "\(set.name)/README.md is missing; it carries the set's ground truth and must not be hosted externally")
        }
    }
}
