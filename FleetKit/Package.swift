// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FleetKit",
    defaultLocalization: "en",
    platforms: [
        .iOS("27.3"),
        .macOS("27.3")
    ],
    products: [
        .library(name: "FleetKit", targets: ["FleetKit"])
    ],
    targets: [
        .target(
            name: "FleetKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(name: "FleetKitTests", dependencies: ["FleetKit"])
    ]
)
