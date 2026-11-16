import SwiftUI

/// Floating glass player capsule at the bottom of the content area.
struct PlayerBar: View {
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 820
            // Layout rule: the controls sit in two equally wide side columns, so the
            // now-playing block between them is always exactly centred in the bar. Inside
            // the block, the cover is as tall as the text column and the title, artist and
            // progress line all start at the same edge right of the cover.
            let side: CGFloat = compact ? 110 : 240
            HStack(spacing: 12) {
                TransportControls(compact: compact)
                    .frame(width: side, alignment: .leading)
                NowPlayingCenter(artSide: d.playerBar - 14)
                    .frame(maxWidth: .infinity)
                TrailingControls(compact: compact)
                    .frame(width: side, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(width: geo.size.width, height: d.playerBar)
            // On hover the bar grows a touch in every direction and turns less transparent.
            .background(
                Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(hover ? 0.6 : 0))
            )
            .glassCapsule()
            .scaleEffect(hover ? 1.012 : 1, anchor: .center)
            .shadow(color: .black.opacity(hover ? 0.22 : 0), radius: 16, y: 6)
            .onHover { h in withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { hover = h } }
        }
        .frame(height: d.playerBar)
    }
}

private struct TransportControls: View {
    let compact: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let e = app.engine
        HStack(spacing: compact ? 6 : 10) {
            if !compact {
                ToolbarIconButton(system: "shuffle", size: 14, help: "Karıştır") { e.shuffle() }
            }
            ToolbarIconButton(system: "backward.fill", size: 16, bounce: true, help: "Önceki") { e.previous() }
            Button { e.togglePlay() } label: {
                ZStack {
                    if e.isLoading && e.track != nil {
                        ProgressView().controlSize(.small)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        // Play ⇄ pause morphs with a symbol replace, plus a small bounce.
                        Image(systemName: e.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                            .symbolEffect(.bounce.down, value: e.isPlaying)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: e.isPlaying)
                .animation(.easeInOut(duration: 0.2), value: e.isLoading && e.track != nil)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .help(e.isPlaying ? "Duraklat" : "Çal")
            ToolbarIconButton(system: "forward.fill", size: 16, bounce: true, help: "Sonraki") { e.next() }
            if !compact {
                ToolbarIconButton(system: e.repeatMode == "ONE" ? "repeat.1" : "repeat", size: 14,
                                  active: e.repeatMode != "NONE",
                                  help: "Tekrarlama: \(e.repeatMode == "NONE" ? "Kapalı" : (e.repeatMode == "ALL" ? "Tümü" : "Tek şarkı"))") {
                    e.cycleRepeat()
                }
            }
        }
        .disabled(e.track == nil)
    }
}

private struct NowPlayingCenter: View {
    /// Height of the cover (and of the text column beside it).
    let artSide: CGFloat
    @Environment(AppModel.self) private var app
    @ViewState var hover = false

    var body: some View {
        let e = app.engine
        // Videos get their real 16:9 frame (mqdefault has no black bars), songs a square cover.
        let isVideo = e.track?.artwork?.contains("ytimg.com") ?? false
        HStack(spacing: 10) {
            Artwork(url: isVideo ? e.track.map { "https://i.ytimg.com/vi/\($0.videoId)/mqdefault.jpg" } : e.track?.artwork,
                    cornerRadius: 5)
                .frame(width: isVideo ? (artSide * 16 / 9).rounded() : artSide, height: artSide)
                .animation(.easeInOut(duration: 0.25), value: isVideo)

            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if let t = e.track {
                        let albumId = e.currentAlbumId
                        VStack(alignment: .leading, spacing: 0) {
                            Marquee(id: t.videoId) {
                                HoverLink(t.title, font: .system(size: 12, weight: .semibold), color: .primary,
                                          action: albumId.map { id in { app.openAlbum(id) } })
                                    .help(albumId == nil ? "" : "Albüme git")
                            }
                            Marquee(id: t.videoId + "a") {
                                ArtistByline(artists: e.currentArtists, fallback: t.artist, font: .system(size: 11))
                            }
                        }
                        .id(t.videoId)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)),
                                                removal: .opacity.combined(with: .offset(y: -6))))
                    } else {
                        Text("Çalan bir şey yok")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProgressLine()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: artSide)
        // One block of fixed maximum width, centred in the bar by its parent.
        .frame(maxWidth: 520)
        .animation(.easeInOut(duration: 0.35), value: e.track?.videoId)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}


private struct ProgressLine: View {
    @Environment(AppModel.self) private var app
    @ViewState var dragValue: Double? = nil

