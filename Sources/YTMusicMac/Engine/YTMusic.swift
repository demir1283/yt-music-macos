import Foundation
import SwiftUI
import WebKit
import Observation

enum WebSheetKind: String, Identifiable {
    /// Google sign-in: the only web page the app ever shows, and only while signing in.
    case login
    var id: String { rawValue }
}

enum EngineError: LocalizedError {
    case notReady
    case badResult
    case js(String)

    var errorDescription: String? {
        switch self {
        case .notReady: return M.t("YouTube Music'e bağlanılamadı.", "Couldn't connect to YouTube Music.")
        case .badResult: return M.t("YouTube Music'ten beklenmeyen bir yanıt geldi.", "YouTube Music sent an unexpected answer.")
        case .js(let m): return m
        }
    }
}

/// Ignores whatever JSON value comes back (used for fire-and-forget commands).
struct Ignored: Decodable {
    init(from decoder: Decoder) throws {}
}

/// The app's engine: YouTube Music data, the play queue and audio playback.
///
/// No web page is involved. Data comes from YouTube Music's API through `NativeCore`
/// (a bare JavaScriptCore context + URLSession); audio is the account's own stream,
/// played untouched by `AudioPlayer` (AVPlayer).
@MainActor
@Observable
final class YTMusic {
    static let shared = YTMusic()

    static let homeURL = URL(string: "https://music.youtube.com/")!
    static let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&passive=true&continue=https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26next%3Dhttps%253A%252F%252Fmusic.youtube.com%252F")!
    static let userAgent = YTAuth.userAgent

    @ObservationIgnored private var core: NativeCore?
    @ObservationIgnored private var audio: AudioPlayer?
    @ObservationIgnored private let nowPlaying: NowPlayingBridge

    /// What is being played and how, e.g. "AAC 256 kbps (Premium)" (Oynatma menüsü).
    private(set) var streamInfo = ""

    @ObservationIgnored private var booting = false
    @ObservationIgnored private var visitorData: String?
    @ObservationIgnored private var playerJS: URL?
    @ObservationIgnored private var playerSts: Int?
    /// Videos whose signed stream failed in AVPlayer: use the anonymous route for them.
    @ObservationIgnored private var unsignedOnly: Set<String> = []
    /// The search field's latest suggestions, by text (in memory; reset with the account).
    @ObservationIgnored private var suggestionCache: [String: SearchSuggestions] = [:]
    @ObservationIgnored private var suggestionOrder: [String] = []
    /// Videos whose playlist (`DashToHLS`) failed in AVPlayer: play their file as it is.
    @ObservationIgnored private var directOnly: Set<String> = []
    /// Whether the playing song was given to AVPlayer as such a playlist.
    @ObservationIgnored private var currentViaPlaylist = false

    // Connection
    private(set) var isReady = false
    private(set) var booted = false
    private(set) var loggedIn = false
    private(set) var avatarURL: String?
    /// Bumped once the account, its library and its name are in place (at launch and after
    /// signing in or out). Pages that depend on the account load when it changes, and not
    /// before: 0 means not ready yet.
    private(set) var sessionID = 0
    private(set) var loadError: String?
    private(set) var account: AccountInfo?
    /// The Google sign-in sheet.
    var webSheet: WebSheetKind?

    // Player
    private(set) var track: TrackInfo?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    /// Kept for the views; audio-only playback never has video frames.
    private(set) var hasVideo = false
    private(set) var likeStatus = "INDIFFERENT"
    private(set) var repeatMode = "NONE"
    private(set) var volume: Double = 100
    private(set) var muted = false
    private(set) var position: Double = 0
    private(set) var positionDate = Date()
    private(set) var queue: [QueueEntry] = []
    /// Artist / album links for the current track (from the API).
    private(set) var trackMeta: TrackMeta?
    @ObservationIgnored private var trackMetaFor: String?

    // Queue
    @ObservationIgnored private var items: [QueueEntry] = []
    @ObservationIgnored private var queueIndex = 0
    @ObservationIgnored private var queueContinuation: String?
    @ObservationIgnored private var loadingMore = false
    @ObservationIgnored private var playToken = 0
    @ObservationIgnored private var resolving = false
    @ObservationIgnored private var streams: [String: ResolvedStream] = [:]
    @ObservationIgnored private var retriedVideo: String?
    @ObservationIgnored private var currentSource = ""
    @ObservationIgnored private var failuresInARow = 0
    /// Set when the last session was restored at launch: where to continue on Play.
    @ObservationIgnored private var resumeAt: Double?
    @ObservationIgnored private var lastSessionSave = Date.distantPast

    /// Artists of the current track, as links.
    var currentArtists: [ArtistRef] {
        if let t = track, !t.artistLinks.isEmpty { return t.artistLinks }
        return trackMetaFor == track?.videoId ? (trackMeta?.artists ?? []) : []
    }

    /// Album of the current track, if known.
    var currentAlbumId: String? {
        if let a = track?.albumLink { return a.id }
        return trackMetaFor == track?.videoId ? trackMeta?.album?.id : nil
    }

