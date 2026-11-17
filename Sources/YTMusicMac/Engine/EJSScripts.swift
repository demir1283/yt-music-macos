import Foundation

// yt-dlp-ejs 0.8.0 (https://github.com/yt-dlp/ejs) — public domain (Unlicense); bundles
// meriyah (ISC) and astring (MIT), whose licence texts are inside lib.min.js.
// It solves the "n" and signature challenges of YouTube's player script, so the app
// can play the exact streams YouTube's own player gets (incl. Premium 256 kbps AAC).
// The two scripts ship in the app bundle (Contents/Resources/ejs), copied by build.sh.
enum EJSScripts {
    static let version = "0.8.0"

    private static func load(_ name: String) -> String? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ejs/\(name)"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/ejs/\(name)"),
        ]
        for case let url? in candidates {
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return nil
    }

    static let lib: String? = load("lib.min.js")
    static let core: String? = load("core.min.js")
}
