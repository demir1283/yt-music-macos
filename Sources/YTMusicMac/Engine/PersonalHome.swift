import Foundation

/// The home page, laid out like Spotify's (rows modelled on its desktop home), built from
/// YouTube Music, regular YouTube and the app's own listening history.
///
/// Rows, top to bottom (each shown only with plenty in it):
///  1. Greeting + 8 tiles: your mixes and what you played lately.
///     Senin için bildirimler: the regular uploads of the last two weeks from the music
///     channels you follow — artists, labels, festivals — newest first (unread ones marked).
///  2. Senin için seçildi (one pick at a time, sliding) + Tavsiye edilen istasyonlar: radios
///     of the 15 artists heard / followed most recently and the 15 listened to longest.
///  3. Son çalınanlar.
///  4. Hızlı seçimler: a fresh random mix each visit of YouTube Music's picks, songs from
///     your saved playlists, what you played lately, worldwide hits and old favourites.
///  5. "<Ad> için derlendi": YouTube Music's personal mixes and artist mixes.
///  6. "<Sanatçı> ile benzer diğer müzikler": the artists its fans also listen to.
///  7. En çok dinlediğin mix'ler.
///  8. Kaldığın yerden devam et: long recordings started but not finished.
///  9. YouTube Music'ten popüler listeler: editorial playlists, local and worldwide in turn.
/// 10. A second "benzer diğer müzikler" row.
/// 11. Yeni çıkanlar: what the artists you follow put out in the last month (found through
///     YouTube's subscriptions feed, shown as the single or album on YouTube Music), with
///     a new release that's popular here or worldwide every few items.
/// 12. Uzun setler: sets in the kinds of music you listen to most (found from the titles of
///     your playlists and of the sets you played), and sets of your artists.
/// 13. Favori sanatçıların: the artists you follow.
/// 14. Living cards: one artist each, on their wide YouTube Music banner.
/// 15. Tekrar dinle, then YouTube Music's remaining rows.
///
/// Left out everywhere: "Yeniden dinleyin", community playlists, songs the history says you
/// don't want, and whatever you said not to recommend. The page is built from scratch each
/// time it is built; HomeView keeps it in memory (PageCache) and decides when that is.
@MainActor
enum PersonalHome {
    struct LoadError: LocalizedError {
        var errorDescription: String? { "Ana sayfa yüklenemedi." }
    }

    /// Fewest cards a row may have; song lists need a little more.
    static let minimumCards = 6
    static let minimumSongs = 8

