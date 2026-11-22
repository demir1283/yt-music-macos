import SwiftUI
import Observation

struct BrowseTarget: Hashable {
    var browseId: String
    var params: String?
    var kind: String
    var title: String?
    /// Set on an artist's popular songs list: the page gets a made cover with the artist's
    /// name ("<Artist> · Popüler şarkılar") instead of a picture.
    var coverArtist: String? = nil

    static let likedSongs = BrowseTarget(browseId: "VLLM", params: nil, kind: "playlist", title: M.t("Beğenilen Müzikler", "Liked Music"))
}

/// Top-level destinations in the sidebar.
enum SidebarItem: Hashable {
    case search
    case home
    case explore
    case charts
    case moods
    case newReleases
    case podcasts
    case library
    case liked
    case history
    case playlist(BrowseTarget)

    var title: String {
        switch self {
        case .search: return M.t("Ara", "Search")
        case .home: return M.t("Ana Sayfa", "Home")
        case .explore: return M.t("Keşfet", "Explore")
        case .charts: return M.t("Listeler", "Charts")
        case .moods: return M.t("Ruh Hali ve Türler", "Moods & Genres")
        case .newReleases: return M.t("Yeni Çıkanlar", "New Releases")
        case .podcasts: return M.t("Podcast'ler", "Podcasts")
        case .library: return M.t("Kitaplık", "Library")
        case .liked: return M.t("Beğenilen Müzikler", "Liked Music")
        case .history: return M.t("Geçmiş", "History")
        case .playlist(let t): return t.title ?? M.t("Çalma Listesi", "Playlist")
        }
    }

    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .home: return "house"
        case .explore: return "globe"
        case .charts: return "chart.line.uptrend.xyaxis"
        case .moods: return "theatermasks"
        case .newReleases: return "sparkles"
        case .podcasts: return "mic"
        case .library: return "square.stack"
        case .liked: return "heart.fill"
        case .history: return "clock.arrow.circlepath"
        case .playlist: return "music.note.list"
        }
    }

    /// Generic YouTube Music browse page behind this item, if any.
    var browseTarget: BrowseTarget? {
        switch self {
        case .explore: return BrowseTarget(browseId: "FEmusic_explore", params: nil, kind: "browse", title: title)
        case .charts: return BrowseTarget(browseId: "FEmusic_charts", params: nil, kind: "browse", title: title)
        case .moods: return BrowseTarget(browseId: "FEmusic_moods_and_genres", params: nil, kind: "browse", title: title)
        case .newReleases: return BrowseTarget(browseId: "FEmusic_new_releases", params: nil, kind: "browse", title: title)
        case .podcasts: return BrowseTarget(browseId: "FEmusic_podcasts", params: nil, kind: "browse", title: title)
        case .history: return BrowseTarget(browseId: "FEmusic_history", params: nil, kind: "browse", title: title)
        case .liked: return .likedSongs
        case .playlist(let t): return t
        default: return nil
        }
    }
}

enum PanelMode: Hashable {
    case nowPlaying
    case lyrics
    case queue
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case playlists, albums, artists
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playlists: return M.t("Çalma Listeleri", "Playlists")
        case .albums: return M.t("Albümler", "Albums")
        case .artists: return M.t("Sanatçılar", "Artists")
        }
    }
}

