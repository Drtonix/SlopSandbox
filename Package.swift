// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SlopSandbox",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "CBox2D",
            path: "Vendor/box2d",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("src")
            ]
        ),
        .target(
            name: "SlopCore",
            dependencies: ["CBox2D"],
            path: "Sources/SlopCore"
        ),
        .executableTarget(
            name: "SlopSandbox",
            dependencies: ["CBox2D", "SlopCore"]
        ),
        .executableTarget(
            name: "SlopSandboxSDL",
            dependencies: ["CBox2D", "SlopCore"]
        ),
    ]
)
