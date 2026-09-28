// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KomorebiIndicator",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (decoding, label formatting, profile discovery) so it can be unit tested.
        .target(name: "IndicatorCore"),
        // The AppKit menubar app.
        .executableTarget(name: "KomorebiIndicator", dependencies: ["IndicatorCore"]),
        .testTarget(
            name: "IndicatorCoreTests",
            dependencies: ["IndicatorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
