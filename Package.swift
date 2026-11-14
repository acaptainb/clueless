// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clueless",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        .target(
            name: "CluelessCore",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "TTSKit", package: "argmax-oss-swift"),
                .product(name: "SpeakerKit", package: "argmax-oss-swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "Clueless", dependencies: ["CluelessCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "clueless-bench", dependencies: ["CluelessCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
