// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoxKey",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoxKey", targets: ["VoxKey"])
    ],
    dependencies: [
        .package(url: "https://github.com/georgecristea/MacUtilityKit.git", from: "0.1.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.4")
    ],
    targets: [
        .executableTarget(
            name: "VoxKey",
            dependencies: [
                "MacUtilityKit",
                .product(name: "FluidAudio", package: "FluidAudio"),
                "whisper"
            ]
        ),
        // Prebuilt whisper.cpp xcframework (universal arm64 + x86_64) — the CPU engine
        // for Intel Macs and the optional verbatim-Whisper engine on Apple Silicon.
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-v1.9.1-xcframework.zip",
            checksum: "8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"
        )
    ],
    swiftLanguageVersions: [.v5]
)
