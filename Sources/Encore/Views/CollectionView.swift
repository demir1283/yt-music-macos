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
                        EmptyStateView(systemImage: "music.note.list", title: "Burada henüz şarkı yok")
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
        .task { await load() }
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
            return PlaylistEditContext(title: title, canMove: false, removeLabel: "Beğenilenlerden Kaldır",
                                       remove: { item in
                                           guard let v = item.videoId else { return }
                                           withAnimation { tracks.removeAll { $0.id == item.id } }
                                           app.engine.rate(videoId: v, status: "INDIFFERENT")
                                       },
                                       move: { _, _ in })
        }
        guard let pl = ownedPlaylistId else { return nil }
        return PlaylistEditContext(title: title, canMove: true, removeLabel: "Bu Listeden Kaldır",
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
        return target.kind == "podcast" ? "Podcast" : "Çalma Listesi"
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
                } else {
                    Artwork(url: page?.header?.thumbnail, cornerRadius: 10, placeholder: "music.note.list")
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
                    CapsuleButton(title: isPlayingHere ? "Duraklat" : "Çal",
                                  systemImage: isPlayingHere ? "pause.fill" : "play.fill", prominent: true) {
                        if isPlayingHere { app.engine.togglePlay() } else { playAll() }
                    }
                    CapsuleButton(title: "Karıştır", systemImage: "shuffle") { shufflePlay() }
                    if let radio = page?.header?.radio {
                        CapsuleButton(title: "Radyo", systemImage: "dot.radiowaves.left.and.right") {
                            app.engine.play(endpoint: radio)
                        }
                    }
                    if ownedPlaylistId != nil {
                        CapsuleButton(title: "Düzenle", systemImage: "pencil") { editPlaylist() }
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
        } else if let pl = contextPlaylist {
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

    private func load(force: Bool = false) async {
        error = nil
        do {
            let p = try await app.page(for: target, force: force)
            let main = p.sections.first { $0.layout == "list" && $0.hasTracks }
            trackSectionID = main?.id
            tracks = (main?.items ?? []).filter(\.isTrack)
            continuation = main?.continuation
            page = p
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
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
