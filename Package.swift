// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Glide",
            path: "Sources/Glide",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
