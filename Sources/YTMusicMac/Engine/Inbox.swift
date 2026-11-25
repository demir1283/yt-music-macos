import Foundation
import Observation

/// The bell at the top right: the latest music from the channels and artists you follow,
/// newest first: an upload by when it went up, a release by the day it came out (its first
/// song's publish date, looked up once and kept), or else by when the bell first listed it.
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

        var ages: [String: Double] = [:]
        for u in uploads { if let v = u.item.videoId, let a = u.ageDays, ages[v] == nil { ages[v] = a } }
        let now = Date()
        var dates: [String: Date] = [:]

        var used = Set<String>()
        let fromUploads = videos.prefix(40).compactMap { v -> MediaItem? in
            var item = v
            let uploaded = v.videoId.flatMap { ages[$0] }.map { now.addingTimeInterval(-$0 * 86_400) }
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
            guard used.insert(item.uid).inserted else { return nil }
            if let uploaded { dates[item.uid] = uploaded }
            return item
        }
        // A release already shown for its upload isn't listed twice.
        let shown = Set(fromUploads.map(\.recommendationKey))
        let releasesOnly = newReleases.filter { r in
            !shown.contains(r.recommendationKey)
                && !fromUploads.contains { PersonalHome.sameTitle(r.title, $0.title) && $0.artists.first?.id == r.artists.first?.id }
        }
        let released = await releaseDays(engine, releasesOnly)
        for r in releasesOnly { dates[r.uid] = released[r.recommendationKey] }
        EngineLog.write("Bildirim zili: YouTube Music'te yeni \(releasesOnly.count) (\(released.count) tarihli), yükleme \(fromUploads.count)")
        return Self.newestFirst(releasesOnly + fromUploads, dates: dates)
    }

    /// Newest first; what has no date keeps its place among the undated, after the dated.
    nonisolated static func newestFirst(_ items: [MediaItem], dates: [String: Date]) -> [MediaItem] {
        items.enumerated().sorted { a, b in
            switch (dates[a.element.uid], dates[b.element.uid]) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    private static let releaseDatesKey = "inboxReleaseDates"
    private static let firstListedKey = "inboxFirstListed"

    /// The day each release came out, looked up once and kept on this Mac. A release whose
    /// day YouTube doesn't give is dated by when the bell first listed it.
    private static func releaseDays(_ engine: YTMusic, _ releases: [MediaItem]) async -> [String: Date] {
        let defaults = UserDefaults.standard
        var known = defaults.dictionary(forKey: releaseDatesKey) as? [String: Double] ?? [:]
        var listed = defaults.dictionary(forKey: firstListedKey) as? [String: Double] ?? [:]
        let missing = releases.filter { known[$0.recommendationKey] == nil && $0.browseId?.hasPrefix("MPRE") == true }
        let found = await withTaskGroup(of: (String, Date?).self) { group in
            for r in missing.prefix(20) {
                let key = r.recommendationKey, id = r.browseId ?? ""
                group.addTask { (key, await engine.releaseDate(id)) }
            }
            var out: [String: Date] = [:]
            for await (key, day) in group { if let day { out[key] = day } }
            return out
        }
        for (key, day) in found { known[key] = day.timeIntervalSince1970 }
        let now = Date().timeIntervalSince1970
        var out: [String: Date] = [:]
        for r in releases {
            let key = r.recommendationKey
            if let t = known[key] {
                // Noon of a day not over yet isn't later than now.
                out[key] = min(Date(timeIntervalSince1970: t), Date())
            } else {
                if listed[key] == nil { listed[key] = now }
                out[key] = Date(timeIntervalSince1970: listed[key] ?? now)
            }
        }
        // Kept: the newest 300 of each.
        func trimmed(_ d: [String: Double]) -> [String: Double] {
            Dictionary(uniqueKeysWithValues: d.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) })
        }
        defaults.set(trimmed(known), forKey: releaseDatesKey)
        defaults.set(trimmed(listed), forKey: firstListedKey)
        return out
    }

    /// "2026-11-20" (or "2026-11-20T00:00:00-08:00"): that day, at noon here.
    nonisolated static func day(_ text: String) -> Date? {
        let parts = text.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    /// "Single", "EP", "Albüm": the kind written in a release's subtitle.
    private static func kind(of release: MediaItem) -> String {
        let parts = release.subtitle.components(separatedBy: " • ")
        let artists = Set(release.artists.map(\.name))
        return parts.first { p in !artists.contains(p) && Int(p) == nil && !p.isEmpty } ?? ""
    }
}
