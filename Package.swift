// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NexusCommand",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "NexusCommand",
            path: "Sources/NexusCommand",
            exclude: [
                "Shaders/BlurShader.metal",
                "Shaders/GlowShader.metal",
                "Resources",
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-bare-slash-regex"]),
            ]
        ),
        .testTarget(
            name: "NexusCommandTests",
            dependencies: ["NexusCommand"],
            path: "Tests/NexusCommandTests"
        ),
    ]
)
