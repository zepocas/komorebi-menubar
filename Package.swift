// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KomorebiMenubar",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (decoding, label formatting, profile discovery) so it can be unit tested.
        .target(name: "MenubarCore"),
        // The AppKit menubar app.
        .executableTarget(name: "KomorebiMenubar", dependencies: ["MenubarCore"]),
        .testTarget(
            name: "MenubarCoreTests",
            dependencies: ["MenubarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
