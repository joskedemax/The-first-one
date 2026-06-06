// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JosType",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/tattn/LocalLLMClient.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "JosType",
            dependencies: [
                .product(name: "LocalLLMClient", package: "LocalLLMClient"),
                .product(name: "LocalLLMClientLlama", package: "LocalLLMClient")
            ],
            path: "Sources/JosType",
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
