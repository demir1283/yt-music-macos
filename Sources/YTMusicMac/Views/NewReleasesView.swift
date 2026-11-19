import SwiftUI

/// The "Yeni Çıkanlar" page (built by `NewReleases`). Kept in memory for 15 minutes like
/// other pages: going back shows it at once, ⌘R builds it again.
struct NewReleasesView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var page: BrowsePage? = nil
    @ViewState var error: String? = nil

    private static var key: String { PageCache.page(SidebarItem.newReleases.browseTarget!) }

    private var shown: BrowsePage? { page ?? PageCache.shared.value(Self.key, as: BrowsePage.self) }

    var body: some View {
        let current = shown
        ScrollView {
            LazyVStack(alignment: .leading, spacing: d.sectionGap) {
                if let current {
                    ForEach(current.sections) { s in
                        ShelfView(section: s).fadeSwap(s.contentKey, id: s.id)
                    }
                    if current.sections.isEmpty {
                        EmptyStateView(systemImage: "sparkles", title: M.t("Yeni çıkan bulunamadı", "No new releases found"),
                                       message: M.t("Biraz sonra yeniden dene.", "Try again in a little while."))
                    }
                } else if let error {
                    ErrorView(message: error) { Task { await load(force: true) } }
                } else {
                    PageSkeleton(layout: .shelves)
                }
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle(M.t("Yeni Çıkanlar", "New Releases"))
        .pageChrome()
        .task(id: "\(app.engine.sessionID)|\(app.refreshToken)") { await load() }
    }

    private func load(force: Bool = false) async {
        let cache = PageCache.shared
        if !force, cache.isFresh(Self.key), let kept = cache.value(Self.key, as: BrowsePage.self) {
            page = kept
            return
        }
        do {
            let built = try await NewReleases.build(app.engine, hidden: app.hiddenKeys)
            guard !Task.isCancelled else { return }
            cache.store(built, for: Self.key, lifetime: PageCache.Lifetime.page)
            error = nil
            if let old = shown, !old.sameContent(as: built) {
                withAnimation(.easeInOut(duration: 0.35)) { page = built }
            } else {
                page = built
            }
        } catch is CancellationError {
        } catch {
            if shown == nil { self.error = error.localizedDescription }
        }
    }
}
