import Foundation

/// What the listening history says about taste: a score per song and per artist, built
/// fresh each time it's needed (nothing derived is stored).
///
/// Per play: finished (or a set heard for 10+ minutes) counts +1, a skip within the first
/// 30 seconds −1, anything in between by how much was heard. Likes add, dislikes take a
/// song out. Older plays count less (half as much after 30 days).
struct ListeningProfile {
    struct Track {
        let videoId: String
        var title: String
        var artists: [String]
        var artistIds: [String]
        var type: String?
        var cover: String?
        var length: Double
        var score: Double = 0
        var plays = 0
        var finished = 0
        var earlySkips = 0
        var last: Int = 0
        var disliked = false

        var isSet: Bool { length >= QueueCurator.setSeconds }
    }

    private(set) var tracks: [String: Track] = [:]
    /// Normalised artist / channel name → score.
    private(set) var artistScores: [String: Double] = [:]
    private(set) var artistNames: [String: String] = [:]
    private(set) var playCount = 0
    /// Normalised artist name → seconds heard, all time.
    private(set) var artistSeconds: [String: Double] = [:]

    /// Too little history to shape anything yet.
    var isEmpty: Bool { playCount < 8 }

    static let halfLifeDays: Double = 30

    /// Reads the history off the main thread.
    static func load() async -> ListeningProfile {
        await Task.detached(priority: .utility) {
            let (plays, ratings) = ListeningLog.shared.read()
            return ListeningProfile(plays: plays, ratings: ratings, now: Date())
        }.value
    }

    init(plays: [ListeningLog.Play], ratings: [ListeningLog.Rating], now: Date) {
        let nowT = now.timeIntervalSince1970
        func weight(_ t: Int) -> Double {
            pow(0.5, max(0, nowT - Double(t)) / 86_400 / Self.halfLifeDays)
        }
        for p in plays {
            var tr = tracks[p.v] ?? Track(videoId: p.v, title: p.ti, artists: p.ar, artistIds: p.ai,
                                          type: p.ty, cover: p.th, length: Double(p.len))
            tr.title = p.ti
            if !p.ar.isEmpty { tr.artists = p.ar; tr.artistIds = p.ai }
            if let th = p.th { tr.cover = th }
            if p.len > 0 { tr.length = Double(p.len) }
            tr.plays += 1
            tr.last = max(tr.last, p.t)
            let w = weight(p.t)
            let length = Double(max(p.len, 1))
            let heard = Double(p.heard)
            let fraction = min(1, heard / length)
            let isSet = Double(p.len) >= QueueCurator.setSeconds
            if p.end == "done" || fraction >= 0.8 || (isSet && heard >= 600) {
                tr.score += w
                tr.finished += 1
            } else if p.end == "skip" && heard < 30 {
                tr.score -= w
                tr.earlySkips += 1
            } else {
                tr.score += (fraction - 0.3) * w
            }
            tracks[p.v] = tr
            for name in p.ar.prefix(2) {
                artistSeconds[Self.key(name), default: 0] += heard
            }
        }
        for r in ratings {
            guard var tr = tracks[r.v] else { continue }
            switch r.s {
            case "LIKE": tr.score += 2 * weight(r.t); tr.disliked = false
            case "DISLIKE": tr.disliked = true
            default: tr.disliked = false
            }
            tracks[r.v] = tr
        }
        playCount = plays.count
        for tr in tracks.values where !tr.disliked {
            for name in tr.artists.prefix(2) {
                let key = Self.key(name)
                guard !key.isEmpty else { continue }
                artistScores[key, default: 0] += tr.score
                if artistNames[key] == nil { artistNames[key] = name }
            }
        }
    }

    /// Artist and channel names compared loosely ("ARTBAT - Topic", "ArtbatVEVO" → "artbat").
    static func key(_ name: String) -> String {
        var n = QueueCurator.normalize(name)
        for suffix in [" topic", " vevo", "vevo", " official", " music"] where n.hasSuffix(suffix) && n.count > suffix.count + 1 {
            n = String(n.dropLast(suffix.count))
        }
        return n.trimmingCharacters(in: .whitespaces)
    }

    /// How much the history likes this artist or channel (0 when unknown).
    func affinity(_ name: String) -> Double {
        artistScores[Self.key(name)] ?? 0
    }

