// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AIMDReader",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "Packages/aimdRenderer")
    ],
    targets: [
        .executableTarget(
            name: "AIMDReader",
            dependencies: [
                .product(name: "aimdRenderer", package: "aimdRenderer")
            ],
            path: ".",
            exclude: [
                "cal",
                "docs",
                "Open",
                "project.yml",
                "CLAUDE.md",
                "INDEX.md",
                "Resources/Info.plist",
                "Resources/AIMDReader.entitlements",
                "Resources/ACKNOWLEDGMENTS.md",
                "Packages",
                "Tests",
                "REFERENCE",
                "scratch",
                "scripts"
            ],
            sources: ["Sources"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Welcome"),
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "AIMDReaderTests",
            path: "Tests/AIMDReaderTests"
        )
    ]
)
