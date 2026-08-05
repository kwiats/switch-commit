// swift-tools-version: 6.2

import PackageDescription

#if os(macOS)
let macOSOnlyProducts: [Product] = [
    .library(name: "SwitchCommitAppLogic", targets: ["SwitchCommitAppLogic"]),
    .executable(name: "SwitchCommitApp", targets: ["SwitchCommitApp"]),
    .executable(name: "SwitchCommitCoreTestRunner", targets: ["SwitchCommitCoreTestRunner"])
]
let macOSOnlyDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
]
let macOSOnlyTargets: [Target] = [
    .target(name: "SwitchCommitAppLogic", dependencies: ["SwitchCommitCore"]),
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
        dependencies: ["SwitchCommitAppLogic", "SwitchCommitCore"]
    )
]
#else
let macOSOnlyProducts: [Product] = []
let macOSOnlyDependencies: [Package.Dependency] = []
let macOSOnlyTargets: [Target] = []
#endif

let package = Package(
    name: "SwitchCommit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SwitchCommitCore", targets: ["SwitchCommitCore"]),
        .executable(name: "switch-commit", targets: ["SwitchCommitCLI"])
    ] + macOSOnlyProducts,
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.2"),
        // Provides `Crypto` for SHA-256 verification. On Apple platforms this compiles down to a
        // thin re-export of CryptoKit; on Linux/Windows it supplies the real implementation, so
        // `CLIBinaryInstaller` can `import Crypto` unconditionally across every supported OS.
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ] + macOSOnlyDependencies,
    targets: [
        .target(
            name: "SwitchCommitCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "SwitchCommitCLI",
            dependencies: [
                "SwitchCommitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ] + macOSOnlyTargets
)