    /// Songs to leave out: disliked, or skipped early again and again and never finished.
    func isUnwanted(_ videoId: String?) -> Bool {
        guard let v = videoId, let tr = tracks[v] else { return false }
        return tr.disliked || (tr.earlySkips >= 2 && tr.finished == 0)
    }

    /// Well-liked songs and sets, best first.
    func favourites(limit: Int) -> [Track] {
        tracks.values
            .filter { !$0.disliked && $0.score >= 0.8 }
            .sorted { ($0.score, $0.last) > ($1.score, $1.last) }
            .prefix(limit)
            .map { $0 }
    }

    /// Artists listened to most, with their best song (to start a mix from).
    func topArtists(limit: Int) -> [(name: String, seed: Track)] {
        let ranked = artistScores.filter { $0.value >= 1 }.sorted { $0.value > $1.value }
        var out: [(name: String, seed: Track)] = []
        for (key, _) in ranked {
            let best = tracks.values
                .filter { t in !t.disliked && !t.isSet && t.artists.prefix(2).contains { Self.key($0) == key } }
                .max { $0.score < $1.score }
            if let best, let name = artistNames[key] { out.append((name: name, seed: best)) }
            if out.count == limit { break }
        }
        return out
    }

    /// Seconds spent listening to this artist (0 when unknown).
    func listened(_ name: String) -> Double {
        artistSeconds[Self.key(name)] ?? 0
    }

    /// Songs finished most often, over all time (variety beyond the latest weeks).
    func allTime(limit: Int) -> [Track] {
        tracks.values
            .filter { !$0.disliked && $0.finished > 0 }
            .sorted { ($0.finished, $0.score) > ($1.finished, $1.score) }
            .prefix(limit)
            .map { $0 }
    }

    /// Songs heard lately (not the ones skipped or disliked), most recent first.
    func recent(limit: Int) -> [Track] {
        tracks.values
            .filter { !$0.disliked && $0.score > -0.5 && $0.finished > 0 }
            .sorted { $0.last > $1.last }
            .prefix(limit)
            .map { $0 }
    }

    /// Long recordings started lately but not finished ("Kaldığın yerden devam et").
    func unfinished(limit: Int, now: Date = Date()) -> [Track] {
        let since = Int(now.timeIntervalSince1970) - 30 * 86_400
        return tracks.values
            .filter { !$0.disliked && $0.finished == 0 && $0.length >= 600 && $0.earlySkips == 0 && $0.last >= since }
            .sorted { $0.last > $1.last }
            .prefix(limit)
            .map { $0 }
    }

    /// An artist as the history knows it: name, channel id, a cover of theirs.
    struct HeardArtist {
        let name: String
        let id: String?
        let cover: String?
    }

    /// Artists heard lately, most recent first (not the ones only skipped).
    func recentArtists(limit: Int) -> [HeardArtist] {
        var seen = Set<String>()
        var out: [HeardArtist] = []
        for tr in tracks.values.sorted(by: { $0.last > $1.last }) where out.count < limit {
            guard !tr.disliked, tr.score > -0.5, let name = tr.artists.first else { continue }
            guard seen.insert(Self.key(name)).inserted else { continue }
            out.append(HeardArtist(name: name, id: tr.artistIds.first, cover: tr.cover))
        }
        return out
    }

    /// Artists listened to longest, all time.
    func topListened(limit: Int) -> [HeardArtist] {
        let ranked = artistSeconds.sorted { $0.value > $1.value }.prefix(limit)
        return ranked.compactMap { key, _ in
            let best = tracks.values
                .filter { t in !t.disliked && t.artists.prefix(2).contains { Self.key($0) == key } }
                .max { $0.score < $1.score }
            guard let best, let i = best.artists.firstIndex(where: { Self.key($0) == key }) else { return nil }
            let id = i < best.artistIds.count ? best.artistIds[i] : nil
            return HeardArtist(name: best.artists[i], id: id, cover: best.cover)
        }
    }

    /// Sets listened to well, to look for similar ones.
    func setSeeds(limit: Int) -> [Track] {
        tracks.values
            .filter { $0.isSet && !$0.disliked && $0.score > 0.5 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
