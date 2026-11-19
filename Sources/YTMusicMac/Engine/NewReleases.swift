import Foundation

/// The "Yeni Çıkanlar" page: what's new that is yours first, then what YouTube Music
/// offers.
///
/// 1. Takip ettiğin sanatçılardan: the latest 20 releases of the artists you follow
///    (`followed`, also the home page's "Yeni çıkanlar" row: both show the same list).
/// 2. Dinlediğin sanatçılardan: this year's releases of artists you listen to in the app
///    but don't follow (from the listening history; artist pages give the year only).
/// 3. Senin için yeni: YouTube Music's new releases (here and worldwide) closest to the
///    artists you listen to and follow.
/// 4. YouTube Music'te yeni: the rest of YouTube Music's new releases. Asked for here and
///    for the US, taken in turns: the page isn't sorted by region, so it isn't called
///    "new in <country>".
/// 5. Yeni müzik videoları.
///
/// The home page's filters apply (what you said not to recommend, unwanted songs,
/// community playlists, releases from before last year), and each release shows once.
/// Releases taken from an artist's page carry the artist's name (the page doesn't write it).
@MainActor
enum NewReleases {
    // MARK: The followed artists' releases (shared with the home page)

    private static let followedKey = "home|new-followed"

    /// The latest 20 releases of the artists you follow. First what they put out this month
    /// (their uploads in YouTube's subscriptions feed, shown as the single or album), then
    /// this year's and last year's releases from their pages (twenty artists at most: those
    /// with an upload this month, then the ones you listen to most), newest year first, the
    /// artists in turns. Kept 15 minutes, so the home page and this page show the same.
    static func followed(_ engine: YTMusic, subs: [MediaItem], uploads: [YouTubeVideo],
                         profile: ListeningProfile, wanted: @escaping (MediaItem) -> Bool) async -> [MediaItem] {
        let cache = PageCache.shared
        if cache.isFresh(followedKey), let kept = cache.value(followedKey, as: [MediaItem].self) {
            return kept.filter(wanted)
        }
        let byId = Dictionary(subs.compactMap { a in a.browseId.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        let byKey = Dictionary(subs.map { (ListeningProfile.key($0.title), $0) }, uniquingKeysWith: { a, _ in a })
        // Uploads of the last month (songs and clips, not sets), newest first.
        let monthUploads: [(MediaItem, YouTubeVideo)] = uploads.compactMap { v in
            guard !v.mix, let age = v.ageDays, age <= 31, v.seconds >= 60, v.seconds < QueueCurator.setSeconds else { return nil }
            let match = v.channelId.flatMap { byId[$0] } ?? byKey[ListeningProfile.key(v.channel)]
            return match.map { ($0, v) }
        }
        let byListening = subs.enumerated()
            .map { ($0.element, profile.listened($0.element.title) - Double($0.offset) * 0.001) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let ids = PersonalHome.unique(monthUploads.map(\.0) + byListening, limit: 20).compactMap(\.browseId)
        let pages = await PersonalHome.pages(engine, ids.map { ($0, String?.none) })
        let pageById = Dictionary(zip(ids, pages), uniquingKeysWith: { a, _ in a })
        let year = Calendar.current.component(.year, from: Date())
        func releases(of id: String) -> [MediaItem] {
            guard let p = pageById[id] else { return [] }
            return releasesOnPage(p, id: id, name: byId[id]?.title ?? "", sinceYear: year - 1, wanted: wanted)
        }

        var list: [MediaItem] = []
        for (artist, video) in monthUploads {
            guard let id = artist.browseId,
                  let r = releases(of: id).first(where: { PersonalHome.sameTitle($0.title, video.item.title) }) else { continue }
            list.append(r)
        }
        let perArtist = ids.map { releases(of: $0) }
        for y in [year, year - 1] {
            let lists = perArtist.map { $0.filter { PersonalHome.year($0) == y } }
            for round in 0..<(lists.map(\.count).max() ?? 0) {
                for l in lists where round < l.count { list.append(l[round]) }
            }
        }
        let out = PersonalHome.unique(list, limit: 20)
        if !out.isEmpty { cache.store(out, for: followedKey, lifetime: PageCache.Lifetime.page) }
        return out
    }

    /// An artist page's albums and singles since `sinceYear`, newest year first (in page
    /// order within a year), with the artist's name on them.
    private static func releasesOnPage(_ page: BrowsePage, id: String, name: String, sinceYear: Int,
                                       wanted: (MediaItem) -> Bool) -> [MediaItem] {
        let artist = page.header?.title ?? name
        return PersonalHome.similarParts(page.sections, wanted).releases
            .filter { (PersonalHome.year($0) ?? 0) >= sinceYear }
            .enumerated()
            .sorted { (PersonalHome.year($0.element) ?? 0, -$0.offset) > (PersonalHome.year($1.element) ?? 0, -$1.offset) }
            .map { $0.element.by(artist, id: id) }
    }

    // MARK: The page

    static func build(_ engine: YTMusic, hidden: Set<String>) async throws -> BrowsePage {
        async let profileTask = ListeningProfile.load()
        async let localTask = try? engine.browse("FEmusic_new_releases", params: nil)
        async let worldTask = try? engine.browse("FEmusic_new_releases", params: nil, region: "US")
        async let subsTask = try? engine.subscribedArtists()
        async let uploadsTask = try? engine.youtubeSubscriptions()
        let profile = await profileTask
        let subs = await subsTask ?? []

        func wanted(_ i: MediaItem) -> Bool {
            !hidden.contains(i.recommendationKey) && !profile.isUnwanted(i.videoId) && !PersonalHome.isCommunityList(i)
        }

        // 1.
        let followedNew = await followed(engine, subs: subs, uploads: (await uploadsTask)?.items ?? [],
                                         profile: profile, wanted: wanted)

        // 2. Artists heard in the app (recently or for long) that you don't follow: up to
        // three releases of this year each, the artists in turns.
        let followedIds = Set(subs.compactMap(\.browseId))
        var heardIds: [String] = []
        var heardNames: [String: String] = [:]
        for a in profile.recentArtists(limit: 30) + profile.topListened(limit: 30) {
            guard let id = a.id, id.hasPrefix("UC"), !followedIds.contains(id), !heardIds.contains(id) else { continue }
            heardIds.append(id)
            heardNames[id] = a.name
            if heardIds.count == 8 { break }
        }
        let heardPages = await PersonalHome.pages(engine, heardIds.map { ($0, String?.none) })
        let year = Calendar.current.component(.year, from: Date())
        let perArtist = zip(heardIds, heardPages).map { id, page in
            Array(releasesOnPage(page, id: id, name: heardNames[id] ?? "", sinceYear: year - 1, wanted: wanted)
                .filter { PersonalHome.isRecent($0) }
                .prefix(3))
        }
        var heardNew: [MediaItem] = []
        for round in 0..<3 {
            for list in perArtist where round < list.count { heardNew.append(list[round]) }
        }

        var used = Set<String>()
        func fresh(_ items: [MediaItem], limit: Int) -> [MediaItem] {
            var out: [MediaItem] = []
            for it in items where out.count < limit && used.insert(it.recommendationKey).inserted { out.append(it) }
            return out
        }
        let row1 = fresh(followedNew, limit: 20)
        let row2 = fresh(heardNew, limit: 24)

        // YouTube Music's new releases: albums and singles, here and worldwide.
        let localPage = await localTask
        let worldPage = await worldTask
        guard localPage != nil || worldPage != nil || !row1.isEmpty || !row2.isEmpty else {
            throw URLError(.cannotLoadFromNetwork)
        }
        func albums(_ page: BrowsePage?) -> [MediaItem] {
            (page?.sections ?? []).flatMap(\.items).filter { $0.kind == "album" && wanted($0) && !PersonalHome.isOld($0) }
        }
        let local = albums(localPage), world = albums(worldPage)
        let mine = PersonalHome.unique(local + world, limit: 200)
            .map { ($0, PersonalHome.releaseScore($0, profile, subs)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let row3 = fresh(mine, limit: 20)
        let row4 = fresh(PersonalHome.interleave(local, world), limit: 40)
        let videos = (localPage?.sections ?? []).flatMap(\.items)
            .filter { $0.isTrack && $0.kind != "song" && wanted($0) }
            .map(\.asWide)
        let row5 = fresh(videos, limit: 30)

        let rows: [(String, String, [MediaItem], Int)] = [
            ("followed", M.t("Takip ettiğin sanatçılardan", "From artists you follow"), row1, 1),
            ("heard", M.t("Dinlediğin sanatçılardan", "From artists you listen to"), row2, 3),
            ("mine", M.t("Senin için yeni", "New for you"), row3, 4),
            ("youtube", M.t("YouTube Music'te yeni", "New on YouTube Music"), row4, 4),
            ("videos", M.t("Yeni müzik videoları", "New music videos"), row5, 4),
        ]
        let sections = rows.filter { $0.2.count >= $0.3 }.map { id, title, items, _ in
            Shelf(id: "new-\(id)", title: title, strapline: nil, layout: "cards", items: items,
                  more: nil, continuation: nil, top: nil)
        }
        return BrowsePage(header: nil, chips: [], sections: sections, continuation: nil)
    }
}
