// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlashClick",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "FlashClick",
            dependencies: []
        ),
    ]
)
