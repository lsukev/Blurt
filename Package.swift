// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Blurt",
    platforms: [.macOS(.v26)],
    dependencies: [
        // Parakeet TDT as CoreML on the Neural Engine. Optional at runtime — Apple's
        // SpeechTranscriber remains the default and needs no dependency at all.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        // The dictionary is its own target so it can be tested directly, and because its
        // behaviour is a cross-platform contract: the Windows app reimplements this logic in
        // C#, and both sides run the same vectors in shared/dictionary-test-vectors.json.
        .target(
            name: "BlurtDictionary",
            path: "Sources/BlurtDictionary",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The setup flow's decisions — step order, which lamps are lit, when to offer the
        // TCC reset — are worth testing, and the code that acts on them (TCC, event taps,
        // System Settings) is not testable at all. Same split, and same reason, as the
        // dictionary above: platform-neutral, so CI can run it without macOS 26.
        .target(
            name: "BlurtSetup",
            path: "Sources/BlurtSetup",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Blurt",
            dependencies: [
                "BlurtDictionary",
                "BlurtSetup",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Blurt",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "BlurtDictionaryTests",
            dependencies: ["BlurtDictionary"],
            path: "Tests/BlurtDictionaryTests",
            resources: [.copy("dictionary-test-vectors.json")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "BlurtSetupTests",
            dependencies: ["BlurtSetup"],
            path: "Tests/BlurtSetupTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
