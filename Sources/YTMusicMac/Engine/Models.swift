import Foundation

// These types mirror the JSON produced by BridgeScript (bridge.js).

struct ArtistRef: Codable, Hashable {
    let name: String
    let id: String
}

struct AlbumRef: Codable, Hashable {
    let name: String
    let id: String
}

struct MediaItem: Codable, Identifiable, Hashable {
    let uid: String
    let kind: String          // song, video, episode, album, playlist, artist, podcast, category, unknown
    let title: String
    var subtitle: String
    var thumbnail: String?
    let videoId: String?
    let browseId: String?
    let params: String?
    let playlistId: String?
    var artists: [ArtistRef]
    let album: AlbumRef?
    let duration: String?
    let explicit: Bool
    let play: String?         // raw YouTube Music endpoint JSON used to start playback
    var wide: Bool
    let color: String?
    /// Entry id inside a playlist (needed to remove or move it).
    var setVideoId: String? = nil
    /// A wide picture behind the item (an artist's banner), for the home page's cards.
    var banner: String? = nil
    /// The channel's picture beside the title (home page notifications).
    var avatar: String? = nil
    /// A notification not read yet on YouTube: a dot before the title.
    var unread: Bool? = nil

    var id: String { uid }
    var isTrack: Bool { videoId != nil }
    /// The item with the artist's name in front of its subtitle ("Tiësto • Single • 2025"),
    /// for a release taken from the artist's own page, where the name isn't written.
    /// `id`: the artist's page, so the name links to it.
    func by(_ artist: String, id: String? = nil) -> MediaItem {
        guard !artist.isEmpty else { return self }
        var copy = self
        if let id, artists.isEmpty { copy.artists = [ArtistRef(name: artist, id: id)] }
        if !subtitle.localizedCaseInsensitiveContains(artist) {
            copy.subtitle = subtitle.isEmpty ? artist : "\(artist) • \(subtitle)"
        }
        return copy
    }

    /// The same item as a 16:9 card (a video).
    var asWide: MediaItem {
        var copy = self
        copy.wide = true
        return copy
    }
    var isArtist: Bool { kind == "artist" }

    var typeLabel: String {
        switch kind {
        case "album": return "Albüm"
        case "playlist": return "Çalma listesi"
        case "artist": return "Sanatçı"
        case "podcast": return "Podcast"
        case "episode": return "Bölüm"
        case "video": return "Video"
        case "song": return "Şarkı"
        case "mix": return "Mix"
        case "artistradio": return "Radyo"
        default: return ""
        }
    }

    var bylineText: String {
        artists.isEmpty ? subtitle : artists.map(\.name).joined(separator: ", ")
    }

    /// Identifies a recommendation across pages ("Bana önerme").
    var recommendationKey: String { videoId ?? playlistId ?? browseId ?? uid }
}

struct MoreLink: Codable, Hashable {
    let browseId: String?
    let params: String?
    let pageType: String?
    let query: String?
}

struct Shelf: Codable, Identifiable {
    let id: String
    let title: String
    let strapline: String?
    let layout: String        // cards, list, nav, top
    var items: [MediaItem]
    let more: MoreLink?
    var continuation: String?
    let top: MediaItem?

    var hasTracks: Bool { items.contains { $0.isTrack } }
}

struct FilterChip: Codable, Hashable, Identifiable {
    let title: String
    let params: String?
    let browseId: String?
    let selected: Bool
    var id: String { title + (params ?? "") }
}

struct PageHeader: Codable {
    let style: String         // collection, artist, plain
    let title: String
    let subtitle: String
    let secondSubtitle: String
    let strapline: String
    let description: String
    let thumbnail: String?
    let strapThumb: String?
    let subscribers: String
    let play: String?
    let shuffle: String?
    let radio: String?
    let artists: [ArtistRef]
    /// Set for playlists the account owns.
    var editable: Bool? = nil
    var privacy: String? = nil
    var playlistId: String? = nil
    var rawDescription: String? = nil
    /// Artist channels: subscription state and what the (un)subscribe calls need.
    var channelId: String? = nil
    var subscribed: Bool? = nil
    var subscriberShort: String? = nil
    var subscribeParams: String? = nil
    var unsubscribeParams: String? = nil
}

