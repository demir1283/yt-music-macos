import SwiftUI

/// Playlist / album / podcast page in the Apple Music layout.
struct CollectionView: View {
    let target: BrowseTarget
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    @ViewState var page: BrowsePage? = nil
    @ViewState var tracks: [MediaItem] = []
    @ViewState var trackSectionID: String? = nil
    @ViewState var continuation: String? = nil
    @ViewState var loadingMore = false
    @ViewState var error: String? = nil
    @ViewState var actionError: String? = nil

    private var isAlbum: Bool { target.kind == "album" }
    private var isMix: Bool { target.kind == "mix" }

    /// Checks again on ⌘R and when the app comes back to the screen.
    private var taskKey: String {
        "\(app.engine.sessionID)|\(app.refreshToken)|\(AppActivity.shared.isVisible)"
    }
    private var isLiked: Bool { target.browseId == "VLLM" }
    private var title: String { page?.header?.title.isEmpty == false ? (page?.header?.title ?? "") : (target.title ?? "") }

    private var contextPlaylist: String? {
        if target.browseId.hasPrefix("VL") { return String(target.browseId.dropFirst(2)) }
        return playlistId(inEndpoint: page?.header?.play) ?? tracks.first?.playlistId
    }

    private var isPlayingHere: Bool {
        guard let v = app.engine.track?.videoId else { return false }
        return app.engine.isPlaying && tracks.contains { $0.videoId == v }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if page != nil {
                    header
                        .padding(.horizontal, d.pad)
                        .padding(.top, d.v(12, 20))
                        .padding(.bottom, d.v(14, 24))
                    if tracks.isEmpty {
                        EmptyStateView(systemImage: "music.note.list", title: M.t("Burada henüz şarkı yok", "No songs here yet"))
                    } else {
                        TrackList(items: tracks, numbered: isAlbum, showArtwork: !isAlbum, showAlbum: !isAlbum,
                                  context: contextPlaylist, onReachEnd: loadMore)
                            .padding(.horizontal, d.pad)
                            .environment(\.playlistEdit, editContext)
                        if loadingMore {
                            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding()
                        }
                        footer
                    }
                    VStack(alignment: .leading, spacing: d.sectionGap) {
                        ForEach(extraSections) { ShelfView(section: $0) }
                    }
                    .padding(.top, d.v(24, 36))
                } else if let error {
                    ErrorView(message: error) { Task { await load(force: true) } }
                } else {
                    PageSkeleton(layout: .collection(album: isAlbum))
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(title)
        .pageChrome()
        .task(id: taskKey) { await load() }
        .onChange(of: app.engine.playlistRevision) { _, _ in
            // Something changed in a playlist (maybe this one): reload quietly.
            Task { await load(force: true) }
        }
    }

    // MARK: Editing (playlists the account owns, and Beğenilen Müzikler)

    private var ownedPlaylistId: String? {
        guard page?.header?.editable == true else { return nil }
        return page?.header?.playlistId ?? (target.browseId.hasPrefix("VL") ? String(target.browseId.dropFirst(2)) : nil)
    }

    private var editContext: PlaylistEditContext? {
        if isLiked {
            return PlaylistEditContext(title: title, canMove: false, removeLabel: M.t("Beğenilenlerden Kaldır", "Remove from Liked Music"),
                                       remove: { item in
                                           guard let v = item.videoId else { return }
                                           withAnimation { tracks.removeAll { $0.id == item.id } }
                                           app.engine.rate(videoId: v, status: "INDIFFERENT")
                                       },
                                       move: { _, _ in })
        }
        guard let pl = ownedPlaylistId else { return nil }
        return PlaylistEditContext(title: title, canMove: true, removeLabel: M.t("Bu Listeden Kaldır", "Remove from This Playlist"),
                                   remove: { item in remove(item, from: pl) },
                                   move: { item, delta in move(item, delta, in: pl) })
    }

    private func remove(_ item: MediaItem, from pl: String) {
        guard let v = item.videoId, let set = item.setVideoId,
              let i = tracks.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation { _ = tracks.remove(at: i) }
        Task {
            do {
                try await app.engine.removeFromPlaylist(pl, videoId: v, setVideoId: set)
            } catch {
                withAnimation { tracks.insert(item, at: min(i, tracks.count)) }
                actionError = error.localizedDescription
            }
        }
    }

    private func move(_ item: MediaItem, _ delta: Int, in pl: String) {
        guard let set = item.setVideoId, let i = tracks.firstIndex(where: { $0.id == item.id }) else { return }
        let j = i + delta
        guard tracks.indices.contains(j) else { return }
        // "Move before X": up → before the previous entry; down → before the one after next.
        let before: String? = delta < 0 ? tracks[j].setVideoId
            : (tracks.indices.contains(i + 2) ? tracks[i + 2].setVideoId : nil)
        withAnimation { tracks.swapAt(i, j) }
        Task {
            do {
                try await app.engine.movePlaylistItem(pl, setVideoId: set, before: before)
            } catch {
                withAnimation { tracks.swapAt(i, j) }
                actionError = error.localizedDescription
            }
        }
    }

    private func editPlaylist() {
        guard let pl = ownedPlaylistId, let h = page?.header else { return }
        app.playlistEditor = .edit(playlistId: pl, title: h.title,
                                   description: h.rawDescription ?? h.description,
                                   privacy: PlaylistPrivacy(rawValue: h.privacy ?? "") ?? .PRIVATE)
    }

    // MARK: Header

    private var typeLabel: String {
        if isAlbum, let first = page?.header?.subtitle.components(separatedBy: " • ").first, !first.isEmpty { return first }
        if isMix { return "Mix" }
        return target.kind == "podcast" ? "Podcast" : M.t("Çalma Listesi", "Playlist")
    }

    private var metaLine: String {
        guard let h = page?.header else { return "" }
        let sub = h.subtitle.components(separatedBy: " • ").filter { !$0.isEmpty }
        var parts: [String] = isAlbum ? Array(sub.dropFirst()) : sub.filter { $0 != typeLabel }
        parts.insert(typeLabel, at: 0)
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: d.v(18, 26)) {
            Group {
                if isLiked {
                    ZStack {
                        Rectangle().fill(Palette.likedGradient)
                        Image(systemName: "heart.fill").font(.system(size: d.headerArt / 3)).foregroundStyle(.white)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if isMix {
                    // The same cover as the mix's card: the artist's picture with its band.
                    ZStack(alignment: .bottomLeading) {
                        Artwork(url: page?.header?.thumbnail, cornerRadius: 10, placeholder: "music.note.list")
                        MixBand(title: title, width: d.headerArt)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if let artist = target.coverArtist, !artist.isEmpty {
                    ArtistListCover(artist: artist, label: M.t("Popüler şarkılar", "Top songs"))
                } else {
                    Artwork(url: page?.header?.thumbnail.flatMap { $0.isEmpty ? nil : $0 }, cornerRadius: 10, placeholder: "music.note.list")
                }
            }
            .frame(width: d.headerArt, height: d.headerArt)
            .shadow(color: .black.opacity(0.25), radius: d.v(10, 16), y: d.v(5, 8))

            VStack(alignment: .leading, spacing: d.v(4, 6)) {
                Text(title)
                    .font(.system(size: d.headerTitle, weight: .bold))
                    .lineLimit(2)
                if let h = page?.header, !h.strapline.isEmpty {
                    if let a = h.artists.first {
                        HoverLink(h.strapline, font: .system(size: d.headerStrap, weight: .medium), color: .brand) { app.openArtist(a.id) }
                    } else {
                        Text(h.strapline).font(.system(size: d.headerStrap, weight: .medium)).foregroundStyle(Color.brand)
                    }
                }
                Text(metaLine)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                if let about = page?.header?.description, !about.isEmpty {
                    Text(about)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(d.isCompact ? 2 : 3)
                        .padding(.top, d.v(2, 4))
                }
                HStack(spacing: 10) {
                    CapsuleButton(title: isPlayingHere ? M.t("Duraklat", "Pause") : M.t("Çal", "Play"),
                                  systemImage: isPlayingHere ? "pause.fill" : "play.fill", prominent: true) {
                        if isPlayingHere { app.engine.togglePlay() } else { playAll() }
                    }
                    CapsuleButton(title: M.t("Karıştır", "Shuffle"), systemImage: "shuffle") { shufflePlay() }
                    if let radio = page?.header?.radio {
                        CapsuleButton(title: M.t("Radyo", "Radio"), systemImage: "dot.radiowaves.left.and.right") {
                            app.engine.play(endpoint: radio)
                        }
                    }
                    if ownedPlaylistId != nil {
                        CapsuleButton(title: M.t("Düzenle", "Edit"), systemImage: "pencil") { editPlaylist() }
                    }
                    if let p = page?.header?.privacy.flatMap(PlaylistPrivacy.init(rawValue:)) {
                        Label(p.title, systemImage: p.icon)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                    }
                }
                .padding(.top, d.v(8, 12))
                if let actionError {
                    Text(actionError)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                        .onTapGesture { self.actionError = nil }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        Text(page?.header?.secondSubtitle ?? "")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, d.pad + 10)
            .padding(.top, d.v(10, 14))
    }

    private var extraSections: [Shelf] {
        (page?.sections ?? []).filter { $0.id != trackSectionID && $0.layout != "top" }
    }

    // MARK: Actions

    private func playAll() {
        if let ep = page?.header?.play {
            app.engine.play(endpoint: ep)
        } else if let first = tracks.first {
            app.play(first, context: contextPlaylist)
        }
    }

    private func shufflePlay() {
        if let ep = page?.header?.shuffle {
            app.engine.play(endpoint: ep)
        } else if let pl = contextPlaylist, !isMix {
            app.engine.play(endpoint: watchPlaylistEndpoint(pl, params: "wAEB"))
        } else {
            playAll()
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                app.engine.shuffle()
            }
        }
    }

    // MARK: Loading

    /// Shows the page kept in memory at once and fetches it again only when it is no
    /// longer current (`force`: in any case, e.g. after the playlist was edited).
    private func load(force: Bool = false) async {
        error = nil
        if page == nil, let kept = app.keptPage(for: target) { apply(kept) }
        if !force, page != nil, PageCache.shared.isFresh(PageCache.page(target)) { return }
        do {
            let p = try await app.page(for: target, force: true)
            guard !Task.isCancelled else { return }
            if let old = page {
                // Unchanged: the list stays as it is (with the songs loaded further down).
                if !old.sameContent(as: p) {
                    withAnimation(.easeInOut(duration: 0.35)) { apply(p) }
                }
            } else {
                apply(p)
            }
        } catch is CancellationError {
        } catch {
            if page == nil { self.error = error.localizedDescription }
        }
    }

    private func apply(_ p: BrowsePage) {
        let main = p.sections.first { $0.layout == "list" && $0.hasTracks }
        trackSectionID = main?.id
        tracks = (main?.items ?? []).filter(\.isTrack)
        continuation = main?.continuation
        page = p
    }

    private func loadMore() {
        guard let token = continuation, !loadingMore else { return }
        loadingMore = true
        Task {
            defer { loadingMore = false }
            if let r = try? await app.engine.more(token) {
                let known = Set(tracks.map(\.id))
                tracks.append(contentsOf: r.items.filter { $0.isTrack && !known.contains($0.id) })
                continuation = r.continuation == token ? nil : r.continuation
            } else {
                continuation = nil
            }
        }
    }
}

/// Made cover for an artist's popular songs list (Spotify / YouTube Music style): the
/// artist's colour (the same one as their station card), the list's name and the artist's
/// name in large type. Drawn, not downloaded.
private struct ArtistListCover: View {
    let artist: String
    let label: String

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            let color = HomePalette.color(for: artist)
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .background(Color.black)
                Image(systemName: "waveform")
                    .font(.system(size: s * 0.62, weight: .bold))
                    .foregroundStyle(.black.opacity(0.07))
                    .frame(width: s, height: s, alignment: .topTrailing)
                    .offset(x: s * 0.16, y: -s * 0.06)
                VStack(alignment: .leading, spacing: s * 0.03) {
                    HStack(spacing: s * 0.03) {
                        Rectangle().fill(.black.opacity(0.75)).frame(width: s * 0.02, height: s * 0.075)
                        Text(M.turkish ? label.uppercased(with: Locale(identifier: "tr_TR")) : label.uppercased())
                            .font(.system(size: s * 0.058, weight: .heavy))
                            .tracking(s * 0.004)
                            .foregroundStyle(.black.opacity(0.72))
                            .lineLimit(1)
                    }
                    Text(artist)
                        .font(.system(size: s * 0.15, weight: .heavy))
                        .foregroundStyle(.black)
                        .lineLimit(3)
                        .minimumScaleFactor(0.45)
                        .multilineTextAlignment(.leading)
                }
                .padding(s * 0.08)
            }
            .frame(width: s, height: s)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
