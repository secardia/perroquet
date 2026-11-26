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
        .target(
            name: "Trimming",
            dependencies: [.product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
        .executableTarget(
            name: "trimbench",
            dependencies: ["Trimming", .product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
        .executableTarget(
            name: "speechspans",
            dependencies: ["Trimming", .product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
        .executableTarget(
            name: "loadbench",
            dependencies: [.product(name: "FluidAudio", package: "fluidaudio-src")]
        ),
    ]
)
