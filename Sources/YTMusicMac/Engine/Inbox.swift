import Foundation
import Observation

/// The bell at the top right: the latest music from the channels and artists you follow,
/// newest first.
///
/// - From YouTube: the regular uploads of the last two weeks from the music channels you
///   follow (the home page's "Senin için bildirimler", PersonalHome.notificationItems): no
///   Shorts, comments or posts, no channels that aren't music.
/// - From YouTube Music: the new singles and albums of artists you follow that YouTube
///   Music lists as new releases (here and worldwide), first; many come out there without
///   an upload on the artist's YouTube channel. And when an upload is a new release of an
///   artist you follow (NewReleases.followed), it shows as that release instead of the video.
///
/// What you have seen is kept on this Mac only (nothing is marked read on YouTube): the bell
/// shows a dot while something new is waiting, and the panel marks it until it is closed.
/// Refreshed shortly after launch, then every 30 minutes, and on opening when older than
/// 5 minutes.
@MainActor
@Observable
final class Inbox {
    static let shared = Inbox()

    private(set) var items: [MediaItem] = []
    private(set) var loading = false
    private(set) var loadedAt: Date?
    /// Items in the list not seen yet (the bell's dot).
    private(set) var unseen = 0

    private var seen: Set<String>
    private static let seenKey = "inboxSeen"
    private static let interval: UInt64 = 30 * 60 * 1_000_000_000
    @ObservationIgnored private var loop: Task<Void, Never>?

    private init() {
        seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? [])
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            // After the home page has had its turn.
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.interval)
            }
        }
    }

    func refreshIfStale() {
        if let at = loadedAt, Date().timeIntervalSince(at) < 5 * 60 { return }
        Task { await refresh() }
    }

    func refresh() async {
        let engine = YTMusic.shared
        guard engine.loggedIn, !loading else { return }
        loading = true
        defer { loading = false }
        let list = await Self.build(engine, hidden: AppModel.shared.hiddenKeys)
        items = list
        loadedAt = Date()
        unseen = list.filter { !seen.contains($0.uid) }.count
        EngineLog.write("Bildirim zili: \(list.count) öğe, \(unseen) yeni")
    }

    func isNew(_ item: MediaItem) -> Bool { !seen.contains(item.uid) }

    /// The panel was closed: what it showed counts as seen.
    func markSeen() {
        guard !items.isEmpty else { return }
        let ids = items.map(\.uid)
        // Kept: what is listed now and the most recent of before (at most 400).
        let before = (UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []).filter { !ids.contains($0) }
        let kept = Array((ids + before).prefix(400))
        UserDefaults.standard.set(kept, forKey: Self.seenKey)
        seen = Set(kept)
        unseen = 0
    }

    private static func build(_ engine: YTMusic, hidden: Set<String>) async -> [MediaItem] {
        async let profileTask = ListeningProfile.load()
        async let subsTask = try? engine.subscribedArtists()
        async let uploadsTask = try? engine.youtubeSubscriptions()
        async let notesTask = PersonalHome.loadNotifications(engine)
        async let localNewTask = try? engine.browse("FEmusic_new_releases", params: nil)
        async let worldNewTask = try? engine.browse("FEmusic_new_releases", params: nil, region: "US")
        let profile = await profileTask
        let subs = await subsTask ?? []
        let uploads = (await uploadsTask)?.items ?? []
        let notes = await notesTask

        func wanted(_ i: MediaItem) -> Bool {
            !hidden.contains(i.recommendationKey) && !profile.isUnwanted(i.videoId)
        }
        let heardIds = Set((profile.recentArtists(limit: 300) + profile.topListened(limit: 300)).compactMap(\.id))
        let videos = await PersonalHome.notificationItems(engine, notes?.items ?? [], uploads: uploads,
                                                          artistIds: Set(subs.compactMap(\.browseId)), heardIds: heardIds)
            .filter(wanted)
        let releases = await NewReleases.followed(engine, subs: subs, uploads: uploads, profile: profile, wanted: wanted)

        // YouTube Music's new releases by the artists you follow.
        let followedIds = Set(subs.compactMap(\.browseId))
        let followedKeys = Set(subs.map { ListeningProfile.key($0.title) })
        let newPages = [await localNewTask, await worldNewTask].compactMap { $0 }
        var newReleases: [MediaItem] = []
        for item in newPages.flatMap({ $0.sections.flatMap(\.items) }) where item.kind == "album" && wanted(item) {
            let byFollowed = item.artists.contains { followedIds.contains($0.id) || followedKeys.contains(ListeningProfile.key($0.name)) }
            guard byFollowed, !newReleases.contains(where: { $0.recommendationKey == item.recommendationKey }) else { continue }
            var r = item
            r.subtitle = [r.subtitle, M.t("YouTube Music'te yeni", "New on YouTube Music")].joined(separator: " • ")
            newReleases.append(r)
        }

        var used = Set<String>()
        let fromUploads = videos.prefix(40).compactMap { v -> MediaItem? in
            var item = v
            if let channel = v.artists.first?.id,
               let release = releases.first(where: { r in
                   r.artists.contains { $0.id == channel } && PersonalHome.sameTitle(r.title, v.title)
               }) {
                // The single or album on YouTube Music, dated by its upload.
                item = release
                item.subtitle = [Self.kind(of: release), v.subtitle].filter { !$0.isEmpty }.joined(separator: " • ")
                item.avatar = v.avatar
                item.unread = v.unread
                item.wide = false
            }
            return used.insert(item.uid).inserted ? item : nil
        }
        // A release already shown for its upload isn't listed twice.
        let shown = Set(fromUploads.map(\.recommendationKey))
        let releasesOnly = newReleases.filter { r in
            !shown.contains(r.recommendationKey)
                && !fromUploads.contains { PersonalHome.sameTitle(r.title, $0.title) && $0.artists.first?.id == r.artists.first?.id }
        }
        EngineLog.write("Bildirim zili: YouTube Music'te yeni \(releasesOnly.count), yükleme \(fromUploads.count)")
        return releasesOnly + fromUploads
    }

    /// "Single", "EP", "Albüm": the kind written in a release's subtitle.
    private static func kind(of release: MediaItem) -> String {
        let parts = release.subtitle.components(separatedBy: " • ")
        let artists = Set(release.artists.map(\.name))
        return parts.first { p in !artists.contains(p) && Int(p) == nil && !p.isEmpty } ?? ""
    }
}
