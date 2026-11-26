import SwiftUI
import AppKit

/// Right column: Now Playing, with expandable Lyrics and Queue sections.
///
/// Nothing selected → big moving cover, info and cards. "Sözler" → the cover slides up
/// into a compact header and the lyrics flow underneath. "Sıra" → the queue opens
/// below (under the lyrics if those are open too).
struct SidePanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 32
            // The cover fills the panel's width when the window is tall enough (a third of
            // the height at most, so the lyrics and queue keep their room).
            let art = max(140, min(w, geo.size.height * 0.32))
            let showLyrics = app.showLyrics && LyricsCenter.shared.available(for: app.engine.track?.videoId)
            VStack(alignment: .leading, spacing: 14) {
                if let t = app.engine.track {
                    NowPlayingHeader(track: t, maxArt: art, width: w)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    if showLyrics {
                        LyricsFlow(videoId: t.videoId, fontSize: d.lyricsFont)
                            .transition(.opacity)
                    }

                    PanelQueueSection()
                        .frame(minHeight: 180, maxHeight: showLyrics ? max(200, geo.size.height * 0.28) : .infinity)
                        .padding(.bottom, 10)
                } else {
                    EmptyStateView(systemImage: "music.note", title: M.t("Çalan bir şey yok", "Nothing playing"),
                                   message: M.t("Bir şarkı seçtiğinde burada kapak ve sıra görünür.", "Pick a song to see its cover and the queue here."))
                        .padding(.top, 40)
                    Spacer()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: showLyrics)
        }
        // Same surface as the sidebar: the system sidebar material (it blends with what is
        // behind the window) with the moving background on top at the same strength.
        .background(AmbientField(strength: MainWindow.paneStrength))
        .background(SidebarMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

/// Lyrics of the current track, loaded once per track as soon as it starts (whether or
/// not the panel is open), so the player bar knows if there are any before you click.
@MainActor
@Observable
final class LyricsCenter {
    static let shared = LyricsCenter()

    enum State { case idle, loading, available, none }

    private(set) var videoId: String?
    private(set) var state: State = .idle
    private(set) var synced: [LyricLine] = []
    private(set) var plain: [String] = []

    func available(for id: String?) -> Bool {
        id != nil && id == videoId && state == .available
    }

    func load(_ track: TrackInfo?) async {
        guard let t = track else {
            videoId = nil
            state = .idle
            return
        }
        if videoId == t.videoId, state == .available || state == .none { return }
        videoId = t.videoId
        synced = []
        plain = []
        state = .loading
        let e = YTMusic.shared
        // Wait for the real duration (it can be 0 for a moment after a track starts).
        for _ in 0..<20 where (e.track?.duration ?? 0) <= 0 {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !Task.isCancelled, e.track?.videoId == t.videoId else { return }
        let cur = e.track ?? t
        var s: [LyricLine] = []
        var p: [String] = []
        if cur.duration > 0, cur.duration < 15 * 60,
           let lines = await SyncedLyricsService.fetch(videoId: t.videoId, title: cur.title,
                                                      artist: cur.artist, duration: cur.duration) {
            s = lines
        } else {
            let l = try? await e.lyrics(videoId: t.videoId)
            p = (l?.text ?? "").components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard !Task.isCancelled, videoId == t.videoId else { return }
        apply(s, p)
    }

    private func apply(_ s: [LyricLine], _ p: [String]) {
        synced = s
        plain = p
        state = s.isEmpty && p.isEmpty ? .none : .available
    }
}

/// Lyrics for the current track. Time-synced lines (LRCLIB) follow the song exactly and
/// can be clicked to seek; if only plain lyrics exist (YouTube Music) they are shown
/// statically — no guessed scrolling.
struct LyricsFlow: View {
    let videoId: String
    var fontSize: CGFloat = 21
    @Environment(AppModel.self) private var app

    var body: some View {
        let e = app.engine
        let center = LyricsCenter.shared
        Group {
            if center.videoId == videoId, !center.synced.isEmpty {
                let ticking = e.isPlaying && !e.isLoading && AppActivity.shared.isVisible
                // Wakes exactly when the next line begins (every few seconds), not 4×/s.
                TimelineView(PlaybackSchedule(position: e.position, date: e.positionDate, running: ticking,
                                              marks: center.synced.map { $0.time - 0.25 })) { ctx in
                    let pos = e.position(at: ctx.date) + 0.25
                    let current = (center.synced.lastIndex { $0.time <= pos }) ?? -1
                    // Equatable: the list is rebuilt only when the sung line changes.
                    SyncedLyricsLines(lines: center.synced, current: current, fontSize: fontSize) { t in e.seek(to: t) }
                        .equatable()
                }
            } else if center.videoId == videoId, !center.plain.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(center.plain.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: fontSize - 3, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                }
                .scrollIndicators(.never)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

private struct SyncedLyricsLines: View, Equatable {
    nonisolated static func == (a: SyncedLyricsLines, b: SyncedLyricsLines) -> Bool {
        a.current == b.current && a.fontSize == b.fontSize && a.lines.count == b.lines.count
            && a.lines.first?.text == b.lines.first?.text && a.lines.last?.text == b.lines.last?.text
    }

    /// The line being sung sits near the top of the lyrics area (not in the middle).
    static let anchor = UnitPoint(x: 0, y: 0.12)
    let lines: [LyricLine]
    let current: Int
    let fontSize: CGFloat
    let seek: (Double) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: fontSize * 0.7) {
                    Color.clear.frame(height: 10)
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        Text(line.text)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundStyle(.primary.opacity(i == current ? 1 : (i < current ? 0.3 : 0.42)))
                            .scaleEffect(i == current ? 1.0 : 0.96, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture { seek(line.time) }
                            .id(i)
                    }
                    Color.clear.frame(height: 160)
                }
                .padding(.horizontal, 18)
                .animation(.easeInOut(duration: 0.35), value: current)
            }
            .scrollIndicators(.never)
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.08),
                                       .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .onAppear { proxy.scrollTo(max(current, 0), anchor: Self.anchor) }
            .onChange(of: current) { _, c in
                withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(max(c, 0), anchor: Self.anchor) }
            }
        }
    }
}

