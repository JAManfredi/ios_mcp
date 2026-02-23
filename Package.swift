// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ios-mcp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ios-mcp", targets: ["IosMcp"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Tools", targets: ["Tools"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "IosMcp",
            dependencies: [
                "Core",
                "Tools",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "Core",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "Tools",
            dependencies: [
                "Core",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: [
                "Core",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .testTarget(
            name: "ToolTests",
            dependencies: ["Tools", "Core"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["Core", "Tools"]
        ),
    ]
)