    static func build(_ engine: YTMusic, hidden: Set<String>) async throws -> BrowsePage {
        async let profileTask = ListeningProfile.load()
        async let musicTask = try? engine.home(params: nil)
        async let feedTask = try? engine.youtubeHome()
        async let releasesTask = try? engine.browse("FEmusic_new_releases", params: nil)
        async let chartsTask = try? engine.globalCharts()
        async let worldReleasesTask = try? engine.browse("FEmusic_new_releases", params: nil, region: "US")
        async let subsTask = try? engine.subscribedArtists()
        async let uploadsTask = try? engine.youtubeSubscriptions()
        async let notesTask = Self.loadNotifications(engine)
        async let editorialTask = Self.editorialPlaylists(engine)
        let profile = await profileTask
        let subs = await subsTask ?? []

        func wanted(_ i: MediaItem) -> Bool {
            !hidden.contains(i.recommendationKey) && !profile.isUnwanted(i.videoId) && !Self.isCommunityList(i)
        }

        // Artists: the ones you follow (Favori sanatçıların), and a hybrid of the 15 heard or
        // followed most recently and the 15 listened to longest (stations, cards).
        let followed = subs.filter(wanted)
            .enumerated()
            .map { (i, a) -> (MediaItem, Double) in (a, profile.listened(a.title) - Double(i) * 0.001) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        let byKey = Dictionary(subs.map { (ListeningProfile.key($0.title), $0) }, uniquingKeysWith: { a, _ in a })
        func artistItem(_ a: ListeningProfile.HeardArtist) -> MediaItem? {
            if let s = byKey[ListeningProfile.key(a.name)] { return s }
            guard let id = a.id, id.hasPrefix("UC") else { return nil }
            return MediaItem(uid: "artist-\(id)", kind: "artist", title: a.name, subtitle: "", thumbnail: a.cover,
                             videoId: nil, browseId: id, params: nil, playlistId: nil, artists: [], album: nil,
                             duration: nil, explicit: false, play: nil, wide: false, color: nil)
        }
        let recentArtists = Self.unique(Self.interleave(profile.recentArtists(limit: 15).compactMap(artistItem),
                                                        Array(subs.prefix(15))), limit: 15)
        let topArtists = Self.unique(profile.topListened(limit: 15).compactMap(artistItem) + followed, limit: 15)
        let hybrid = Self.unique(Self.interleave(topArtists, recentArtists), limit: 30).filter { wanted($0) && $0.browseId != nil }

        // What the artists you follow uploaded in the last month (songs and clips, not sets or
        // Shorts), newest first, from YouTube's subscriptions feed.
        let uploads = await uploadsTask
        let followedById = Dictionary(followed.compactMap { a in a.browseId.map { ($0, a) } }, uniquingKeysWith: { a, _ in a })
        let followedByKey = Dictionary(followed.map { (ListeningProfile.key($0.title), $0) }, uniquingKeysWith: { a, _ in a })
        let monthUploads: [(MediaItem, YouTubeVideo)] = (uploads?.items ?? []).compactMap { v -> (MediaItem, YouTubeVideo)? in
            guard !v.mix, let age = v.ageDays, age <= 31, v.seconds >= 60, v.seconds < QueueCurator.setSeconds else { return nil }
            let match = v.channelId.flatMap { followedById[$0] } ?? followedByKey[ListeningProfile.key(v.channel)]
            return match.map { ($0, v) }
        }
        let releaseArtists = Self.unique(monthUploads.map { $0.0 }, limit: 12)

        // Artist pages: banners, fans also like and releases for the cards and "benzer" rows
        // (first six of the hybrid), this year's releases of the followed artists above.
        let pageIds = Array(Set(hybrid.prefix(6).compactMap(\.browseId) + releaseArtists.compactMap(\.browseId)))
        async let artistPagesTask = Self.pages(engine, pageIds.map { ($0, String?.none) })
        // Songs of three of your saved playlists, picked at random.
        let saved = engine.library.playlists.filter { wanted($0) && $0.browseId != nil }.shuffled().prefix(3)
        async let savedTask = Self.pages(engine, saved.map { ($0.browseId ?? "", $0.params) })
        let genres = Self.topGenres(profile, playlists: engine.library.playlists.map(\.title), limit: 3)
        let setQueries = genres.map { "\($0) dj set" } + Self.setSearchArtists(profile, followed).prefix(2).map { "\($0) set" }
        async let setsTask = Self.longSets(engine, seeds: profile.setSeeds(limit: 3).map(\.videoId), queries: setQueries)

        // Uploads of the music channels you follow (while the rest still loads).
        let notes = await notesTask
        if let notes { EngineLog.write("Bildirimler: \(notes.summary)") }
        let heardIds = Set((profile.recentArtists(limit: 300) + profile.topListened(limit: 300)).compactMap(\.id))
        let noteItems = await Self.notificationItems(engine, notes?.items ?? [], uploads: uploads?.items ?? [],
                                                     artistIds: Set(subs.compactMap(\.browseId)), heardIds: heardIds)
            .filter(wanted)

        guard let music = await musicTask else { throw LoadError() }
        let feed = await feedTask
        let releasesPage = await releasesTask
        let charts = await chartsTask
        let worldReleasesPage = await worldReleasesTask

        // YouTube Music's rows, cleaned up.
        var ytRows: [Shelf] = music.sections.compactMap { s -> Shelf? in
            if Self.isListenAgain(s) || Self.isCommunity(s) { return nil }
            var s = s
            s.items = s.items.filter(wanted)
            // "Kitaplığınızdan": playlists and albums, not artists.
            if Self.titled(s, ["kitaplığınızdan", "kitaplığından", "from your library"]) {
                s.items = s.items.filter { $0.kind == "playlist" || $0.kind == "album" }
            }
            return s.items.isEmpty ? nil : s
        }
        // Its personal mixes (Beğendiğim müzikler, Tekrar Mix'i, Karışık Keşif…) move up.
        let ytMixes = ytRows.flatMap(\.items).filter { Self.isPersonalMix($0) }
        ytRows = ytRows.compactMap { s -> Shelf? in
            var s = s
            s.items.removeAll { Self.isPersonalMix($0) }
            return s.items.isEmpty ? nil : s
        }
        let quick = ytRows.firstIndex { Self.titled($0, ["hızlı seçim", "quick picks"]) }.map { ytRows.remove(at: $0) }
        // Thin rows are left out (their "more" pages are often about something else).
        ytRows = ytRows.compactMap { s -> Shelf? in
            var s = s
            s.items = s.items.filter(wanted)
            let least = s.hasTracks && s.layout == "list" ? Self.minimumSongs : Self.minimumCards
            return (s.layout == "nav" || s.items.count >= least) ? s : nil
        }

        var used = Set<String>()
        func take(_ items: [MediaItem], limit: Int) -> [MediaItem] {
            var out: [MediaItem] = []
            for item in items where out.count < limit {
                if used.insert(item.recommendationKey).inserted { out.append(item) }
            }
            return out
        }
        func shelf(_ id: String, _ title: String, _ subtitle: String?, _ items: [MediaItem],
                   limit: Int, minimum: Int = PersonalHome.minimumCards, layout: String = "cards",
                   top: MediaItem? = nil) -> Shelf? {
            let fresh = take(items, limit: limit)
            guard fresh.count >= minimum else { return nil }
            return Shelf(id: "home-\(id)", title: title, strapline: subtitle, layout: layout,
                         items: fresh, more: nil, continuation: nil, top: top)
        }

        let quickItems = quick?.items ?? []
        let recentSongs = profile.recent(limit: 20).map { Self.item($0) }.filter(wanted)
        let topMixes = profile.topArtists(limit: 12)
            .sorted { profile.listened($0.name) > profile.listened($1.name) }
            .map { Self.mix(name: $0.name, seed: $0.seed) }

        // New releases: albums and singles, artists you listen to and follow first.
        let releases = (releasesPage?.sections ?? []).flatMap(\.items)
            .filter { $0.kind == "album" && wanted($0) && !Self.isOld($0) }
            .enumerated()
            .map { (i, item) -> (MediaItem, Double) in (item, Self.releaseScore(item, profile, followed) - Double(i) * 0.001) }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        // Trending songs, worldwide and here (songs before music videos).
        func trendingSongs(_ page: BrowsePage?) -> [MediaItem] {
            let all = (page?.sections ?? []).filter(\.hasTracks).flatMap(\.items).filter(wanted)
            return all.filter { $0.kind == "song" } + all.filter { $0.kind != "song" && $0.isTrack }
        }
        let trendSongs = trendingSongs(charts)
        let worldReleases = (worldReleasesPage?.sections ?? []).flatMap(\.items)
            .filter { $0.kind == "album" && wanted($0) && !Self.isOld($0) }

        // Mixes around the artists of your quick picks, one per artist.
        var mixTitles = Set(topMixes.map(\.title))
        var seedMixes: [MediaItem] = []
        for it in quickItems + recentSongs + trendSongs where seedMixes.count < 16 {
            guard let vid = it.videoId else { continue }
            let name = it.artists.first?.name ?? it.subtitle.components(separatedBy: " • ").first ?? ""
            guard !name.isEmpty, mixTitles.insert("\(name) Mix").inserted else { continue }
            seedMixes.append(Self.mix(name: name, videoId: vid, cover: it.thumbnail))
        }

        // YouTube Music's editorial playlists, the official ones on its home first.
        let homeOfficial = music.sections.flatMap(\.items).filter { Self.isOfficial($0) }
        let editorial = Self.unique(homeOfficial + (await editorialTask), limit: 60).filter(wanted)

        let fetched = await artistPagesTask
        let pageById = Dictionary(zip(pageIds, fetched), uniquingKeysWith: { a, _ in a })
        let artistPages = hybrid.prefix(6).map { a in a.browseId.flatMap { pageById[$0] } ?? BrowsePage(header: nil, chips: [], sections: [], continuation: nil) }
        // Each upload as the single or album it belongs to (matched by title among the
        // artist's releases of this year), newest upload first.
        var monthReleases: [MediaItem] = []
        for (artist, video) in monthUploads {
            guard let id = artist.browseId, let p = pageById[id] else { continue }
            let releases = Self.similarParts(p.sections, wanted).releases.filter { Self.isRecent($0) }
            if let r = releases.first(where: { Self.sameTitle($0.title, video.item.title) }) { monthReleases.append(r) }
        }
        monthReleases = Self.unique(monthReleases, limit: 30)
        // Already among the notifications (as the video): not again under "Yeni çıkanlar".
        monthReleases.removeAll { r in noteItems.contains { Self.sameTitle(r.title, $0.title) } }
        let savedSongs = (await savedTask).flatMap { $0.sections.flatMap(\.items) }.filter { $0.isTrack && wanted($0) }
        let stations = hybrid.map { Self.station($0) }

        // Long sets: in the kinds of music you listen to most, or naming your artists.
        let setSources = await setsTask
        let names = Self.listenedNames(profile, followed, quickItems + recentSongs)
            .union(genres.map { QueueCurator.normalize($0) })
        let sets = Self.rank(
            (setSources.related + (setSources.searched + (feed?.items ?? [])).filter { Self.mentions($0, names) })
                .filter { !$0.mix && $0.seconds >= QueueCurator.setSeconds && wanted($0.item) },
            profile).map(\.item)

        var page: [Shelf] = []

        // 1. Tiles: shortcuts, so what they show may appear again below.
        var tilePool: [MediaItem] = Array(ytMixes.prefix(4))
        tilePool.append(contentsOf: topMixes.prefix(2))
        tilePool.append(contentsOf: recentSongs)
        tilePool.append(contentsOf: ytMixes.dropFirst(4))
        tilePool.append(contentsOf: seedMixes)
        tilePool.append(contentsOf: quickItems)
        let tiles = Self.unique(tilePool, limit: 8)
        if tiles.count >= 4 {
            page.append(Shelf(id: "home-tiles", title: Self.greeting(), strapline: nil, layout: "shortcuts",
                              items: tiles, more: nil, continuation: nil, top: nil))
        }

        // Notifications: right under the tiles, newest first.
        if let s = shelf("notifications", "Senin için bildirimler", nil, noteItems, limit: 20, minimum: 2) { page.append(s) }

        // 2. One pick at a time + stations.
        let picks = take(Array(releases.prefix(3)) + Array(editorial.prefix(2)), limit: 5)
        if !picks.isEmpty || stations.count >= 4 {
            page.append(Shelf(id: "home-picks", title: "Tavsiye edilen istasyonlar",
                              strapline: nil, layout: "picks",
                              items: picks + (stations.count >= 4 ? stations : []), more: nil, continuation: nil, top: nil))
        }
        // 3.
        if let s = shelf("recent", "Son çalınanlar", nil, recentSongs, limit: 20) { page.append(s) }
        // 4. Quick picks: a fresh random mix, every source represented, two songs per artist at most.
        let favourites = (profile.allTime(limit: 30) + profile.favourites(limit: 30)).map { Self.item($0) }.filter(wanted)
        let picksList = Self.randomMix([
            (quickItems.filter(wanted), 6), (savedSongs, 6), (recentSongs, 4), (trendSongs, 4), (favourites, 4),
        ], perArtist: 2, limit: 24)
        if picksList.count >= Self.minimumSongs {
            page.append(Shelf(id: quick?.id ?? "home-quick", title: quick?.title ?? "Hızlı seçimler",
                              strapline: quick?.strapline, layout: "list", items: picksList,
                              more: nil, continuation: nil, top: nil))
        }
        // 5.
        if let s = shelf("compiled", "\(Self.ownerName(engine)) için derlendi", nil, ytMixes + seedMixes, limit: 24) { page.append(s) }
        // 6.
        if let first = hybrid.first, let p = artistPages.first,
           let s = Self.similarShelf(first, p.sections, wanted, shelf) { page.append(s) }
        // 7.
        if let s = shelf("topmixes", "En çok dinlediğin mix'ler", nil, topMixes, limit: 12) { page.append(s) }
        // 8.
        if let s = shelf("continue", "Kaldığın yerden devam et", nil,
                         profile.unfinished(limit: 20).map { Self.item($0) }.filter(wanted), limit: 20) { page.append(s) }
        // 9.
        if let s = shelf("editorial", "YouTube Music'ten popüler listeler", nil, editorial, limit: 30) { page.append(s) }
        // 10.
        if hybrid.count > 1, artistPages.count > 1,
           let s = Self.similarShelf(hybrid[1], artistPages[1].sections, wanted, shelf) { page.append(s) }
        // 11.–13.
        // A popular new release (here or worldwide) after every four of yours, at least two,
        // and enough of them for a full row when your artists were quiet.
        let popularNew = Self.unique(Self.interleave(releases, worldReleases), limit: 40)
            .filter { !used.contains($0.recommendationKey) }
        var newRow: [MediaItem] = []
        var extra = 0
        for (i, r) in monthReleases.enumerated() {
            newRow.append(r)
            if (i + 1) % 4 == 0, extra < popularNew.count { newRow.append(popularNew[extra]); extra += 1 }
        }
        while extra < popularNew.count, extra < 2 || newRow.count < 8 {
            newRow.append(popularNew[extra])
            extra += 1
        }
        if let s = shelf("releases", "Yeni çıkanlar", nil, newRow, limit: 30) { page.append(s) }
        if let s = shelf("sets", "Uzun setler", nil, sets, limit: 30) { page.append(s) }
        if let s = shelf("artists", "Favori sanatçıların", nil, followed, limit: 30) { page.append(s) }
        // 14. Living cards.
        if let s = Self.spotlight(Array(hybrid.prefix(6)), artistPages, wanted) { page.append(s) }
        // 15.
        if let s = shelf("again", "Tekrar dinle", nil,
                         profile.favourites(limit: 40).shuffled().map { Self.item($0) }.filter(wanted),
                         limit: 16, minimum: Self.minimumSongs, layout: "list") { page.append(s) }
        page += ytRows

        guard !page.isEmpty else { throw LoadError() }
        return BrowsePage(header: nil, chips: music.chips, sections: page, continuation: nil)
    }

    // MARK: - Artist rows and cards

    /// "Ayşe Y." from the account name (as Spotify writes it), or "Senin".
    private static func ownerName(_ engine: YTMusic) -> String {
        let parts = (engine.account?.name ?? "").split(separator: " ").map(String.init)
        guard let first = parts.first else { return "Senin" }
        if parts.count > 1, let initial = parts.last?.first { return "\(first) \(initial)." }
        return first
    }

    /// An artist's radio card.
    private static func station(_ artist: MediaItem, title: String? = nil, subtitle: String? = nil) -> MediaItem {
        MediaItem(uid: "station-\(artist.recommendationKey)", kind: "artistradio", title: title ?? artist.title,
                  subtitle: subtitle ?? "\(artist.title) ve benzer sanatçılar", thumbnail: artist.thumbnail,
                  videoId: nil, browseId: artist.browseId, params: nil, playlistId: nil, artists: [],
                  album: nil, duration: nil, explicit: false, play: nil, wide: false, color: nil)
    }

    /// From an artist page: similar artists, playlists it's on, its albums and singles.
    private static func similarParts(_ sections: [Shelf], _ wanted: (MediaItem) -> Bool)
        -> (artists: [MediaItem], playlists: [MediaItem], releases: [MediaItem]) {
        let items = sections.flatMap(\.items).filter(wanted)
        return (items.filter(\.isArtist), items.filter { $0.kind == "playlist" }, items.filter { $0.kind == "album" })
    }

    /// Other artists the artist's fans listen to (never the artist's own releases).
    private static func similarShelf(_ artist: MediaItem, _ sections: [Shelf], _ wanted: (MediaItem) -> Bool,
                                     _ shelf: (String, String, String?, [MediaItem], Int, Int, String, MediaItem?) -> Shelf?) -> Shelf? {
        let own = ListeningProfile.key(artist.title)
        let items = similarParts(sections, wanted).artists.filter {
            $0.browseId != artist.browseId && ListeningProfile.key($0.title) != own
        }
        return shelf("similar-\(artist.recommendationKey)", "\(artist.title) ile benzer diğer müzikler", nil,
                     items, 24, minimumCards, "similar", artist)
    }

    /// Living cards, one artist each (no artist twice), on the artist's wide banner: their
    /// radio, or a release for their fans. An even count, for two columns.
    private static func spotlight(_ artists: [MediaItem], _ pages: [BrowsePage], _ wanted: (MediaItem) -> Bool) -> Shelf? {
        var cards: [(String, MediaItem)] = []
        for (i, artist) in artists.enumerated() where i < pages.count {
            let page = pages[i]
            let banner = page.header?.style == "artist" ? page.header?.thumbnail : nil
            let parts = similarParts(page.sections, wanted)
            if i % 2 == 1, var release = parts.releases.first ?? parts.playlists.first {
                release.banner = banner
                cards.append(("\(artist.title) hayranları için", release))
            } else {
                var radio = station(artist, title: "\(artist.title) Radyosu",
                                    subtitle: "\(artist.title) ve benzer sanatçılarla kesintisiz müzik")
                radio.banner = banner
                cards.append(("\(artist.title) ile benzer diğer müzikler", radio))
            }
        }
        let count = cards.count - cards.count % 2
        guard count >= 2 else { return nil }
        let chosen = Array(cards.prefix(count))
        return Shelf(id: "home-spotlight", title: "", strapline: chosen.map { $0.0 }.joined(separator: "\n"),
                     layout: "spotlight", items: chosen.map { $0.1 }, more: nil, continuation: nil, top: nil)
    }

    // MARK: - Sources

    /// Pages fetched side by side, in the order asked (a failed one comes back empty).
    // MARK: Notifications

    static let notificationDays = 14

    /// "Senin için bildirimler": the regular uploads (not Shorts, Mixes or clips under a
    /// minute) of the last two weeks from the music channels you follow, newest first, from
    /// YouTube's subscriptions feed. The bell itself carries almost only Shorts, so it only
    /// marks the uploads it announced and you haven't read.
    ///
    /// A channel counts as music when you follow it as an artist on YouTube Music, when you
    /// listened to it in the app, or when its video is in YouTube's Music category (looked
    /// up once per channel, newest uploads first, and kept for the session).
    private static func notificationItems(_ engine: YTMusic, _ notes: [YouTubeNotification], uploads: [YouTubeVideo],
                                          artistIds: Set<String>, heardIds: Set<String>) async -> [MediaItem] {
        var seen = Set<String>()
        let recent = uploads.filter { u in
            guard !u.mix, u.seconds >= 60, let age = u.ageDays, age <= Double(notificationDays),
                  u.channelId != nil, let v = u.item.videoId else { return false }
            return seen.insert(v).inserted
        }
        guard !recent.isEmpty else {
            EngineLog.write("Bildirimler: abonelik akışında (\(uploads.count) video) son \(notificationDays) günden normal yükleme yok")
            return []
        }

        // One video of each channel not decided yet.
        func decided(_ channel: String) -> Bool {
            artistIds.contains(channel) || heardIds.contains(channel) || engine.musicChannels[channel] != nil
        }
        var channelOfLookup: [String: String] = [:]
        for u in recent {
            guard let c = u.channelId, let v = u.item.videoId, !decided(c),
                  !channelOfLookup.values.contains(c) else { continue }
            channelOfLookup[v] = c
        }
        let lookups = Array(channelOfLookup.keys.sorted { a, b in
            (recent.firstIndex { $0.item.videoId == a } ?? 0) < (recent.firstIndex { $0.item.videoId == b } ?? 0)
        }.prefix(40))
        let infos = await videoInfos(engine, lookups)
        var answered = 0
        for (v, info) in infos {
            guard let c = channelOfLookup[v], let category = info.category else { continue }
            answered += 1
            if engine.musicChannels[c] == nil {
                engine.musicChannels[c] = ["music", "müzik"].contains(category.lowercased(with: Locale(identifier: "tr_TR")))
            }
        }

        let unread = Set(notes.filter { !$0.read }.compactMap(\.videoId))
        var notMusic = 0
        let items = recent.compactMap { u -> MediaItem? in
            guard let c = u.channelId, let v = u.item.videoId else { return nil }
            guard artistIds.contains(c) || heardIds.contains(c) || engine.musicChannels[c] == true else {
                notMusic += 1
                return nil
            }
            var item = MediaItem(uid: "note-\(v)", kind: "video", title: u.item.title,
                                 subtitle: [u.channel, Self.uploadAge(u.ageDays)].filter { !$0.isEmpty }.joined(separator: " • "),
                                 thumbnail: u.item.thumbnail, videoId: v, browseId: nil, params: nil, playlistId: nil,
                                 artists: [], album: nil, duration: u.item.duration, explicit: false, play: u.item.play,
                                 wide: true, color: nil)
            item.avatar = u.avatar
            item.unread = unread.contains(v) ? true : nil
            return item
        }
        EngineLog.write("Bildirimler: \(recent.count) yükleme (son \(notificationDays) gün), \(lookups.count) kanal sorgusu "
                        + "(\(answered) yanıt), müzik olmayan \(notMusic), rafta \(items.count); "
                        + "\(artistIds.count) sanatçı, \(heardIds.count) dinlenen kanal")
        return items
    }

    /// "Bugün", "Dün", "3 gün önce".
    private static func uploadAge(_ days: Double?) -> String {
        guard let days else { return "" }
        switch Int(days) {
        case ..<1: return "Bugün"
        case 1: return "Dün"
        case let n: return "\(n) gün önce"
        }
    }

    private static func videoInfos(_ engine: YTMusic, _ ids: [String]) async -> [String: YouTubeVideoInfo] {
        await withTaskGroup(of: (String, YouTubeVideoInfo?).self) { group in
            for id in ids { group.addTask { (id, await engine.youtubeVideoInfo(id)) } }
            var out: [String: YouTubeVideoInfo] = [:]
            for await (id, info) in group { if let info { out[id] = info } }
            return out
        }
    }

    private static func loadNotifications(_ engine: YTMusic) async -> NotificationFeed? {
        do {
            return try await engine.youtubeNotifications(days: notificationDays)
        } catch {
            EngineLog.write("Bildirimler alınamadı: \(error.localizedDescription)")
            return nil
        }
    }

    private static func pages(_ engine: YTMusic, _ targets: [(String, String?)]) async -> [BrowsePage] {
        let empty = BrowsePage(header: nil, chips: [], sections: [], continuation: nil)
        return await withTaskGroup(of: (Int, BrowsePage).self) { group in
            for (i, t) in targets.enumerated() where !t.0.isEmpty {
                group.addTask { (i, (try? await engine.browse(t.0, params: t.1)) ?? empty) }
            }
            var out = [BrowsePage](repeating: empty, count: targets.count)
            for await (i, p) in group { out[i] = p }
            return out
        }
    }

    /// Sets similar to the ones you finished (`related`), and searches (genres you listen to,
    /// your artists) for long videos (`searched`, still checked against what you listen to).
    private static func longSets(_ engine: YTMusic, seeds: [String], queries: [String])
        async -> (related: [YouTubeVideo], searched: [YouTubeVideo]) {
        await withTaskGroup(of: (Int, [YouTubeVideo]).self) { group in
            for (i, id) in seeds.enumerated() {
                group.addTask { (i, (try? await engine.youtubeRelated(id))?.items ?? []) }
            }
            for (j, query) in queries.enumerated() {
                group.addTask { (10 + j, (try? await engine.youtubeSearch(query, long: true))?.items ?? []) }
            }
            var parts: [(Int, [YouTubeVideo])] = []
            for await part in group { parts.append(part) }
            parts.sort { $0.0 < $1.0 }
            return (parts.filter { $0.0 < 10 }.flatMap { $0.1 }, parts.filter { $0.0 >= 10 }.flatMap { $0.1 })
        }
    }

    /// Kinds of music, most specific first (normalised, as in titles).
    private static let genreWords = [
        "melodic techno", "melodic house", "afro house", "organic house", "deep house", "tech house",
        "progressive house", "indie dance", "minimal techno", "hard techno", "peak time techno",
        "nu disco", "drum and bass", "psytrance", "lo fi", "lofi", "downtempo", "chillout", "chill house",
        "techno", "house", "trance", "dubstep", "ambient", "jazz", "soul", "funk", "disco", "hip hop",
        "rap", "trap", "turkce pop", "arabesk", "pop", "rock", "metal", "edm", "chill",
    ]

    /// The kinds of music you listen to most, from the titles of your playlists and of what
    /// you played (sets count most: their titles usually name the genre).
    private static func topGenres(_ profile: ListeningProfile, playlists: [String], limit: Int) -> [String] {
        var counts: [String: Double] = [:]
        func count(_ text: String, _ weight: Double) {
            var hay = " " + QueueCurator.normalize(text) + " "
            for g in genreWords where hay.contains(" \(g) ") {
                counts[g, default: 0] += weight
                hay = hay.replacingOccurrences(of: " \(g) ", with: " ")
            }
        }
        for title in playlists { count(title, 2) }
        for t in profile.tracks.values where !t.disliked && t.score > 0 {
            count(t.title, t.isSet ? 3 : 1)
        }
        return counts.filter { $0.value >= 1 }.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }

    /// Who to search sets for: the most listened artists, or the first ones you follow.
    private static func setSearchArtists(_ profile: ListeningProfile, _ followed: [MediaItem]) -> [String] {
        var names = profile.topArtists(limit: 3).map { $0.name }
        for a in followed where names.count < 3 && !names.contains(a.title) { names.append(a.title) }
        return names
    }

    /// Artist names (normalised) from your history, the artists you follow and your picks.
    private static func listenedNames(_ profile: ListeningProfile, _ followed: [MediaItem], _ songs: [MediaItem]) -> Set<String> {
        var names = Set(profile.topListened(limit: 60).map { QueueCurator.normalize($0.name) })
        names.formUnion(followed.map { QueueCurator.normalize($0.title) })
        for s in songs { names.formUnion(s.artists.map { QueueCurator.normalize($0.name) }) }
        return names.filter { $0.count >= 3 }
    }

    /// Whether a YouTube video names one of these artists in its title or channel.
    private static func mentions(_ v: YouTubeVideo, _ names: Set<String>) -> Bool {
        let hay = " " + QueueCurator.normalize(v.item.title + " " + v.channel) + " "
        return names.contains { hay.contains(" \($0) ") }
    }

    /// YouTube Music's editorial ("RDCLAK…") playlists, local and worldwide in turn: the
    /// explore, charts and mood / genre pages here, and the explore and mood / genre pages as
/// shown in the US.
    private static func editorialPlaylists(_ engine: YTMusic) async -> [MediaItem] {
        async let local = editorialFrom(engine, region: nil)
        async let world = editorialFrom(engine, region: "US")
        let (l, w) = await (local, world)
        return unique(interleave(l, w), limit: 80)
    }

    private static func editorialFrom(_ engine: YTMusic, region: String?) async -> [MediaItem] {
        async let explore = try? engine.browse("FEmusic_explore", params: nil, region: region)
        // Charts only here: worldwide ones come from the global charts fetched for the page.
        async let charts = Self.localCharts(engine, region)
        async let moods = try? engine.browse("FEmusic_moods_and_genres", params: nil, region: region)
        let categories = Array(((await moods)?.sections ?? []).flatMap { Array($0.items.prefix(2)) }
            .compactMap { c -> (String, String?)? in c.browseId.map { ($0, c.params) } }
            .prefix(4))
        let categoryItems = await withTaskGroup(of: (Int, [MediaItem]).self) { group in
            for (i, c) in categories.enumerated() {
                group.addTask {
                    (i, ((try? await engine.browse(c.0, params: c.1, region: region))?.sections ?? []).flatMap(\.items))
                }
            }
            var out: [(Int, [MediaItem])] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
        var lists: [[MediaItem]] = [
            ((await explore)?.sections ?? []).flatMap(\.items),
            ((await charts)?.sections ?? []).flatMap(\.items),
        ]
        lists += categoryItems
        let official = lists.map { $0.filter { isOfficial($0) } }
        // Round robin over the sources, so no single page fills the row.
        var out: [MediaItem] = []
        for i in 0..<(official.map(\.count).max() ?? 0) {
            for list in official where i < list.count { out.append(list[i]) }
        }
        return unique(out, limit: 60)
    }

    private static func localCharts(_ engine: YTMusic, _ region: String?) async -> BrowsePage? {
        guard region == nil else { return nil }
        return try? await engine.browse("FEmusic_charts", params: nil)
    }

    // MARK: - Mixing

    private static func interleave(_ a: [MediaItem], _ b: [MediaItem]) -> [MediaItem] {
        var out: [MediaItem] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    /// Each item once, in order.
    private static func unique(_ items: [MediaItem], limit: Int) -> [MediaItem] {
        var keys = Set<String>()
        var out: [MediaItem] = []
        for it in items where out.count < limit {
            if keys.insert(it.recommendationKey).inserted { out.append(it) }
        }
        return out
    }

    /// Each item once, at most `perArtist` per artist.
    private static func varied(_ items: [MediaItem], perArtist: Int, limit: Int) -> [MediaItem] {
        var keys = Set<String>()
        var counts: [String: Int] = [:]
        var out: [MediaItem] = []
        for it in items where out.count < limit {
            guard keys.insert(it.recommendationKey).inserted else { continue }
            let artist = ListeningProfile.key(it.artists.first?.name ?? it.subtitle.components(separatedBy: " • ").first ?? "")
            guard counts[artist, default: 0] < perArtist else { continue }
            counts[artist, default: 0] += 1
            out.append(it)
        }
        return out
    }

    /// A random mix: a share from each source (shuffled), topped up from what's left, then
    /// shuffled again so the sources are spread out.
    private static func randomMix(_ sources: [([MediaItem], Int)], perArtist: Int, limit: Int) -> [MediaItem] {
        var first: [MediaItem] = []
        var rest: [MediaItem] = []
        for (items, share) in sources {
            let shuffled = items.shuffled()
            first += shuffled.prefix(share)
            rest += shuffled.dropFirst(share)
        }
        return varied(first + rest.shuffled(), perArtist: perArtist, limit: limit).shuffled()
    }

    // MARK: - Release dates

    /// Whether a YouTube upload ("CamelPhat - Loving Me (Official Visualiser)") is this
    /// release ("Loving Me").
    static func sameTitle(_ release: String, _ upload: String) -> Bool {
        func core(_ t: String) -> String {
            var t = QueueCurator.stripDecorations(t)
            if let r = t.range(of: " - ") { t = String(t[r.upperBound...]) }
            return QueueCurator.normalize(t)
        }
        let a = core(release), b = core(upload)
        guard a.count >= 2, b.count >= 2 else { return false }
        return a == b || (a.count >= 4 && b.contains(a)) || (b.count >= 4 && a.contains(b))
    }

    /// The year shown with a release ("Single • 2024"), if any.
    static func year(_ item: MediaItem) -> Int? {
        item.subtitle.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { $0.count == 4 }
            .compactMap { Int($0) }
            .first { (1950...2100).contains($0) }
    }

    /// Out this year (or last year, in January and February).
    static func isRecent(_ item: MediaItem, now: Date = Date()) -> Bool {
        guard let y = year(item) else { return false }
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: now)
        return y >= thisYear || (y == thisYear - 1 && cal.component(.month, from: now) <= 2)
    }

    /// Shows a year before last year.
    static func isOld(_ item: MediaItem, now: Date = Date()) -> Bool {
        guard let y = year(item) else { return false }
        return y < Calendar.current.component(.year, from: now) - 1
    }

    // MARK: - Page bits

    /// "Günaydın", "İyi günler"… as Spotify greets by the time of day.
    static func greeting(_ date: Date = Date()) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return "Günaydın"
        case 12..<18: return "İyi günler"
        case 18..<23: return "İyi akşamlar"
        default: return "İyi geceler"
        }
    }