    // Library
    private(set) var library = LibraryData.empty
    /// Albums and playlists just added from the app. YouTube lists them a little later, so
    /// for a while a reload that lacks them keeps them at the top.
    @ObservationIgnored private var justAdded: [String: (list: LibraryFilter, item: MediaItem, at: Date)] = [:]
    private(set) var libraryLoading = false
    /// Lists whose later pages are still coming in.
    private(set) var libraryPaging: Set<LibraryFilter> = []
    /// The order each list is shown in (saved per list).
    private(set) var librarySorts: [LibraryFilter: LibrarySort] =
        Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { ($0, LibrarySort.saved($0)) })
    /// Lists read to the end, in their current order.
    @ObservationIgnored private var libraryComplete: Set<LibraryFilter> = []
    @ObservationIgnored private var libraryRuns: [LibraryFilter: UUID] = [:]
    @ObservationIgnored private var libraryPageTasks: [LibraryFilter: Task<Void, Never>] = [:]

    @ObservationIgnored private var playGuard = Date.distantPast
    @ObservationIgnored private var seekGuard = Date.distantPast
    @ObservationIgnored private var lastNowPlayingPush = Date.distantPast

    private init() {
        nowPlaying = NowPlayingBridge()
        nowPlaying.snapshot = { [weak self] in
            guard let self else { return nil }
            return NowPlayingState(track: self.track, playing: self.isPlaying,
                                   loading: self.isLoading || self.resolving,
                                   position: self.position(at: Date()),
                                   queueIndex: self.queueIndex, queueCount: self.items.count)
        }
        nowPlaying.activate()
        if let v = UserDefaults.standard.object(forKey: "volume") as? Double { volume = min(100, max(0, v)) }
        Task { await self.boot(syncFromSignIn: false) }
    }

    // MARK: - Start-up

    /// `syncFromSignIn`: copy the cookies of a sign-in that just happened in the sheet.
    private func boot(syncFromSignIn: Bool) async {
        guard !booting else { return }
        booting = true
        defer { booting = false }
        loadError = nil
        if !booted { EngineLog.reset() }
        EngineLog.write("Başlangıç: istek")
        if core == nil { core = NativeCore() }
        guard let core else {
            loadError = M.t("JavaScript motoru başlatılamadı.", "The JavaScript engine couldn't start.")
            return
        }

        // Only touches WebKit's cookie store right after signing in (or for a first
        // migration); normally the app's own cookie storage is used.
        await YTAuth.syncCookies(force: syncFromSignIn)
        let html: String
        do {
            html = try await core.fetchText(Self.homeURL)
        } catch {
            EngineLog.write("Başlangıç: ana sayfa alınamadı — \(error.localizedDescription)")
            loadError = error.localizedDescription
            return
        }
        let args: [String: Any] = [
            "html": html,
            "hasAuth": YTAuth.hasAuthCookies,
            "lang": Locale.current.language.languageCode?.identifier ?? "en",
            "region": Locale.current.region?.identifier ?? "US",
            // YouTube's own texts (row titles, "Videos", dates) in the app's language, so the
            // two never mix (a Turkish Mac with an English YouTube account, say).
            "forceLang": M.turkish ? "tr" : "en",
            "ui": M.turkish ? "tr" : "en",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let json = try? await core.call("bootstrap", argsJSON: String(decoding: data, as: UTF8.self)),
              let info = try? JSONDecoder().decode(BootInfo.self, from: Data(json.utf8)) else {
            EngineLog.write("Başlangıç: yapılandırma okunamadı")
            loadError = M.t("YouTube Music yapılandırması okunamadı.", "YouTube Music's configuration couldn't be read.")
            return
        }
        visitorData = info.visitorData
        playerSts = info.sts
        playerJS = info.playerJs.flatMap { SigSolver.canonicalPlayerURL($0) }
        if playerJS == nil, let api = try? await core.fetchText(URL(string: "https://www.youtube.com/iframe_api")!),
           let r = api.range(of: #"player\\?/[0-9a-fA-F]{8}\\?/"#, options: .regularExpression) {
            let id = api[r].filter { $0.isHexDigit }.suffix(8)
            playerJS = URL(string: "https://www.youtube.com/s/player/\(id)/player_ias.vflset/en_US/base.js")
        }
        EngineLog.write("Başlangıç: giriş=\(info.loggedIn) yapılandırma=\(info.parsed) oynatıcı=\(playerJS.map { SigSolver.playerID($0) } ?? "yok")")
        if let playerJS {
            // Get the stream solver ready before the first song is played.
            Task.detached(priority: .utility) {
                do { try await SigSolver.shared.prepare(playerURL: playerJS) }
                catch { EngineLog.write("Çözücü hazırlanamadı: \(error.localizedDescription)") }
            }
        }
        loggedIn = info.loggedIn
        isReady = true
        booted = true
        if loggedIn {
            // Library and account name together (the home page uses both).
            async let accountInfo = try? call("account", as: AccountInfo?.self)
            await loadLibrary()
            account = (await accountInfo) ?? nil
            avatarURL = account?.photo
            // Which playlist holds which song: reads every playlist, so it waits until the
            // home page and the first song have had the connection to themselves.
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await rebuildPlaylistIndex()
            }
        } else {
            library = .empty
            account = nil
            avatarURL = nil
        }
        // Only now do the account's pages load: once, with everything they need. Pages
        // kept from the previous account (or from before signing in) go.
        PageCache.shared.clear()
        musicChannels = [:]
        suggestionCache = [:]
        suggestionOrder = []
        sessionID += 1
        await restoreLastSession()
    }

    // MARK: - Last session (shown, paused, at launch)

    /// Only the current song and where it was (a few hundred bytes); the queue is rebuilt.
    private struct SavedSession: Codable {
        var items: [QueueEntry]
        var index: Int
        var position: Double
        var continuation: String?
        /// When it was saved (absent in sessions saved before 3.2.1).
        var savedAt: Date? = nil
    }

    private static let sessionKey = "lastSong"

    private func saveSession() {
        guard items.indices.contains(queueIndex) else { return }
        lastSessionSave = Date()
        let s = SavedSession(items: [items[queueIndex]], index: 0,
                             position: resumeAt ?? position(at: Date()), continuation: nil, savedAt: Date())
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: Self.sessionKey) }
    }

    /// Called when the app quits.
    func saveSessionNow() { saveSession() }

    /// The app is quitting: note the play in progress, save where it was.
    func prepareToQuit() {
        endListen(.stop)
        saveSession()
    }

    /// Puts the last played song in the player bar and side panel, paused: the one this app
    /// played last, where it was left, with its queue. The account's YouTube Music history
    /// takes its place only when it is plainly newer — something played today (on another
    /// device) while this app last played on an earlier day. The history alone used to
    /// decide, and since its top often lags behind (a play reaches it late, or not at all),
    /// the same old song kept coming back.
    private func restoreLastSession() async {
        guard track == nil else { return }
        let saved = UserDefaults.standard.data(forKey: Self.sessionKey)
            .flatMap { try? JSONDecoder().decode(SavedSession.self, from: $0) }
        var latest: MediaItem?
        var latestToday = false
        if loggedIn, let page = try? await call("browse", ["browseId": "FEmusic_history"], as: BrowsePage.self) {
            if let section = page.sections.first(where: { $0.items.contains(where: \.isTrack) }) {
                latest = section.items.first { $0.isTrack }
                latestToday = ["bugün", "today"].contains(section.title.lowercased(with: Locale(identifier: "tr_TR")))
            }
        }
        guard track == nil else { return }   // something was started meanwhile

        let savedSong = saved.flatMap { s in s.items.indices.contains(s.index) ? s.items[s.index] : nil }
        let historyIsNewer: Bool = {
            guard let latest, latest.videoId != savedSong?.videoId else { return false }
            guard savedSong != nil else { return true }
            guard latestToday, let at = saved?.savedAt else { return false }
            return at < Calendar.current.startOfDay(for: Date())
        }()
        if let latest, savedSong != nil, latest.videoId != savedSong?.videoId {
            EngineLog.write("Son oturum: bu Mac'te \(savedSong?.title ?? "?"), geçmişte \(latest.title)\(latestToday ? " (bugün)" : "")"
                            + " → \(historyIsNewer ? "geçmiş" : "bu Mac")")
        }

        if let s = saved, s.items.indices.contains(s.index), !historyIsNewer {
            let e = s.items[s.index]
            // Rebuild the queue for that song (its list/radio), keep the saved position. If
            // the saved list no longer contains the song, fall back to the song's radio.
            var rebuilt: WatchQueue?
            if let vid = e.videoId {
                if let ep = e.endpoint,
                   let q = try? await call("watchQueue", ["endpoint": ep, "context": ""], as: WatchQueue.self),
                   q.items.contains(where: { $0.videoId == vid }) {
                    rebuilt = q
                } else {
                    rebuilt = try? await call("watchQueue", ["endpoint": Self.watchJSON(vid), "context": ""], as: WatchQueue.self)
                }
            }
            if let vid = e.videoId, let q = rebuilt, !q.items.isEmpty, track == nil {
                let (list, current) = arranged(q, keep: q.items.firstIndex { $0.videoId == vid })
                items = list
                queueContinuation = q.continuation
                queueIndex = list.firstIndex { $0.videoId == vid } ?? min(max(0, current), list.count - 1)
            } else {
                guard track == nil else { return }
                items = [e]
                queueIndex = 0
                queueContinuation = nil
                queueIsRadio = false
            }
            showRestored(position: s.position)
            EngineLog.write("Son oturum geri yüklendi: \(s.items[s.index].title)")
        } else if let latest, let vid = latest.videoId {
            let ep = latest.play ?? Self.watchJSON(vid)
            guard let q = try? await call("watchQueue", ["endpoint": ep, "context": ""], as: WatchQueue.self),
                  !q.items.isEmpty, track == nil else { return }
            let (list, current) = arranged(q, keep: min(max(0, q.current), q.items.count - 1))
            items = list
            queueContinuation = q.continuation
            queueIndex = min(max(0, current), list.count - 1)
            showRestored(position: 0)
            EngineLog.write("Geçmişten son şarkı: \(latest.title)")
        }
    }

    private func showRestored(position p: Double) {
        let e = items[queueIndex]
        let (info, links) = trackInfo(for: e)
        track = info
        let start = info.duration > 0 && p >= info.duration - 2 ? 0 : max(0, p)
        position = start
        positionDate = Date()
        resumeAt = start
        isPlaying = false
        isLoading = false
        likeStatus = resolvedLike(e.like, info)
        streamInfo = ""
        publishQueue()
        pushNowPlaying()
        if links.isEmpty, let vid = e.videoId { loadTrackMeta(vid) }
        // If the queue couldn't be rebuilt (e.g. the network wasn't up yet at launch),
        // "Sıradaki" would stay empty: fill it with the song's radio, retrying a few times.
        Task { await ensureUpcoming() }
    }

    /// When nothing follows the current song — the list ran out, or a song near its end was
    /// picked from "Sıradaki" — the list's next page comes first; when there is none (or it
    /// brings nothing new), the song's radio follows, as YouTube Music does. Retries with a
    /// growing pause, since right after launch the connection may still be coming up.
    private func ensureUpcoming() async {
        if queueContinuation != nil, items.indices.contains(queueIndex), queueIndex == items.count - 1 {
            await loadMoreQueue()
        }
        for attempt in 0..<4 {
            // "Tümünü tekrarla" starts the list over instead.
            guard repeatMode != "ALL", items.indices.contains(queueIndex), queueIndex == items.count - 1,
                  let vid = items[queueIndex].videoId else { return }
            if attempt > 0 { try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000) }
            guard let q = try? await call("watchQueue", ["endpoint": Self.watchJSON(vid), "context": ""],
                                          as: WatchQueue.self) else { continue }
            // Still the same song, still at the end of the queue?
            guard items.indices.contains(queueIndex), items[queueIndex].videoId == vid,
                  queueIndex == items.count - 1 else { return }
            let known = Set(items.compactMap(\.videoId))
            let fresh = q.items.filter { e in e.videoId.map { !known.contains($0) } ?? false }
            let upcoming = filtered(fresh, keep: nil).0
            guard !upcoming.isEmpty else { return }
            queueIsRadio = true
            appendUpcoming(upcoming)
            queueContinuation = q.continuation
            publishQueue()
            EngineLog.write("Sıra tamamlandı: \(upcoming.count) şarkı eklendi (\(vid))")
            return
        }
    }

    private func trackInfo(for e: QueueEntry) -> (TrackInfo, [BylineLink]) {
        var links = (e.artists ?? []).map { BylineLink(text: $0.name, kind: "artist", id: $0.id) }
        if let a = e.album { links.append(BylineLink(text: a.name, kind: "album", id: a.id)) }
        let names = (e.artists ?? []).map(\.name)
        let info = TrackInfo(videoId: e.videoId ?? "", title: e.title,
                             artist: names.isEmpty ? e.subtitle : names.joined(separator: ", "),
                             album: e.album?.name ?? "", artwork: e.art ?? e.thumbnail,
                             duration: e.seconds, links: links)
        return (info, links)
    }

    private func wait(timeout: TimeInterval = 30, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { throw EngineError.notReady }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    // MARK: - Commands

    func call<T: Decodable>(_ name: String, _ args: [String: Any] = [:], as type: T.Type = T.self) async throws -> T {
        let argData = try JSONSerialization.data(withJSONObject: args)
        try await wait { self.booted }
        guard let core else { throw EngineError.notReady }
        do {
            let json = try await core.call(name, argsJSON: String(decoding: argData, as: UTF8.self))
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            EngineLog.write("Veri hatası (\(name)): \(error.localizedDescription)")
            throw error
        }
    }

    /// Smoothly interpolated playback position for the progress bar.
    func position(at date: Date) -> Double {
        guard isPlaying, !isLoading else { return position }
        let p = position + date.timeIntervalSince(positionDate)
        if let d = track?.duration, d > 0 { return min(p, d) }
        return p
    }

    // MARK: - Starting playback

    /// `seed`: the card that was clicked. YouTube Music describes a regular YouTube upload
    /// in its own words (another title, often one artist); the song that starts keeps the
    /// title and artists the card showed, so the player and the card agree.
    func play(endpoint: String, context: String? = nil, seed: MediaItem? = nil) {
        isLoading = true
        failuresInARow = 0
        playToken += 1
        let token = playToken
        resolving = true
        audio?.pause()
        Task {
            do {
                let q: WatchQueue = try await call("watchQueue", ["endpoint": endpoint, "context": context ?? ""])
                guard token == playToken else { return }
                guard !q.items.isEmpty else { throw StreamError.noFormat }
                var (list, current) = arranged(q, keep: min(max(0, q.current), q.items.count - 1))
                if let seed, let vid = seed.videoId, list.indices.contains(current), list[current].videoId == vid {
                    if !seed.title.isEmpty { list[current].title = seed.title }
                    if !seed.artists.isEmpty { list[current].artists = seed.artists }
                }
                items = list
                queueContinuation = q.continuation
                retriedVideo = nil
                startTrack(current)
            } catch {
                guard token == playToken else { return }
                resolving = false
                isLoading = false
                streamInfo = M.t("Çalınamadı: \(error.localizedDescription)", "Couldn't play: \(error.localizedDescription)")
            }
        }
    }

    /// When the current song was asked for; cleared once its sound starts (diagnostic log).
    @ObservationIgnored private var playRequestedAt: Date?

    private func ensureAudio() -> AudioPlayer {
        if let audio { return audio }
        let a = AudioPlayer()
        a.volume = volume
        a.isMuted = muted
        // Plays to the output chosen in the player bar (or the system one) and follows it.
        let outputs = AudioOutputs.shared
        outputs.start()
        a.outputDeviceUID = outputs.activeUID
        outputs.onChange = { [weak a] uid in a?.outputDeviceUID = uid }
        a.onTime = { [weak self] t in self?.audioTime(t) }
        a.onState = { [weak self] playing, buffering in self?.audioState(playing: playing, buffering: buffering) }
        a.onEnded = { [weak self] in self?.audioEnded() }
        a.onFailed = { [weak self] message in self?.audioFailed(message) }
        a.onCrossfade = { [weak self] in self?.crossfadeToNext() }
        a.crossfade = Self.crossfadeSeconds
        audio = a
        return a
    }

    private func stream(for videoId: String) async throws -> ResolvedStream {
        if let s = streams[videoId], s.expires > Date() { return s }
        var errors: [String] = []
        var result: ResolvedStream?
        // 1) The account's own stream, exactly what YouTube Music's player would play.
        if loggedIn, let core, !unsignedOnly.contains(videoId) {
            do {
                result = try await StreamResolver.resolveSigned(videoId: videoId, core: core,
                                                                playerJS: playerJS, sts: playerSts)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errors.append(M.t("hesap akışı: \(error.localizedDescription)", "account stream: \(error.localizedDescription)"))
                EngineLog.write("Akış (hesap) \(videoId): \(error.localizedDescription)")
            }
        }
        // 2) Anonymous app clients (128 kbps).
        if result == nil {
            do {
                result = try await StreamResolver.resolve(videoId: videoId, visitorData: visitorData)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errors.append(M.t("uygulama akışı: \(error.localizedDescription)", "app stream: \(error.localizedDescription)"))
                EngineLog.write("Akış (uygulama) \(videoId): \(error.localizedDescription)")
            }
        }
        guard var s = result else { throw StreamError.unplayable(errors.joined(separator: "; ")) }
        EngineLog.write("Akış \(videoId): \(s.label) [\(s.source)]")
        if !directOnly.contains(videoId) {
            s.playlist = await DashToHLS.shared.playlist(for: s, key: videoId)
        }
        // Only the current and the next track's address are kept.
        let keep: Set<String> = [track?.videoId, items.indices.contains(queueIndex + 1) ? items[queueIndex + 1].videoId : nil]
            .compactMap { $0 }.reduce(into: Set<String>()) { $0.insert($1) }
        streams = streams.filter { keep.contains($0.key) }
        streams[videoId] = s
        return s
    }

    private static func watchJSON(_ videoId: String) -> String {
        "{\"watchEndpoint\":{\"videoId\":\"\(videoId)\"}}"
    }

    /// `crossfade` > 0: the song before keeps playing and fades out under this one (see
    /// crossfadeToNext); it counts as heard to the end.
    private func startTrack(_ index: Int, startAt: Double = 0, crossfade: Double = 0) {
        guard items.indices.contains(index) else { return }
        endListen(crossfade > 0 ? .done : .skip)
        playToken += 1
        let token = playToken
        queueIndex = index
        resumeAt = nil
        let e = items[index]
        guard let vid = e.videoId else { advance(); return }
        let player = ensureAudio()
        resolving = true
        if crossfade == 0 { player.pause() }
        let requested = Date()
        playRequestedAt = requested
        EngineLog.write("Çalma isteği \(vid)\(startAt > 1 ? " (\(Int(startAt)). sn'den)" : "")")

        let (info, trackLinks) = trackInfo(for: e)
        track = info
        position = startAt
        positionDate = Date()
        isLoading = true
        isPlaying = true
        likeStatus = resolvedLike(e.like, info)
        publishQueue()
        pushNowPlaying()
        if trackLinks.isEmpty { loadTrackMeta(vid) }

        Task {
            do {
                let s = try await stream(for: vid)
                guard token == playToken else { return }
                EngineLog.write(String(format: "Akış çözüldü %@ (+%.1f sn)", vid, Date().timeIntervalSince(requested)))
                if info.duration <= 0, s.duration > 0 {
                    track = TrackInfo(videoId: vid, title: info.title, artist: info.artist, album: info.album,
                                      artwork: info.artwork, duration: s.duration.rounded(.down), links: trackLinks)
                }
                streamInfo = s.label + (s.source == "signed" ? M.t(" · hesabınla", " · with your account") : "")
                currentSource = s.source
                currentViaPlaylist = s.playlist != nil
                resolving = false
                failuresInARow = 0
                currentLoudness = s.loudnessDb
                player.load(url: s.playURL, headers: s.headers, duration: s.duration, autoplay: true, startAt: startAt,
                            gain: Self.gain(for: s.loudnessDb), crossfade: crossfade)
                if let db = s.loudnessDb {
                    EngineLog.write(String(format: "Ses yüksekliği %@: %+.1f dB → kazanç %.2f", vid, db, Self.gain(for: db)))
                } else {
                    EngineLog.write("Ses yüksekliği \(vid): bilgi yok")
                }
                pushNowPlaying()
                saveSession()
                beginListen(e, startAt: startAt)
                afterStart(vid)
            } catch {
                guard token == playToken else { return }
                resolving = false
                skipUnplayable(error.localizedDescription)
            }
        }
    }

    /// A song's or video's artists and album as YouTube Music knows them (one request).
    func lookUpTrack(_ videoId: String) async -> TrackMeta? {
        try? await call("trackMeta", ["videoId": videoId], as: TrackMeta.self)
    }

    private func loadTrackMeta(_ videoId: String) {
        Task {
            let meta = try? await call("trackMeta", ["videoId": videoId], as: TrackMeta.self)
            if track?.videoId == videoId {
                trackMetaFor = videoId
                trackMeta = meta
            }
        }
    }

    /// A track that can't be played is skipped (like the official apps do); after a few
    /// in a row playback stops instead of running through the whole queue.
    private func skipUnplayable(_ reason: String) {
        EngineLog.write("Çalınamadı \(track?.videoId ?? "?"): \(reason)")
        streamInfo = M.t("Çalınamadı: \(reason)", "Couldn't play: \(reason)")
        failuresInARow += 1
        guard failuresInARow < 3, queueIndex + 1 < items.count else {
            finishQueue()
            return
        }
        let token = playToken
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard token == playToken else { return }
            advance()
        }
    }

    private func afterStart(_ videoId: String) {
        if queueIndex >= items.count - 3 {
            Task {
                await loadMoreQueue()
                await ensureUpcoming()
            }
        }
        // Resolve the next track's address now, and once this one has played a few seconds
        // (not while skipping through) load the next one's first 10 seconds, so the change
        // to it is immediate. Nothing is written to disk.
        if items.indices.contains(queueIndex + 1), let next = items[queueIndex + 1].videoId {
            Task {
                guard let s = try? await stream(for: next) else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard track?.videoId == videoId, repeatMode != "ONE",
                      items.indices.contains(queueIndex + 1), items[queueIndex + 1].videoId == next else { return }
                audio?.prepareNext(url: s.playURL, headers: s.headers)
                EngineLog.write("Sıradaki hazır: \(next) (ilk \(Int(AudioPlayer.standbySeconds)) sn)")
            }
        }
        // The play is reported to the account's history from noteListen, once heard.
    }

    /// The list's next page. A page whose songs were all there already (or left out) is
    /// followed by the next one, three pages at most.
    private func loadMoreQueue() async {
        guard !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        for _ in 0..<3 {
            guard let token = queueContinuation else { return }
            guard let more = try? await call("queueMore", ["token": token], as: WatchQueue.self) else {
                queueContinuation = nil
                return
            }
            // The queue may have been replaced while this was loading.
            guard queueContinuation == token else { return }
            let before = items.count
            appendUpcoming(more.items)
            queueContinuation = more.items.isEmpty || more.continuation == token ? nil : more.continuation
            publishQueue()
            if items.count > before { return }
        }
    }

    private func publishQueue() {
        var out = items
        for i in out.indices {
            out[i].index = i
            out[i].selected = i == queueIndex
        }
        if out != queue { queue = out }
    }

    private func pushNowPlaying() {
        lastNowPlayingPush = Date()
        nowPlaying.refresh()
    }

    // MARK: - Audio callbacks

    private func audioTime(_ t: Double) {
        guard !resolving else { return }
        noteListen(t)
        let now = Date()
        if now > seekGuard, abs(position(at: now) - t) > 0.3 {
            position = t
            positionDate = now
        }
        if now.timeIntervalSince(lastNowPlayingPush) > 5 { pushNowPlaying() }
        if now.timeIntervalSince(lastSessionSave) > 15 { saveSession() }
    }

    private func audioState(playing: Bool, buffering: Bool) {
        guard !resolving else { return }
        let now = Date()
        if playing, !buffering, let asked = playRequestedAt {
            playRequestedAt = nil
            EngineLog.write(String(format: "Ses başladı %@ (+%.1f sn)", track?.videoId ?? "?", now.timeIntervalSince(asked)))
        }
        var changed = false
        if isLoading != buffering {
            isLoading = buffering
            changed = true   // the widget's clock stops while buffering and resumes after
        }
        if now > seekGuard, let audio {
            position = audio.currentTime
            positionDate = now
        }
        if now > playGuard, isPlaying != playing {
            // Diagnostic log: the player changed the state on its own (not a click).
            EngineLog.write("Durum: oynatıcı \(playing ? "çalıyor" : "durdu")\(buffering ? " (ara belleğe alıyor)" : "")")
            isPlaying = playing
            changed = true
        }
        if changed { pushNowPlaying() }
    }

    private func audioEnded() {
        endListen(.done)
        // Sleep timer set to the end of this song: stop here. Play again goes on with the
        // next song.
        if sleepTimer == .endOfSong {
            sleepTimer = .off
            sleepMinutes = nil
            isPlaying = false
            isLoading = false
            pushNowPlaying()
            return
        }
        if repeatMode == "ONE", let audio {
            audio.seek(to: 0)
            audio.play()
            position = 0
            positionDate = Date()
            pushNowPlaying()
            if items.indices.contains(queueIndex) { beginListen(items[queueIndex], startAt: 0) }
            return
        }
        advance()
    }

    private func audioFailed(_ message: String) {
        guard let vid = track?.videoId else { return }
        EngineLog.write("Çalma hatası \(vid) [\(currentSource)\(currentViaPlaylist ? ", liste" : "")]: \(message)")
        streams[vid] = nil
        if currentViaPlaylist, !directOnly.contains(vid) {
            // The playlist made from the file's index was refused: play the file itself,
            // from where it was.
            directOnly.insert(vid)
            startTrack(queueIndex, startAt: position(at: Date()))
        } else if currentSource == "signed" {
            // The deciphered stream was refused: use the other route for this track.
            unsignedOnly.insert(vid)
            startTrack(queueIndex)
        } else if retriedVideo != vid {
            // The address may simply have expired: ask for a fresh one once.
            retriedVideo = vid
            startTrack(queueIndex)
        } else {
            skipUnplayable(message)
        }
    }

    private func advance() {
        let n = queueIndex + 1
        if n < items.count {
            startTrack(n)
        } else if queueContinuation != nil {
            isLoading = true
            Task {
                await loadMoreQueue()
                if queueIndex + 1 < items.count { startTrack(queueIndex + 1) } else { finishQueue() }
            }
        } else if repeatMode == "ALL", !items.isEmpty {
            startTrack(0)
        } else {
            finishQueue()
        }
    }

    private func finishQueue() {
        audio?.pause()
        audio?.seek(to: 0)
        isPlaying = false
        isLoading = false
        position = 0
        positionDate = Date()
        pushNowPlaying()
    }

    // MARK: - Transport

    func togglePlay() {
        guard track != nil, !resolving else { return }
        // Restored at launch and not loaded yet: start it where it was left.
        if let at = resumeAt, audio?.hasItem != true {
            EngineLog.write("Kullanıcı: çal (kaldığı yerden, \(Int(at)). sn)")
            failuresInARow = 0
            startTrack(queueIndex, startAt: at)
            return
        }
        guard let audio, audio.hasItem else { return }
        position = audio.currentTime
        positionDate = Date()
        isPlaying.toggle()
        EngineLog.write("Kullanıcı: \(isPlaying ? "çal" : "duraklat")")
        playGuard = Date().addingTimeInterval(0.5)
        if isPlaying { audio.play() } else { audio.pause() }
        pushNowPlaying()
        if !isPlaying {
            if var l = listen {
                flushListen(&l, to: l.lastPos)
                listen = l
            }
            saveSession()
        }
    }

    func next() {
        guard track != nil else { return }
        failuresInARow = 0
        advance()
    }

    func previous() {
        guard track != nil else { return }
        if position(at: Date()) > 3 || queueIndex == 0 {
            seek(to: 0)
        } else {
            failuresInARow = 0
            startTrack(queueIndex - 1)
        }
    }

    func seek(to t: Double) {
        if resumeAt != nil, audio?.hasItem != true { resumeAt = max(0, t) }
        position = max(0, t)
        positionDate = Date()
        seekGuard = Date().addingTimeInterval(0.9)
        audio?.seek(to: t)
        pushNowPlaying()
    }

    // MARK: - Sleep timer

    enum SleepTimer: Equatable {
        case off
        case at(Date)
        case endOfSong
    }

    private(set) var sleepTimer: SleepTimer = .off
    /// The length picked, while a timed sleep timer runs (the panel marks it).
    private(set) var sleepMinutes: Int?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// The sound fades out over the timer's last seconds.
    static let sleepFade: Double = 8

    func sleep(after minutes: Int) {
        sleepTask?.cancel()
        audio?.cancelFade()
        let end = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimer = .at(end)
        sleepMinutes = minutes
        sleepTask = Task { [weak self] in
            let wait = end.addingTimeInterval(-YTMusic.sleepFade).timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            self?.fallAsleep()
        }
        EngineLog.write("Uyku zamanlayıcı: \(minutes) dk")
    }

    func sleepAtEndOfSong() {
        sleepTask?.cancel()
        sleepTask = nil
        audio?.cancelFade()
        sleepTimer = .endOfSong
        sleepMinutes = nil
    }

    func cancelSleep() {
        sleepTask?.cancel()
        sleepTask = nil
        audio?.cancelFade()
        sleepTimer = .off
        sleepMinutes = nil
    }

    private func fallAsleep() {
        sleepTask = nil
        guard isPlaying, let audio else { sleepTimer = .off; return }
        audio.fadeOut(over: Self.sleepFade) { [weak self] in
            guard let self else { return }
            if self.isPlaying { self.togglePlay() }   // the usual pause (listening reported)
            self.sleepTimer = .off
            self.sleepMinutes = nil
        }
    }

    // MARK: - Crossfade
    //
    // The crossfade button in the player bar: 0 (off), 3, 6, 9 or 12 seconds. Near
    // the end of a song the player offers the change (the next song must already be
    // waiting in its standby player); it happens only where the songs aren't meant to run
    // into each other or the listener wants a clean stop.

    static let crossfadeKey = "crossfadeSeconds"
    static let crossfadeChoices = [0, 3, 6, 9, 12]
    static var crossfadeSeconds: Double { Double(UserDefaults.standard.integer(forKey: crossfadeKey)) }

    /// Whether the change from `current` to `next` may overlap: not when one song repeats,
    /// when the sleep timer waits for this song's end, into or out of a long set (sets are
    /// mixes of their own), with very short songs, or between consecutive songs of the same
    /// album (live and DJ albums run into each other as recorded).
    nonisolated static func mayCrossfade(from current: QueueEntry, to next: QueueEntry,
                                         repeatOne: Bool, sleepAtEnd: Bool) -> Bool {
        guard !repeatOne, !sleepAtEnd, current.videoId != nil, next.videoId != nil else { return false }
        if QueueCurator.isSet(current) || QueueCurator.isSet(next) { return false }
        if (current.seconds > 0 && current.seconds < 30) || (next.seconds > 0 && next.seconds < 30) { return false }
        if let album = current.album?.id, !album.isEmpty, album == next.album?.id { return false }
        return true
    }

    /// The player says the end is near and the next song is ready: start it, overlapping.
    private func crossfadeToNext() {
        let length = Self.crossfadeSeconds
        let n = queueIndex + 1
        guard length > 0, isPlaying, let audio, items.indices.contains(queueIndex), items.indices.contains(n),
              Self.mayCrossfade(from: items[queueIndex], to: items[n],
                                repeatOne: repeatMode == "ONE", sleepAtEnd: sleepTimer == .endOfSong),
              let next = items[n].videoId, let s = streams[next], s.expires > Date(),
              audio.preparedURL == s.playURL
        else { return }
        failuresInARow = 0
        startTrack(n, crossfade: length)
    }

    /// The setting changed: applies from the current song on.
    func crossfadeChanged() {
        audio?.crossfade = Self.crossfadeSeconds
        EngineLog.write("Geçiş ayarı: \(Int(Self.crossfadeSeconds)) sn")
    }

    /// Quitting: the sound fades out first; `done` follows (the app waits for it).
    func fadeOutForQuit(then done: @escaping () -> Void) {
        guard isPlaying, let audio else { done(); return }
        audio.pause(then: done)
    }

    // MARK: - Volume leveling
    //
    // YouTube measures every song's loudness; `loudnessDb` is how far it is above its
    // reference level. Every song is brought to a target 6 dB below that reference: most
    // songs measure between about −9 and +2 dB, so nearly all of them can be turned down
    // to the same level (the player can't turn a song up past its own level; the few
    // quieter than the target stay as they are). The whole app is somewhat quieter;
    // the volume slider makes up for it once. Settings → Listening turns it off.

    static var levelingOn: Bool { UserDefaults.standard.object(forKey: "normalizeVolume") as? Bool ?? true }

    @ObservationIgnored private var currentLoudness: Double?

    /// The level every song is brought to, in dB relative to YouTube's reference.
    static let levelTarget: Double = -6

    static func gain(for loudnessDb: Double?) -> Float {
        guard levelingOn else { return 1 }
        // A song without a measurement counts as being at the reference level.
        let over = (loudnessDb ?? 0) - levelTarget
        guard over > 0 else { return 1 }
        return Float(pow(10, -over / 20))
    }

    /// The setting changed: the playing song eases to its new level.
    func levelingChanged() {
        audio?.setGain(Self.gain(for: currentLoudness), smoothly: true)
    }

    func setVolume(_ v: Double) {
        let clamped = min(100, max(0, v))
        guard abs(clamped - volume) >= 0.5 || muted else { return }
        volume = clamped
        if clamped > 0 { muted = false }
        UserDefaults.standard.set(clamped, forKey: "volume")
        audio?.volume = clamped
        audio?.isMuted = muted
    }

    func toggleMute() {
        muted.toggle()
        audio?.isMuted = muted
    }

    private func rate(_ status: String) {
        likeStatus = status
        guard let id = track?.videoId else { return }
        updateLiked(id, title: track?.title, artist: track?.artist, status: status)
        if items.indices.contains(queueIndex) { items[queueIndex].like = status }
        rememberRating(id, status)
        Task { _ = try? await call("rate", ["videoId": id, "status": status], as: Ignored.self) }
    }

    func like() {
        rate(likeStatus == "LIKE" ? "INDIFFERENT" : "LIKE")
    }

    /// YouTube Music's own "beğenmedim": the account learns from it and stops recommending
    /// the song. The app also skips it now and keeps it out of every queue it builds.
    func dislike() {
        rate(likeStatus == "DISLIKE" ? "INDIFFERENT" : "DISLIKE")
        if likeStatus == "DISLIKE" { next() }
    }

    /// Rate any song (from a list's menu), not only the one playing.
    func rate(videoId: String, status: String) {
        if track?.videoId == videoId {
            if status == "DISLIKE" { dislike() } else { rate(status) }
            return
        }
        rememberRating(videoId, status)
        updateLiked(videoId, title: nil, artist: nil, status: status)
        Task { _ = try? await call("rate", ["videoId": videoId, "status": status], as: Ignored.self) }
    }

    // MARK: - Is the playing song among my liked songs?
    //
    // YouTube's queue data often says nothing about a song being liked (or the song was
    // liked as its music video, under another id), so Liked Music is indexed like the
    // playlists: its video ids and "title|artist" keys, read at launch and kept in step
    // with every rating made here.

    @ObservationIgnored private var likedIndex: IndexedPlaylist?

    private func inLiked(_ videoId: String, title: String, artist: String) -> Bool {
        guard let liked = likedIndex else { return false }
        if liked.videos.contains(videoId) { return true }
        if let k = IndexedPlaylist.key(title: title, artist: artist) { return liked.keys.contains(k) }
        return false
    }

    /// A rating YouTube or the user gave wins; otherwise the song is liked when it is in
    /// Liked Music, under this id or as the same song.
    private func resolvedLike(_ like: String?, _ info: TrackInfo) -> String {
        if like == "LIKE" || like == "DISLIKE" { return like! }
        if like == nil || like == "INDIFFERENT", inLiked(info.videoId, title: info.title, artist: info.artist) { return "LIKE" }
        return "INDIFFERENT"
    }

    private func updateLiked(_ videoId: String, title: String?, artist: String?, status: String) {
        guard var liked = likedIndex else { return }
        let key = title.flatMap { t in artist.flatMap { IndexedPlaylist.key(title: t, artist: $0) } }
        if status == "LIKE" {
            liked.videos.insert(videoId)
            if let key { liked.keys.insert(key) }
        } else {
            liked.videos.remove(videoId)
            if let key { liked.keys.remove(key) }
        }
        likedIndex = liked
    }

    /// Once Liked Music is read, the playing song's button catches up.
    private func refreshLike() {
        guard let t = track, items.indices.contains(queueIndex), items[queueIndex].videoId == t.videoId else { return }
        likeStatus = resolvedLike(items[queueIndex].like, t)
    }

    // MARK: - Disliked songs stay out of queues

    @ObservationIgnored private var disliked: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "dislikedVideos") ?? [])

    func isDisliked(_ videoId: String?) -> Bool {
        videoId.map { disliked.contains($0) } ?? false
    }

    private func rememberRating(_ videoId: String, _ status: String) {
        PageCache.shared.markStale { $0.hasPrefix("page|VLLM|") }
        ListeningLog.shared.record(ListeningLog.Rating(t: Int(Date().timeIntervalSince1970), v: videoId, s: status))
        if status == "DISLIKE" {
            disliked.insert(videoId)
            // Take it out of what's coming up.
            let before = items.count
            var kept: [QueueEntry] = []
            var newIndex = queueIndex
            for (i, e) in items.enumerated() {
                if i > queueIndex, e.videoId == videoId { continue }
                kept.append(e)
                if i == queueIndex { newIndex = kept.count - 1 }
            }
            if kept.count != before {
                items = kept
                queueIndex = newIndex
                publishQueue()
            }
        } else {
            disliked.remove(videoId)
        }
        UserDefaults.standard.set(Array(disliked.suffix(2000)), forKey: "dislikedVideos")
    }

    // MARK: - Radio cleanup

    @ObservationIgnored private var queueIsRadio = false

    /// Radios are arranged (official versions first…) unless switched off in Ayarlar.
    private var curating: Bool {
        queueIsRadio && (UserDefaults.standard.object(forKey: "curateRadio") as? Bool ?? true)
    }

    /// A freshly built queue: disliked songs out and, in a radio, the cleanup over what
    /// comes after the song asked for.
    private func arranged(_ q: WatchQueue, keep keepIndex: Int?) -> ([QueueEntry], Int) {
        queueIsRadio = q.radio ?? false
        let (list, index) = filtered(q.items, keep: keepIndex)
        guard curating, list.indices.contains(index) else { return (list, index) }
        let head = Array(list[...index])
        return (head + QueueCurator.arrange(pending: Array(list[(index + 1)...]), fixed: head), index)
    }

    /// Adds rows to the end of the queue. In a radio the cleanup runs over everything still
    /// to come, so uploads stay behind the official songs that arrive later.
    private func appendUpcoming(_ rows: [QueueEntry]) {
        let fresh = filtered(rows, keep: nil).0
        guard curating, items.indices.contains(queueIndex) else {
            items.append(contentsOf: fresh)
            return
        }
        let head = Array(items[...queueIndex])
        let pending = Array(items[(queueIndex + 1)...]) + fresh
        items = head + QueueCurator.arrange(pending: pending, fixed: head)
    }

    // MARK: - Listening

    /// The play in progress: how much of it was really heard, for the account's history on
    /// YouTube and the app's own listening history.
    private struct Listen {
        let videoId: String
        let entry: QueueEntry
        let radio: Bool
        var heard: Double = 0
        var lastPos: Double
        var segmentStart: Double
        var session: String? = nil
        var requested = false
        var lastFlush = Date()
    }

    private enum ListenEnd: String { case done, skip, stop }

    @ObservationIgnored private var listen: Listen?

    private func beginListen(_ e: QueueEntry, startAt: Double) {
        guard let vid = e.videoId else { listen = nil; return }
        listen = Listen(videoId: vid, entry: e, radio: queueIsRadio, lastPos: startAt, segmentStart: startAt)
    }

    /// Called with each position update: counts what was heard, notices seeks, and reports
    /// to YouTube (the play after 10 seconds heard, then the stretches heard each minute).
    private func noteListen(_ t: Double) {
        guard var l = listen, track?.videoId == l.videoId else { return }
        let step = t - l.lastPos
        if step > 0 && step < 1.6 {
            l.heard += step
        } else if abs(step) >= 1.6 {
            flushListen(&l, to: l.lastPos)   // a seek: report what was heard before it
            l.segmentStart = t
        }
        l.lastPos = t
        if !l.requested, l.heard >= 10, loggedIn {
            l.requested = true
            let vid = l.videoId
            Task {
                let ticket = try? await call("trackStart", ["videoId": vid], as: ListenTicket.self)
                if listen?.videoId == vid { listen?.session = ticket?.session }
            }
        }
        if l.session != nil, Date().timeIntervalSince(l.lastFlush) >= 60 { flushListen(&l, to: t) }
        listen = l
    }

    /// Reports the stretch heard since the last report (once YouTube's report is open).
    private func flushListen(_ l: inout Listen, to end: Double) {
        guard let session = l.session else { return }
        let st = l.segmentStart
        let et = max(st, end)
        l.segmentStart = et
        l.lastFlush = Date()
        guard et - st >= 1 else { return }
        Task { _ = try? await call("trackWatch", ["session": session, "st": st, "et": et], as: Ignored.self) }
    }

    /// The play is over: last report to YouTube, one line in the listening history.
    private func endListen(_ how: ListenEnd) {
        guard var l = listen else { return }
        listen = nil
        let info = track?.videoId == l.videoId ? track : nil
        let length = info?.duration ?? l.entry.seconds
        let finished = how == .done || (length > 0 && l.lastPos >= length - 5)
        flushListen(&l, to: finished && length > 0 ? length : l.lastPos)
        // A song skipped before a second of it played wasn't a judgement on it.
        guard l.heard >= 1 else { return }
        let artists = l.entry.artists ?? []
        let names = artists.isEmpty ? [l.entry.subtitle.components(separatedBy: " • ").first ?? ""] : artists.map(\.name)
        ListeningLog.shared.record(ListeningLog.Play(
            t: Int(Date().timeIntervalSince1970), v: l.videoId, ti: info?.title ?? l.entry.title,
            ar: names, ai: artists.map(\.id), ty: l.entry.videoType, len: Int(length.rounded()),
            heard: Int(l.heard.rounded()), at: Int(l.lastPos.rounded()),
            end: finished ? "done" : how.rawValue, src: l.radio ? "radio" : "list",
            th: l.entry.art ?? l.entry.thumbnail))
        // Heard properly (half a minute, or to the end): counts towards rebuilding the home
        // page; the history page changes either way.
        if finished || l.heard >= 30 { listenCount += 1 }
        PageCache.shared.markStale { $0.hasPrefix("page|FEmusic_history|") }
    }

    /// Drops disliked songs from a freshly built queue (keeping the one asked for).
    private func filtered(_ entries: [QueueEntry], keep keepIndex: Int?) -> ([QueueEntry], Int) {
        guard !disliked.isEmpty else { return (entries, keepIndex ?? 0) }
        var out: [QueueEntry] = []
        var newIndex = 0
        for (i, e) in entries.enumerated() {
            if i == keepIndex { newIndex = out.count; out.append(e); continue }
            if let v = e.videoId, disliked.contains(v) || e.like == "DISLIKE" { continue }
            out.append(e)
        }
        return (out, newIndex)
    }

    // MARK: - Playlists

    /// Playlists a song can be added to: all of mine (from the index), plus any YouTube
    /// offers that the index doesn't know yet. `contains` comes from the index.
    func playlistOptions(for videoId: String, title: String = "", artist: String = "") async throws -> [PlaylistOption] {
        let inside = Set(playlists(containing: videoId, title: title, artist: artist).map(\.id))
        var out = ownPlaylists.map {
            PlaylistOption(playlistId: $0.id, title: $0.title, thumbnail: $0.thumbnail,
                           contains: inside.contains($0.id), privacy: nil)
        }
        let known = Set(out.map(\.playlistId))
        if let extra = try? await call("addToPlaylistOptions", ["videoId": videoId], as: [PlaylistOption].self) {
            if out.isEmpty && extra.isEmpty { throw EngineError.js(M.t("Çalma listesi bulunamadı.", "Playlist not found.")) }
            out.append(contentsOf: extra.filter { !known.contains($0.playlistId) })
        } else if out.isEmpty {
            throw EngineError.js(M.t("Çalma listeleri alınamadı.", "Playlists couldn't be loaded."))
        }
        return out
    }

    func addToPlaylist(_ playlistId: String, videoId: String) async throws {
        _ = try await call("addToPlaylist", ["playlistId": playlistId, "videoId": videoId], as: Ignored.self)
        indexAdd(playlistId, videoId: videoId)
        playlistsChanged(reindex: playlistIndex[playlistId] == nil)
    }

    /// Subscribes to / unsubscribes from an artist's channel (YouTube Music's "Abone ol").
    /// The library's artist list (subscriptions) is refreshed afterwards.
    func setSubscribed(_ on: Bool, channelId: String, params: String?) async throws {
        var args: [String: Any] = ["channelId": channelId, "on": on]
        if let params { args["params"] = params }
        _ = try await call("subscribe", args, as: Ignored.self)
        EngineLog.write(on ? "Abone olundu: \(channelId)" : "Abonelik iptal: \(channelId)")
        // The home page (favourite artists, stations, new releases) and the artist's page.
        PageCache.shared.markStale { $0.hasPrefix("home|") }
        PageCache.shared.forget { $0.hasPrefix("page|\(channelId)|") }
        // Unsubscribed: the artist just leaves the list. Reading the list again right after
        // can come back empty while YouTube catches up, so only a new artist is read for.
        if on {
            Task { await loadLibraryList(.artists) }
        } else {
            library.artists.removeAll { $0.browseId == channelId }
        }
    }

    // MARK: - Keeping things in the library

    /// The library list an item belongs in: albums, playlists, followed artists, podcasts.
    private func libraryList(for item: MediaItem) -> LibraryFilter? {
        switch item.kind {
        case "album": return .albums
        case "playlist": return .playlists
        case "artist": return .artists
        case "podcast": return .podcasts
        default: return nil
        }
    }

    func inLibrary(_ item: MediaItem) -> Bool {
        guard let list = libraryList(for: item), let id = item.browseId else { return false }
        return library[list].contains { $0.browseId == id }
    }

    /// Whether the menu can add the item to the library or take it out: albums, followed
    /// artists, and playlists made by others. The account's own playlists are deleted on
    /// their page instead; Beğenilen müzikler and the like stay.
    func canKeepInLibrary(_ item: MediaItem) -> Bool {
        guard loggedIn, let list = libraryList(for: item), let id = item.browseId else { return false }
        switch list {
        case .albums: return id.hasPrefix("MPRE")
        case .artists: return id.hasPrefix("UC")
        case .podcasts: return id.hasPrefix("MPSP")
        case .playlists:
            let pid = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
            guard !pid.isEmpty, pid != "LM", pid != "SE", !pid.hasPrefix("RD") else { return false }
            // In the library: only when it is known not to be the account's own.
            guard inLibrary(item) else { return true }
            return playlistIndex[pid].map { !$0.editable } ?? false
        }
    }

    /// Adds the item to the library or takes it out (an artist: subscribe / unsubscribe).
    /// Taken out, it leaves the list at once; on failure it comes back. Returns whether it worked.
    @discardableResult
    func setInLibrary(_ item: MediaItem, _ on: Bool) async -> Bool {
        guard let list = libraryList(for: item), let id = item.browseId else { return false }
        let place = library[list].firstIndex { $0.browseId == id }
        if !on {
            library[list].removeAll { $0.browseId == id }
            justAdded[id] = nil
        }
        do {
            if list == .artists {
                try await setSubscribed(on, channelId: id, params: nil)
                return true
            }
            _ = try await call("saveToLibrary", ["browseId": id, "playlistId": item.playlistId ?? "",
                                                 "play": item.play ?? "", "on": on], as: Ignored.self)
            EngineLog.write(on ? "Kitaplığa eklendi: \(item.title)" : "Kitaplıktan kaldırıldı: \(item.title)")
            PageCache.shared.markStale { $0.hasPrefix("page|\(id)|") || $0.hasPrefix("home|") }
            if on {
                // In the list at once, then read again once YouTube has caught up.
                justAdded[id] = (list, item, Date())
                if !library[list].contains(where: { $0.browseId == id }) {
                    let sort = librarySorts[list] ?? .recent
                    library[list] = sort.apply([item] + library[list])
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await loadLibraryList(list)
                }
            }
            return true
        } catch {
            // Back where it was, if it went.
            if !on, let place, !library[list].contains(where: { $0.browseId == id }) {
                library[list].insert(item, at: min(place, library[list].count))
            }
            EngineLog.write("Kitaplık değişmedi (\(item.title)): \(error.localizedDescription)")
            return false
        }
    }

    /// Where a YouTube link the app doesn't read itself leads (handles, podcast addresses).
    func resolveLink(_ url: String) async -> LinkRoute? {
        do {
            return try await call("resolveLink", ["url": url], as: ResolvedLink.self).route
        } catch {
            EngineLog.write("Bağlantı çözülemedi (\(url)): \(error.localizedDescription)")
            return nil
        }
    }

    /// Play counts a playlist's page left out, read from the same list on YouTube.
    func playCounts(playlistId: String, videoIds: [String]) async -> [String: String] {
        (try? await call("playCounts", ["playlistId": playlistId, "videoIds": videoIds], as: [String: String].self)) ?? [:]
    }

    /// Lengths a list's page left out (podcast episodes), read from its play queue.
    func lengths(playlistId: String, videoIds: [String]) async -> [String: String] {
        (try? await call("lengths", ["playlistId": playlistId, "videoIds": videoIds], as: [String: String].self)) ?? [:]
    }

    func removeFromPlaylist(_ playlistId: String, videoId: String, setVideoId: String) async throws {
        _ = try await call("removeFromPlaylist", ["playlistId": playlistId, "videoId": videoId, "setVideoId": setVideoId],
                           as: Ignored.self)
        playlistsChanged()
    }

    func movePlaylistItem(_ playlistId: String, setVideoId: String, before: String?) async throws {
        _ = try await call("movePlaylistItem", ["playlistId": playlistId, "setVideoId": setVideoId,
                                                "beforeSetVideoId": before ?? ""], as: Ignored.self)
        playlistsChanged()
    }

    @discardableResult
    func createPlaylist(title: String, description: String, privacy: PlaylistPrivacy, videoIds: [String] = []) async throws -> String {
        let id: String = try await call("createPlaylist", ["title": title, "description": description,
                                                           "privacy": privacy.rawValue, "videoIds": videoIds])
        playlistsChanged()
        return id
    }

    func updatePlaylist(_ playlistId: String, title: String, description: String, privacy: PlaylistPrivacy) async throws {
        _ = try await call("updatePlaylist", ["playlistId": playlistId, "title": title, "description": description,
                                              "privacy": privacy.rawValue], as: Ignored.self)
        playlistsChanged()
    }

    func deletePlaylist(_ playlistId: String) async throws {
        _ = try await call("deletePlaylist", ["playlistId": playlistId], as: Ignored.self)
        playlistsChanged()
    }

    /// Bumped after any playlist change: open playlist pages reload, the sidebar refreshes.
    private(set) var playlistRevision = 0

    /// Songs heard properly since launch (see endListen): the home page is rebuilt every
    /// few of them.
    private(set) var listenCount = 0

    // MARK: - Which of my playlists contain a song?
    //
    // YouTube doesn't tell (its add-to-playlist data lists a few recent playlists and no
    // membership), so the app keeps its own index: the songs of every library playlist,
    // refreshed in the background at launch and updated at once on every change.

    private(set) var playlistIndex: [String: IndexedPlaylist] = [:]
    @ObservationIgnored private var indexing = false
    @ObservationIgnored private var indexAgain = false



    /// Only playlists the account can edit count as "mine" (when that is known).
    private var ownPlaylists: [IndexedPlaylist] {
        let all = Array(playlistIndex.values)
        let mine = all.filter(\.editable)
        return (mine.isEmpty ? all : mine).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func playlists(containing videoId: String, title: String, artist: String) -> [IndexedPlaylist] {
        let key = IndexedPlaylist.key(title: title, artist: artist)
        return ownPlaylists.filter { p in
            if p.videos.contains(videoId) { return true }
            if let key { return p.keys.contains(key) }
            return false
        }
    }

    /// Titles of my playlists that contain the current song (player bar indicator).
    var savedIn: [String] {
        guard let t = track else { return [] }
        return playlists(containing: t.videoId, title: t.title, artist: t.artist).map(\.title)
    }

    private func libraryPlaylistIDs() -> [(id: String, item: MediaItem)] {
        library.playlists.compactMap { p in
            let raw = p.playlistId ?? p.browseId ?? ""
            let id = raw.hasPrefix("VL") ? String(raw.dropFirst(2)) : raw
            guard !id.isEmpty, id != "LM", id != "SE", !id.hasPrefix("RD") else { return nil }
            return (id, p)
        }
    }

    // The index lives in memory only (nothing on disk); it is rebuilt at each launch.

    func rebuildPlaylistIndex() async {
        guard loggedIn else { return }
        if indexing { indexAgain = true; return }
        indexing = true
        defer { indexing = false }
        repeat {
            indexAgain = false
            if let d = try? await call("playlistIndex", ["playlistId": "LM"], as: PlaylistIndexData.self) {
                var keys: Set<String> = []
                for t in d.tracks { if let k = IndexedPlaylist.key(title: t.t, artist: t.a) { keys.insert(k) } }
                likedIndex = IndexedPlaylist(id: "LM", title: d.title, thumbnail: nil, editable: false,
                                             videos: Set(d.tracks.map(\.v)), keys: keys)
                refreshLike()
                EngineLog.write("Beğenilenler dizini: \(d.tracks.count) şarkı")
            }
            var fresh: [String: IndexedPlaylist] = [:]
            var songs = 0
            for (n, (id, item)) in libraryPlaylistIDs().enumerated() {
                // Every few playlists, let the script engine free the pages it has read
                // (otherwise memory peaks at several hundred MB during the first minute).
                if n > 0, n % 4 == 0 { core?.collectGarbage() }
                guard let d = try? await call("playlistIndex", ["playlistId": id], as: PlaylistIndexData.self) else {
                    if let old = playlistIndex[id] { fresh[id] = old }
                    continue
                }
                var keys: Set<String> = []
                for t in d.tracks { if let k = IndexedPlaylist.key(title: t.t, artist: t.a) { keys.insert(k) } }
                fresh[id] = IndexedPlaylist(id: id, title: d.title.isEmpty ? item.title : d.title,
                                            thumbnail: item.thumbnail ?? d.thumbnail, editable: d.editable,
                                            videos: Set(d.tracks.map(\.v)), keys: keys)
                songs += d.tracks.count
            }
            playlistIndex = fresh
            EngineLog.write("Liste dizini: \(fresh.count) liste (\(fresh.values.filter(\.editable).count) düzenlenebilir), \(songs) şarkı")
        } while indexAgain
        // Reading every playlist leaves a lot of garbage in the script engine.
        core?.collectGarbage()
    }

    private func indexAdd(_ playlistId: String, videoId: String) {
        guard var p = playlistIndex[playlistId] else { return }
        p.videos.insert(videoId)
        if let t = track, t.videoId == videoId, let k = IndexedPlaylist.key(title: t.title, artist: t.artist) { p.keys.insert(k) }
        playlistIndex[playlistId] = p
    }

    private func playlistsChanged(reindex: Bool = true) {
        PageCache.shared.markStale { $0.hasPrefix("page|VL") || $0.hasPrefix("page|FEmusic_li") }
        playlistRevision += 1
        Task {
            await loadLibrary()
            await libraryPagesDone()
            if reindex { await rebuildPlaylistIndex() }
        }
    }

    func shuffle() {
        guard queueIndex + 1 < items.count else { return }
        let head = Array(items[...queueIndex])
        let tail = Array(items[(queueIndex + 1)...]).shuffled()
        items = head + tail
        publishQueue()
    }

    func cycleRepeat() {
        repeatMode = repeatMode == "NONE" ? "ALL" : (repeatMode == "ALL" ? "ONE" : "NONE")
    }

    func playQueue(index: Int) {
        failuresInARow = 0
        startTrack(index)
    }

    // MARK: - Media keys / Control Center

    func remoteSetPlaying(_ wantPlaying: Bool?) {
        if let wantPlaying {
            if isPlaying != wantPlaying { togglePlay() }
        } else {
            togglePlay()
        }
    }

    func remoteNext() { next() }
    func remotePrevious() { previous() }

    // MARK: - Data

    func home(params: String?, browseId: String? = nil) async throws -> BrowsePage {
        try await call("home", ["params": params ?? "", "browseId": browseId ?? ""])
    }

    /// Regular YouTube's home feed (music only when YouTube offers that filter).
    func youtubeHome() async throws -> YouTubeFeed {
        try await call("ytHome")
    }

    /// Latest uploads of the channels the account follows, newest first. Shared for 5
    /// minutes by the home page, the new releases page and the bell (one request at a time);
    /// when YouTube answers with nothing, the last good feed stands in.
    func youtubeSubscriptions() async throws -> YouTubeFeed {
        if let kept = subscriptionFeed, Date().timeIntervalSince(kept.at) < 5 * 60 { return kept.feed }
        if let running = subscriptionTask { return try await running.value }
        let task = Task { () throws -> YouTubeFeed in try await call("ytSubscriptions") }
        subscriptionTask = task
        defer { subscriptionTask = nil }
        do {
            let feed = try await task.value
            if !feed.items.isEmpty {
                subscriptionFeed = (feed, Date())
                return feed
            }
            EngineLog.write("Abonelik akışı boş geldi (\(feed.summary ?? "?"))"
                            + (subscriptionFeed != nil ? "; öncekiyle devam" : ""))
            return subscriptionFeed?.feed ?? feed
        } catch {
            EngineLog.write("Abonelik akışı alınamadı: \(error.localizedDescription)"
                            + (subscriptionFeed != nil ? "; öncekiyle devam" : ""))
            if let kept = subscriptionFeed { return kept.feed }
            throw error
        }
    }

    @ObservationIgnored private var subscriptionFeed: (feed: YouTubeFeed, at: Date)?
    @ObservationIgnored private var subscriptionTask: Task<YouTubeFeed, Error>?

    /// The account's YouTube notifications (the bell) of the last `days` days, newest
    /// first. Read only: nothing is marked as seen or read on YouTube.
    func youtubeNotifications(days: Int) async throws -> NotificationFeed {
        try await call("ytNotifications", ["days": days])
    }

    /// Whether a channel is a music channel (artist, label, festival), decided once per
    /// session: kept in memory only, gone when the app quits or the account changes.
    @ObservationIgnored var musicChannels: [String: Bool] = [:]

    /// A video's channel and category (one request).
    func youtubeVideoInfo(_ videoId: String) async -> YouTubeVideoInfo? {
        try? await call("ytVideoInfo", ["videoId": videoId])
    }

    /// The day an album or single came out (its first song's publish date), if YouTube says.
    func releaseDate(_ browseId: String) async -> Date? {
        guard let text = (try? await call("releaseDate", ["browseId": browseId], as: String?.self)) ?? nil else { return nil }
        return Inbox.day(text)
    }

    /// Regular YouTube search (`long`: only videos over 20 minutes).
    func youtubeSearch(_ query: String, long: Bool) async throws -> YouTubeFeed {
        try await call("ytSearch", ["query": query, "long": long])
    }

    /// Suggestions for the search field. The last 20 texts' are kept in memory, so deleting
    /// back over what was typed asks for nothing again.
    func searchSuggestions(_ query: String) async throws -> SearchSuggestions {
        let key = query.lowercased()
        if let kept = suggestionCache[key] { return kept }
        let found: SearchSuggestions = try await call("searchSuggestions", ["query": query])
        suggestionCache[key] = found
        suggestionOrder.removeAll { $0 == key }
        suggestionOrder.append(key)
        while suggestionOrder.count > 20 { suggestionCache[suggestionOrder.removeFirst()] = nil }
        return found
    }

    /// Artists the account is subscribed to.
    func subscribedArtists() async throws -> [MediaItem] {
        try await call("subscriptions")
    }

    /// A page as YouTube Music shows it in another country (`region` nil: the account's own).
    func browse(_ browseId: String, params: String?, region: String?) async throws -> BrowsePage {
        guard let region else { return try await browse(browseId, params: params) }
        return try await call("browseIn", ["browseId": browseId, "params": params ?? "", "gl": region])
    }

    /// YouTube Music's charts for the whole world.
    func globalCharts() async throws -> BrowsePage {
        try await call("globalCharts")
    }

    /// Channels' own square pictures (their avatars on regular YouTube), by channel id;
    /// kept in memory while the app runs. Channels without one are left out.
    func channelPhotos(_ ids: [String]) async -> [String: String] {
        let missing = Array(Set(ids.filter { $0.hasPrefix("UC") && channelPhotoCache[$0] == nil }))
        // The script reads 30 channels per call: the rest in further calls, side by side.
        let batches = stride(from: 0, to: missing.count, by: 30).map { Array(missing[$0..<min($0 + 30, missing.count)]) }
        let results = await withTaskGroup(of: [String: String?].self) { group in
            for batch in batches {
                group.addTask {
                    do {
                        return try await self.call("channelPhotos", ["ids": batch], as: [String: String?].self)
                    } catch {
                        EngineLog.write("Kanal fotoğrafları alınamadı (\(batch.count)): \(error.localizedDescription)")
                        return [:]
                    }
                }
            }
            var all: [[String: String?]] = []
            for await r in group { all.append(r) }
            return all
        }
        // Only the channels actually read are kept ("" for one without a picture); one
        // left out (a request that failed, or past the 30) is asked again next time.
        for found in results {
            for (id, url) in found { channelPhotoCache[id] = url ?? "" }
        }
        if !missing.isEmpty {
            let read = results.reduce(0) { $0 + $1.count }
            let pictures = results.reduce(0) { $0 + $1.values.filter { $0 != nil }.count }
            EngineLog.write("Kanal fotoğrafları: \(missing.count) istendi, \(read) okundu, \(pictures) fotoğraf")
        }
        return ids.reduce(into: [:]) { out, id in
            if let url = channelPhotoCache[id], !url.isEmpty { out[id] = url }
        }
    }

    /// "" for a channel looked up without a picture (so it isn't asked again).
    @ObservationIgnored private var channelPhotoCache: [String: String] = [:]

    /// What regular YouTube suggests next to a video.
    func youtubeRelated(_ videoId: String) async throws -> YouTubeFeed {
        try await call("ytRelated", ["videoId": videoId])
    }

    /// A mix as a page (mixes have none on YouTube Music): the queue YouTube Music builds
    /// for it, under the mix's own title, subtitle and cover. `target.params`: its endpoint.
    func mixPage(_ target: BrowseTarget) async throws -> BrowsePage {
        let endpoint = target.params ?? ""
        let q: WatchQueue = try await call("watchQueue", ["endpoint": endpoint, "context": ""])
        var seen = Set<String>()
        let items = q.items.compactMap { e -> MediaItem? in
            guard let v = e.videoId, seen.insert(v).inserted else { return nil }
            let song = e.videoType == nil || e.videoType == "MUSIC_VIDEO_TYPE_ATV"
            return MediaItem(uid: "mix-\(target.browseId)-\(v)", kind: song ? "song" : "video", title: e.title,
                             subtitle: e.subtitle, thumbnail: e.thumbnail ?? e.art, videoId: v, browseId: nil,
                             params: nil, playlistId: nil, artists: e.artists ?? [], album: e.album,
                             duration: e.duration.isEmpty ? nil : e.duration, explicit: false, play: nil,
                             wide: false, color: nil)
        }
        let header = PageHeader(style: "collection", title: target.title ?? "", subtitle: target.about ?? "",
                                secondSubtitle: M.t("\(items.count) şarkı", M.count(items.count, "song", "songs")), strapline: "",
                                description: "", thumbnail: target.cover, strapThumb: nil, subscribers: "",
                                play: endpoint, shuffle: nil, radio: nil, artists: [])
        let list = Shelf(id: "mix-songs", title: "", strapline: nil, layout: "list", items: items,
                         more: nil, continuation: nil, top: nil)
        return BrowsePage(header: header, chips: [], sections: [list], continuation: nil)
    }

    func browse(_ browseId: String, params: String?) async throws -> BrowsePage {
        var args: [String: Any] = ["browseId": browseId]
        if let params { args["params"] = params }
        return try await call("browse", args)
    }

    func more(_ token: String) async throws -> MoreResult {
        try await call("more", ["token": token])
    }

    func search(_ query: String, params: String?) async throws -> BrowsePage {
        var args: [String: Any] = ["query": query]
        if let params { args["params"] = params }
        return try await call("search", args)
    }

    func searchMore(_ token: String) async throws -> MoreResult {
        try await call("searchMore", ["token": token])
    }

    func lyrics(videoId: String) async throws -> LyricsData {
        try await call("lyrics", ["videoId": videoId])
    }

    /// Every library list: waits for the first pages; the rest come in behind them.
    func loadLibrary() async {
        guard loggedIn else { return }
        libraryLoading = true
        defer { libraryLoading = false }
        await withTaskGroup(of: Void.self) { group in
            for list in LibraryFilter.allCases {
                group.addTask { await self.loadLibraryList(list) }
            }
        }
    }

    /// Waits until every library list has been read to the end (or given up on).
    func libraryPagesDone() async {
        for task in libraryPageTasks.values { await task.value }
    }

    /// Shows `list` in `sort`. A–Z and Z–A of a list read to the end need no new request.
    func sortLibrary(_ list: LibraryFilter, _ sort: LibrarySort) {
        guard librarySorts[list] != sort else { return }
        librarySorts[list] = sort
        sort.save(for: list)
        if sort != .recent, libraryComplete.contains(list) {
            library[list] = sort.apply(library[list])
            return
        }
        Task { await loadLibraryList(list) }
    }

    /// The first page of `list` in its order, then the rest page by page in the background.
    /// A newer load of the same list makes an older one stop.
    private func loadLibraryList(_ list: LibraryFilter) async {
        let run = UUID()
        libraryRuns[list] = run
        libraryPageTasks[list]?.cancel()
        libraryComplete.remove(list)
        libraryPaging.remove(list)
        let sort = librarySorts[list] ?? .recent
        guard let first = try? await call("libraryPage", ["browseId": list.browseId, "params": sort.params],
                                          as: LibraryPage.self),
              libraryRuns[list] == run else { return }
        var seen = Set<String>()
        var items = first.items.filter { list.keeps($0) && seen.insert($0.browseId ?? $0.uid).inserted }
        // Just added here but not listed by YouTube yet: kept at the top for two minutes.
        justAdded = justAdded.filter { Date().timeIntervalSince($0.value.at) < 120 }
        let waiting = justAdded.values.filter { $0.list == list && !seen.contains($0.item.browseId ?? "") }
            .sorted { $0.at > $1.at }.map(\.item)
        if !items.isEmpty, !waiting.isEmpty {
            for w in waiting { seen.insert(w.browseId ?? w.uid) }
            items = waiting + items
        }
        // An empty answer for a list that had things is YouTube's hiccup, not an empty library:
        // what is shown stays.
        if items.isEmpty, !library[list].isEmpty {
            EngineLog.write("Kitaplık: \(list.rawValue) boş geldi; eldeki \(library[list].count) öğe kaldı")
            return
        }
        library[list] = sort.apply(items)
        guard let token = first.continuation else {
            libraryComplete.insert(list)
            EngineLog.write("Kitaplık: \(list.rawValue) \(items.count) öğe")
            return
        }
        libraryPaging.insert(list)
        libraryPageTasks[list] = Task { [weak self] in
            await self?.pageLibrary(list, run: run, sort: sort, items: items, seen: seen,
                                    token: token, ordered: first.ordered)
        }
    }

    /// The rest of `list` after its first page, at most 40 pages.
    private func pageLibrary(_ list: LibraryFilter, run: UUID, sort: LibrarySort, items start: [MediaItem],
                             seen known: Set<String>, token first: String, ordered: Bool) async {
        var items = start, seen = known, token = first, pages = 1
        defer { if libraryRuns[list] == run { libraryPaging.remove(list) } }
        while pages < 40, !Task.isCancelled {
            guard let more = try? await call("more", ["token": token], as: MoreResult.self),
                  libraryRuns[list] == run else { return }
            let fresh = more.items.filter { $0.browseId != nil && list.keeps($0) && seen.insert($0.browseId ?? $0.uid).inserted }
            pages += 1
            if !fresh.isEmpty {
                items += fresh
                library[list] = sort.apply(items)
            }
            guard let next = more.continuation, next != token, !fresh.isEmpty else { break }
            token = next
        }
        guard libraryRuns[list] == run else { return }
        libraryComplete.insert(list)
        EngineLog.write("Kitaplık: \(list.rawValue) \(items.count) öğe, \(pages) sayfa"
                        + (ordered ? "" : " (YouTube sırayı almadı)"))
    }

    // MARK: - Account

    func showLogin() {
        webSheet = .login
    }

    /// Called by the sign-in sheet once Google has redirected back to YouTube Music.
    func loginFinished() {
        webSheet = nil
        // The sign-in page's cache/storage isn't needed once the cookies are copied.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            StorageCleanup.clearWebCaches()
        }
        Task { await boot(syncFromSignIn: true) }
    }

    func signOut() {
        YTAuth.clearCookies()
        // Also clear the sign-in sheet's own cookies, so the next sign-in starts fresh.
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let targets = records.filter { $0.displayName.contains("google") || $0.displayName.contains("youtube") }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: targets) {
                Task { @MainActor in YTMusic.shared.reloadHome() }
            }
        }
    }

    /// Re-reads the sign-in state and reloads everything.
    func reloadHome() {
        Task { await boot(syncFromSignIn: false) }
    }
}
