// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GraphicsEngine",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "EngineCore", targets: ["EngineCore"]),
        .library(name: "EngineMetal", targets: ["EngineMetal"]),
        .library(name: "EngineMac", targets: ["EngineMac"]),
    ],
    targets: [
        .target(name: "GPUShared"),
        .target(name: "EngineCore"),
        .target(
            name: "EngineMetal", dependencies: ["EngineCore", "GPUShared"],
            resources: [.process("Shaders")]),
        .target(name: "EngineMac", dependencies: ["EngineCore", "EngineMetal"]),
        .testTarget(name: "EngineCoreTests", dependencies: ["EngineCore"]),
        .testTarget(name: "EngineMetalTests", dependencies: ["EngineCore", "EngineMetal"]),
        .testTarget(name: "EngineMacTests", dependencies: ["EngineMac"]),
    ]
)