    var body: some View {
        let e = app.engine
        let activity = AppActivity.shared
        // Wakes on each whole second of the song (half second while in front, so the bar
        // moves smoothly), only while it plays and a window is on screen.
        let ticking = e.isPlaying && !e.isLoading && activity.isVisible
        TimelineView(PlaybackSchedule(position: e.position, date: e.positionDate, running: ticking,
                                      step: activity.isActive ? 0.5 : 1)) { ctx in
            let duration = e.track?.duration ?? 0
            let pos = dragValue ?? e.position(at: ctx.date)
            // Room for "1:23:45" on long sets, "3:45" otherwise.
            let long = duration >= 3600
            let elapsedW: CGFloat = long ? 44 : (duration >= 600 ? 32 : 28)
            HStack(spacing: 6) {
                Text(formatTime(pos))
                    .frame(width: elapsedW, alignment: .leading)   // starts at the title's edge
                ThinSlider(value: duration > 0 ? pos / duration : 0,
                           onChanged: { dragValue = $0 * duration },
                           onEnded: {
                               e.seek(to: $0 * duration)
                               dragValue = nil
                           })
                Text(duration > 0 ? "-" + formatTime(max(0, duration - pos)) : "")
                    .frame(width: elapsedW + 6, alignment: .leading)
            }
            .font(.system(size: 10).monospacedDigit())
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(.secondary)
        }
        .disabled(e.track == nil)
    }
}

/// Minimal slider: thin track that thickens on hover.
struct ThinSlider: View {
    var value: Double
    var onChanged: (Double) -> Void
    var onEnded: (Double) -> Void
    var tint: Color = .primary
    @ViewState var hover = false
    @ViewState var dragging = false

    var body: some View {
        GeometryReader { g in
            let w = max(1, g.size.width)
            let v = min(max(value.isFinite ? value : 0, 0), 1)
            let thickness: CGFloat = hover || dragging ? 5 : 3
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15)).frame(height: thickness)
                Capsule().fill(tint.opacity(0.75)).frame(width: w * v, height: thickness)
            }
            .frame(width: w, height: g.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { d in
                        dragging = true
                        onChanged(min(max(d.location.x / w, 0), 1))
                    }
                    .onEnded { d in
                        dragging = false
                        onEnded(min(max(d.location.x / w, 0), 1))
                    }
            )
        }
        .frame(height: 10)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

private struct TrailingControls: View {
    let compact: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        let e = app.engine
        HStack(spacing: 4) {
            if !compact {
                ToolbarIconButton(system: e.likeStatus == "DISLIKE" ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                                  size: 14, help: "Beğenme") { e.dislike() }
                    .disabled(e.track == nil)
            }
            ToolbarIconButton(system: e.likeStatus == "LIKE" ? "hand.thumbsup.fill" : "hand.thumbsup",
                              size: 14, active: e.likeStatus == "LIKE", help: "Beğen") { e.like() }
                .disabled(e.track == nil)
            if !compact && e.loggedIn {
                let saved = !e.savedIn.isEmpty
                ToolbarIconButton(system: saved ? "text.badge.checkmark" : "text.badge.plus", size: 14, active: saved,
                                  help: saved ? "Şu listelerde: \(e.savedIn.joined(separator: ", ")) — başka bir listeye ekle"
                                              : "Çalma listesine ekle") {
                    app.addCurrentToPlaylist()
                }
                .disabled(e.track == nil)
            }
            ToolbarIconButton(system: volumeIcon(e), size: 14, help: e.muted ? "Sesi aç" : "Sessiz") { e.toggleMute() }
            if !compact {
                ThinSlider(value: e.muted ? 0 : e.volume / 100,
                           onChanged: { e.setVolume(($0 * 100).rounded()) },
                           onEnded: { e.setVolume(($0 * 100).rounded()) })
                    .frame(width: 80)
            }
            let hasLyrics = LyricsCenter.shared.available(for: e.track?.videoId)
            ToolbarIconButton(system: "quote.bubble", size: 14, active: hasLyrics && app.isPanelVisible && app.showLyrics,
                              help: !hasLyrics ? "Bu şarkının sözleri yok"
                                  : (app.isPanelVisible && app.showLyrics ? "Şarkı sözlerini gizle" : "Şarkı sözlerini göster")) {
                app.toggleLyrics()
            }
            .disabled(!hasLyrics)
            .opacity(hasLyrics ? 1 : 0.35)
        }
    }

    private func volumeIcon(_ e: YTMusic) -> String {
        if e.muted || e.volume == 0 { return "speaker.slash.fill" }
        if e.volume < 34 { return "speaker.wave.1.fill" }
        if e.volume < 67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
