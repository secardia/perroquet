// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fluidbench",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../fluidaudio-src")],
    targets: [
        .executableTarget(
            name: "fluidbench",
            dependencies: [.product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
        .executableTarget(
            name: "trimbench",
            dependencies: [.product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
        .executableTarget(
            name: "loadbench",
            dependencies: [.product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
    ]
)
