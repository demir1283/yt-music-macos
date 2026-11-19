import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var page: BrowsePage? = nil
    /// The cache key `page` was built for (the home page or a category chip).
    @ViewState var pageKey: String? = nil
    @ViewState var chips: [FilterChip] = []
    @ViewState var error: String? = nil
    @ViewState var chip: FilterChip? = nil
    /// The account session the page belongs to: another account (or signing out) starts
    /// over with the loading preview, not the previous account's page.
    @ViewState var session = 0

    private var cacheKey: String { PageCache.home(chip) }

    /// Loads again when the account or the chip changes, on ⌘R, after a song is heard (the
    /// home page is rebuilt every few) and when the app comes back to the screen.
    private var taskKey: String {
        "\(app.engine.sessionID)|\(chip?.id ?? "")|\(app.refreshToken)|\(app.engine.listenCount)|\(AppActivity.shared.isVisible)"
    }

    /// What shows: the page built here, or the one kept in memory from before (at once,
    /// without the loading preview).
    private var shown: BrowsePage? {
        if let page, pageKey == cacheKey, session == app.engine.sessionID { return page }
        guard app.engine.sessionID > 0 else { return nil }
        return PageCache.shared.value(cacheKey, as: BrowsePage.self)
    }

    private var shownChips: [FilterChip] {
        if !chips.isEmpty { return chips }
        guard app.engine.sessionID > 0 else { return [] }
        return PageCache.shared.value(PageCache.home(nil), as: BrowsePage.self)?.chips ?? []
    }

    var body: some View {
        let current = shown
        let rows = current.map { visibleRows($0.sections) } ?? []
        let chipList = shownChips
        ScrollView {
            // Lazy: shelves far below the window are built (and their covers loaded) only
            // when scrolled to, instead of all at once.
            LazyVStack(alignment: .leading, spacing: d.sectionGap) {
                if !chipList.isEmpty {
                    FilterChips(chips: chipList, selected: chip) { chip = $0 }
                }
                if let current {
                    if !app.engine.loggedIn && chip == nil {
                        SignInBanner()
                    }
                    ForEach(rows) { row in
                        // A row refreshed with other items fades over; the rest stay put.
                        ShelfView(section: row.shelf).fadeSwap(row.key, id: row.id)
                    }
                    if current.sections.isEmpty {
                        EmptyStateView(systemImage: "music.note", title: M.t("Bu kategoride içerik bulunamadı", "Nothing found in this category"))
                    }
                } else if let error {
                    // Through the page task (not a loose Task that would outlive the page).
                    ErrorView(message: error) { app.refresh() }
                } else {
                    // Category chips load shelves of covers; the home page also starts with
                    // quick picks (and its chips, the first time).
                    PageSkeleton(layout: chip != nil ? .shelves : .home(chips: chipList.isEmpty))
                }
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle(chip?.title ?? M.t("Ana Sayfa", "Home"))
        .onChange(of: app.homeResetToken) { _, _ in
            if chip != nil { chip = nil }
        }
        .pageChrome()
        .task(id: taskKey) { await load() }
    }

    /// Shows what is kept at once, fetches again only when it is no longer current (see
    /// PageCache), and while the page stays on screen checks again when it expires.
    private func load() async {
        // Before the account is ready nothing loads (the preview shows): loading earlier
        // fetched YouTube Music's own home as if signed out, showed it for a moment, then
        // built the real page again once the account was known.
        guard app.engine.sessionID > 0 else { return }
        let key = cacheKey
        let cache = PageCache.shared
        error = nil
        if session != app.engine.sessionID {
            session = app.engine.sessionID
            page = nil
            pageKey = nil
            chips = []
        }
        if pageKey != key, let kept = cache.value(key, as: BrowsePage.self) {
            page = kept
            pageKey = key
            if chip == nil { chips = kept.chips }
        }
        while !Task.isCancelled {
            if !(pageKey == key && cache.isFresh(key)) {
                // Diagnostics (rare: at most every few minutes): why the page is fetched.
                EngineLog.write("Ana sayfa alınıyor: \(key) — \(pageKey == key ? "yenileme" : "ilk kez")")
                guard await fetch(key) else { return }
            }
            // Only while someone can see it; hidden, the task stops (taskKey) and runs again
            // when the app is back.
            guard AppActivity.shared.isVisible, let until = cache.expiry(key) else { return }
            let wait = max(5, until.timeIntervalSinceNow)
            do { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) } catch { return }
        }
    }

    /// Builds the page and keeps it. A page already on screen changes only where its rows
    /// changed, with a short fade.
    private func fetch(_ key: String) async -> Bool {
        let first = page == nil || pageKey != key
        do {
            let built = try await build()
            // A newer load (account changed, chip picked) has taken over.
            guard !Task.isCancelled else { return false }
            PageCache.shared.store(built, for: key, lifetime: PageCache.Lifetime.home)
            if chip == nil { chips = built.chips }
            if first {
                page = built
            } else if let old = page, !old.sameContent(as: built) {
                withAnimation(.easeInOut(duration: 0.35)) { page = built }
            }
            pageKey = key
            return true
        } catch is CancellationError {
            return false
        } catch {
            if first && shown == nil { self.error = error.localizedDescription }
            return false
        }
    }

    private func build() async throws -> BrowsePage {
        guard let c = chip else {
            // Signed in: the app's own home (YouTube's music feed + listening history +
            // YouTube Music's official playlists). Signed out: YouTube Music's home.
            if app.engine.loggedIn {
                return try await PersonalHome.build(app.engine, hidden: app.hiddenKeys)
            }
            return try await app.engine.home(params: nil)
        }
        // Mood chips (Enerjik, Rahatlama, Antrenman…) map to YouTube Music's own mood
        // pages, which hold the real playlists for that mood.
        // Either way only what fits the category is shown: official playlists and
        // songs, not "Yeniden dinleyin" / "Sizin için derlenenler" / community lists.
        if let target = await categoryTarget(for: c) {
            return PersonalHome.categoryPage(try await app.page(for: target))
        }
        return PersonalHome.categoryPage(try await app.engine.home(params: c.params, browseId: c.browseId))
    }

    private struct Row: Identifiable {
        let shelf: Shelf
        /// The row's items before hiding: what "Bana önerme" takes away slides out of the
        /// row instead of fading the whole row.
        let key: String
        var id: String { shelf.id }
    }

    /// What "Beğenmedim" / "Bana önerme" took away leaves at once; the rest slides up.
    private func visibleRows(_ sections: [Shelf]) -> [Row] {
        let hidden = app.hiddenKeys
        return sections.compactMap { s -> Row? in
            let key = s.contentKey
            guard !hidden.isEmpty, s.layout != "nav" else { return Row(shelf: s, key: key) }
            var s = s
            s.items.removeAll { hidden.contains($0.recommendationKey) }
            return s.items.isEmpty ? nil : Row(shelf: s, key: key)
        }
    }

    private func categoryTarget(for chip: FilterChip) async -> BrowseTarget? {
        let tr = Locale(identifier: "tr_TR")
        let name = chip.title.lowercased(with: tr)
        if name.contains("podcast") {
            return BrowseTarget(browseId: "FEmusic_podcasts", params: nil, kind: "browse", title: chip.title)
        }
        guard let moods = try? await app.page(for: BrowseTarget(browseId: "FEmusic_moods_and_genres", params: nil,
                                                                kind: "browse", title: nil)) else { return nil }
        let categories = moods.sections.flatMap(\.items).filter { $0.browseId != nil }
        func key(_ s: String) -> String { String(s.lowercased(with: tr).filter { $0.isLetter }.prefix(5)) }
        let k = key(chip.title)
        guard k.count >= 3 else { return nil }
        let match = categories.first { $0.title.lowercased(with: tr) == name }
            ?? categories.first { key($0.title) == k }
            ?? categories.first { $0.title.lowercased(with: tr).hasPrefix(String(name.prefix(4))) }
        guard let m = match, let id = m.browseId else { return nil }
        return BrowseTarget(browseId: id, params: m.params, kind: "category", title: chip.title)
    }
}

struct SignInBanner: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        HStack(spacing: 14) {
            AppGlyph(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(M.t("YouTube Music hesabınla oturum aç", "Sign in with your YouTube Music account"))
                    .font(.system(size: 15, weight: .semibold))
                Text(M.t("Kişisel önerilerin, kitaplığın ve Premium ses kalitesi için.", "For your recommendations, your library and Premium audio quality."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CapsuleButton(title: M.t("Oturum Aç", "Sign In"), systemImage: "person.crop.circle", prominent: true) {
                app.engine.showLogin()
            }
        }
        .padding(d.v(12, 16))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, d.pad)
    }
}
