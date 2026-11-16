import AppKit
import MediaPlayer

/// Publishes the current track to Control Center / the menu bar Now Playing widget and
/// routes media keys (F7–F9, AirPods, Touch Bar) back to the player.
@MainActor
final class NowPlayingBridge {
    private var artworkURL: String?
    private var artwork: MPMediaItemArtwork?
    private var lastTrack: TrackInfo?
    private var lastPlaying = false
    private var lastPosition: Double = 0

    private var active = false

    init() {}

    /// The app publishes Now Playing itself (direct playback).
    func activate() {
        guard !active else { return }
        active = true
        Self.registerCommands()
    }

    // Built outside the main actor so the closures don't inherit main-actor isolation
    // (MediaPlayer may invoke them from its own queues).
    nonisolated private static func registerCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in YTMusic.shared.remoteSetPlaying(nil) }
            return .success
        }
        c.playCommand.addTarget { _ in
            Task { @MainActor in YTMusic.shared.remoteSetPlaying(true) }
            return .success
        }
        c.pauseCommand.addTarget { _ in
            Task { @MainActor in YTMusic.shared.remoteSetPlaying(false) }
            return .success
        }
        c.nextTrackCommand.addTarget { _ in
            Task { @MainActor in YTMusic.shared.remoteNext() }
            return .success
        }
        c.previousTrackCommand.addTarget { _ in
            Task { @MainActor in YTMusic.shared.remotePrevious() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in YTMusic.shared.seek(to: t) }
            return .success
        }
    }

    nonisolated private static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    func update(track: TrackInfo?, playing: Bool, position: Double) {
        guard active else { return }
        lastTrack = track
        lastPlaying = playing
        lastPosition = position
        let center = MPNowPlayingInfoCenter.default()
        guard let track else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if track.artwork == artworkURL, let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused

        if let url = track.artwork, url != artworkURL {
            artworkURL = url
            artwork = nil
            Task { [weak self] in
                guard let image = await ImageLoader.shared.load(url, maxPixel: 600) else { return }
                guard let self, self.artworkURL == url else { return }
                self.artwork = Self.makeArtwork(image)
                self.update(track: self.lastTrack, playing: self.lastPlaying, position: self.lastPosition)
            }
        }
    }
}
