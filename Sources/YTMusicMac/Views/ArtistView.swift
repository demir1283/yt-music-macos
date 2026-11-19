import SwiftUI

struct ArtistView: View {
    let target: BrowseTarget
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    @ViewState var page: BrowsePage? = nil
    @ViewState var error: String? = nil

    private var name: String { shown?.header?.title ?? target.title ?? "" }

    /// The page loaded here, or the one kept in memory from before (shown at once).
    private var shown: BrowsePage? {
        page ?? app.keptPage(for: target)
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
                    hero(page.header)
                    ForEach(page.sections) { s in
                        VStack(alignment: .leading, spacing: 0) {
                            // The popular songs list opened from here gets a cover with the artist's name.
                            if s.layout == "list" && s.hasTracks {
                                TrackListSection(section: s, limit: 5, numbered: false)
                                    .environment(\.pageArtist, name)
                            } else {
                                ShelfView(section: s)
                            }
                        }
                        .fadeSwap(s.contentKey, id: s.id)
                    }
                    if let about = page.header?.description, !about.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: M.t("Hakkında", "About"))
                            Text(about)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                                .frame(maxWidth: 720, alignment: .leading)
                            if let subs = page.header?.subscribers, !subs.isEmpty {
                                Text(subs).font(.system(size: 12, weight: .medium))
                            }
                        }
                        .padding(.horizontal, d.pad)
                    }
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else {
                    PageSkeleton(layout: .artist)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(name)
        .pageChrome()
        .task(id: taskKey) { await load() }
    }

    private func hero(_ h: PageHeader?) -> some View {
        ZStack(alignment: .bottomLeading) {
            Artwork(url: h?.thumbnail, cornerRadius: 0, placeholder: "person.fill")
                .frame(height: d.heroHeight)
                .frame(maxWidth: .infinity)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 16) {
                PlayCircle(size: d.v(42, 50)) { playShuffle(h) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: d.heroTitle, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .shadow(color: .black.opacity(0.3), radius: 8)
                    if let subs = h?.subscribers, !subs.isEmpty {
                        Text(subs)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
                if let h, h.channelId != nil {
                    SubscribeButton(name: name, header: h)
                }
                if let radio = h?.radio {
                    Button { app.engine.play(endpoint: radio) } label: {
                        Label(M.t("Radyo", "Radio"), systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(.white.opacity(0.2)))
                    }
                    .buttonStyle(PressScaleStyle())
                }
            }
            .padding(d.v(16, 24))
        }
        .frame(height: d.heroHeight)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 20, style: .continuous))
    }

    private func playShuffle(_ h: PageHeader?) {
        if let ep = h?.shuffle ?? h?.play {
            app.engine.play(endpoint: ep)
        } else if let first = shown?.sections.flatMap(\.items).first(where: { $0.isTrack }) {
            app.play(first)
        }
    }

    private func load() async {
        error = nil
        if page == nil, let kept = app.keptPage(for: target) { page = kept }
        // Kept and still current: nothing to fetch.
        if page != nil, PageCache.shared.isFresh(PageCache.page(target)) { return }
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

/// YouTube Music's "Abone ol" button on artist pages. Subscribing is one click (with the
/// subscriber count beside it); unsubscribing asks first, as YouTube Music does. Signed
/// out, it opens the sign-in. The change shows at once and is undone if YouTube refuses it.
private struct SubscribeButton: View {
    let name: String
    let header: PageHeader
    @Environment(AppModel.self) private var app
    /// nil until changed here: the header's state applies.
    @ViewState var subscribed: Bool? = nil
    @ViewState var busy = false
    @ViewState var confirm = false
    @ViewState var hover = false
    @ViewState var failure: String? = nil

    var body: some View {
        let on = subscribed ?? (header.subscribed ?? false)
        Button {
            guard app.engine.loggedIn else { app.engine.showLogin(); return }
            if on { confirm = true } else { set(true) }
        } label: {
            HStack(spacing: 6) {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(on ? M.t("Abone olundu", "Subscribed") : M.t("Abone ol", "Subscribe"))
                if !on, let count = header.subscriberShort, !count.isEmpty {
                    Text(count).opacity(0.55)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? Color.white : Color.black)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule().fill(on ? Color.white.opacity(hover ? 0.3 : 0.2) : Color.white.opacity(hover ? 0.88 : 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(busy)
        .onHover { hover = $0 }
        .help(failure ?? (on ? M.t("Aboneliği iptal et", "Unsubscribe") : M.t("\(name) kanalına abone ol", "Subscribe to \(name)")))
        .animation(.easeInOut(duration: 0.2), value: on)
        .confirmationDialog(M.t("\(name) kanalından aboneliğin iptal edilsin mi?", "Unsubscribe from \(name)?"), isPresented: $confirm) {
            Button(M.t("Abonelikten Çık", "Unsubscribe"), role: .destructive) { set(false) }
            Button(M.t("Vazgeç", "Cancel"), role: .cancel) {}
        }
    }

    private func set(_ value: Bool) {
        guard let id = header.channelId else { return }
        let before = subscribed ?? (header.subscribed ?? false)
        withAnimation(.easeInOut(duration: 0.2)) { subscribed = value }
        busy = true
        failure = nil
        Task {
            do {
                try await app.engine.setSubscribed(value, channelId: id,
                                                   params: value ? header.subscribeParams : header.unsubscribeParams)
            } catch {
                withAnimation(.easeInOut(duration: 0.2)) { subscribed = before }
                failure = M.t("İşlem yapılamadı: \(error.localizedDescription)", "That didn't work: \(error.localizedDescription)")
            }
            busy = false
        }
    }
}
