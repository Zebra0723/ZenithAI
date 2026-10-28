// swift-tools-version:5.10
import PackageDescription

// ZenithCore is pure Swift (Foundation only): missions, the budget governor, the
// Claude Code stream parser, forecasts and prompts. It builds and tests anywhere,
// Linux included. The app itself only builds on macOS.
var targets: [Target] = [
    .target(name: "ZenithCore", path: "Sources/ZenithCore"),
    .testTarget(name: "ZenithCoreTests", dependencies: ["ZenithCore"], path: "Tests/ZenithCoreTests"),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Zenith",
        dependencies: ["ZenithCore"],
        path: "Sources/Zenith",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
#endif

let package = Package(
    name: "Zenith",
    platforms: [.macOS(.v14)],
    targets: targets
)
