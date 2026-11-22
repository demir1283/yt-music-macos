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
        // `swift test`: the app's pure logic (no network, no window). Run by GitHub
        // Actions on every push; locally it needs Xcode's test tools.
        .testTarget(
            name: "YTMusicMacTests",
            dependencies: ["YTMusicMac"],
            path: "Tests/YTMusicMacTests"
        ),
    ]
)
