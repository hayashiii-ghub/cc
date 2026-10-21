// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cc",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "cc", targets: ["CC"]),
        .executable(name: "cc-demo", targets: ["CCDemo"]),
        .executable(name: "cc-shelf", targets: ["CCCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "CC",
            dependencies: [
                "CCCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CC"
        ),
        .executableTarget(
            name: "CCDemo",
            path: "Tools/CCDemo"
        ),
        .target(name: "CCCore", path: "Sources/CCCore"),
        .executableTarget(
            name: "CCCLI",
            dependencies: ["CCCore"],
            path: "Sources/CCCLI"
        ),
        .testTarget(
            name: "CCCoreTests",
            dependencies: ["CCCore"],
            path: "Tests/CCCoreTests"
        ),
        .testTarget(
            name: "CCCLITests",
            dependencies: ["CCCLI", "CCCore"],
            path: "Tests/CCCLITests"
        ),
        .testTarget(
            name: "CCTests",
            dependencies: ["CC", "CCCore"],
            path: "Tests/CCTests"
        )
    ]
)
