import Foundation

/// Where a pasted YouTube Music or YouTube link leads. Most links are read here; the rest
/// (handles such as youtube.com/@name, podcast addresses) are asked of YouTube (`resolve`).
enum LinkRoute: Equatable {
    /// A song, video or episode, played (inside its list when the link names one).
    case watch(videoId: String, list: String?)
    /// A playlist's page (the id without "VL").
    case playlist(String)
    /// A YouTube Mix or radio ("RD…"): played, as it has no page of its own.
    case mix(String)
    /// An album, artist, podcast or other page.
    case browse(id: String, kind: String)
    case search(String)
    /// A YouTube link the app doesn't read itself.
    case resolve(String)

    private static let videoID = "^[A-Za-z0-9_-]{11}$"

    static func parse(_ raw: String) -> LinkRoute? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        // A bare video id ("dQw4w9WgXcQ").
        if text.range(of: videoID, options: .regularExpression) != nil { return .watch(videoId: text, list: nil) }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text), var host = url.host?.lowercased() else { return nil }
        for prefix in ["www.", "m."] where host.hasPrefix(prefix) { host = String(host.dropFirst(prefix.count)) }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first })
        let parts = url.pathComponents.filter { $0 != "/" }

        if host == "youtu.be" {
            guard let id = parts.first, id.range(of: videoID, options: .regularExpression) != nil else { return nil }
            return .watch(videoId: id, list: query["list"])
        }
        guard host == "youtube.com" || host == "music.youtube.com" else { return nil }

        let list = query["list"].flatMap { $0.isEmpty ? nil : $0 }
        switch parts.first ?? "" {
        case "watch":
            if let v = query["v"], v.range(of: videoID, options: .regularExpression) != nil {
                return .watch(videoId: v, list: list)
            }
            return list.map(forPlaylist)
        case "shorts", "live", "embed":
            guard parts.count > 1, parts[1].range(of: videoID, options: .regularExpression) != nil else { return nil }
            return .watch(videoId: parts[1], list: nil)
        case "playlist":
            guard let list else { return nil }
            // An album's own playlist ("OLAK5uy…"): YouTube says which album it is.
            return list.hasPrefix("OLAK5uy") ? .resolve(url.absoluteString) : forPlaylist(list)
        case "browse":
            guard parts.count > 1 else { return nil }
            return forPage(parts[1], pageType: nil)
        case "channel":
            guard parts.count > 1, parts[1].hasPrefix("UC") else { return .resolve(url.absoluteString) }
            return .browse(id: parts[1], kind: "artist")
        case "search", "results":
            guard let q = query["q"] ?? query["search_query"], !q.isEmpty else { return nil }
            return .search(q)
        case "":
            return nil
        default:
            return .resolve(url.absoluteString)
        }
    }

    /// A playlist id: a page, or a mix to play.
    static func forPlaylist(_ id: String) -> LinkRoute {
        let plain = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        return plain.hasPrefix("RD") ? .mix(plain) : .playlist(plain)
    }

    /// A page by its id (and YouTube's page type, when known).
    static func forPage(_ id: String, pageType: String?) -> LinkRoute {
        if id.hasPrefix("VL") { return forPlaylist(id) }
        switch pageType ?? "" {
        case "MUSIC_PAGE_TYPE_ALBUM", "MUSIC_PAGE_TYPE_AUDIOBOOK": return .browse(id: id, kind: "album")
        case "MUSIC_PAGE_TYPE_PLAYLIST": return forPlaylist(id)
        case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL": return .browse(id: id, kind: "artist")
        case "MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE": return .browse(id: id, kind: "podcast")
        default: break
        }
        if id.hasPrefix("MPRE") { return .browse(id: id, kind: "album") }
        if id.hasPrefix("MPSP") { return .browse(id: id, kind: "podcast") }
        if id.hasPrefix("UC") { return .browse(id: id, kind: "artist") }
        return .browse(id: id, kind: "browse")
    }

    /// A link typed or pasted into the search field: only a real YouTube address counts
    /// there (an 11-letter word is a search, not a video id).
    static func pasted(_ text: String) -> LinkRoute? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t.contains("youtu"), !t.contains(" ") else { return nil }
        return parse(text)
    }

    /// What the link opens, shown in the search field's tag before Enter.
    var label: String {
        switch self {
        case .watch: return M.t("Çal", "Play")
        case .playlist: return M.t("Çalma listesi", "Playlist")
        case .mix: return M.t("Mix'i çal", "Play mix")
        case .browse(_, let kind):
            switch kind {
            case "album": return M.t("Albüm", "Album")
            case "artist": return M.t("Sanatçı ya da kanal", "Artist or channel")
            case "podcast": return "Podcast"
            default: return M.t("Sayfa", "Page")
            }
        case .search: return M.t("Ara", "Search")
        case .resolve: return M.t("Bağlantıyı aç", "Open link")
        }
    }
}

/// What YouTube says a link leads to (bridge `resolveLink`).
struct ResolvedLink: Decodable {
    let videoId: String?
    let playlistId: String?
    let browseId: String?
    let pageType: String?

    var route: LinkRoute? {
        if let v = videoId { return .watch(videoId: v, list: playlistId) }
        if let b = browseId { return LinkRoute.forPage(b, pageType: pageType) }
        if let p = playlistId { return LinkRoute.forPlaylist(p) }
        return nil
    }
}
