// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrumNotation",
    platforms: [.iOS("17.5"), .macOS(.v14)],
    products: [.library(name: "DrumNotation", targets: ["DrumNotation"])],
    targets: [
        .target(
            name: "DrumNotation",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "DrumNotationTests", dependencies: ["DrumNotation"])
    ],
    swiftLanguageVersions: [.v5]
)
