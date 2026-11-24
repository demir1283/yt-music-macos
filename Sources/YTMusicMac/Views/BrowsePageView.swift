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
                        EmptyStateView(systemImage: "music.note", title: M.t("Burada gösterilecek bir şey yok", "Nothing to show here"))
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