    /// How much a release is "yours": artists you listen to, and artists you follow.
    private static func releaseScore(_ item: MediaItem, _ profile: ListeningProfile, _ followed: [MediaItem]) -> Double {
        var names = item.artists.map(\.name)
        if names.isEmpty {
            names = item.subtitle.components(separatedBy: " • ").first?
                .components(separatedBy: CharacterSet(charactersIn: ",&")) ?? []
        }
        let keys = Set(followed.map { ListeningProfile.key($0.title) })
        return names.map { name -> Double in
            let n = name.trimmingCharacters(in: .whitespaces)
            return profile.affinity(n) + (keys.contains(ListeningProfile.key(n)) ? 1 : 0)
        }.max() ?? 0
    }

    // MARK: - Which rows and items

    static func titled(_ s: Shelf, _ words: [String]) -> Bool {
        let title = s.title.lowercased(with: Locale(identifier: "tr_TR"))
        return words.contains { title.contains($0) }
    }

    /// YouTube Music's "Yeniden dinleyin" / "Listen again".
    private static func isListenAgain(_ s: Shelf) -> Bool { titled(s, ["yeniden dinle", "listen again"]) }

    /// "Topluluktan" / "From the community".
    private static func isCommunity(_ s: Shelf) -> Bool { titled(s, ["topluluk", "community"]) }

