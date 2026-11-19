import Foundation
import AVFoundation

/// Thin wrapper around AVPlayer: plays the stream exactly as YouTube serves it.
///
/// Buffering: nothing is written to disk. The playing song keeps about a minute buffered
/// ahead in memory (a 3-hour set is never held whole: ~1.9 MB at 256 kbps, refilled as it
/// plays; long files are handed over as a playlist of their pieces, see `DashToHLS`, so
/// AVPlayer doesn't read them through before starting). The next song's first 10 seconds
/// wait in a second, silent player (`Standby`, ~320 KB); when that song comes up, the
/// standby player simply takes over, so the change is immediate instead of waiting for the
/// first bytes to download.
@MainActor
final class AudioPlayer {
    private var player = AVPlayer()
    private var timeObserver: Any?
    private var controlObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var currentID: ObjectIdentifier?
    private var knownDuration: Double = 0
    private var finished = false
    /// Seek-then-play to perform once the new item is ready (resuming a saved position).
    private var pendingStart: (seek: Double, play: Bool)?
    /// Diagnostic log only: when the current item was given to the player (cleared once it
    /// plays), and the last waiting reason written.
    private var loadedAt: Date?
    private var toldWait: String?

    var onTime: ((Double) -> Void)?
    var onState: ((_ playing: Bool, _ buffering: Bool) -> Void)?
    var onEnded: (() -> Void)?
    var onFailed: ((String) -> Void)?

    var volume: Double {
        get { Double(player.volume) * 100 }
        set { player.volume = Float(min(100, max(0, newValue)) / 100) }
    }

    var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    /// CoreAudio UID of the device to play to; nil follows the system output. The waiting
    /// player gets it too, so the next song comes out of the same place.
    var outputDeviceUID: String? {
        didSet {
            player.audioOutputDeviceUniqueID = outputDeviceUID
            standby?.player.audioOutputDeviceUniqueID = outputDeviceUID
        }
    }

    var hasItem: Bool { player.currentItem != nil }

    var currentTime: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    /// Seconds of the next song kept ready.
    static let standbySeconds: Double = 10
    /// Seconds kept buffered ahead of the playing song.
    static let playingSeconds: Double = 60

    /// The next song, loaded in a muted, paused player that buffers only its opening.
    private final class Standby {
        let player = AVPlayer()
        let url: URL

        init(url: URL, item: AVPlayerItem, output: String?) {
            self.url = url
            player.isMuted = true
            player.audioOutputDeviceUniqueID = output
            player.automaticallyWaitsToMinimizeStalling = true
            player.allowsExternalPlayback = false
            player.replaceCurrentItem(with: item)   // a paused player still buffers its item
        }

        func discard() {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private var standby: Standby?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback = false
        attachPlayerObservers()
    }

