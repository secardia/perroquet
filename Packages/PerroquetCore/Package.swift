// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerroquetCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "PerroquetCore", targets: ["PerroquetCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.18.3"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "2.4.0"),
    ],
    targets: [
        .target(
            name: "PerroquetCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PerroquetCoreTests",
            dependencies: [
                "PerroquetCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
    ]
)
