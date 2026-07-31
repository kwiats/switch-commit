// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwitchCommit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwitchCommitCore",
            targets: ["SwitchCommitCore"]
        ),
        .library(
            name: "SwitchCommitAppLogic",
            targets: ["SwitchCommitAppLogic"]
        ),
        .executable(
            name: "SwitchCommitApp",
            targets: ["SwitchCommitApp"]
        ),
        .executable(
            name: "SwitchCommitCoreTestRunner",
            targets: ["SwitchCommitCoreTestRunner"]
        ),
        .executable(
            name: "switch-commit",
            targets: ["SwitchCommitCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2")
    ],
    targets: [
        .target(
            name: "SwitchCommitCore"
        ),
        .target(
            name: "SwitchCommitAppLogic",
            dependencies: ["SwitchCommitCore"]
        ),
        .executableTarget(
            name: "SwitchCommitApp",
            dependencies: [
                "SwitchCommitAppLogic",
                "SwitchCommitCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "SwitchCommitCoreTestRunner",
            dependencies: [
                "SwitchCommitAppLogic",
                "SwitchCommitCore"
            ]
        ),
        .executableTarget(
            name: "SwitchCommitCLI",
            dependencies: [
                "SwitchCommitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
