// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "GitAccountSwitcher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "GitAccountSwitcherCore",
            targets: ["GitAccountSwitcherCore"]
        ),
        .executable(
            name: "GitAccountSwitcherApp",
            targets: ["GitAccountSwitcherApp"]
        ),
        .executable(
            name: "GitAccountSwitcherCoreTestRunner",
            targets: ["GitAccountSwitcherCoreTestRunner"]
        )
    ],
    targets: [
        .target(
            name: "GitAccountSwitcherCore"
        ),
        .executableTarget(
            name: "GitAccountSwitcherApp",
            dependencies: ["GitAccountSwitcherCore"]
        ),
        .executableTarget(
            name: "GitAccountSwitcherCoreTestRunner",
            dependencies: ["GitAccountSwitcherCore"]
        )
    ]
)
