import SwiftUI
import AppKit

/// Top of the side panel: the cover on its own (no frame around it) and, below it with
/// clear spacing, the title (→ album) and artists (→ artist pages).
struct NowPlayingHeader: View {
    let track: TrackInfo
    /// Largest side the cover may take (keeps room for lyrics and the queue).
    let maxArt: CGFloat
    /// Width available inside the panel; the cover never exceeds it.
    let width: CGFloat
    @Environment(AppModel.self) private var app
    @ViewState var aspect: CGFloat = 1
    /// Full-frame 16:9 thumbnail for videos (falls back to the player's artwork).
    @ViewState var videoArt: String? = nil

    private var isVideo: Bool {
        app.engine.hasVideo || (track.artwork?.contains("ytimg.com") ?? false)
    }

    var body: some View {
        let e = app.engine
        let wide = aspect > 1.2
        let artW = wide ? width : min(maxArt, width)
        let artH = wide ? artW / aspect : artW
        let albumId = e.currentAlbumId

        VStack(alignment: .leading, spacing: 14) {
            RemoteImage(url: videoArt ?? track.artwork)
                .frame(width: artW, height: artH)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Marquee(id: track.videoId) {
                    HoverLink(track.title, font: .system(size: 19, weight: .bold), color: .primary,
                              action: albumId.map { id in { app.openAlbum(id) } })
                        .help(albumId == nil ? "" : M.t("Albüme git", "Go to album"))
                }
                Marquee(id: track.videoId + "a") {
                    ArtistByline(artists: e.currentArtists, fallback: track.artist,
                                 font: .system(size: 14, weight: .medium))
                }
            }
            .frame(width: width, alignment: .leading)
            .id(track.videoId)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity))
        }
        .animation(.easeInOut(duration: 0.35), value: track.videoId)
        .frame(width: width, alignment: .leading)
        .clipped()
        .task(id: "\(track.videoId)|\(track.artwork ?? "")|\(isVideo)") {
            if isVideo {
                // maxresdefault is the real 16:9 frame (what YouTube shows as the preview).
                let ids = track.videoId
                for name in ["maxresdefault", "sddefault", "hqdefault"] {
                    let u = "https://i.ytimg.com/vi/\(ids)/\(name).jpg"
                    if let img = await ImageLoader.shared.load(u), img.size.height > 0 {
                        guard !Task.isCancelled else { return }
                        let r = img.size.width / img.size.height
                        // sd/hq are 4:3 with black bars: a 16:9 crop removes just the bars.
                        aspect = r < 1.5 ? 16.0 / 9.0 : r
                        videoArt = u
                        return
                    }
                }
            }
            guard !Task.isCancelled else { return }
            videoArt = nil
            if let u = track.artwork, let img = await ImageLoader.shared.load(u), img.size.height > 0 {
                aspect = img.size.width / img.size.height
            } else {
                aspect = 1
            }
        }
    }
}
