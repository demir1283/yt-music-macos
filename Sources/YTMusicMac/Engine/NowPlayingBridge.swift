import AppKit
import MediaPlayer

/// What the system Now Playing UI shows, read from the player whenever it is refreshed.
struct NowPlayingState {
    var track: TrackInfo?
    var playing: Bool
    var loading: Bool
    var position: Double
    var queueIndex: Int
    var queueCount: Int
}

/// Publishes the current track to Control Center / the menu bar Now Playing widget and
/// routes media keys (F7–F9, AirPods, Touch Bar) and the widget's buttons back to the player.
///
/// Every refresh rebuilds the whole entry from the player's live state (never from a copy
/// kept here), so the widget can't keep showing a song that is no longer playing:
/// - a new song gets a new content identifier and, until its cover arrives, the app icon,
///   so the previous song's cover never lingers;
/// - commands from the widget run before it is answered, so it reads the new song at once;
/// - the entry is published again shortly after a song change, since the system may drop
///   updates that arrive in quick succession.
@MainActor
final class NowPlayingBridge {
    /// The player's current state.
    var snapshot: (@MainActor () -> NowPlayingState?)?

    private var active = false
    private var publishedID: String?
    private var artworkURL: String?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var confirmTask: Task<Void, Never>?
    private var placeholder: MPMediaItemArtwork?

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
            onMain { YTMusic.shared.remoteSetPlaying(nil) }
            return .success
        }
        c.playCommand.addTarget { _ in
            onMain { YTMusic.shared.remoteSetPlaying(true) }
            return .success
        }
        c.pauseCommand.addTarget { _ in
            onMain { YTMusic.shared.remoteSetPlaying(false) }
            return .success
        }
        c.nextTrackCommand.addTarget { _ in
            onMain { YTMusic.shared.remoteNext() }
            return .success
        }
        c.previousTrackCommand.addTarget { _ in
            onMain { YTMusic.shared.remotePrevious() }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            onMain { YTMusic.shared.seek(to: t) }
            return .success
        }
    }

    /// Runs a command right away when called on the main thread (the usual case), so the
    /// new state is published before the widget gets its answer; otherwise hops to it.
    nonisolated private static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }

    nonisolated private static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    /// Publishes the player's current state.
    func refresh() {
        guard active, let state = snapshot?() else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let track = state.track else {
            confirmTask?.cancel()
            artworkTask?.cancel()
            publishedID = nil
            artworkURL = nil
            artwork = nil
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        if track.artwork != artworkURL {
            artworkURL = track.artwork
            artwork = nil
            loadArtwork(track.artwork)
        }

        // While a song is being fetched or buffers, time stands still in the widget too.
        let running = state.playing && !state.loading
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, state.position),
            MPNowPlayingInfoPropertyPlaybackRate: running ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyExternalContentIdentifier: track.videoId,
        ]
        if track.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = track.duration }
        if state.queueCount > 0 {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = state.queueIndex
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = state.queueCount
        }
        if let art = artwork ?? appIcon() { info[MPMediaItemPropertyArtwork] = art }

        center.nowPlayingInfo = info
        center.playbackState = state.playing ? .playing : .paused

        if track.videoId != publishedID {
            publishedID = track.videoId
            confirm(track.videoId)
        }
    }

    /// Publishes once more after a song change, in case the system dropped the update.
    private func confirm(_ videoId: String) {
        confirmTask?.cancel()
        confirmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self, self.publishedID == videoId else { return }
            self.refresh()
        }
    }

    private func loadArtwork(_ url: String?) {
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let image = await ImageLoader.shared.load(url, maxPixel: 600), !Task.isCancelled else { return }
            guard let self, self.artworkURL == url else { return }
            self.artwork = Self.makeArtwork(image)
            self.refresh()   // with the live position, not the one from when loading began
        }
    }

    private func appIcon() -> MPMediaItemArtwork? {
        if let placeholder { return placeholder }
        let art = Self.makeArtwork(NSApplication.shared.applicationIconImage)
        placeholder = art
        return art
    }
}
