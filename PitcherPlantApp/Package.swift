// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PitcherPlantApp",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "PitcherPlantApp", targets: ["PitcherPlantApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.19"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "PitcherPlantApp",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "ZIPFoundation",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PitcherPlantApp"
        ),
        .testTarget(
            name: "PitcherPlantAppTests",
            dependencies: ["PitcherPlantApp"],
            path: "Tests/PitcherPlantAppTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
