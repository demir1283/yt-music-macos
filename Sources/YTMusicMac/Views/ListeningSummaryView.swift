import SwiftUI

/// Sidebar → Your listening: the history kept on this Mac, summed up for a period, in the
/// app's own layout — period chips as at the top of the home page, a headline like the
/// home page's greeting, the top artists and channels as cards with their own pictures,
/// and the top songs as a regular song list (play, right-click menu, the playing song
/// highlighted). Everything is computed on this Mac (ListeningSummary).
struct ListeningSummaryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var period: ListeningSummary.Period = .month
    @ViewState var summary: ListeningSummary? = nil
    /// Artist and channel pictures (their own square avatars), by channel id.
    @ViewState var photos: [String: String] = [:]
    /// The song list shows 20, then all 50 on "Show More".
    @ViewState var allSongs = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: d.sectionGap) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ListeningSummary.Period.allCases) { p in
                            ChipButton(title: p.title, isOn: period == p) { period = p }
                        }
                    }
                    .padding(.horizontal, d.pad)
                }

                if let summary {
                    if summary.isEmpty {
                        EmptyStateView(systemImage: "chart.bar.xaxis",
                                       title: M.t("Bu dönemde dinleme yok", "No listening in this period"),
                                       message: ListeningLog.isEnabled
                                           ? M.t("Şarkı dinledikçe özetin burada oluşur.", "Your summary builds up here as you listen.")
                                           : M.t("Dinleme geçmişi kapalı: Ayarlar → Gizlilik'ten açabilirsin.",
                                                 "Listening history is off: turn it on in Settings → Privacy."))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                            .transition(.softReveal)
                    } else {
                        content(summary)
                    }
                } else {
                    PageSkeleton(layout: .tiles)
                }

                Text(M.t("Bu özet yalnızca bu Mac'teki dinleme geçmişinden hesaplanır; hiçbir yere gönderilmez. En az 30 saniye dinlenen şarkılar sayılır.",
                         "Computed only from the listening history on this Mac; nothing is sent anywhere. Songs heard for at least 30 seconds count."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, d.pad)
            }
            .padding(.vertical, d.pageTop)
        }
        .navigationTitle(M.t("Dinleme özetin", "Your listening"))
        .pageChrome()
        .task(id: period) {
            let s = await ListeningSummary.load(period)
            withAnimation(.soft) { summary = s }
            await loadPhotos(for: s)
        }
    }

    @ViewBuilder
    private func content(_ s: ListeningSummary) -> some View {
        // Headline, like the home page's greeting.
        VStack(alignment: .leading, spacing: 4) {
            Text(headline(s))
                .font(.system(size: d.v(22, 26), weight: .bold))
                .contentTransition(.numericText())
            Text(M.t("\(s.songCount) farklı şarkı · \(s.artistCount) sanatçı ve kanal · \(s.plays) dinleme",
                     "\(M.count(s.songCount, "different song", "different songs")) · \(M.count(s.artistCount, "artist or channel", "artists and channels")) · \(M.count(s.plays, "play", "plays"))"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, d.pad)
        .animation(.soft, value: s.seconds)

        // Top artists and channels: the app's square cards, with their own pictures.
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            SectionTitle(title: M.t("En çok dinlediğin sanatçılar ve kanallar", "Your top artists and channels"))
                .padding(.horizontal, d.pad)
            CardCarousel(section: Shelf(id: "summary-artists-\(period.rawValue)", title: "", strapline: nil, layout: "cards",
                                        items: s.topArtists.map(artistItem), more: nil, continuation: nil, top: nil))
        }

        // Top songs: a regular song list.
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            SectionTitle(title: M.t("En çok dinlediğin şarkılar", "Your top songs"))
                .padding(.horizontal, d.pad)
            TrackList(items: (allSongs ? s.topSongs : Array(s.topSongs.prefix(20))).map(songItem),
                      numbered: true, showArtwork: true, showAlbum: false, showHeader: false)
                .padding(.horizontal, d.pad)
                .animation(.soft, value: allSongs)
            if s.topSongs.count > 20 {
                Button(allSongs ? M.t("Daha Az Göster", "Show Less") : M.t("Daha Fazla Göster", "Show More")) {
                    withAnimation(.soft) { allSongs.toggle() }
                }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func headline(_ s: ListeningSummary) -> String {
        let time = Self.duration(s.seconds)
        switch period {
        case .week: return M.t("Son 7 günde \(time) dinledin", "\(time) of listening in the last 7 days")
        case .month: return M.t("Son 30 günde \(time) dinledin", "\(time) of listening in the last 30 days")
        case .year: return M.t("Bu yıl \(time) dinledin", "\(time) of listening this year")
        case .all: return M.t("Toplam \(time) dinledin", "\(time) of listening in all")
        }
    }

    /// A card that opens the artist's (or channel's) page; its time under the name.
    private func artistItem(_ a: ListeningSummary.Artist) -> MediaItem {
        MediaItem(uid: "summary-artist-\(a.id)", kind: "artist", title: a.name, subtitle: Self.duration(a.seconds),
                  thumbnail: a.channelId.flatMap { photos[$0] }, videoId: nil, browseId: a.channelId, params: nil,
                  playlistId: nil, artists: [], album: nil, duration: nil, explicit: false, play: nil,
                  wide: false, color: nil)
    }

    /// A song row; how often it was played stands where a list shows the length.
    private func songItem(_ song: ListeningSummary.Song) -> MediaItem {
        MediaItem(uid: "summary-song-\(song.id)", kind: "song", title: song.title, subtitle: song.artist,
                  thumbnail: song.cover ?? "https://i.ytimg.com/vi/\(song.id)/hqdefault.jpg",
                  videoId: song.id, browseId: nil, params: nil, playlistId: nil,
                  artists: zip(song.artists, song.artistIds).map { ArtistRef(name: $0.0, id: $0.1) },
                  album: nil, duration: M.t("\(song.plays) kez", "\(song.plays)×"), explicit: false,
                  play: watchEndpoint(videoId: song.id), wide: false, color: nil)
    }

    /// The top artists' and channels' own square pictures (not their pages' banners).
    private func loadPhotos(for s: ListeningSummary) async {
        let ids = s.topArtists.compactMap(\.channelId).filter { $0.hasPrefix("UC") }
        guard ids.contains(where: { photos[$0] == nil }) else { return }
        let found = await app.engine.channelPhotos(ids)
        guard !Task.isCancelled else { return }
        withAnimation(.soft) { photos.merge(found) { _, new in new } }
    }

    /// "12 sa 30 dk", "45 dk", "1 dk".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return M.t("\(h) sa \(m) dk", "\(h) h \(m) min") }
        return M.t("\(max(m, seconds > 0 ? 1 : 0)) dk", "\(max(m, seconds > 0 ? 1 : 0)) min")
    }
}