/// A playlist offered in "Çalma listesine ekle".
struct PlaylistOption: Codable, Identifiable, Hashable {
    let playlistId: String
    let title: String
    var thumbnail: String?
    let contains: Bool
    let privacy: String?
    var raw: String? = nil
    var id: String { playlistId }
}

/// One playlist's songs, as fetched for the membership index.
struct PlaylistIndexData: Codable {
    struct Track: Codable {
        let v: String
        let t: String
        let a: String
    }
    let editable: Bool
    let title: String
    let thumbnail: String?
    let tracks: [Track]
}

/// A library playlist with the ids (and title/artist keys) of its songs.
struct IndexedPlaylist: Codable {
    let id: String
    var title: String
    var thumbnail: String?
    var editable: Bool
    var videos: Set<String>
    /// "title|artist" keys: the same song often exists as a song and as a video.
    var keys: Set<String>

    static func key(title: String, artist: String) -> String? {
        func norm(_ s: String) -> String {
            var out = s.lowercased()
            // Drop "(feat. …)", "[Official Video]" and similar decorations.
            for pattern in [#"\([^)]*\)"#, #"\[[^\]]*\]"#] {
                out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
            }
            return String(out.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        }
        let first = artist.replacingOccurrences(of: " ve ", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ",&")).first ?? artist
        let t = norm(title), a = norm(first)
        guard t.count >= 2, a.count >= 2 else { return nil }
        return t + "|" + a
    }
}

enum PlaylistPrivacy: String, CaseIterable, Identifiable {
    case PRIVATE, UNLISTED, PUBLIC
    var id: String { rawValue }
    var title: String {
        switch self {
        case .PRIVATE: return "Gizli"
        case .UNLISTED: return "Liste dışı"
        case .PUBLIC: return "Herkese açık"
        }
    }
    var icon: String {
        switch self {
        case .PRIVATE: return "lock.fill"
        case .UNLISTED: return "link"
        case .PUBLIC: return "globe"
        }
    }
}

struct BrowsePage: Codable {
    let header: PageHeader?
    let chips: [FilterChip]
    var sections: [Shelf]
    var continuation: String?
}

struct MoreResult: Codable {
    let items: [MediaItem]
    let continuation: String?
}

struct LibraryData: Codable {
    var playlists: [MediaItem]
    var albums: [MediaItem]
    var artists: [MediaItem]

    static let empty = LibraryData(playlists: [], albums: [], artists: [])
    var isEmpty: Bool { playlists.isEmpty && albums.isEmpty && artists.isEmpty }
}

struct LyricsData: Codable {
    let text: String?
    let source: String?
}

struct QueueEntry: Codable, Identifiable, Equatable {
    var index: Int
    let title: String
    let subtitle: String
    let duration: String
    let thumbnail: String?
    var selected: Bool
    let videoId: String?
    /// Set for entries that came from the watch API rather than the page's queue.
    var endpoint: String? = nil
    /// Large cover, artist / album links and rating (native queue only).
    var art: String? = nil
    var artists: [ArtistRef]? = nil
    var album: AlbumRef? = nil
    var like: String? = nil
    /// YouTube's kind of upload: MUSIC_VIDEO_TYPE_ATV (song), _OMV (music video), _UGC
    /// (user upload)…
    var videoType: String? = nil
    /// The other half of a song / music video pair, when YouTube Music offers one.
    var alt: [QueueEntry]? = nil
    var id: Int { index }
    /// Identity in lists that animate removals (the index shifts when a row goes).
    var rowKey: String { videoId ?? "\(index)-\(title)" }

