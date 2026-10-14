// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Context",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Context", targets: ["Context"]),
        .executable(name: "ContextDemo", targets: ["ContextDemo"]),
        .executable(name: "ContextCLI", targets: ["ContextCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "Context",
            dependencies: [
                "ContextCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Context"
        ),
        .executableTarget(
            name: "ContextDemo",
            path: "Tools/ContextDemo"
        ),
        .target(name: "ContextCore", path: "Sources/ContextCore"),
        .executableTarget(
            name: "ContextCLI",
            dependencies: ["ContextCore"],
            path: "Sources/ContextCLI"
        ),
        .testTarget(
            name: "ContextCoreTests",
            dependencies: ["ContextCore"],
            path: "Tests/ContextCoreTests"
        ),
        .testTarget(
            name: "ContextTests",
            dependencies: ["Context", "ContextCore"],
            path: "Tests/ContextTests"
        )
    ]
)
