// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "yt-music-macos",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "YTMusicMac",
            path: "Sources/YTMusicMac",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("JavaScriptCore"),
            ]
        ),
    ]
)
