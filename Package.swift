// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoSwitch",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "AutoSwitch",
            targets: ["AutoSwitch"]
        ),
    ],
    dependencies: [
    ],
    targets: [
        .executableTarget(
            name: "AutoSwitch",
            dependencies: [],
            path: ".",
            exclude: ["Info.plist", "AutoSwitch.entitlements", "AutoSwitch-Distribution.entitlements", ".build-release", "README.md", "LICENSE", "CHANGELOG.md", "AutoSwitch.app", "build", "Tests", "docs", "scripts"],
            sources: ["Sources", "AutoSwitchApp.swift"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "AutoSwitchTests",
            dependencies: ["AutoSwitch"],
            path: "Tests/AutoSwitchTests",
            exclude: ["Fixtures"]
        )
    ]
)
