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
    ],
    targets: [
        .target(
            name: "StitchKit",
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
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
