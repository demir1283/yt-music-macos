import SwiftUI

/// Generic YouTube Music page: Explore, Charts, Moods & Genres, New Releases,
/// Podcasts, History, "see all" pages and mood categories.
struct BrowsePageView: View {
    let target: BrowseTarget
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var page: BrowsePage? = nil
    @ViewState var error: String? = nil

    private var title: String {
        if let t = shown?.header?.title, !t.isEmpty { return t }
        return target.title ?? ""
    }

    /// The loading preview matching what this page will show.
    private var skeleton: SkeletonLayout {
        switch target.browseId {
        case "FEmusic_moods_and_genres": return .tiles
        case "FEmusic_charts": return .charts
        case "FEmusic_history": return .songList
        default:
            // YouTube Music's own pages and mood categories are shelves of covers;
            // "see all" pages are one wrapping grid.
            if target.kind == "category" || target.browseId.hasPrefix("FEmusic_") { return .shelves }
            return .cardGrid
        }
    }

    /// The page loaded here, or the one kept in memory from before (shown at once).
    private var shown: BrowsePage? {
        if let page { return page }
        return app.engine.sessionID > 0 ? app.keptPage(for: target) : nil
    }

    /// Checks again on ⌘R and when the app comes back to the screen.
    private var taskKey: String {
        "\(app.engine.sessionID)|\(app.refreshToken)|\(AppActivity.shared.isVisible)"
    }

    var body: some View {
        let current = shown
        ScrollView {
            // Lazy: shelves far below the window are built (and their covers loaded) only
            // when scrolled to, instead of all at once.
            LazyVStack(alignment: .leading, spacing: d.sectionGap) {
                if let page = current {
                    let single = page.sections.count == 1
                    ForEach(page.sections) { s in
                        VStack(alignment: .leading, spacing: 0) {
                            if s.layout == "cards" && single {
                                VStack(alignment: .leading, spacing: d.v(10, 12)) {
                                    if !s.title.isEmpty { SectionTitle(title: s.title).padding(.horizontal, d.pad) }
                                    CardGrid(items: s.items)
                                }
                            } else if s.layout == "list" && s.hasTracks {
                                TrackListSection(section: s, limit: single ? 300 : 10, numbered: target.browseId == "FEmusic_charts")
                            } else {
                                ShelfView(section: s)
                            }
                        }
                        .fadeSwap(s.contentKey, id: s.id)
                    }
                    if page.sections.isEmpty {
                        EmptyStateView(systemImage: "music.note", title: "Burada gösterilecek bir şey yok")
                    }
                } else if let error {
                    ErrorView(message: error) { Task { await load(force: true) } }
                } else {
                    PageSkeleton(layout: skeleton)
                }
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle(title)
        .pageChrome()
        .task(id: taskKey) { await load() }
    }

    private func load(force: Bool = false) async {
        // Loads once the account is ready (see YTMusic.sessionID), not twice.
        guard app.engine.sessionID > 0 else { return }
        error = nil
        if page == nil, let kept = app.keptPage(for: target) { page = kept }
        // Kept and still current: nothing to fetch.
        if !force, page != nil, PageCache.shared.isFresh(PageCache.page(target)) { return }
        do {
            let loaded = try await app.page(for: target, force: true)
            guard !Task.isCancelled else { return }
            if let old = page {
                // Refreshed behind the page: only rows that changed fade over.
                if !old.sameContent(as: loaded) {
                    withAnimation(.easeInOut(duration: 0.35)) { page = loaded }
                }
            } else {
                page = loaded
            }
        } catch is CancellationError {
        } catch {
            if page == nil { self.error = error.localizedDescription }
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        @Bindable var app = app
        let lib = app.engine.library
        let items: [MediaItem] = {
            switch app.libraryFilter {
            case .playlists: return lib.playlists
            case .albums: return lib.albums
            case .artists: return lib.artists
            }
        }()
        ScrollView {
            VStack(alignment: .leading, spacing: d.v(14, 20)) {
                Picker("", selection: $app.libraryFilter) {
                    ForEach(LibraryFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .padding(.horizontal, d.pad)

                if app.engine.libraryLoading && items.isEmpty {
                    PageSkeleton(layout: .cardGrid)
                } else if items.isEmpty {
                    EmptyStateView(systemImage: "square.stack", title: "Burada henüz bir şey yok")
                } else {
                    CardGrid(items: items)
                }
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle("Kitaplık")
        .pageChrome()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await app.engine.loadLibrary() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Kitaplığı yenile")
            }
        }
    }
}
