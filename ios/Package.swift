// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TeslaTimestampCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TeslaTimestampCore",
            targets: ["TeslaTimestampCore"]
        )
    ],
    targets: [
        .target(
            name: "TeslaTimestampCore",
            path: "TeslaTimestamp/Core"
        ),
        .testTarget(
            name: "TeslaTimestampTests",
            dependencies: ["TeslaTimestampCore"],
            path: "TeslaTimestampTests"
        )
    ]
)