    private func attachPlayerObservers() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let s = time.seconds
            Task { @MainActor [weak self] in self?.tick(s) }
        }
        controlObserver = player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.stateChanged() }
        }
    }

    private func detachPlayerObservers() {
        if let t = timeObserver { player.removeTimeObserver(t) }
        timeObserver = nil
        controlObserver?.invalidate()
        controlObserver = nil
    }

    private static func makeItem(url: URL, headers: [String: String], buffer: Double) -> AVPlayerItem {
        var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": headers]
        if !url.absoluteString.contains(".m3u8") && !url.absoluteString.contains("/playlist") {
            // googlevideo serves raw MP4 audio; tell AVFoundation so it doesn't have to guess.
            options[AVURLAssetOverrideMIMETypeKey] = "audio/mp4"
        }
        let asset = AVURLAsset(url: url, options: options)
        if url.scheme == DashToHLS.scheme {
            asset.resourceLoader.setDelegate(DashToHLS.shared, queue: DashToHLS.shared.queue)
        }
        let item = AVPlayerItem(asset: asset)
        // Only this much is downloaded ahead; nothing beyond it sits in memory.
        item.preferredForwardBufferDuration = buffer
        return item
    }

    /// Loads the first `standbySeconds` of the song that comes next, in a silent player.
    func prepareNext(url: URL, headers: [String: String]) {
        if standby?.url == url { return }
        standby?.discard()
        standby = Standby(url: url, item: Self.makeItem(url: url, headers: headers, buffer: Self.standbySeconds),
                          output: outputDeviceUID)
    }

    /// Drops the prepared next song (the queue changed).
    func discardNext() {
        standby?.discard()
        standby = nil
    }

    func load(url: URL, headers: [String: String], duration: Double, autoplay: Bool, startAt: Double = 0) {
        if EngineLog.enabled {
            loadedAt = Date()
            toldWait = nil
            EngineLog.write("Oynatıcı: yükleniyor — çıkış \(outputDeviceUID ?? "sistem")"
                            + (standby?.url == url ? ", önceden hazırlanmış" : ""))
        }
        clearItemObservers()
        finished = false
        knownDuration = duration
        // The next song was prepared: its player takes over with the opening already loaded.
        if let s = standby, s.url == url, startAt <= 1, let item = s.player.currentItem, item.status != .failed {
            standby = nil
            takeOver(s.player, item: item, autoplay: autoplay)
            return
        }
        discardNext()
        let item = Self.makeItem(url: url, headers: headers, buffer: Self.playingSeconds)
        player.replaceCurrentItem(with: item)
        observe(item)
        if startAt > 1 {
            pendingStart = (startAt, autoplay)
        } else {
            pendingStart = nil
            if autoplay { player.play() }
        }
    }

    /// Makes the standby player the playing one (same volume and mute), and lets the old
    /// one go.
    private func takeOver(_ next: AVPlayer, item: AVPlayerItem, autoplay: Bool) {
        let old = player
        detachPlayerObservers()
        old.pause()
        old.replaceCurrentItem(with: nil)
        next.volume = old.volume
        next.isMuted = old.isMuted
        next.audioOutputDeviceUniqueID = outputDeviceUID
        player = next
        attachPlayerObservers()
        item.preferredForwardBufferDuration = Self.playingSeconds
        pendingStart = nil
        observe(item)
        if autoplay { player.play() }
        stateChanged()
    }

    private func observe(_ item: AVPlayerItem) {
        let id = ObjectIdentifier(item)
        currentID = id
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription ?? M.t("Oynatılamadı", "Couldn't play")
            Task { @MainActor [weak self] in self?.statusChanged(id, status, message) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish(id) }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)?.localizedDescription ?? M.t("Oynatılamadı", "Couldn't play")
            Task { @MainActor [weak self] in self?.failed(id, message) }
        }
    }

    private func statusChanged(_ id: ObjectIdentifier, _ status: AVPlayerItem.Status, _ message: String) {
        guard id == currentID else { return }
        if status == .readyToPlay, let t = loadedAt {
            EngineLog.write(String(format: "Oynatıcı: öğe hazır (+%.1f sn)", Date().timeIntervalSince(t)))
        }
        if status == .failed {
            failed(id, message)
        } else if status == .readyToPlay, let p = pendingStart {
            pendingStart = nil
            player.seek(to: CMTime(seconds: p.seek, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard p.play else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.currentID == id else { return }
                    self.player.play()
                }
            }
        }
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(to seconds: Double) {
        finished = false
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    func stop() {
        discardNext()
        clearItemObservers()
        currentID = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func clearItemObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        if let o = failObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        failObserver = nil
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, currentID != nil else { return }
        onTime?(seconds)
        // Some streams report a longer duration than the real one: end on the known length.
        if knownDuration > 1, seconds >= knownDuration - 0.05, let id = currentID { finish(id) }
    }

    private func stateChanged() {
        guard currentID != nil else { return }
        let status = player.timeControlStatus
        if let t = loadedAt {
            if status == .waitingToPlayAtSpecifiedRate {
                let why = (player.reasonForWaitingToPlay?.rawValue ?? "?").replacingOccurrences(of: "AVPlayerWaiting", with: "")
                if why != toldWait {
                    toldWait = why
                    EngineLog.write(String(format: "Oynatıcı: bekliyor — %@ (+%.1f sn)", why, Date().timeIntervalSince(t)))
                }
            } else if status == .playing {
                loadedAt = nil
                let event = player.currentItem?.accessLog()?.events.last
                EngineLog.write(String(format: "Oynatıcı: çalıyor (+%.1f sn) — indirme %.0f kbps, %lld bayt, ara bellek %.1f sn",
                                       Date().timeIntervalSince(t), (event?.observedBitrate ?? 0) / 1000,
                                       event?.numberOfBytesTransferred ?? 0, bufferedAhead))
            }
        }
        onState?(status != .paused, status == .waitingToPlayAtSpecifiedRate)
    }

    /// Seconds loaded ahead of the play position (diagnostic log).
    private var bufferedAhead: Double {
        guard let item = player.currentItem else { return 0 }
        let now = item.currentTime().seconds
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            if range.start.seconds <= now + 0.5, range.end.seconds >= now { return range.end.seconds - now }
        }
        return 0
    }

    private func finish(_ id: ObjectIdentifier) {
        guard id == currentID, !finished else { return }
        finished = true
        onEnded?()
    }

    private func failed(_ id: ObjectIdentifier, _ message: String) {
        guard id == currentID else { return }
        onFailed?(message)
    }
}
