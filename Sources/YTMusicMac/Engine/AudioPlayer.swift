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
///
/// Crossfade: when the setting is on, the standby player starts `crossfade` seconds before
/// the playing song ends and the two overlap — one turned down, the other up — until the
/// old one is let go (see `beginCrossfade`).
///
/// Nothing starts or stops abruptly: playing comes in over `softSeconds`, pausing goes out
/// over it, and a song cut short by another (a click, a skip) fades out in its own player
/// while the new one comes in (see `release`). A song that simply ends hands over to the
/// next as it is, so the next one's first beat isn't softened.
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
    /// The playing song is `crossfade` seconds from its end and the next one is ready: the
    /// engine may start it now with `load(…, crossfade:)`.
    var onCrossfade: (() -> Void)?

    /// Seconds the songs overlap (0: off). Set by the engine from the setting.
    var crossfade: Double = 0
    /// The current song has already offered its crossfade (once per song, again after a
    /// seek back).
    private var crossfadeOffered = false

    /// The listener's volume, 0…100. What the player gets is this times the song's `gain`.
    var volume: Double {
        get { Double(userVolume) * 100 }
        set {
            userVolume = Float(min(100, max(0, newValue)) / 100)
            applyVolume()
        }
    }
    private var userVolume: Float = 1

    /// What the players play at: the listener's volume, each song's leveling, the sleep
    /// timer's fade and, during a crossfade, how far it has come.
    private func applyVolume() {
        let curve = Self.crossfadeCurve(mix)
        player.volume = userVolume * gain * fade * ease * curve.incoming
        outgoing?.volume = userVolume * outgoingGain * fade * curve.outgoing
    }

    /// Volume leveling for the playing song: 1 leaves it as it is, below 1 turns a loud
    /// master down to YouTube's reference level. Changed mid-song, it eases over ~0.4 s.
    private(set) var gain: Float = 1
    private var gainRamp: Timer?
    private var rampFrom: Float = 1
    private var rampTo: Float = 1
    private var rampStep = 0
    private static let rampSteps = 12

    func setGain(_ value: Float, smoothly: Bool) {
        gainRamp?.invalidate()
        gainRamp = nil
        let target = min(1, max(0.1, value))
        guard smoothly, abs(target - gain) > 0.01 else {
            gain = target
            applyVolume()
            return
        }
        rampFrom = gain
        rampTo = target
        rampStep = 0
        // The timer runs on the main run loop, where this class lives.
        gainRamp = Timer.scheduledTimer(withTimeInterval: 0.4 / Double(Self.rampSteps), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rampTick() }
        }
    }

    private func rampTick() {
        rampStep += 1
        let t = Float(rampStep) / Float(Self.rampSteps)
        gain = rampFrom + (rampTo - rampFrom) * (t * t * (3 - 2 * t))
        applyVolume()
        if rampStep >= Self.rampSteps {
            gainRamp?.invalidate()
            gainRamp = nil
        }
    }

    // MARK: Sleep timer fade

    private var fade: Float = 1
    private var fadeTimer: Timer?
    private var fadeStep = 0
    private var fadeSteps = 1
    private var fadeDone: (() -> Void)?

    /// Turns the sound down to nothing over `seconds`, then calls `done` (which pauses);
    /// the volume is back to normal afterwards, ready for the next play.
    func fadeOut(over seconds: Double, then done: @escaping () -> Void) {
        cancelFade()
        fadeSteps = max(1, Int(seconds * 10))
        fadeStep = 0
        fadeDone = done
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeTick() }
        }
    }

    private func fadeTick() {
        fadeStep += 1
        let t = Float(fadeStep) / Float(fadeSteps)
        fade = max(0, 1 - t * t * (3 - 2 * t))
        applyVolume()
        guard fadeStep >= fadeSteps else { return }
        fadeTimer?.invalidate()
        fadeTimer = nil
        let done = fadeDone
        fadeDone = nil
        done?()
        fade = 1
        applyVolume()
    }

    func cancelFade() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        fadeDone = nil
        if fade != 1 {
            fade = 1
            applyVolume()
        }
    }

    // MARK: Soft start and stop

    /// How long playing, pausing and changing songs take to come in or go out.
    static let softSeconds: Double = 0.4
    private static let softSteps = 16

    /// The playing song's own fade in and out (0…1), and the one under way.
    private var ease: Float = 1
    private var easeStart: Float = 1
    private var easeEnd: Float = 1
    private var easeStep = 0
    private var easeTimer: Timer?
    private var easeDone: (() -> Void)?
    /// The loaded song comes in softly once its sound really starts.
    private var easeInOnStart = false

    /// A repeating timer that also runs while a menu is open, the window is being
    /// scrolled, or the app waits to quit (common run-loop modes).
    private static func repeating(_ interval: Double, _ block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func easeVolume(to target: Float, then done: (() -> Void)? = nil) {
        easeTimer?.invalidate()
        easeTimer = nil
        easeDone = done
        guard abs(target - ease) > 0.001 else {
            ease = target
            applyVolume()
            easeDone = nil
            done?()
            return
        }
        easeStart = ease
        easeEnd = target
        easeStep = 0
        easeTimer = Self.repeating(Self.softSeconds / Double(Self.softSteps)) { [weak self] _ in
            MainActor.assumeIsolated { self?.easeTick() }
        }
    }

    private func easeTick() {
        easeStep += 1
        let t = Float(easeStep) / Float(Self.softSteps)
        ease = easeStart + (easeEnd - easeStart) * (t * t * (3 - 2 * t))
        applyVolume()
        guard easeStep >= Self.softSteps else { return }
        easeTimer?.invalidate()
        easeTimer = nil
        let done = easeDone
        easeDone = nil
        done?()
    }

    /// Stops a fade under way (and what was to follow it, such as the pause).
    private func cancelEase() {
        easeTimer?.invalidate()
        easeTimer = nil
        easeDone = nil
    }

    /// Players let go while still sounding: each fades out from where it is, then stops.
    private struct Fading {
        let player: AVPlayer
        let start: Float
        var step = 0
        var timer: Timer?
    }
    private var fading: [ObjectIdentifier: Fading] = [:]

    private func release(_ old: AVPlayer) {
        let id = ObjectIdentifier(old)
        guard fading[id] == nil else { return }
        guard old.timeControlStatus != .paused, old.volume > 0.001 else {
            Self.stopNow(old)
            return
        }
        var f = Fading(player: old, start: old.volume)
        f.timer = Self.repeating(Self.softSeconds / Double(Self.softSteps)) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseTick(id) }
        }
        fading[id] = f
    }

    private func releaseTick(_ id: ObjectIdentifier) {
        guard var f = fading[id] else { return }
        f.step += 1
        let t = Float(f.step) / Float(Self.softSteps)
        f.player.volume = f.start * (1 - t * t * (3 - 2 * t))
        if f.step >= Self.softSteps {
            f.timer?.invalidate()
            fading[id] = nil
            Self.stopNow(f.player)
        } else {
            fading[id] = f
        }
    }

    private static func stopNow(_ p: AVPlayer) {
        p.pause()
        p.replaceCurrentItem(with: nil)
    }

    /// Makes `next` the playing player (same mute and output, observed) and returns the
    /// one it replaces, still as it was.
    private func swapPlayer(to next: AVPlayer) -> AVPlayer {
        let old = player
        detachPlayerObservers()
        player = next
        next.isMuted = old.isMuted
        next.audioOutputDeviceUniqueID = outputDeviceUID
        attachPlayerObservers()
        return old
    }

    // MARK: Crossfade

    /// The song being faded out, its leveling, and how far the crossfade has come (0…1;
    /// 1 when none runs).
    private var outgoing: AVPlayer?
    private var outgoingGain: Float = 1
    private var mix: Float = 1
    private var mixTimer: Timer?
    private var mixStep = 0
    private var mixSteps = 1
    private static let mixRate: Double = 20   // volume steps per second

    /// Equal-power curve: the sum of the two songs' power stays the same through the
    /// change, so the sound doesn't dip in the middle.
    nonisolated static func crossfadeCurve(_ t: Float) -> (incoming: Float, outgoing: Float) {
        let x = min(1, max(0, t)) * .pi / 2
        return (sin(x), cos(x))
    }

    /// The next song is ready and loaded enough to start now.
    private var nextIsReady: Bool {
        guard let item = standby?.player.currentItem, item.status == .readyToPlay else { return false }
        let needed = min(crossfade, Self.standbySeconds) - 1
        return item.loadedTimeRanges.contains { $0.timeRangeValue.end.seconds >= needed }
    }

    /// The address of the prepared next song, if one is waiting.
    var preparedURL: URL? { standby?.url }

    private func beginCrossfade(from old: AVPlayer, oldGain: Float, over seconds: Double) {
        outgoing = old
        outgoingGain = oldGain
        mix = 0
        mixStep = 0
        mixSteps = max(1, Int(seconds * Self.mixRate))
        mixTimer = Self.repeating(1 / Self.mixRate) { [weak self] _ in
            MainActor.assumeIsolated { self?.mixTick() }
        }
        EngineLog.write(String(format: "Geçiş: %.0f sn", seconds))
    }

    private func mixTick() {
        mixStep += 1
        mix = Float(mixStep) / Float(mixSteps)
        applyVolume()
        if mixStep >= mixSteps { endCrossfade() }
    }

    /// Lets the old song go: at the end of the crossfade, or (fading out quickly) when the
    /// listener pauses, seeks or plays something else.
    private func endCrossfade() {
        mixTimer?.invalidate()
        mixTimer = nil
        if let old = outgoing {
            outgoing = nil
            release(old)
        }
        if mix != 1 {
            mix = 1
            applyVolume()
        }
    }

    var isMuted: Bool {
        get { player.isMuted }
        set {
            player.isMuted = newValue
            outgoing?.isMuted = newValue
        }
    }

    /// CoreAudio UID of the device to play to; nil follows the system output. The waiting
    /// player gets it too, so the next song comes out of the same place.
    var outputDeviceUID: String? {
        didSet {
            player.audioOutputDeviceUniqueID = outputDeviceUID
            outgoing?.audioOutputDeviceUniqueID = outputDeviceUID
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

    /// `crossfade` > 0: the prepared next song starts under the playing one, which fades
    /// out over that many seconds (when the next song isn't the prepared one, the change is
    /// immediate as usual).
    func load(url: URL, headers: [String: String], duration: Double, autoplay: Bool, startAt: Double = 0,
              gain: Float = 1, crossfade: Double = 0) {
        endCrossfade()
        // The song before ended by itself: the change is as it is. Otherwise it was cut
        // short: it fades out, and this one comes in.
        let natural = finished
        cancelEase()
        // The new song's leveling applies once the old one has its own player (it fades
        // out at its own level).
        let previousGain = self.gain
        if EngineLog.enabled {
            loadedAt = Date()
            toldWait = nil
            EngineLog.write("Oynatıcı: yükleniyor — çıkış \(outputDeviceUID ?? "sistem")"
                            + (standby?.url == url ? ", önceden hazırlanmış" : ""))
        }
        clearItemObservers()
        finished = false
        crossfadeOffered = false
        knownDuration = duration
        // The next song was prepared: its player takes over with the opening already loaded.
        if let s = standby, s.url == url, startAt <= 1, let item = s.player.currentItem, item.status != .failed {
            standby = nil
            takeOver(s.player, item: item, autoplay: autoplay, gain: gain,
                     crossfade: crossfade, previousGain: previousGain, soft: !natural)
            return
        }
        discardNext()
        let item = Self.makeItem(url: url, headers: headers, buffer: Self.playingSeconds)
        if player.timeControlStatus != .paused {
            // The old song still sounds: it fades out in its own player, the new one gets
            // a fresh player.
            let fresh = AVPlayer()
            fresh.automaticallyWaitsToMinimizeStalling = true
            fresh.allowsExternalPlayback = false
            fresh.replaceCurrentItem(with: item)
            release(swapPlayer(to: fresh))
        } else {
            player.replaceCurrentItem(with: item)
        }
        setGain(gain, smoothly: false)
        comeIn(softly: !natural && autoplay)
        observe(item)
        if startAt > 1 {
            pendingStart = (startAt, autoplay)
        } else {
            pendingStart = nil
            if autoplay { player.play() }
        }
    }

    /// Makes the standby player the playing one (same volume and mute), and lets the old
    /// one go: over `crossfade` seconds under the new one, quickly if it was cut short
    /// (`soft`), or at once at its natural end.
    private func takeOver(_ next: AVPlayer, item: AVPlayerItem, autoplay: Bool, gain: Float,
                          crossfade: Double = 0, previousGain: Float = 1, soft: Bool = false) {
        let crossfades = crossfade > 0 && autoplay && player.timeControlStatus != .paused
        let old = swapPlayer(to: next)
        if crossfades {
            beginCrossfade(from: old, oldGain: previousGain, over: crossfade)
        } else {
            release(old)
        }
        setGain(gain, smoothly: false)
        comeIn(softly: soft && !crossfades && autoplay)
        item.preferredForwardBufferDuration = Self.playingSeconds
        pendingStart = nil
        observe(item)
        if autoplay { player.play() }
        stateChanged()
    }

    /// The new song's own level: from silence, rising once its sound starts (`softly`), or
    /// straight away.
    private func comeIn(softly: Bool) {
        ease = softly ? 0 : 1
        easeInOnStart = softly
        applyVolume()
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

    /// Plays on: from a pause it comes in softly once the sound starts; during a pause
    /// still fading out it simply comes back up.
    func play() {
        cancelEase()
        if player.timeControlStatus == .paused {
            comeIn(softly: true)
        } else {
            easeInOnStart = false
            easeVolume(to: 1)
        }
        player.play()
    }

    /// Pauses after fading out; `done` follows the pause (quitting waits for it).
    func pause(then done: (() -> Void)? = nil) {
        endCrossfade()
        easeInOnStart = false
        let p = player
        // Already silent (paused, or the sleep timer's fade has just ended): at once.
        guard p.timeControlStatus != .paused, ease > 0.001, fade > 0.001 else {
            cancelEase()
            p.pause()
            done?()
            return
        }
        easeVolume(to: 0) {
            p.pause()
            done?()
        }
    }

    func seek(to seconds: Double) {
        endCrossfade()
        finished = false
        crossfadeOffered = false
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    func stop() {
        endCrossfade()
        cancelEase()
        easeInOnStart = false
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
        // Near the end, with the next song ready: offer the crossfade (once).
        if crossfade > 0, !crossfadeOffered, knownDuration > crossfade * 3,
           seconds >= knownDuration - crossfade, outgoing == nil, nextIsReady {
            crossfadeOffered = true
            onCrossfade?()
        }
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
        if status == .playing, easeInOnStart {
            easeInOnStart = false
            easeVolume(to: 1)
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