    /// A playlist made by some other YouTube user (shown with its view count); those belong
    /// in search results only.
    static func isCommunityList(_ item: MediaItem) -> Bool {
        guard item.kind == "playlist", !isOfficial(item) else { return false }
        let sub = item.subtitle.lowercased(with: Locale(identifier: "tr_TR"))
        return sub.contains("görüntüleme") || sub.contains(" views") || sub.contains("izlenme")
    }

    /// YouTube Music's mixes for this account: liked songs, supermixes, discovery mixes.
    private static func isPersonalMix(_ item: MediaItem) -> Bool {
        let id = item.playlistId ?? item.browseId ?? ""
        return id.contains("RDTMAK") || id == "LM" || id == "VLLM"
    }

    /// YouTube Music's editorial playlists ("RDCLAK…").
    static func isOfficial(_ item: MediaItem) -> Bool {
        (item.playlistId ?? item.browseId ?? "").contains("RDCLAK")
    }

    // MARK: - Category pages

    /// Rows that are about the listener, not the category.
    private static let personalTitles = [
        "yeniden dinle", "tekrar dinle", "listen again", "sizin için", "senin için", "for you",
        "derlenen", "topluluk", "community",
    ]

    /// A mood / genre page (Rahatlama, Uyku…): only what fits the category — YouTube
    /// Music's official playlists and songs — without the personal rows (Yeniden dinleyin,
    /// Sizin için derlenenler) and community playlists.
    static func categoryPage(_ page: BrowsePage) -> BrowsePage {
        var out = page
        out.sections = page.sections.compactMap { s -> Shelf? in
            if s.layout == "nav" { return s }
            if titled(s, personalTitles) { return nil }
            var s = s
            s.items = s.items.filter { Self.isOfficial($0) || $0.kind == "song" }
            return s.items.count >= 3 ? s : nil
        }
        if out.sections.contains(where: { $0.layout != "nav" }) { return out }
        // Nothing official there: at least leave out the personal rows.
        out.sections = page.sections.filter { !titled($0, personalTitles) }
        return out
    }

