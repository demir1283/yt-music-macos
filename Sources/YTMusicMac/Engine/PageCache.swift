import Foundation

/// Pages kept in memory while the app runs, so going back to a page shows it at once
/// instead of fetching it again. Nothing is written to disk: quitting the app empties it,
/// and so does signing in or out.
///
/// Each kind of page has a lifetime. A page past it still shows at once; it is fetched
/// again behind it and the rows that changed fade in. Nothing is fetched while the app
/// is in the background: a page is checked when it shows, and while it is on screen.
@MainActor
final class PageCache {
    static let shared = PageCache()

    enum Lifetime {
        static let home: TimeInterval = 15 * 60
        static let page: TimeInterval = 15 * 60
        /// The account's own lists: playlists it owns, liked songs, history.
        static let personal: TimeInterval = 5 * 60
        static let search: TimeInterval = 5 * 60
    }

    /// The home page is also rebuilt once this many songs have been heard since it was built.
    static let homeListens = 5

    private struct Entry {
        let value: Any
        var expires: Date
        /// Songs heard (YTMusic.listenCount) when it was stored.
        let listens: Int
    }

    private var entries: [String: Entry] = [:]
    /// Least recently stored first.
    private var order: [String] = []
    private let limit = 60
    private let searchLimit = 10

    private init() {}

    // MARK: Keys

    static func home(_ chip: FilterChip?) -> String { "home|" + (chip?.id ?? "") }
    static func page(_ target: BrowseTarget) -> String { "page|\(target.browseId)|\(target.params ?? "")" }
    static func search(_ query: String) -> String { "search|" + query.lowercased() }

    static func lifetime(for target: BrowseTarget, _ page: BrowsePage) -> TimeInterval {
        let id = target.browseId
        if id == "VLLM" || id == "FEmusic_history" || id.hasPrefix("FEmusic_library") || id.hasPrefix("FEmusic_liked")
            || page.header?.editable == true {
            return Lifetime.personal
        }
        return Lifetime.page
    }

    // MARK: Reading

    func value<T>(_ key: String, as type: T.Type = T.self) -> T? {
        entries[key]?.value as? T
    }

    /// Kept and still current: no need to fetch it again.
    func isFresh(_ key: String) -> Bool {
        guard let e = entries[key], Date() < e.expires else { return false }
        if key.hasPrefix("home|") {
            return YTMusic.shared.listenCount - e.listens < Self.homeListens
        }
        return true
    }

    /// When the page stops being current (nil: not kept).
    func expiry(_ key: String) -> Date? {
        entries[key]?.expires
    }

    // MARK: Writing

    func store(_ value: Any, for key: String, lifetime: TimeInterval) {
        entries[key] = Entry(value: value, expires: Date().addingTimeInterval(lifetime),
                             listens: YTMusic.shared.listenCount)
        order.removeAll { $0 == key }
        order.append(key)
        let searches = order.filter { $0.hasPrefix("search|") }
        if searches.count > searchLimit { drop(Array(searches.prefix(searches.count - searchLimit))) }
        if order.count > limit { drop(Array(order.prefix(order.count - limit))) }
    }

    /// Pages to fetch again the next time they show (meanwhile they still show at once).
    func markStale(where match: (String) -> Bool) {
        for key in Array(entries.keys) where match(key) {
            entries[key]?.expires = .distantPast
        }
    }

    /// Pages that would show something no longer true (an artist's page right after
    /// subscribing): gone, so they load anew.
    func forget(where match: (String) -> Bool) {
        drop(entries.keys.filter(match))
    }

    func clear() {
        entries = [:]
        order = []
    }

    private func drop(_ keys: [String]) {
        let gone = Set(keys)
        for key in gone { entries[key] = nil }
        order.removeAll { gone.contains($0) }
    }
}

extension Shelf {
    /// Changes when the row's items change: a row refreshed with other items fades over,
    /// an unchanged one stays as it is.
    var contentKey: String {
        var h = Hasher()
        h.combine(id)
        h.combine(title)
        for item in items { h.combine(item.id) }
        return "\(id)#\(h.finalize())"
    }
}

extension BrowsePage {
    /// Same rows with the same items (and the same header): nothing to redraw.
    func sameContent(as other: BrowsePage) -> Bool {
        sections.map(\.contentKey) == other.sections.map(\.contentKey)
            && header?.title == other.header?.title
            && header?.thumbnail == other.header?.thumbnail
            && header?.subtitle == other.header?.subtitle
            && header?.subscribed == other.header?.subscribed
    }
}
