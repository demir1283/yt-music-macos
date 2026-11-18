import Foundation

/// The app's own listening history, which its recommendations learn from: one line per
/// play (what, how much of it was heard, finished or skipped) and per rating.
///
/// It is the one thing besides the stream solver the app keeps on disk, on purpose: it
/// stays on this Mac (Application Support), never leaves it, is capped in size, and can be
/// switched off or erased in Ayarlar.
final class ListeningLog: @unchecked Sendable {
    static let shared = ListeningLog()

    /// UserDefaults switch (Ayarlar → Geçmiş); on unless turned off.
    static let enabledKey = "listeningHistory"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Above this the oldest half is dropped (≈ 20 000 plays).
    private static let maxBytes: UInt64 = 4_000_000

    let url: URL
    private let queue = DispatchQueue(label: "ytmusic.listening", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        url = base.appendingPathComponent(AppIdentity.bundleID, isDirectory: true)
            .appendingPathComponent("listening.jsonl")
    }

    /// One play. Short keys keep each line around 200 bytes.
    struct Play: Codable {
        var k = "play"
        let t: Int           // when it ended (Unix time)
        let v: String        // videoId
        let ti: String       // title
        let ar: [String]     // artist names
        let ai: [String]     // artist ids
        let ty: String?      // YouTube's type: ATV (song), OMV (music video), UGC (upload)…
        let len: Int         // length, seconds
        let heard: Int       // seconds actually heard
        let at: Int          // where it stopped, seconds
        let end: String      // "done" (finished), "skip" or "stop" (app quit)
        let src: String      // "radio" or "list"
        var th: String? = nil // cover
    }

    /// A like / dislike / removed rating.
    struct Rating: Codable {
        var k = "rate"
        let t: Int
        let v: String
        let s: String        // LIKE, DISLIKE, INDIFFERENT
    }

    func record<T: Encodable>(_ event: T) {
        guard Self.isEnabled, var line = try? JSONEncoder().encode(event) else { return }
        line.append(0x0A)
        let url = url
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let h = try? FileHandle(forWritingTo: url) else { return }
            let size = (try? h.seekToEnd()) ?? 0
            try? h.write(contentsOf: line)
            try? h.close()
            if size + UInt64(line.count) > Self.maxBytes { Self.dropOldestHalf(url) }
        }
    }

    private static func dropOldestHalf(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        var kept = Data()
        for l in lines.suffix(lines.count / 2) {
            kept.append(contentsOf: l)
            kept.append(0x0A)
        }
        try? kept.write(to: url, options: .atomic)
    }

    /// Everything recorded, oldest first (read off the main thread).
    func read() -> (plays: [Play], ratings: [Rating]) {
        let data: Data? = queue.sync { try? Data(contentsOf: url) }
        guard let data else { return ([], []) }
        let decoder = JSONDecoder()
        let playTag = Data(#""k":"play""#.utf8)
        let rateTag = Data(#""k":"rate""#.utf8)
        var plays: [Play] = []
        var ratings: [Rating] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let d = Data(line)
            if d.range(of: playTag) != nil, let p = try? decoder.decode(Play.self, from: d) {
                plays.append(p)
            } else if d.range(of: rateTag) != nil, let r = try? decoder.decode(Rating.self, from: d) {
                ratings.append(r)
            }
        }
        return (plays, ratings)
    }

    /// Erases the history.
    func erase() {
        let url = url
        queue.async { try? FileManager.default.removeItem(at: url) }
    }

    /// Size on disk, for Ayarlar.
    var byteCount: Int {
        queue.sync {
            ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        }
    }
}
