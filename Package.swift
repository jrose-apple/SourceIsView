// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "SourceIsView",
    products: [
        .library(
            name: "SourceIsView",
            targets: ["SourceIsView"]),
        .executable(
            name: "source-is-view",
            targets: ["source-is-view"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-syntax.git",
            .exact("0.50000.0")),
    ],
    targets: [
        .target(
            name: "SourceIsView",
            dependencies: ["SwiftSyntax"]),
        .target(
            name: "source-is-view",
            dependencies: ["SourceIsView", "SwiftSyntax"]),
    ]
)