/// UI-level state: sidebar selection, navigation stack, side panels, search text.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let engine: YTMusic

    var section: SidebarItem = .home
    var path: [BrowseTarget] = []
    /// Dominant colour of the current artwork (panel + player bar take it on).
    var artTint: Color = .clear
    var panelVisible = true
    /// Lyrics section inside the side panel (toggled from the player bar).
    var showLyrics = true
    /// The Ayarlar sheet.
    var showSettings = false
    /// "Çalma listesine ekle" sheet for this song.
    var addToPlaylistTarget: PlaylistTarget?
    /// "Yeni çalma listesi" / "Çalma listesini düzenle" sheet.
    var playlistEditor: PlaylistEditorMode?
    var libraryFilter: LibraryFilter = .playlists
    var searchQuery = ""
    var searchFocusToken = 0
    /// Recommendations the user asked not to see ("Beğenmedim", "Bana önerme"): they leave
    /// every page at once and stay out of the home page.
    private(set) var hiddenKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenRecommendations") ?? [])

    func hide(_ item: MediaItem) {
        withAnimation(.soft) {
            _ = hiddenKeys.insert(item.recommendationKey)
        }
        UserDefaults.standard.set(Array(hiddenKeys.prefix(1000)), forKey: "hiddenRecommendations")
    }

    /// "Bana önerme" on a song in "Sıradaki": out of the queue at once (the engine's
    /// dislike takes it out of this and every later queue), and off every page.
    func notInterested(_ entry: QueueEntry) {
        guard let v = entry.videoId else { return }
        withAnimation(.soft) {
            engine.rate(videoId: v, status: "DISLIKE")
            _ = hiddenKeys.insert(v)
        }
        UserDefaults.standard.set(Array(hiddenKeys.prefix(1000)), forKey: "hiddenRecommendations")
    }

    func unhide(_ item: MediaItem) {
        withAnimation(.soft) { _ = hiddenKeys.remove(item.recommendationKey) }
        UserDefaults.standard.set(Array(hiddenKeys), forKey: "hiddenRecommendations")
    }


    private init() {
        engine = YTMusic.shared
        // Cards ignore the pointer while a page scrolls under it (see ScrollAwareHover).
        ScrollActivity.start()
        AudioOutputs.shared.start()
    }

    // MARK: Navigation

    /// Bumped when "Ana Sayfa" is clicked while already there: back to the "Tümü" chip.
    var homeResetToken = 0

    func select(_ item: SidebarItem) {
        if item == .home && section == .home { homeResetToken += 1 }
        // Leaving the search page clears the search field (opening a result keeps it, so
        // Back returns to the same results).
        if section == .search && item != .search { searchQuery = "" }
        section = item
        path = []
    }

    func push(_ target: BrowseTarget) {
        if path.last == target { return }
        path.append(target)
    }

    func back() {
        if !path.isEmpty { path.removeLast() }
    }

    /// What a click on a cover does, everywhere in the app: it opens the item's page — an
    /// artist's, an album's, a playlist's; a song opens its album, an artist's radio the
    /// artist. A song or video without a known album is looked up on YouTube Music: its
    /// album, else its artist's or channel's page. Only mixes (no page at all) play.
    /// Playing is the play button's job.
    func open(_ item: MediaItem) {
        if item.kind == "artistradio", let id = item.browseId, id.hasPrefix("UC") {
            openArtist(id)
            return
        }
        // Mixes (the app's artist mixes, YouTube Mixes) have no page: they start playing.
        if item.kind == "mix" || item.kind == "artistradio" {
            play(item)
            return
        }
        // Songs and videos: their album. (Some carry a channel/browse id too, which would
        // open an empty page.)
        if item.isTrack && ["song", "video", "unknown"].contains(item.kind), let vid = item.videoId {
            if let album = item.album?.id {
                openAlbum(album)
                return
            }
            Task {
                let meta = await engine.lookUpTrack(vid)
                if let album = meta?.album?.id {
                    openAlbum(album)
                } else if let artist = (item.artists + (meta?.artists ?? [])).first(where: { $0.id.hasPrefix("UC") }) {
                    openArtist(artist.id)
                } else {
                    play(item)
                }
            }
        } else if item.isTrack && item.kind == "episode" {
            play(item)
        } else if let id = item.browseId, id.hasPrefix("MPED") {
            // Episode page: nothing to show there, play the episode itself.
            let vid = String(id.dropFirst(4))
            engine.play(endpoint: item.play ?? watchEndpoint(videoId: vid, playlistId: nil), context: nil)
        } else if let id = item.browseId {
            push(BrowseTarget(browseId: id, params: item.params, kind: item.kind, title: item.title))
        } else if item.isTrack {
            play(item)
        }
    }

    func openArtist(_ id: String) {
        push(BrowseTarget(browseId: id, params: nil, kind: "artist", title: nil))
    }

    func openAlbum(_ id: String) {
        push(BrowseTarget(browseId: id, params: nil, kind: "album", title: nil))
    }

    func openMore(_ more: MoreLink, title: String, artist: String? = nil) {
        if let id = more.browseId {
            let kind: String
            switch more.pageType ?? "" {
            case "MUSIC_PAGE_TYPE_ALBUM": kind = "album"
            case "MUSIC_PAGE_TYPE_PLAYLIST": kind = "playlist"
            case "MUSIC_PAGE_TYPE_ARTIST", "MUSIC_PAGE_TYPE_USER_CHANNEL": kind = "artist"
            default: kind = "browse"
            }
            push(BrowseTarget(browseId: id, params: more.params, kind: kind, title: title, coverArtist: artist))
        } else if let q = more.query {
            searchQuery = q
            select(.search)
        }
    }

    func focusSearch() {
        select(.search)
        searchFocusToken += 1
    }

    func toggleLyrics() {
        guard LyricsCenter.shared.available(for: engine.track?.videoId) else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            if !panelVisible {
                panelVisible = true
                showLyrics = true
            } else {
                showLyrics.toggle()
            }
        }
    }

    func togglePanel() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { panelVisible.toggle() }
    }

    var isPanelVisible: Bool {
        get { panelVisible }
        set { panelVisible = newValue }
    }

    // MARK: Playback

    func play(_ item: MediaItem, context: String? = nil) {
        // An artist's radio (home page stations): YouTube Music's own radio for the artist.
        if item.kind == "artistradio", let id = item.browseId {
            Task {
                guard let page = try? await engine.browse(id, params: nil),
                      let ep = page.header?.radio ?? page.header?.shuffle ?? page.header?.play else { return }
                engine.play(endpoint: ep, context: nil)
            }
            return
        }
        if let ep = item.play {
            engine.play(endpoint: ep, context: context, seed: item)
        } else if let videoId = item.videoId {
            engine.play(endpoint: watchEndpoint(videoId: videoId, playlistId: context), context: nil, seed: item)
        } else if let pl = item.playlistId {
            engine.play(endpoint: watchPlaylistEndpoint(pl), context: nil)
        } else if let id = item.browseId {
            // Album / artist without a direct play endpoint: load the page and play from it.
            Task {
                guard let page = try? await engine.browse(id, params: item.params) else { return }
                if let ep = page.header?.play ?? page.header?.shuffle {
                    engine.play(endpoint: ep, context: nil)
                } else if let first = page.sections.flatMap(\.items).first(where: { $0.isTrack }), let ep = first.play {
                    engine.play(endpoint: ep, context: nil)
                }
            }
        }
    }

    /// An artist's popular songs, from the top: the full list behind "Popular songs" on the
    /// artist page (a playlist), or that list's first song, or the page's own play button.
    func playPopular(artistId: String) {
        Task {
            guard let artist = try? await self.page(for: BrowseTarget(browseId: artistId, params: nil, kind: "artist", title: nil))
            else { return }
            let songs = artist.sections.first { $0.layout == "list" && $0.hasTracks }
            if let list = songs?.more?.browseId, list.hasPrefix("VL") {
                engine.play(endpoint: watchPlaylistEndpoint(String(list.dropFirst(2))), context: nil)
            } else if let first = songs?.items.first(where: { $0.isTrack }) {
                play(first)
            } else if let ep = artist.header?.play ?? artist.header?.shuffle {
                engine.play(endpoint: ep, context: nil)
            }
        }
    }

    /// An artist's popular songs: the full list behind "Popular songs" on their page, or
    /// the few the page shows. Pages come from memory when recently opened.
    func popularSongs(artistId: String) async -> [MediaItem] {
        guard let artist = try? await page(for: BrowseTarget(browseId: artistId, params: nil, kind: "artist", title: nil))
        else { return [] }
        let songs = artist.sections.first { $0.layout == "list" && $0.hasTracks }
        if let list = songs?.more?.browseId, list.hasPrefix("VL"),
           let full = try? await page(for: BrowseTarget(browseId: list, params: nil, kind: "playlist", title: nil)) {
            let tracks = full.sections.flatMap(\.items).filter(\.isTrack)
            if !tracks.isEmpty { return tracks }
        }
        return songs?.items.filter(\.isTrack) ?? []
    }

    func shuffle(_ item: MediaItem) {
        if let pl = item.playlistId {
            engine.play(endpoint: watchPlaylistEndpoint(pl, params: "wAEB"), context: nil)
        } else {
            play(item)
        }
    }

    func addToPlaylist(_ item: MediaItem) {
        guard let v = item.videoId else { return }
        addToPlaylistTarget = PlaylistTarget(videoId: v, title: item.title,
                                       subtitle: item.artists.map(\.name).joined(separator: ", "), thumbnail: item.thumbnail)
    }

    func addCurrentToPlaylist() {
        guard let t = engine.track else { return }
        addToPlaylistTarget = PlaylistTarget(videoId: t.videoId, title: t.title, subtitle: t.artist, thumbnail: t.artwork)
    }

    func startRadio(_ item: MediaItem) {
        guard let v = item.videoId else { return }
        engine.play(endpoint: watchEndpoint(videoId: v, playlistId: "RDAMVM" + v), context: nil)
    }

    // MARK: Data

    /// YouTube Music no longer serves "FEmusic_podcasts" (404). Try the podcasts page ids
    /// it uses now, then fall back to the home page's own "Podcast'ler" chip — the same
    /// feed the website shows for podcasts.
    private func podcastsPage() async throws -> BrowsePage {
        for id in ["FEmusic_non_music_audio", "FEmusic_podcasts"] {
            if let p = try? await engine.browse(id, params: nil), !p.sections.isEmpty { return p }
        }
        let home = try await engine.home(params: nil)
        let tr = Locale(identifier: "tr_TR")
        if let chip = home.chips.first(where: { $0.title.lowercased(with: tr).contains("podcast") }),
           chip.params != nil || chip.browseId != nil {
            return try await engine.home(params: chip.params, browseId: chip.browseId)
        }
        throw EngineError.js(M.t("Bu hesapta podcast sayfası bulunamadı.", "No podcast page was found for this account."))
    }

    /// The page from memory while it is current (see PageCache), otherwise fetched again.
    /// `force`: fetch it in any case.
    func page(for target: BrowseTarget, force: Bool = false) async throws -> BrowsePage {
        let key = PageCache.page(target)
        let cache = PageCache.shared
        if !force, cache.isFresh(key), let kept = cache.value(key, as: BrowsePage.self) { return kept }
        let page = target.browseId == "FEmusic_podcasts"
            ? try await podcastsPage()
            : try await engine.browse(target.browseId, params: target.params)
        cache.store(page, for: key, lifetime: PageCache.lifetime(for: target, page))
        return page
    }

    /// The page kept in memory, current or not (shown at once while a newer one loads).
    func keptPage(for target: BrowseTarget) -> BrowsePage? {
        PageCache.shared.value(PageCache.page(target), as: BrowsePage.self)
    }

    // MARK: Refresh (⌘R)

    /// Bumped by "Yenile": the page on screen fetches itself again.
    var refreshToken = 0

    func refresh() {
        let cache = PageCache.shared
        if let top = path.last {
            let key = PageCache.page(top)
            cache.markStale { $0 == key }
        } else if section == .home {
            cache.markStale { $0.hasPrefix("home|") }
        } else if section == .search {
            cache.markStale { $0.hasPrefix("search|") }
        } else if section == .library {
            Task { await engine.loadLibrary() }
        } else if let t = section.browseTarget {
            let key = PageCache.page(t)
            cache.markStale { $0 == key }
        }
        refreshToken += 1
    }
}

/// The song being added to a playlist.
struct PlaylistTarget: Identifiable {
    let videoId: String
    let title: String
    let subtitle: String
    let thumbnail: String?
    var id: String { videoId }
}

enum PlaylistEditorMode: Identifiable {
    /// New playlist, optionally starting with a song.
    case create(firstVideoId: String?)
    case edit(playlistId: String, title: String, description: String, privacy: PlaylistPrivacy)

    var id: String {
        switch self {
        case .create(let v): return "create-\(v ?? "")"
        case .edit(let id, _, _, _): return "edit-\(id)"
        }
    }
}
