import SwiftUI

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

    struct ExpandedShelf: Identifiable {
        let kind: Kind
        let title: String
        let section: Shelf
        var id: String { kind.rawValue + title }
    }

    enum Kind: String {
        case songs, videos, albums, artists, playlists, other

        static func of(_ chipTitle: String) -> Kind {
            let t = chipTitle.lowercased(with: Locale(identifier: "tr_TR"))
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
            case .videos: return 4
            case .other: return 5
            }
        }
    }

    private var query: String { app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchKey: String { query + "|" + (chip?.params ?? "") }

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
        .navigationTitle(query.isEmpty ? "Ara" : "“\(query)”")
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
        FilterChips(chips: results?.chips ?? [], selected: chip) { chip = $0 }
        if let results {
            if chip == nil {
                overview(results)
            } else {
                filteredList
            }
            if results.sections.isEmpty && chipItems.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass", title: "Sonuç yok",
                               message: "“\(query)” için bir şey bulunamadı.")
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
            Button("Daha Fazla Göster") { loadMoreFiltered() }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func overview(_ page: BrowsePage) -> some View {
        let top = page.sections.first { $0.layout == "top" }
        let songShelf = expanded.first { $0.kind == .songs }?.section
            ?? page.sections.first { $0.layout == "list" && $0.hasTracks }
        let allSongs = (songShelf?.items ?? top?.items ?? []).filter(\.isTrack)
        let headSongs = Array(allSongs.prefix(5))
        let moreSongs = Array(allSongs.dropFirst(5))

        if top?.top != nil || !headSongs.isEmpty {
            VStack(alignment: .leading, spacing: d.v(8, 10)) {
                // Titles on one baseline row, content boxes below share top and bottom edges.
                HStack(alignment: .firstTextBaseline, spacing: d.v(16, 24)) {
                    if top?.top != nil {
                        SectionTitle(title: "En İyi Sonuç").frame(width: d.topResult, alignment: .leading)
                    }
                    if !headSongs.isEmpty {
                        SectionTitle(title: "Şarkılar", action: songsChip.map { c in { chip = c } })
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(alignment: .top, spacing: d.v(16, 24)) {
                    if let item = top?.top {
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

        if !moreSongs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Diğer Şarkılar", action: songsChip.map { c in { chip = c } })
                    .padding(.horizontal, d.pad)
                TrackList(items: moreSongs, numbered: false, showArtwork: true, showAlbum: true)
                    .padding(.horizontal, d.pad)
            }
        }

        if expanded.isEmpty {
            // Per-type searches still loading (or unavailable): show the combined shelves.
            ForEach(page.sections.filter { $0.id != top?.id && $0.id != songShelf?.id }) { s in
                if s.hasTracks {
                    TrackListSection(section: s, limit: 4)
                } else {
                    CardCarousel(section: s)
                }
            }
        } else {
            ForEach(expanded.filter { $0.kind != .songs }) { e in
                ExpandedShelfView(shelf: Shelf(id: e.section.id, title: e.title, strapline: nil,
                                               layout: e.section.layout, items: e.section.items,
                                               more: nil, continuation: nil, top: nil),
                                  isVideo: e.kind == .videos)
            }
        }
    }

    private var songsChip: FilterChip? {
        results?.chips.first { Kind.of($0.title) == .songs }
    }

    // MARK: Loading

    private func runSearch() async {
        let q = query
        guard !q.isEmpty else { results = nil; expanded = []; return }
        if q != lastQuery {
            lastQuery = q
            if chip != nil { chip = nil; return }   // the key change re-runs the task
        }
        do { try await Task.sleep(nanoseconds: 280_000_000) } catch { return }   // debounce typing
        error = nil
        let engine = app.engine
        do {
            let r = try await engine.search(q, params: chip?.params)
            guard !Task.isCancelled else { return }
            if chip != nil {
                let main = r.sections.first { $0.layout != "top" && !$0.items.isEmpty }
                chipItems = main?.items ?? []
                chipToken = main?.continuation
                if results == nil { results = r }
                return
            }
            results = r
            expanded = []
            chipItems = []
            chipToken = nil

            // Fan out the per-type searches.
            var wanted: [(Kind, FilterChip)] = []
            for c in r.chips where c.params != nil {
                let k = Kind.of(c.title)
                if k != .other { wanted.append((k, c)) }
            }
            var collected: [ExpandedShelf] = []
            for (kind, c) in wanted {
                guard !Task.isCancelled else { return }
                if let page = try? await engine.search(q, params: c.params),
                   let shelf = page.sections.first(where: { $0.layout != "top" && !$0.items.isEmpty }) {
                    collected.append(ExpandedShelf(kind: kind, title: c.title, section: shelf))
                    // Show results progressively (songs first).
                    if kind == .songs { expanded = collected }
                }
            }
            guard !Task.isCancelled, q == query else { return }
            expanded = collected.sorted { $0.kind.order < $1.kind.order }
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

private struct ExpandedShelfView: View {
    let shelf: Shelf
    let isVideo: Bool

    var body: some View {
        if !isVideo && shelf.hasTracks {
            TrackListSection(section: shelf, limit: 6)
        } else {
            CardCarousel(section: shelf)
        }
    }
}

struct TopResultCard: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: d.v(10, 14)) {
            Artwork(url: item.thumbnail, cornerRadius: 8, circle: false,
                    placeholder: item.isArtist ? "person.fill" : "music.note")
                .frame(width: d.v(76, 100), height: d.v(76, 100))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: d.v(19, 22), weight: .bold))
                        .lineLimit(2)
                    if item.explicit { ExplicitBadge() }
                }
                Text([item.typeLabel, item.isArtist ? "" : item.bylineText].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(d.v(14, 18))
        .frame(maxWidth: .infinity, minHeight: d.v(160, 210), maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(hover ? 0.09 : 0.05)))
        .overlay(alignment: .bottomTrailing) {
            if hover {
                PlayCircle(size: 40) { app.play(item) }
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
