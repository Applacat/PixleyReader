// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PixleyReader",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "PixleyReader",
            path: ".",
            exclude: [
                "cal",
                "docs",
                "Open",
                "project.yml",
                "CLAUDE.md",
                "Resources/Info.plist",
                "Resources/PixleyWriter.entitlements"
            ],
            sources: ["Sources"],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Welcome")
            ]
        )
    ]
)
