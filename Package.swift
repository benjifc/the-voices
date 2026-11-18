// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheVoices",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "VoicesDSP",
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        .target(
            name: "VoicesAudio",
            dependencies: ["VoicesDSP"],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
            ]
        ),
        .target(
            name: "VoicesKit",
            dependencies: ["VoicesDSP", "VoicesAudio"]
        ),
        .executableTarget(
            name: "TheVoices",
            dependencies: [
                "VoicesDSP", "VoicesAudio", "VoicesKit",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .testTarget(name: "VoicesDSPTests", dependencies: ["VoicesDSP"]),
        .testTarget(name: "VoicesAudioTests", dependencies: ["VoicesAudio"]),
        .testTarget(name: "VoicesKitTests", dependencies: ["VoicesKit"]),
    ]
)
