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
        .library(
            name: "GitAccountSwitcherAppLogic",
            targets: ["GitAccountSwitcherAppLogic"]
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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "GitAccountSwitcherCore"
        ),
        .target(
            name: "GitAccountSwitcherAppLogic",
            dependencies: ["GitAccountSwitcherCore"]
        ),
        .executableTarget(
            name: "GitAccountSwitcherApp",
            dependencies: [
                "GitAccountSwitcherAppLogic",
                "GitAccountSwitcherCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
        ),
        .executableTarget(
            name: "GitAccountSwitcherCoreTestRunner",
            dependencies: [
                "GitAccountSwitcherAppLogic",
                "GitAccountSwitcherCore"
            ]
        )
    ]
)