private struct PanelQueueSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(M.t("Sıradaki", "Up Next"))
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 18)
                .padding(.top, 12)
            QueuePanel(showCurrent: false)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.05)))
        .padding(.horizontal, 10)
    }
}

/// Loads and shows the current track's lyrics (shared by the side panel and full-screen player).
struct LyricsContent: View {
    var fontSize: CGFloat = 19
    var showHeader = true
    @Environment(AppModel.self) private var app
    @ViewState var lyrics: LyricsData? = nil
    @ViewState var loading = false

    var body: some View {
        let track = app.engine.track
        VStack(alignment: .leading, spacing: 16) {
            if let track {
                if showHeader {
                    HStack(spacing: 10) {
                        Artwork(url: track.artwork, cornerRadius: 5).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(track.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                if loading && lyrics == nil {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
                } else if let text = lyrics?.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: fontSize, weight: .semibold))
                        .lineSpacing(fontSize * 0.38)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let src = lyrics?.source, !src.isEmpty {
                        Text(src).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                } else {
                    EmptyStateView(systemImage: "quote.bubble", title: M.t("Söz bulunamadı", "No lyrics found"),
                                   message: M.t("Bu şarkı için YouTube Music'te söz yok.", "YouTube Music has no lyrics for this song."))
                }
            } else {
                EmptyStateView(systemImage: "music.note", title: M.t("Çalan bir şey yok", "Nothing playing"))
            }
        }
        .task(id: track?.videoId) {
            guard let id = track?.videoId else { lyrics = nil; return }
            lyrics = nil
            loading = true
            let l = try? await app.engine.lyrics(videoId: id)
            if !Task.isCancelled { lyrics = l }
            loading = false
        }
    }
}

struct QueuePanel: View {
    /// When false only the upcoming tracks are listed (no "now playing" row / labels).
    var showCurrent = true
    @Environment(AppModel.self) private var app

    var body: some View {
        let queue = app.engine.queue
        let current = queue.firstIndex(where: { $0.selected })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if queue.isEmpty && app.engine.track != nil {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if queue.isEmpty {
                    EmptyStateView(systemImage: "list.bullet", title: M.t("Sıra boş", "The queue is empty"),
                                   message: M.t("Bir şey çalmaya başladığında sıradaki şarkılar burada görünür.", "Once something plays, the songs coming up appear here."))
                } else if !showCurrent {
                    ForEach(queue.dropFirst((current ?? -1) + 1), id: \.rowKey) { entry in
                        QueueRow(entry: entry, current: false)
                            .transition(Self.rowTransition)
                    }
                } else {
                    if let c = current {
                        Text(M.t("Şu an çalıyor", "Now Playing"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                        QueueRow(entry: queue[c], current: true)
                    }
                    Text(M.t("Sıradaki", "Up Next"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 14)
                    ForEach(queue.dropFirst((current ?? -1) + 1), id: \.rowKey) { entry in
                        QueueRow(entry: entry, current: false)
                            .transition(Self.rowTransition)
                    }
                }
            }
            .padding(8)
        }
    }

    /// A song taken out slides away; the rest close the gap.
    static let rowTransition = AnyTransition.asymmetric(
        insertion: .opacity,
        removal: .move(edge: .trailing).combined(with: .opacity))
}

struct QueueRow: View {
    let entry: QueueEntry
    let current: Bool
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Artwork(url: entry.thumbnail, cornerRadius: 4)
                if current && app.engine.isPlaying {
                    Color.black.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 4))
                    EqualizerIcon(color: .white)
                } else if hover {
                    Color.black.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 4))
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: d.queueArt, height: d.queueArt)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: current ? .semibold : .regular))
                    .foregroundStyle(current ? Color.brand : Color.primary)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(entry.duration)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, d.v(4, 5))
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if !current { app.engine.playQueue(index: entry.index) } }
        .contextMenu {
            if !current {
                Button(M.t("Çal", "Play")) { app.engine.playQueue(index: entry.index) }
                if entry.videoId != nil {
                    Divider()
                    Button(M.t("Bana önerme", "Don't recommend")) { app.notInterested(entry) }
                }
            }
        }
    }
}