    // MARK: - Helpers

    /// YouTube's order, nudged by how much the history likes each channel or artist.
    private static func rank(_ list: [YouTubeVideo], _ profile: ListeningProfile) -> [YouTubeVideo] {
        let n = Double(max(list.count, 1))
        return list.enumerated()
            .map { (i, v) -> (YouTubeVideo, Double) in
                (v, (n - Double(i)) / n + 0.5 * min(2, max(-2, profile.affinity(v.channel))))
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    private static func item(_ t: ListeningProfile.Track) -> MediaItem {
        let song = t.type == QueueCurator.song
        let artists = zip(t.artists, t.artistIds).map { ArtistRef(name: $0.0, id: $0.1) }
        return MediaItem(uid: "home-again-\(t.videoId)", kind: song ? "song" : "video", title: t.title,
                         subtitle: t.artists.joined(separator: ", "),
                         thumbnail: t.cover ?? "https://i.ytimg.com/vi/\(t.videoId)/hqdefault.jpg",
                         videoId: t.videoId, browseId: nil, params: nil, playlistId: nil, artists: artists,
                         album: nil, duration: nil, explicit: false, play: endpoint(t.videoId, nil),
                         wide: !song, color: nil)
    }

    /// A radio started from the artist's best-liked song.
    private static func mix(name: String, seed: ListeningProfile.Track) -> MediaItem {
        mix(name: name, videoId: seed.videoId, cover: seed.cover)
    }

    /// A radio around an artist, started from one of their songs.
    private static func mix(name: String, videoId: String, cover: String?) -> MediaItem {
        MediaItem(uid: "home-mix-\(videoId)", kind: "mix", title: "\(name) Mix",
                  subtitle: "\(name) ve benzerleri",
                  thumbnail: cover ?? "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg",
                  videoId: nil, browseId: nil, params: nil, playlistId: "RDAMVM" + videoId, artists: [],
                  album: nil, duration: nil, explicit: false, play: endpoint(videoId, "RDAMVM" + videoId),
                  wide: false, color: nil)
    }

    private static func endpoint(_ videoId: String, _ playlistId: String?) -> String {
        var w: [String: String] = ["videoId": videoId]
        if let playlistId { w["playlistId"] = playlistId }
        let data = (try? JSONSerialization.data(withJSONObject: ["watchEndpoint": w])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
