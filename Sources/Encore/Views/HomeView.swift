import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var page: BrowsePage? = nil
    @ViewState var chips: [FilterChip] = []
    @ViewState var error: String? = nil
    @ViewState var chip: FilterChip? = nil
    @ViewState var loading = false

    private var taskKey: String { "\(app.engine.sessionID)|\(chip?.id ?? "")" }

    var body: some View {
        ScrollView {
            // Lazy: shelves far below the window are built (and their covers loaded) only
            // when scrolled to, instead of all at once.
            LazyVStack(alignment: .leading, spacing: d.sectionGap) {
                if !chips.isEmpty {
                    FilterChips(chips: chips, selected: chip) { chip = $0 }
                }
                if let page, !loading {
                    if !app.engine.loggedIn && chip == nil {
                        SignInBanner()
                    }
                    ForEach(page.sections) { section in
                        ShelfView(section: section)
                    }
                    if page.sections.isEmpty {
                        EmptyStateView(systemImage: "music.note", title: "Bu kategoride içerik bulunamadı")
                    }
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else {
                    // Category chips load shelves of covers; the home page also starts with
                    // quick picks (and its chips, the first time).
                    PageSkeleton(layout: chip != nil ? .shelves : .home(chips: chips.isEmpty))
                }
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle(chip?.title ?? "Ana Sayfa")
        .onChange(of: app.homeResetToken) { _, _ in
            if chip != nil { chip = nil }
        }
        .pageChrome()
        .task(id: taskKey) { await load() }
    }

    private func load() async {
        error = nil
        loading = page != nil
        defer { loading = false }
        do {
            guard let c = chip else {
                let p = try await app.engine.home(params: nil)
                chips = p.chips
                page = p
                return
            }
            // Mood chips (Enerjik, Rahatlama, Antrenman…) map to YouTube Music's own mood
            // pages, which hold the real playlists for that mood.
            if let target = await categoryTarget(for: c) {
                let loaded = try await app.page(for: target)
                page = loaded
            } else {
                let loaded = try await app.engine.home(params: c.params, browseId: c.browseId)
                page = loaded
            }
        } catch is CancellationError {
        } catch {
            if page == nil { self.error = error.localizedDescription }
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
                Text("YouTube Music hesabınla oturum aç")
                    .font(.system(size: 15, weight: .semibold))
                Text("Kişisel önerilerin, kitaplığın ve Premium ses kalitesi için.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            CapsuleButton(title: "Oturum Aç", systemImage: "person.crop.circle", prominent: true) {
                app.engine.showLogin()
            }
        }
        .padding(d.v(12, 16))
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, d.pad)
    }
}
