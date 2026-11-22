import SwiftUI

/// Sidebar → Your listening: the on-device history summed up for a period. Everything is
/// computed on this Mac (ListeningSummary); nothing is sent anywhere.
struct ListeningSummaryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var period: ListeningSummary.Period = .month
    @ViewState var summary: ListeningSummary? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: d.sectionGap) {
                Picker("", selection: $period) {
                    ForEach(ListeningSummary.Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

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
                            .transition(.softReveal)
                    }
                } else {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
                }

                Text(M.t("Bu özet yalnızca bu Mac'teki dinleme geçmişinden hesaplanır; hiçbir yere gönderilmez. En az 30 saniye dinlenen şarkılar sayılır.",
                         "Computed only from the listening history on this Mac; nothing is sent anywhere. Songs heard for at least 30 seconds count."))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, d.pad)
            .padding(.vertical, d.pageTop)
            .animation(.soft, value: summary?.seconds)
        }
        .navigationTitle(M.t("Dinleme özetin", "Your listening"))
        .pageChrome()
        .task(id: period) {
            let s = await ListeningSummary.load(period)
            withAnimation(.soft) { summary = s }
        }
    }

    @ViewBuilder
    private func content(_ s: ListeningSummary) -> some View {
        HStack(spacing: 12) {
            StatTile(value: Self.duration(s.seconds), label: M.t("dinleme", "listened"), icon: "headphones")
            StatTile(value: "\(s.songCount)", label: M.t("farklı şarkı", "different songs"), icon: "music.note")
            StatTile(value: "\(s.artistCount)", label: M.t("farklı sanatçı ve kanal", "different artists and channels"), icon: "person.2")
        }

        HStack(alignment: .top, spacing: d.v(20, 32)) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: M.t("En çok dinlediğin sanatçılar ve kanallar", "Your top artists and channels"))
                let top = s.topArtists.first?.seconds ?? 1
                ForEach(Array(s.topArtists.enumerated()), id: \.element.id) { i, a in
                    ArtistBar(rank: i + 1, artist: a, fraction: a.seconds / max(top, 1), time: Self.duration(a.seconds)) {
                        if let id = a.channelId, id.hasPrefix("UC") { app.openArtist(id) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: M.t("En çok dinlediğin şarkılar", "Your top songs"))
                VStack(spacing: 0) {
                    ForEach(Array(s.topSongs.enumerated()), id: \.element.id) { i, song in
                        SongLine(rank: i + 1, song: song,
                                 detail: M.t("\(song.plays) kez · \(Self.duration(song.seconds))",
                                             "\(song.plays)× · \(Self.duration(song.seconds))"),
                                 isCurrent: app.engine.track?.videoId == song.id) {
                            // As everywhere in the app: the song, then YouTube Music's radio from it.
                            app.engine.play(endpoint: watchEndpoint(videoId: song.id))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// "12 sa 30 dk", "45 dk", "1 dk".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h > 0 { return M.t("\(h) sa \(m) dk", "\(h) h \(m) min") }
        return M.t("\(max(m, seconds > 0 ? 1 : 0)) dk", "\(max(m, seconds > 0 ? 1 : 0)) min")
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
    }
}

private struct ArtistBar: View {
    let rank: Int
    let artist: ListeningSummary.Artist
    let fraction: Double
    let time: String
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(rank). \(artist.name)")
                        .font(.system(size: 13, weight: rank == 1 ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer()
                    Text(time)
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    Capsule()
                        .fill(Color.brand.opacity(hover ? 1 : 0.8))
                        .frame(width: max(4, g.size.width * fraction))
                }
                .frame(height: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.soft, value: fraction)
    }
}

/// A top song: rank, cover, title, artist, how often and how long. As in every song
/// list: the cover's ▶︎ (or a double-click) plays it, followed by YouTube Music's radio
/// from it; the right-click menu says so.
private struct SongLine: View {
    let rank: Int
    let song: ListeningSummary.Song
    let detail: String
    let isCurrent: Bool
    let play: () -> Void
    @ViewState var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18)
            ZStack {
                Artwork(url: song.cover, cornerRadius: 4, circle: false)
                if hover {
                    Color.black.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 4))
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
            .help(M.t("Çal (ardından bu şarkının radyosu)", "Play (then this song's radio)"))
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                    .lineLimit(1)
                Text(song.artist).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(detail)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2, perform: play)
        .contextMenu {
            Button(M.t("Şarkı Radyosunu Başlat", "Start Song Radio"), action: play)
        }
    }
}
