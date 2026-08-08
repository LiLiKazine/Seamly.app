// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StitchKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v15),
    ],
    products: [
        .library(name: "StitchKit", targets: ["StitchKit"]),
        // Diagnostic driver for real captures — see Sources/stitch-cli.
        .executable(name: "stitch-cli", targets: ["stitch-cli"]),
        .executable(name: "stitch-harness", targets: ["stitch-harness"]),
    ],
    targets: [
        .target(
            name: "StitchKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "stitch-cli",
            dependencies: ["StitchKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "StitchHarness",
            dependencies: ["StitchKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .executableTarget(
            name: "stitch-harness",
            dependencies: ["StitchHarness"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "StitchHarnessTests",
            dependencies: ["StitchHarness"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "StitchKitTests",
            dependencies: ["StitchKit"],
            resources: [
                .copy("Fixtures/wikipedia.png"),
                .copy("Fixtures/RealDevice"),
                .copy("Fixtures/Example"),
                .copy("Fixtures/Screenshots"),
                .copy("Fixtures/Screenshots2"),
                .copy("Fixtures/Recordings"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
