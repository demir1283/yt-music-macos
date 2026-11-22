import Foundation

/// "Your listening": what the on-device history (ListeningLog) says about a period —
/// time listened, distinct songs and artists, the top artists and songs. Computed on this Mac from the same file the recommendations learn from;
/// nothing is sent anywhere.
///
/// A play counts once at least 30 seconds of it were heard. Time is the time actually
/// heard. A song by several artists counts fully for each.
struct ListeningSummary {
    enum Period: String, CaseIterable, Identifiable {
        case week, month, year, all
        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: return M.t("Son 7 gün", "Last 7 days")
            case .month: return M.t("Son 30 gün", "Last 30 days")
            case .year: return M.t("Bu yıl", "This year")
            case .all: return M.t("Tümü", "All time")
            }
        }
    }

    struct Artist: Identifiable, Equatable {
        let id: String          // the artist's channel id, or the name when there is none
        let name: String
        let channelId: String?
        var seconds: Double = 0
        var plays = 0
    }

    struct Song: Identifiable, Equatable {
        let id: String          // videoId
        var title: String
        var artist: String
        var cover: String?
        var seconds: Double = 0
        var plays = 0
        /// Names and channel ids, for the song list's artist links.
        var artists: [String] = []
        var artistIds: [String] = []
    }

    static let minimumHeard = 30

    var seconds: Double = 0
    var plays = 0
    var songCount = 0
    var artistCount = 0
    var topArtists: [Artist] = []
    var topSongs: [Song] = []

    var isEmpty: Bool { plays == 0 }

    init(plays all: [ListeningLog.Play], period: Period, now: Date = Date(), calendar: Calendar = .current) {
        let start = Self.start(of: period, now: now, calendar: calendar)
        let counted = all.filter { p in
            p.heard >= Self.minimumHeard && (start.map { Double(p.t) >= $0.timeIntervalSince1970 } ?? true)
        }
        var artists: [String: Artist] = [:]
        var songs: [String: Song] = [:]

        for p in counted {
            let heard = Double(p.len > 0 ? min(p.heard, p.len) : p.heard)
            seconds += heard
            plays += 1

            var song = songs[p.v] ?? Song(id: p.v, title: p.ti, artist: p.ar.joined(separator: ", "), cover: p.th,
                                          artists: p.ar, artistIds: p.ai)
            song.seconds += heard
            song.plays += 1
            if let th = p.th { song.cover = th }
            songs[p.v] = song

            for (i, name) in p.ar.enumerated() where !name.isEmpty {
                let channel = i < p.ai.count && !p.ai[i].isEmpty ? p.ai[i] : nil
                let key = channel ?? name.lowercased()
                var a = artists[key] ?? Artist(id: key, name: name, channelId: channel)
                a.seconds += heard
                a.plays += 1
                artists[key] = a
            }

        }

        songCount = songs.count
        artistCount = artists.count
        topArtists = Array(artists.values.sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }.prefix(20))
        topSongs = Array(songs.values.sorted { ($0.plays, $0.seconds) > ($1.plays, $1.seconds) }.prefix(50))
    }

    /// Reads the history off the main thread.
    static func load(_ period: Period) async -> ListeningSummary {
        await Task.detached(priority: .userInitiated) {
            ListeningSummary(plays: ListeningLog.shared.read().plays, period: period)
        }.value
    }

    static func start(of period: Period, now: Date, calendar: Calendar) -> Date? {
        switch period {
        case .week: return calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))
        case .month: return calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))
        case .year: return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .all: return nil
        }
    }
}