    /// "3:45" / "1:02:03" → seconds.
    var seconds: Double {
        duration.split(separator: ":").reduce(0) { $0 * 60 + (Double($1) ?? 0) }
    }
}

/// A playback queue built by the app itself (no web player involved).
struct WatchQueue: Codable {
    let items: [QueueEntry]
    let current: Int
    let continuation: String?
    /// A radio or mix YouTube Music builds on its own (the app may arrange it).
    var radio: Bool? = nil
}

/// Videos and mixes from regular YouTube (home feed or "up next").
struct YouTubeFeed: Decodable {
    let items: [YouTubeVideo]
    /// Filtered to music by YouTube itself.
    let musicOnly: Bool
}

struct YouTubeVideo: Decodable {
    let item: MediaItem
    let channel: String
    let channelId: String?
    let seconds: Double
    let mix: Bool
    /// How long ago it was uploaded, in days (when YouTube shows it).
    let ageDays: Double?
    /// The channel's picture (when YouTube sends it).
    let avatar: String?
}

/// One entry of YouTube's notifications (the bell), see ytNotifications in bridge.js.
struct YouTubeNotification: Decodable {
    /// video (upload, premiere, live stream), short, comment, post, other.
    let kind: String
    let videoId: String?
    let title: String
    /// What comes before the title: "Tomorrowland yükledi".
    let lead: String
    let ageDays: Double?
    let ageText: String
    let read: Bool
    let thumbnail: String?
    let avatar: String?
}

struct NotificationFeed: Decodable {
    let items: [YouTubeNotification]
    /// Counts and field names only, for the diagnostic log.
    let summary: String
}

/// A video's channel and YouTube category (see ytVideoInfo in bridge.js).
struct YouTubeVideoInfo: Decodable {
    let channelId: String?
    let channel: String
    let category: String?
    let seconds: Double
}

/// A listening report started with YouTube (see trackStart in bridge.js).
struct ListenTicket: Decodable {
    let session: String?
}

struct BootInfo: Codable {
    let loggedIn: Bool
    let visitorData: String?
    let parsed: Bool
    let playerJs: String?
    let sts: Int?
}

/// Audio streams of one video, as YouTube Music's web player receives them.
/// As-you-type suggestions for the search field.
struct SearchSuggestions: Codable {
    struct Suggestion: Codable, Hashable {
        let text: String
        /// "history" (your recent searches), "music" (YouTube Music) or "youtube".
        let source: String
    }
    let suggestions: [Suggestion]
    /// Artists, songs, albums… YouTube Music offers for the text, with covers.
    let items: [MediaItem]
}

struct PlayerData: Codable {
    struct Format: Codable {
        let itag: Int
        let mimeType: String
        let bitrate: Int
        let averageBitrate: Int
        let url: String?
        let cipher: String?
        let approxDurationMs: String?
        /// Byte ranges [start, end] of the file's header and of its index.
        let initRange: [Int]?
        let indexRange: [Int]?
        let drc: Bool
        let isDefault: Bool
    }
    let status: String
    let reason: String
    let videoId: String?
    let length: Double
    let formats: [Format]
    let hls: String?
    let sabr: Bool
}

struct BylineLink: Codable, Hashable {
    let text: String
    let kind: String          // artist, album
    let id: String
}

/// The part of the player state that only changes when the track changes.
struct TrackInfo: Equatable {
    let videoId: String
    let title: String
    let artist: String
    let album: String
    let artwork: String?
    let duration: Double
    let links: [BylineLink]

    var artistLinks: [ArtistRef] {
        links.filter { $0.kind == "artist" }.map { ArtistRef(name: $0.text, id: $0.id) }
    }
    var albumLink: BylineLink? { links.first { $0.kind == "album" } }
}

struct TrackMeta: Codable, Equatable {
    let artists: [ArtistRef]
    let album: AlbumRef?
}

struct AccountInfo: Codable, Equatable {
    let name: String
    let handle: String
    let photo: String?
}
