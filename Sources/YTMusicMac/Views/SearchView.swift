import SwiftUI
import AppKit

/// Search results. The query lives in the centered toolbar field.
///
/// YouTube Music's combined ("All") search returns only a handful of items per type, so
/// the overview also runs the per-type searches (songs, artists, albums, playlists,
/// videos) in parallel and shows their full first pages. Filtered views page further
/// as you scroll.
struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var results: BrowsePage? = nil
    @ViewState var expanded: [ExpandedShelf] = []
    @ViewState var categories: BrowsePage? = nil
    @ViewState var chip: FilterChip? = nil
    @ViewState var chipItems: [MediaItem] = []
    @ViewState var chipToken: String? = nil
    @ViewState var loadingMore = false
    @ViewState var error: String? = nil
    @ViewState var lastQuery = ""
    /// When the search is an artist's name: that artist's popular songs, shown first under
    /// "Songs" (YouTube Music ranks by the text, so remixes naming the artist came first).
    @ViewState var artistSongs: [MediaItem] = []
    @ViewState var artistName = ""

    struct ExpandedShelf: Identifiable {
        let kind: Kind
        let title: String
        let section: Shelf
        var id: String { kind.rawValue + title }
    }

    enum Kind: String {
        /// `community`: playlists made by users. They join the playlists, after YouTube's
        /// and YouTube Music's own.
        case songs, videos, albums, artists, playlists, community, podcasts, hidden, other

        static func of(_ chipTitle: String) -> Kind {
            let t = chipTitle.lowercased(with: Locale(identifier: "tr_TR"))
            // YouTube profiles aren't offered.
            if t.contains("profil") { return .hidden }
            if t.contains("topluluk") || t.contains("community") { return .community }
            if t.contains("podcast") || t.contains("bölüm") || t.contains("episode") { return .podcasts }
            if t.contains("şarkı") || t.contains("song") { return .songs }
            if t.contains("video") { return .videos }
            if t.contains("albüm") || t.contains("album") { return .albums }
            if t.contains("sanatçı") || t.contains("artist") { return .artists }
            if t.contains("çalma") || t.contains("playlist") || t.contains("liste") { return .playlists }
            return .other
        }

        var order: Int {
            switch self {
            case .songs: return 0
            case .artists: return 1
            case .albums: return 2
            case .playlists: return 3
            case .community: return 3
            case .videos: return 4
            case .podcasts: return 5
            case .hidden, .other: return 6
            }
        }

        /// The row's title on the overview.
        var title: String {
            switch self {
            case .songs: return M.t("Şarkılar", "Songs")
            case .artists: return M.t("Sanatçılar", "Artists")
            case .albums: return M.t("Albümler", "Albums")
            case .playlists, .community: return M.t("Çalma listeleri", "Playlists")
            case .videos: return M.t("Videolar", "Videos")
            case .podcasts: return M.t("Podcast'ler", "Podcasts")
            case .hidden, .other: return ""
            }
        }
    }

    /// The filters shown: in a fixed order (songs, artists, albums, playlists, videos,
    /// podcasts), without profiles; "featured playlists" are just "playlists", and the
    /// community playlists are in it rather than a filter of their own.
    private var chips: [FilterChip] {
        (results?.chips ?? [])
            .map { c in (c, Kind.of(c.title)) }
            .filter { $0.1 != .hidden && $0.1 != .community }
            .enumerated()
            .sorted { ($0.element.1.order, $0.offset) < ($1.element.1.order, $1.offset) }
            .map { _, pair in
                let (c, kind) = pair
                return kind == .playlists
                    ? FilterChip(title: Kind.playlists.title, params: c.params, browseId: c.browseId, selected: c.selected)
                    : c
            }
    }

    private func chip(for kind: Kind) -> FilterChip? {
        chips.first { Kind.of($0.title) == kind }
    }

    /// What is searched for; a pasted link isn't (Enter opens it).
    private var query: String {
        let q = app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkRoute.pasted(q) == nil ? q : ""
    }
    private var searchKey: String { query + "|" + (chip?.params ?? "") + "|\(app.refreshToken)" }

    /// A whole overview (the combined results and the per-type shelves), kept in memory
    /// for the last few searches (PageCache).
    private struct Snapshot {
        let results: BrowsePage
        let expanded: [ExpandedShelf]
        let artistSongs: [MediaItem]
        let artistName: String
    }

    /// The artist the search names, if it is exactly an artist's name ("charlotte de witte").
    private static func namedArtist(_ query: String, _ page: BrowsePage, _ shelves: [ExpandedShelf]) -> MediaItem? {
        let key = QueueCurator.normalize(query)
        let candidates = page.sections.compactMap(\.top) + page.sections.flatMap(\.items)
            + shelves.filter { $0.kind == .artists }.flatMap(\.section.items)
        return candidates.first { $0.isArtist && $0.browseId != nil && QueueCurator.normalize($0.title) == key }
    }

    /// Songs with the artist's own first: their popular songs, then the results by them,
    /// then the rest (remixes and mentions), each song once.
    private static func artistFirst(_ popular: [MediaItem], _ found: [MediaItem], artist: String) -> [MediaItem] {
        guard !popular.isEmpty else { return found }
        let key = QueueCurator.normalize(artist)
        func byArtist(_ i: MediaItem) -> Bool { i.artists.contains { QueueCurator.normalize($0.name) == key } }
        var seen = Set<String>()
        var out: [MediaItem] = []
        for i in popular + found.filter(byArtist) + found.filter({ !byArtist($0) }) {
            if seen.insert(i.videoId ?? i.id).inserted { out.append(i) }
        }
        return out
    }

    var body: some View {
        ScrollView {
            // Lazy: shelves far below the window are built (and their covers loaded) only
            // when scrolled to, instead of all at once.
            LazyVStack(alignment: .leading, spacing: d.sectionGap) {
                if query.isEmpty {
                    browseAll
                } else {
                    resultsView
                }
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle(query.isEmpty ? M.t("Ara", "Search") : "“\(query)”")
        .pageChrome()
        .task(id: searchKey) { await runSearch() }
        .task { await loadCategories() }
    }

    // MARK: Browse

    @ViewBuilder
    private var browseAll: some View {
        if let categories {
            ForEach(categories.sections) { s in
                if s.layout == "nav" { CategoryGrid(section: s) } else { ShelfView(section: s) }
            }
        } else {
            PageSkeleton(layout: .tiles)
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsView: some View {
        FilterChips(chips: chips, selected: chip) { chip = $0 }
        if let results {
            if chip == nil {
                overview(results)
            } else {
                filteredList
            }
            if results.sections.isEmpty && chipItems.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: M.t("Sonuç yok", "No results"),
                               message: M.t("“\(query)” için bir şey bulunamadı.", "Nothing found for “\(query)”."))
            }
        } else if let error {
            ErrorView(message: error) { Task { await runSearch() } }
        } else {
            PageSkeleton(layout: .search)
        }
    }

    @ViewBuilder
    private var filteredList: some View {
        let tracks = chipItems.contains { $0.isTrack }
        if tracks {
            TrackList(items: chipItems, numbered: false, showArtwork: true, showAlbum: true,
                      onReachEnd: { loadMoreFiltered() })
                .padding(.horizontal, d.pad)
        } else {
            CardGrid(items: chipItems)
        }
        if loadingMore {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if chipToken != nil && !tracks {
            Button(M.t("Daha Fazla Göster", "Show More")) { loadMoreFiltered() }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func overview(_ page: BrowsePage) -> some View {
        // What the user said not to recommend leaves every part of the page at once.
        let hidden = app.hiddenKeys
        let keep: (MediaItem) -> Bool = { !hidden.contains($0.recommendationKey) }
        let top = page.sections.first { $0.layout == "top" }
        let songShelf = expanded.first { $0.kind == .songs }?.section
            ?? page.sections.first { $0.layout == "list" && $0.hasTracks }
        let ytTop = top?.top.flatMap { keep($0) ? $0 : nil }
        // The top result is always an official artist or channel: YouTube Music's own pick
        // when it is one, else the first artist among the results.
        let topItem = (ytTop?.isArtist == true ? ytTop : nil)
            ?? page.sections.lazy.flatMap(\.items).first(where: { $0.isArtist && keep($0) })
            ?? expanded.first(where: { $0.kind == .artists })?.section.items.first(where: { $0.isArtist && keep($0) })
            ?? ytTop
        let headSongs = Array((artistSongs.isEmpty ? (songShelf?.items ?? top?.items ?? []) : artistSongs)
            .filter { $0.isTrack && keep($0) && !Self.same($0, topItem) }
            .prefix(4))
        // What's already shown above doesn't come again in the rows below.
        let shownAbove = Set(headSongs.map(\.id))
        let shelves = Dictionary(expanded.map { ($0.kind, $0.section.items) }, uniquingKeysWith: { a, _ in a })
        let artists = Array((shelves[.artists] ?? []).filter { $0.isArtist && !Self.same($0, topItem) }.prefix(2))
        let albums = (shelves[.albums] ?? []).filter { !Self.same($0, topItem) }
        let playlists = Self.officialFirst((shelves[.playlists] ?? []) + (shelves[.community] ?? []))
            .filter { !Self.same($0, topItem) }
        let videos = (shelves[.videos] ?? []).filter { !Self.same($0, topItem) && !shownAbove.contains($0.id) }.map(\.asWide)

        if topItem != nil || !headSongs.isEmpty {
            VStack(alignment: .leading, spacing: d.v(8, 10)) {
                // Titles on one baseline row, content boxes below share top and bottom edges.
                HStack(alignment: .firstTextBaseline, spacing: d.v(16, 24)) {
                    if topItem != nil {
                        SectionTitle(title: M.t("En iyi sonuç", "Top result")).frame(width: d.topResult, alignment: .leading)
                    }
                    if !headSongs.isEmpty {
                        SectionTitle(title: Kind.songs.title, action: chip(for: .songs).map { c in { chip = c } })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(alignment: .top, spacing: d.v(16, 24)) {
                    if let item = topItem {
                        TopResultCard(item: item)
                            .frame(width: d.topResult)
                            .frame(maxHeight: .infinity)
                    }
                    if !headSongs.isEmpty {
                        TrackList(items: headSongs, numbered: false, showArtwork: true, showAlbum: false, showHeader: false)
                            .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, d.pad)
        }

        if expanded.isEmpty {
            // Per-type searches still loading (or unavailable): the combined shelves.
            ForEach(page.sections.filter { s in
                s.id != top?.id && s.id != songShelf?.id && Kind.of(s.title) != .hidden
            }) { s in
                if s.hasTracks {
                    TrackListSection(section: s, limit: 4)
                } else {
                    CardCarousel(section: s)
                }
            }
        } else {
            // A search is mostly about one artist, who is the top result: the other artists
            // (two at most) and the albums share a row, the albums scrolling sideways.
            if !artists.isEmpty || !albums.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    if !artists.isEmpty {
                        VStack(alignment: .leading, spacing: d.v(8, 10)) {
                            SectionTitle(title: Kind.artists.title, action: chip(for: .artists).map { c in { chip = c } })
                            HStack(alignment: .top, spacing: d.cardGap) {
                                ForEach(artists) { a in ItemCard(item: a, width: d.card) }
                            }
                        }
                        .padding(.leading, d.pad)
                        .fixedSize()
                    }
                    if !albums.isEmpty {
                        row(.albums, albums)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            row(.playlists, playlists)
            row(.videos, videos)
        }
    }

    /// A row of cards with its title; "Show all" switches to that filter.
    @ViewBuilder
    private func row(_ kind: Kind, _ items: [MediaItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: d.v(8, 10)) {
                SectionTitle(title: kind.title, action: chip(for: kind).map { c in { chip = c } })
                    .padding(.horizontal, d.pad)
                CardCarousel(section: Shelf(id: "search-\(kind.rawValue)", title: "", strapline: nil, layout: "cards",
                                            items: items, more: nil, continuation: nil, top: nil))
            }
        }
    }

    /// Playlists from YouTube and YouTube Music first, then those users made; each once.
    private static func officialFirst(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.recommendationKey).inserted }
        func official(_ i: MediaItem) -> Bool {
            i.subtitle.components(separatedBy: " • ").contains { part in
                let p = part.trimmingCharacters(in: .whitespaces).lowercased()
                return p == "youtube music" || p == "youtube"
            }
        }
        return unique.filter(official) + unique.filter { !official($0) }
    }

    /// Whether two results are the same thing (the top result also comes in its own row).
    private static func same(_ a: MediaItem, _ b: MediaItem?) -> Bool {
        guard let b else { return false }
        if let v = a.videoId, v == b.videoId { return true }
        if let id = a.browseId, id == b.browseId { return true }
        return a.id == b.id
    }

    // MARK: Loading

    private func runSearch() async {
        let q = query
        guard !q.isEmpty else { results = nil; expanded = []; return }
        if q != lastQuery {
            lastQuery = q
            if chip != nil { chip = nil; return }   // the key change re-runs the task
        }
        // A search made a moment ago shows at once; past its lifetime it is run again
        // behind the results, which then change in place.
        let cacheKey = PageCache.search(q)
        var refreshing = false
        if chip == nil, let kept = PageCache.shared.value(cacheKey, as: Snapshot.self) {
            results = kept.results
            expanded = kept.expanded
            artistSongs = kept.artistSongs
            artistName = kept.artistName
            chipItems = []
            chipToken = nil
            error = nil
            if PageCache.shared.isFresh(cacheKey) { return }
            refreshing = true
        } else if chip == nil {
            // A new search: the loading preview until everything has come, then the whole
            // page at once (no rows dropping in, no top result changing afterwards).
            results = nil
            expanded = []
            artistSongs = []
            artistName = ""
        }
        do { try await Task.sleep(nanoseconds: 280_000_000) } catch { return }   // debounce typing
        error = nil
        let engine = app.engine
        do {
            let r = try await engine.search(q, params: chip?.params)
            guard !Task.isCancelled else { return }
            if chip != nil {
                let main = r.sections.first { $0.layout != "top" && !$0.items.isEmpty }
                var found = main?.items ?? []
                var token = main?.continuation
                // "Playlists": YouTube's and YouTube Music's own, then the ones users made
                // ("Show more" goes on with the users' ones).
                if Kind.of(chip?.title ?? "") == .playlists,
                   let community = (results?.chips ?? r.chips).first(where: { Kind.of($0.title) == .community }),
                   let page = try? await engine.search(q, params: community.params),
                   let shelf = page.sections.first(where: { $0.layout != "top" && !$0.items.isEmpty }) {
                    guard !Task.isCancelled else { return }
                    found = Self.officialFirst(found + shelf.items)
                    token = shelf.continuation
                }
                chipItems = Kind.of(chip?.title ?? "") == .songs
                    ? Self.artistFirst(artistSongs, found, artist: artistName) : found
                chipToken = token
                if results == nil { results = r }
                return
            }
            chipItems = []
            chipToken = nil

            // Fan out the per-type searches.
            var wanted: [(Kind, FilterChip)] = []
            for c in r.chips where c.params != nil {
                let k = Kind.of(c.title)
                if ![.other, .hidden, .podcasts].contains(k) { wanted.append((k, c)) }
            }
            // An artist named in the search: their popular songs, asked for alongside.
            let named = Self.namedArtist(q, r, [])
            let app = self.app
            let popularTask = named?.browseId.map { id in Task { await app.popularSongs(artistId: id) } }
            // All at the same time; the page shows once every one has answered.
            let collected: [ExpandedShelf] = await withTaskGroup(of: ExpandedShelf?.self) { group in
                for (kind, c) in wanted {
                    group.addTask {
                        guard let page = try? await engine.search(q, params: c.params),
                              let shelf = page.sections.first(where: { $0.layout != "top" && !$0.items.isEmpty })
                        else { return nil }
                        return ExpandedShelf(kind: kind, title: c.title, section: shelf)
                    }
                }
                var out: [ExpandedShelf] = []
                for await e in group { if let e { out.append(e) } }
                return out
            }
            guard !Task.isCancelled, q == query else { return }
            let all = collected.sorted { $0.kind.order < $1.kind.order }
            // The artist may only show in the artists' search.
            let artist = named ?? Self.namedArtist(q, r, all)
            var popular = await popularTask?.value ?? []
            if popularTask == nil, let id = artist?.browseId { popular = await app.popularSongs(artistId: id) }
            guard !Task.isCancelled, q == query else { return }
            artistSongs = popular
            artistName = artist?.title ?? ""
            if refreshing {
                // Behind a kept page: it changes only if the answer did, all in one go.
                let changed = !(results?.sameContent(as: r) ?? false)
                    || all.map(\.section.contentKey) != expanded.map(\.section.contentKey)
                if changed {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        results = r
                        expanded = all
                    }
                }
            } else {
                results = r
                expanded = all
            }
            PageCache.shared.store(Snapshot(results: r, expanded: all, artistSongs: popular, artistName: artist?.title ?? ""),
                                   for: cacheKey, lifetime: PageCache.Lifetime.search)
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }

    private func loadMoreFiltered() {
        guard let token = chipToken, !loadingMore else { return }
        loadingMore = true
        Task {
            defer { loadingMore = false }
            if let r = try? await app.engine.searchMore(token) {
                let known = Set(chipItems.map(\.id))
                chipItems.append(contentsOf: r.items.filter { !known.contains($0.id) })
                chipToken = r.items.isEmpty ? nil : r.continuation
            } else {
                chipToken = nil
            }
        }
    }

    private func loadCategories() async {
        guard categories == nil else { return }
        categories = try? await app.page(for: BrowseTarget(browseId: "FEmusic_moods_and_genres", params: nil, kind: "browse", title: nil))
    }
}

struct TopResultCard: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.density) private var d

    var body: some View {
        let cover = d.v(92, 112)
        VStack(alignment: .leading, spacing: d.v(12, 16)) {
            Artwork(url: item.thumbnail, cornerRadius: 8,
                    placeholder: item.isArtist ? "person.fill" : "music.note")
                .frame(width: cover, height: cover)
                .cardShadow(cornerRadius: 8, opacity: 0.2, radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: d.v(22, 26), weight: .bold))
                        .lineLimit(2)
                    if item.explicit { ExplicitBadge() }
                }
                HStack(spacing: 8) {
                    // What it is, as a small tag (Spotify's "Artist" / "Song" pill).
                    Text(item.typeLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                    if !item.isArtist, !item.bylineText.isEmpty {
                        Text(item.bylineText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(d.v(14, 18))
        .frame(maxWidth: .infinity, minHeight: d.v(160, 210), maxHeight: .infinity, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack {
                shape.fill(Color.primary.opacity(hover ? 0.09 : 0.05))
                // The accent colour chosen in Settings and two neighbours of it: a diagonal
                // blend and a soft glow in two corners; a little stronger in dark mode.
                let tones = Self.tones(of: Color.brand)
                let k: Double = scheme == .dark ? 1.25 : 0.85
                shape.fill(LinearGradient(colors: [tones.0.opacity(0.30 * k), tones.1.opacity(0.18 * k), tones.2.opacity(0.10 * k)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.fill(RadialGradient(colors: [tones.1.opacity(0.24 * k), .clear],
                                          center: .topTrailing, startRadius: 0, endRadius: 260))
                shape.fill(RadialGradient(colors: [tones.2.opacity(0.18 * k), .clear],
                                          center: .bottomLeading, startRadius: 0, endRadius: 220))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hover {
                // An artist: their popular songs.
                PlayCircle(size: 44) {
                    if item.isArtist, let id = item.browseId { app.playPopular(artistId: id) } else { app.play(item) }
                }
                .help(item.isArtist ? M.t("Popüler şarkılarını çal", "Play their popular songs") : M.t("Çal", "Play"))
                .padding(16)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

private extension TopResultCard {
    /// A colour and two neighbours of it: the hue turned a little each way, one lighter,
    /// one deeper.
    static func tones(of color: Color) -> (Color, Color, Color) {
        guard let c = NSColor(color).usingColorSpace(.deviceRGB) else { return (color, color, color) }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        func turned(_ by: CGFloat) -> CGFloat { (h + by + 1).truncatingRemainder(dividingBy: 1) }
        return (color,
                Color(hue: turned(0.07), saturation: min(1, s * 1.05), brightness: min(1, b * 1.15)),
                Color(hue: turned(-0.07), saturation: s * 0.9, brightness: b * 0.8))
    }
}
