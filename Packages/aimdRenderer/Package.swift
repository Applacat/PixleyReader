// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "aimdRenderer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "aimdRenderer",
            targets: ["aimdRenderer"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0")
    ],
    targets: [
        .target(
            name: "aimdRenderer",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/aimdRenderer"
        ),
        .testTarget(
            name: "aimdRendererTests",
            dependencies: ["aimdRenderer"],
            path: "Tests/aimdRendererTests"
        )
    ]
)
