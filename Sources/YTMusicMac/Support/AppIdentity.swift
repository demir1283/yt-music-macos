import Foundation

/// The app's identity on macOS: preferences, caches and the sign-in cookies are kept
/// under it.
enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.demir1283.ytmusic"
}
