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
    /// A cover's measured shape, for the cover it was measured on.
    @ViewState var measured: (url: String, aspect: CGFloat)? = nil
    /// Full-frame 16:9 thumbnail for a video, for the video it belongs to.
    @ViewState var frame: (videoId: String, url: String)? = nil

    private var isVideo: Bool {
        app.engine.hasVideo || (track.artwork?.contains("ytimg.com") ?? false)
    }

    /// Known before any picture arrives, so the cover takes its shape at once (at launch,
    /// nothing is in memory yet): a video is 16:9 — its frames are cut to that — a song is
    /// square until its own cover says otherwise. A shape measured on another cover is never
    /// borrowed.
    private var aspect: CGFloat {
        if isVideo { return 16.0 / 9.0 }
        if let m = measured, m.url == track.artwork { return m.aspect }
        return 1
    }

    /// The video's own frame once found; until then the player's artwork (its 4:3 black
    /// bars fall outside the 16:9 crop). Never the previous video's frame.
    private var picture: String? {
        if isVideo, let f = frame, f.videoId == track.videoId { return f.url }
        return track.artwork
    }

    var body: some View {
        let e = app.engine
        let wide = aspect > 1.2
        let artW = wide ? width : min(maxArt, width)
        let artH = wide ? artW / aspect : artW
        let albumId = e.currentAlbumId

        VStack(alignment: .leading, spacing: 14) {
            RemoteImage(url: picture)
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
                // maxresdefault is the real 16:9 frame (what YouTube shows as the preview);
                // sd/hq are 4:3 with black bars, which the 16:9 crop removes.
                let id = track.videoId
                guard frame?.videoId != id else { return }
                for name in ["maxresdefault", "sddefault", "hqdefault"] {
                    let u = "https://i.ytimg.com/vi/\(id)/\(name).jpg"
                    if let img = await ImageLoader.shared.load(u), img.size.height > 0 {
                        guard !Task.isCancelled else { return }
                        frame = (id, u)
                        return
                    }
                }
                return
            }
            guard let u = track.artwork, measured?.url != u,
                  let img = await ImageLoader.shared.load(u), img.size.height > 0,
                  !Task.isCancelled else { return }
            let r = img.size.width / img.size.height
            // A cover that is nearly square is shown square.
            measured = (u, abs(r - 1) < 0.05 ? 1 : r)
        }
    }
}
