import Foundation

/// One timed lyric line.
struct LyricLine: Hashable {
    let time: Double
    let text: String
}

/// Time-synced lyrics from LRCLIB (https://lrclib.net), an open lyrics database
/// (also used by Kaset). YouTube Music's web API only exposes plain lyrics here.
enum SyncedLyricsService {
    private struct Entry: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }


    /// Returns timed lines, or nil when LRCLIB has no synced lyrics for the track.
    static func fetch(videoId: String, title: String, artist: String, duration: Double) async -> [LyricLine]? {
        let cleanTitle = clean(title)
        let firstArtist = artist
            .components(separatedBy: CharacterSet(charactersIn: ",&"))
            .first?
            .replacingOccurrences(of: " ve ", with: ",")
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces) ?? artist

        var lines: [LyricLine]? = await search(track: cleanTitle, artist: firstArtist, duration: duration)
        if lines == nil {
            lines = await search(query: "\(cleanTitle) \(firstArtist)", duration: duration,
                                 title: cleanTitle, artist: firstArtist)
        }
        return lines
    }

    private static func search(track: String, artist: String, duration: Double) async -> [LyricLine]? {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name: "track_name", value: track),
                        URLQueryItem(name: "artist_name", value: artist)]
        return await run(c.url, duration: duration, title: track, artist: artist)
    }

    private static func search(query: String, duration: Double, title: String, artist: String) async -> [LyricLine]? {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [URLQueryItem(name: "q", value: query)]
        return await run(c.url, duration: duration, title: title, artist: artist)
    }

    private static func run(_ url: URL?, duration: Double, title: String, artist: String) async -> [LyricLine]? {
        guard let url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Encore/1.0 (macOS YouTube Music client)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        guard let result = try? await NoCacheSession.shared.data(for: req) else { return nil }
        let (data, resp) = result
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return nil }
        // Same song only: title and artist must match (not just a similar duration).
        let wantTitle = norm(title), wantArtist = norm(artist)
        let synced = entries.filter { e in
            guard e.syncedLyrics?.isEmpty == false, e.instrumental != true else { return false }
            let t = norm(e.trackName ?? ""), a = norm(e.artistName ?? "")
            let titleOK = !t.isEmpty && (t == wantTitle || t.hasPrefix(wantTitle) || wantTitle.hasPrefix(t))
            let artistOK = !a.isEmpty && (a.contains(wantArtist) || wantArtist.contains(a))
            return titleOK && artistOK
        }
        guard !synced.isEmpty else { return nil }
        // Pick the closest duration; reject clearly different recordings.
        let best = synced.min { abs(($0.duration ?? 0) - duration) < abs(($1.duration ?? 0) - duration) }!
        // Reject other recordings (live sets, extended mixes…): durations must match closely.
        guard duration > 0, let d = best.duration, abs(d - duration) <= 6 else { return nil }
        let lines = parse(best.syncedLyrics ?? "")
        return lines.isEmpty ? nil : lines
    }

    /// Parses LRC text: "[mm:ss.xx] line" (a line may carry several timestamps).
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                let parts = tag.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    times.append(m * 60 + s)
                }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for t in times { out.append(LyricLine(time: t, text: text.isEmpty ? "♪" : text)) }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Lowercased, accent-free, letters and digits only ("Şımarık" → "simarik").
    private static func norm(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Drops "(feat. …)", "[Official Video]", "- Remastered" etc. for better matches.
    private static func clean(_ title: String) -> String {
        var t = title
        let patterns = [
            "\\s*[\\(\\[][^\\)\\]]*(feat|ft\\.|official|video|audio|lyric|remaster|visualizer)[^\\)\\]]*[\\)\\]]",
            "\\s+-\\s+.*(remaster|version|edit).*$",
        ]
        for pattern in patterns {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return t.trimmingCharacters(in: .whitespaces)
    }
}
