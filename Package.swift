// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Encore",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Encore",
            path: "Sources/Encore",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("JavaScriptCore"),
            ]
        ),
    ]
)
