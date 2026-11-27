import SwiftUI

struct ArtistView: View {
    let target: BrowseTarget
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    @ViewState var page: BrowsePage? = nil
    @ViewState var error: String? = nil
    /// The artist's own square picture (their channel avatar on YouTube).
    @ViewState var photo: String? = nil
    /// The header's entrance has played (once per visit, not each time it scrolls back).
    @ViewState var heroShown = false

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
                    // A thin page (only a row of long videos, say) wraps its card rows into
                    // grids that fill the screen instead of one row to scroll.
                    let grids = ShelfGrid.rows(for: page.sections)
                    ForEach(page.sections) { s in
                        VStack(alignment: .leading, spacing: 0) {
                            // The popular songs list opened from here gets a cover with the artist's name.
                            if s.layout == "list" && s.hasTracks {
                                TrackListSection(section: s, limit: 5, numbered: false)
                                    .environment(\.pageArtist, name)
                            } else {
                                ShelfView(section: s, gridRows: grids[s.id])
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
        .task(id: target.browseId) {
            let id = target.browseId
            guard id.hasPrefix("UC") else { return }
            let found = await app.engine.channelPhotos([id])[id]
            withAnimation(.soft) { photo = found }
        }
    }

    /// "Dağılan sahne": the artist's banner on the right, melting leftwards and downwards
    /// into the page, with a soft wash of its colours across the whole width. On the open
    /// left, the artist's round photo, their name, the subscribers and the buttons. Without
    /// a banner, the artist's own colour makes the wash.
    private func hero(_ h: PageHeader?) -> some View {
        let photoSide = d.v(68, 88)
        let banner = h?.thumbnail.flatMap { $0.isEmpty ? nil : $0 }
        return ZStack(alignment: .bottomLeading) {
            GeometryReader { g in
                ZStack(alignment: .trailing) {
                    Group {
                        if let banner {
                            Artwork(url: banner, cornerRadius: 0, placeholder: "person.fill")
                                .frame(width: g.size.width, height: g.size.height)
                                .clipped()
                                .blur(radius: 50)
                                .opacity(0.4)
                        } else {
                            HomePalette.color(for: name).opacity(0.3)
                        }
                    }
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                    if let banner {
                        Artwork(url: banner, cornerRadius: 0, placeholder: "person.fill")
                            .frame(width: g.size.width * 0.64, height: g.size.height)
                            .clipped()
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                         .init(color: .black.opacity(0.75), location: 0.3),
                                                         .init(color: .black, location: 0.55)],
                                                 startPoint: .leading, endPoint: .trailing))
                            // A long, soft fall-off at the bottom: no line where it ends.
                            .mask(LinearGradient(stops: [.init(color: .black, location: 0.35),
                                                         .init(color: .black.opacity(0.55), location: 0.7),
                                                         .init(color: .clear, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                            .transition(.opacity)
                    }
                }
                .frame(width: g.size.width, height: g.size.height)
            }
            .allowsHitTesting(false)
            // The banner comes in slowly.
            .opacity(heroShown ? 1 : 0)

            VStack(alignment: .leading, spacing: 0) {
                // The round photo beside the name and the subscribers.
                HStack(alignment: .center, spacing: d.v(14, 18)) {
                    ArtistPhoto(url: photo, name: name)
                        .frame(width: photoSide, height: photoSide)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: d.heroTitle, weight: .heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if let subs = h?.subscribers, !subs.isEmpty {
                            Text(subs)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    PlayCircle(size: d.v(36, 42)) { playShuffle(h) }
                    if let h, h.channelId != nil {
                        SubscribeButton(name: name, header: h)
                    }
                    if let radio = h?.radio {
                        CapsuleButton(title: M.t("Radyo", "Radio"), systemImage: "dot.radiowaves.left.and.right") {
                            app.engine.play(endpoint: radio)
                        }
                    }
                }
                .padding(.top, d.v(14, 18))
            }
            .padding(.leading, d.pad)
            .padding(.trailing, d.pad)
            .padding(.bottom, d.v(18, 28))
            // The photo, name and buttons float up into place after the banner.
            .opacity(heroShown ? 1 : 0)
            .offset(y: heroShown ? 0 : 14)
        }
        .frame(height: d.heroHeight)
        .onAppear {
            guard !heroShown else { return }
            withAnimation(.smooth(duration: 0.7).delay(0.05)) { heroShown = true }
        }
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

/// The artist's round photo on their page; until it comes (or without one), a circle in
/// the artist's colour with their initial.
private struct ArtistPhoto: View {
    let url: String?
    let name: String

    var body: some View {
        GeometryReader { geo in
            ZStack {
                HomePalette.color(for: name)
                Text(name.prefix(1).uppercased())
                    .font(.system(size: geo.size.width * 0.42, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.55))
                if let url {
                    Artwork(url: url, cornerRadius: 0, placeholder: "person.fill")
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
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
                    Text(count).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            // Quiet like the page's other buttons (Play is the one that stands out); once
            // subscribed, a soft tint of the accent colour with a tick.
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                Capsule().fill(on ? Color.brand.opacity(hover ? 0.22 : 0.15) : Color.primary.opacity(hover ? 0.12 : 0.07))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(busy)
        .onHover { hover = $0 }
        .help(failure ?? (on ? M.t("Abonelikten çık", "Unsubscribe") : M.t("\(name) kanalına abone ol", "Subscribe to \(name)")))
        .animation(.easeInOut(duration: 0.2), value: on)
        .confirmationDialog(M.t("\(name) aboneliğinden çıkılsın mı?", "Unsubscribe from \(name)?"), isPresented: $confirm) {
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
