import SwiftUI

/// Renders any YouTube Music shelf in the matching style.
struct ShelfView: View {
    let section: Shelf
    var trackLimit = 6
    /// Rows to wrap a card row into (instead of one row to scroll), when the page has
    /// little else to show (ShelfGrid.rows).
    var gridRows: Int? = nil
    @Environment(AppModel.self) private var app

    /// Without what the user said not to recommend (it leaves at once, the rest closes up).
    private var visible: Shelf {
        let hidden = app.hiddenKeys
        guard !hidden.isEmpty, section.items.contains(where: { hidden.contains($0.recommendationKey) }) else { return section }
        var s = section
        s.items.removeAll { hidden.contains($0.recommendationKey) }
        return s
    }

    var body: some View {
        let section = visible
        Group {
            switch section.layout {
            case "shortcuts":
                ShortcutGrid(section: section)
            case "picks":
                PicksRow(section: section)
            case "similar":
                SimilarRow(section: section)
            case "spotlight":
                SpotlightGrid(section: section)
            case "nav":
                CategoryGrid(section: section)
            case "top":
                EmptyView()
            case "list":
                if !section.hasTracks {
                    CardCarousel(section: section)
                } else if section.items.count > 8 {
                    SongGrid(section: section)
                } else {
                    TrackListSection(section: section, limit: trackLimit)
                }
            default:
                if let rows = gridRows {
                    ShelfGrid(section: section, rows: rows)
                } else {
                    CardCarousel(section: section)
                }
            }
        }
        .fadeIn()
    }
}

/// A card row wrapped into a grid: on a page with little else (an artist with only long
/// videos, say) one row to scroll sideways would leave the screen empty.
struct ShelfGrid: View {
    let section: Shelf
    let rows: Int
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            ShelfHeader(section: section)
            PagedCardGrid(items: section.items, startRows: rows, moreLink: section.more,
                          title: section.title, continuation: section.continuation)
        }
    }

    /// Which card rows of a page to wrap, and into how many rows each: only when the page
    /// is thin — four rows in all at most, and at most two card rows with six cards or more —
    /// so one row to scroll would leave most of the screen empty. A lone big row gets three
    /// rows, two big rows two each. Videos count as cards here (they have a videoId, but
    /// they are a row of cards all the same).
    nonisolated static func rows(for sections: [Shelf]) -> [String: Int] {
        let big = sections.filter { s in
            s.items.count >= 6
                && !["shortcuts", "picks", "similar", "spotlight", "nav", "top", "list"].contains(s.layout)
        }
        guard sections.count <= 4, !big.isEmpty, big.count <= 2 else { return [:] }
        let rows = big.count == 1 ? 3 : 2
        return Dictionary(uniqueKeysWithValues: big.map { ($0.id, rows) })
    }
}

/// The artist whose popular songs a shelf lists: the list its "see all" opens gets a made
/// cover with the artist's name.
private struct PageArtistKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var pageArtist: String? {
        get { self[PageArtistKey.self] }
        set { self[PageArtistKey.self] = newValue }
    }
}

extension View {
    /// A page row that fades over when its content (`key`) changes inside an animation,
    /// while keeping `id` as its identity in the lazy stack.
    func fadeSwap(_ key: String, id: String) -> some View {
        ZStack(alignment: .topLeading) {
            self.id(key).transition(.opacity)
        }
        .id(id)
    }
}

private struct ShelfHeader: View {
    let section: Shelf
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @Environment(\.pageArtist) private var pageArtist

    var body: some View {
        if !section.title.isEmpty {
            SectionTitle(title: section.title, subtitle: section.strapline,
                         action: section.more.map { more in { app.openMore(more, title: section.title, artist: pageArtist) } })
                .padding(.horizontal, d.pad)
        }
    }
}

// MARK: - Card carousel

struct CardCarousel: View {
    let section: Shelf
    @ViewState var hover = false
    @ViewState var position: String? = nil
    /// Width the row has on screen: the arrows show only when the cards don't all fit.
    @ViewState var viewport: CGFloat = 0
    @Environment(\.density) private var d
    @Environment(AppModel.self) private var app

    /// Without what the user said not to recommend: it leaves at once, wherever the row is.
    private var items: [MediaItem] {
        let hidden = app.hiddenKeys
        return hidden.isEmpty ? section.items : section.items.filter { !hidden.contains($0.recommendationKey) }
    }

    private var index: Int {
        guard let p = position, let i = items.firstIndex(where: { $0.id == p }) else { return 0 }
        return i
    }

    var body: some View {
        // Mixed shelves (square covers + 16:9 videos) share one image height so every
        // card's title sits on the same line and nothing gets clipped.
        let mixed = items.contains { $0.wide }
        let imageH: CGFloat = mixed ? d.cardMixed : d.card
        let content = items.reduce(CGFloat(0)) { $0 + ($1.wide ? imageH * 16 / 9 : imageH) }
            + d.cardGap * CGFloat(max(items.count - 1, 0)) + d.pad * 2
        let overflows = content > viewport + 1
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            ShelfHeader(section: section)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: d.cardGap) {
                    ForEach(items) { item in
                        ItemCard(item: item, width: item.wide ? imageH * 16 / 9 : imageH, imageHeight: imageH)
                            .id(item.id)
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, d.pad, for: .scrollContent)
            .scrollPosition(id: $position, anchor: .leading)
            .frame(height: imageH + d.v(44, 50))
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { viewport = g.size.width }
                    .onChange(of: g.size.width) { _, w in viewport = w }
            })
            .overlay(alignment: .leading) {
                if hover && overflows && index > 0 {
                    CarouselArrow(system: "chevron.left") { move(-3) }
                        .padding(.leading, 10)
                }
            }
            .overlay(alignment: .trailing) {
                if hover && overflows && index < items.count - 3 {
                    CarouselArrow(system: "chevron.right") { move(3) }
                        .padding(.trailing, 10)
                }
            }
        }
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        let target = max(0, min(items.count - 1, index + delta))
        withAnimation(.easeInOut(duration: 0.4)) {
            position = items[target].id
        }
    }
}

struct CarouselArrow: View {
    let system: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 30)
                .glassCircle()
        }
        .buttonStyle(PressScaleStyle())
        .offset(y: -22)
        .transition(.opacity)
    }
}

/// Square artwork card with title + subtitle (Apple Music style).
struct ItemCard: View {
    let item: MediaItem
    var width: CGFloat = 176
    var imageHeight: CGFloat? = nil
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    private var isCurrent: Bool {
        guard let v = item.videoId else { return false }
        return app.engine.track?.videoId == v
    }

    private var canPlay: Bool {
        item.play != nil || item.videoId != nil || item.playlistId != nil || item.kind == "album"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Artwork(url: item.thumbnail, cornerRadius: 8,
                        placeholder: item.isArtist ? "person.fill" : "music.note")
                    .frame(width: width, height: imageHeight ?? (item.wide ? width * 9 / 16 : width))
                    .cardShadow(cornerRadius: 8, opacity: hover ? 0.25 : 0.12,
                                radius: hover ? 10 : 4, y: 3)
                if item.kind == "mix" {
                    MixBand(title: item.title, width: width)
                }

                if hover && !item.isArtist {
                    LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .allowsHitTesting(false)
                }
                if canPlay && (hover || (isCurrent && app.engine.isPlaying)) {
                    PlayCircle(size: d.v(28, 32), playing: isCurrent && app.engine.isPlaying) {
                        if isCurrent { app.engine.togglePlay() } else { app.play(item) }
                    }
                    .padding(d.v(8, 10))
                    .transition(.opacity)
                }
            }
            .frame(width: width, height: imageHeight ?? (item.wide ? width * 9 / 16 : width))

            HStack(alignment: .top, spacing: 8) {
                // Notifications: the channel's picture beside the title.
                if let avatar = item.avatar {
                    Artwork(url: avatar, circle: true, placeholder: "person.fill")
                        .frame(width: d.v(26, 30), height: d.v(26, 30))
                }
                VStack(alignment: item.isArtist ? .center : .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        // Not read yet on YouTube.
                        if item.unread == true {
                            Circle().fill(Color.brand).frame(width: 7, height: 7)
                        }
                        Text(item.title)
                            .font(.system(size: d.v(12.5, 13), weight: .medium))
                            .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                            .lineLimit(1)
                        if item.explicit { ExplicitBadge() }
                    }
                    if !item.isArtist {
                        // A subtitle starting with the artists' names ("Tiësto • Single • 2025",
                        // a video's channels "A ve B • 3:45"): each name links to its page.
                        if let byline = Self.byline(item) {
                            HStack(spacing: 0) {
                                ArtistByline(artists: item.artists, fallback: byline.names, font: .system(size: d.v(11, 12)))
                                    .layoutPriority(1)
                                Text(byline.rest)
                                    .font(.system(size: d.v(11, 12)))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text(item.subtitle)
                                .font(.system(size: d.v(11, 12)))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: item.isArtist ? .center : .leading)
            }
            .frame(width: width, alignment: item.isArtist ? .center : .leading)
        }
        .contentShape(Rectangle())
        // Continuous hover (plain onHover can miss cards that scrolled under the pointer with
        // the carousel arrows), ignored while the page scrolls under a still pointer.
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

// MARK: - Song grid (quick picks)

struct SongGrid: View {
    let section: Shelf
    @ViewState var hover = false
    @ViewState var position: Int? = nil
    /// Width the grid has on screen: the arrows show only when the columns don't all fit.
    @ViewState var viewport: CGFloat = 0
    @Environment(\.density) private var d

    private var rows: Int { max(1, min(4, section.items.count)) }
    /// The grid fills column by column; scroll positions are column numbers.
    private var columns: [[MediaItem]] {
        stride(from: 0, to: section.items.count, by: rows).map {
            Array(section.items[$0..<min($0 + rows, section.items.count)])
        }
    }

    var body: some View {
        let cols = columns
        let index = position ?? 0
        let rowH = d.songRow
        let content = CGFloat(cols.count) * d.songColumn + d.v(18, 24) * CGFloat(max(cols.count - 1, 0)) + d.pad * 2
        let overflows = content > viewport + 1
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            ShelfHeader(section: section)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: d.v(18, 24)) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { c, items in
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                CompactSongRow(item: item)
                                    .frame(width: d.songColumn, height: rowH)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(height: CGFloat(rows) * rowH, alignment: .top)
                        .id(c)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, d.pad, for: .scrollContent)
            .scrollPosition(id: $position, anchor: .leading)
            .frame(height: CGFloat(rows) * rowH)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { viewport = g.size.width }
                    .onChange(of: g.size.width) { _, w in viewport = w }
            })
            .overlay(alignment: .leading) {
                if hover && overflows && index > 0 {
                    CarouselArrow(system: "chevron.left") { move(-2, cols.count) }
                        .padding(.leading, 10)
                        .offset(y: 22)
                }
            }
            .overlay(alignment: .trailing) {
                if hover && overflows && index < cols.count - 2 {
                    CarouselArrow(system: "chevron.right") { move(2, cols.count) }
                        .padding(.trailing, 10)
                        .offset(y: 22)
                }
            }
        }
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
    }

    private func move(_ delta: Int, _ count: Int) {
        guard count > 0 else { return }
        let target = max(0, min(count - 1, (position ?? 0) + delta))
        withAnimation(.easeInOut(duration: 0.4)) { position = target }
    }
}

struct CompactSongRow: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    private var isCurrent: Bool { item.videoId != nil && app.engine.track?.videoId == item.videoId }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Artwork(url: item.thumbnail, cornerRadius: 4)
                if hover || isCurrent {
                    Color.black.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 4))
                    if isCurrent && app.engine.isPlaying && !hover {
                        EqualizerIcon(color: .white)
                    } else {
                        Image(systemName: isCurrent && app.engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: d.songArt, height: d.songArt)
            .onTapGesture { isCurrent ? app.engine.togglePlay() : app.play(item) }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                        .lineLimit(1)
                    if item.explicit { ExplicitBadge() }
                }
                ArtistByline(artists: item.artists, fallback: item.subtitle, font: .system(size: 12))
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, d.v(4, 6))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, d.songArt + 10)
        }
        .contentShape(Rectangle())
        .scrollAwareHover($hover)
        .onTapGesture(count: 2) { app.play(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

// MARK: - Track lists

struct TrackListSection: View {
    let section: Shelf
    var limit = 6
    var numbered = false
    @ViewState var expanded = false
    @Environment(\.density) private var d

    var body: some View {
        let shown = expanded ? section.items : Array(section.items.prefix(limit))
        VStack(alignment: .leading, spacing: 8) {
            ShelfHeader(section: section)
            TrackList(items: shown, numbered: numbered, showArtwork: true, showAlbum: true)
                .padding(.horizontal, d.pad)
            if section.items.count > limit {
                Button(expanded ? M.t("Daha Az Göster", "Show Less") : M.t("Tümünü Göster", "Show All")) {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, d.pad)
            }
        }
    }
}

/// Striped track table (Apple Music style) with column headers.
struct TrackList: View {
    let items: [MediaItem]
    var numbered = true
    var showArtwork = true
    var showAlbum = true
    var showHeader = true
    var context: String?
    var onReachEnd: (() -> Void)?

    var body: some View {
        TrackListRows(items: items, numbered: numbered, showArtwork: showArtwork,
                      showAlbum: showAlbum, showHeader: showHeader, context: context, onReachEnd: onReachEnd)
    }
}

private struct TrackListRows: View {
    let items: [MediaItem]
    let numbered: Bool
    let showArtwork: Bool
    let showAlbum: Bool
    let showHeader: Bool
    let context: String?
    let onReachEnd: (() -> Void)?
    @ViewState var width: CGFloat = 900
    /// On an artist's own page: their name, left out of the Artist column.
    @Environment(\.pageArtist) private var pageArtist

    var body: some View {
        // On the artist's page the Artist column names only the others (features); with
        // none in the list, it goes.
        let leaveOut = pageArtist.flatMap { $0.isEmpty ? nil : $0 }
        let artistColumn = leaveOut.map { name in
            items.contains { item in item.artists.contains { !Self.same($0.name, name) } }
        } ?? true
        // The third column: the songs' albums; for episodes and videos, which have none,
        // the date they came out (taken out of "12 B görüntüleme • 11 Eyl 2025"); else none.
        let third = showAlbum && width > 700 ? ThirdColumn(items) : .hidden
        let time = TimeColumn(items)
        // Albums and playlists: how often each song was played, in a column of its own.
        let plays = third != .date && width > 640 && items.contains { $0.isTrack && $0.plays != nil }
        // Room for an hour ("3:26:23", long episodes) when a row needs it.
        let timeWidth: CGFloat = items.contains { item in
            (item.duration ?? "").filter { $0 == ":" }.count >= 2
        } ? 62 : 48
        VStack(spacing: 0) {
            if showHeader {
                TrackListHeader(numbered: numbered, showArtwork: showArtwork, third: third,
                                secondTitle: plays ? M.t("Sanatçı", "Artist") : Self.secondColumnTitle(items),
                                showSecond: artistColumn,
                                plays: plays, time: time, timeWidth: timeWidth)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    TrackRow(item: item, index: numbered ? i + 1 : nil, showArtwork: showArtwork,
                             showSecond: artistColumn, leaveOutArtist: leaveOut,
                             showAlbum: third == .album, showDate: third == .date, showPlays: plays,
                             showTime: time != .hidden, timeWidth: timeWidth, striped: i % 2 == 0, context: context)
                        .onAppear { if i >= items.count - 4 { onReachEnd?() } }
                }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    }

    static func same(_ a: String, _ b: String) -> Bool { TrackListRowsNames.same(a, b) }

    /// Album pages list play counts ("28 Mn dinlenme") where other lists show artists.
    static func secondColumnTitle(_ items: [MediaItem]) -> String {
        let tracks = items.filter(\.isTrack)
        guard !tracks.isEmpty, tracks.allSatisfy({ $0.artists.isEmpty }) else { return M.t("Sanatçı", "Artist") }
        let counts = tracks.filter { PlayCount.isCount($0.subtitle) }
        return counts.count * 2 >= tracks.count ? M.t("Dinlenme", "Plays") : M.t("Sanatçı", "Artist")
    }
}

/// Artist names compared as people read them (case and accents aside).
enum TrackListRowsNames {
    static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// A row's play count and the rest of its subtitle: "12 B görüntüleme • 11 Eyl 2025" →
/// ("12 B görüntüleme", "11 Eyl 2025").
enum PlayCount {
    static let words = ["dinlenme", "plays", "play", "görüntüleme", "izlenme", "views", "view"]
    static let columnWidth: CGFloat = 92

    /// A count needs its number too ("Playboi Carti" isn't one).
    static func isCount(_ text: String) -> Bool {
        let s = text.lowercased()
        return s.contains(where: \.isNumber) && words.contains { s.contains($0) }
    }

    /// The subtitle without its play count: "Justice • 4,3 Mn dinlenme" → "Justice".
    static func without(_ subtitle: String) -> String {
        subtitle.components(separatedBy: " • ").filter { !$0.isEmpty && !isCount($0) }.joined(separator: " • ")
    }

    static func split(_ subtitle: String) -> (count: String, date: String)? {
        let parts = subtitle.components(separatedBy: " • ").filter { !$0.isEmpty }
        guard parts.count >= 2, let i = parts.firstIndex(where: isCount) else { return nil }
        let rest = parts.enumerated().filter { $0.offset != i }.map(\.element)
        return (parts[i], rest.joined(separator: " • "))
    }
}

/// What a list's third column holds.
enum ThirdColumn {
    case album, date, hidden

    init(_ items: [MediaItem]) {
        let tracks = items.filter(\.isTrack)
        if tracks.isEmpty || tracks.contains(where: { $0.album != nil }) {
            self = .album
        } else if tracks.filter({ $0.artists.isEmpty && PlayCount.split($0.subtitle) != nil }).count * 2 >= tracks.count {
            self = .date
        } else {
            self = .hidden
        }
    }
}

/// What a list's last column holds: the songs' lengths, the releases' years (an artist's
/// albums and singles), or nothing when no row has either (the column then goes).
enum TimeColumn {
    case duration, year, hidden

    init(_ items: [MediaItem]) {
        if items.contains(where: { $0.duration?.isEmpty == false }) { self = .duration }
        else if items.contains(where: { $0.releaseYear != nil }) { self = .year }
        else { self = .hidden }
    }
}

/// Column titles; mirrors TrackRow's layout exactly so the columns line up.
struct TrackListHeader: View {
    let numbered: Bool
    let showArtwork: Bool
    var third = ThirdColumn.album
    var secondTitle = M.t("Sanatçı", "Artist")
    var showSecond = true
    var plays = false
    var time = TimeColumn.duration
    var timeWidth: CGFloat = 48
    @Environment(\.density) private var d

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if numbered || !showArtwork {
                    Text(numbered ? "#" : "")
                        .frame(width: 26, alignment: .center)
                }
                if showArtwork {
                    Color.clear.frame(width: d.trackArt, height: 1)
                }
                ColumnTitle(M.t("Başlık", "Title"), icon: "music.note")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showSecond {
                    ColumnTitle(secondTitle, icon: secondTitle == M.t("Dinlenme", "Plays") ? "headphones" : "music.mic")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                switch third {
                case .album:
                    ColumnTitle(M.t("Albüm", "Album"), icon: "opticaldisc")
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .date:
                    ColumnTitle(M.t("Yayın Tarihi", "Published"), icon: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .hidden:
                    EmptyView()
                }
                if plays {
                    ColumnTitle(M.t("Dinlenme", "Plays"), icon: "headphones")
                        .frame(width: PlayCount.columnWidth, alignment: .leading)
                }
                switch time {
                case .duration:
                    Image(systemName: "clock")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color.brand.opacity(0.85))
                        .help(M.t("Süre", "Length"))
                        .frame(width: timeWidth, alignment: .trailing)
                case .year:
                    ColumnTitle(M.t("Yıl", "Year"), icon: "calendar")
                        .frame(width: timeWidth, alignment: .trailing)
                case .hidden:
                    EmptyView()
                }
                Color.clear.frame(width: 22, height: 1)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: d.v(24, 28))
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 0.5)
                .padding(.bottom, 4)
        }
    }
}

/// A column's name with a small icon before it, in the accent colour as the left menu's.
private struct ColumnTitle: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.brand.opacity(0.85))
            Text(title)
        }
        .lineLimit(1)
    }
}

struct TrackRow: View {
    let item: MediaItem
    var index: Int?
    var showArtwork = true
    /// The Artist column (gone on an artist's page whose songs are all theirs).
    var showSecond = true
    /// On an artist's page: their own name, left out of the Artist column.
    var leaveOutArtist: String? = nil
    var showAlbum = true
    /// Episodes and videos: their date in a column of its own, out of the subtitle.
    var showDate = false
    /// Albums and playlists: the play count in a column of its own, out of the subtitle.
    var showPlays = false
    /// The last column: the length, or the year of a release without one.
    var showTime = true
    var timeWidth: CGFloat = 48
    var striped = false
    var context: String?

    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    private var isCurrent: Bool { item.videoId != nil && app.engine.track?.videoId == item.videoId }
    /// The play count and the date, when the date has its own column.
    private var dated: (count: String, date: String)? {
        showDate && item.artists.isEmpty ? PlayCount.split(item.subtitle) : nil
    }

    /// Said "don't recommend" / disliked: the song stays in its list, faded and marked, and
    /// is left out when the list plays (unless clicked itself).
    private var isHidden: Bool { item.isTrack && app.hiddenKeys.contains(item.recommendationKey) }

    var body: some View {
        HStack(spacing: 12) {
            if index != nil || !showArtwork {
                leading.frame(width: 26, alignment: .center)
            }
            if showArtwork {
                ZStack {
                    Artwork(url: item.thumbnail, cornerRadius: 4, circle: false,
                            placeholder: item.isArtist ? "person.fill" : "music.note")
                    if index == nil && (hover || isCurrent) && item.isTrack {
                        Color.black.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 4))
                        if isCurrent && app.engine.isPlaying && !hover {
                            EqualizerIcon(color: .white)
                        } else {
                            Image(systemName: isCurrent && app.engine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: d.trackArt, height: d.trackArt)
                .onTapGesture { primaryAction() }
            }

            HStack(spacing: 5) {
                Text(item.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                    .lineLimit(1)
                if item.explicit { ExplicitBadge() }
                if isHidden {
                    Image(systemName: "hand.thumbsdown.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help(M.t("Beğenmedin: bu liste çalınırken atlanır.", "Disliked: skipped when this list plays."))
                        .transition(.softReveal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showSecond {
                Group {
                    if item.isTrack, let name = leaveOutArtist {
                        // The artist's own page: the others on the song; a song of their own
                        // alone keeps their name, so no row is left empty.
                        let others = item.artists.filter { !TrackListRowsNames.same($0.name, name) }
                        ArtistByline(artists: others.isEmpty ? item.artists : others,
                                     fallback: PlayCount.without(item.subtitle), font: .system(size: 13))
                    } else if item.isTrack {
                        ArtistByline(artists: item.artists,
                                     fallback: dated?.count ?? (showPlays ? PlayCount.without(item.subtitle) : item.subtitle),
                                     font: .system(size: 13))
                    } else {
                        Text(item.subtitle.isEmpty ? item.typeLabel : item.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showAlbum {
                Group {
                    if let album = item.album {
                        HoverLink(album.name) { app.openAlbum(album.id) }
                    } else {
                        Text("")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showDate {
                Text(dated?.date ?? "")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showPlays {
                Text(item.plays ?? "")
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .frame(width: PlayCount.columnWidth, alignment: .leading)
            }

            if showTime {
                Text(item.duration ?? item.releaseYear ?? "")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .frame(width: timeWidth, alignment: .trailing)
            }

            Menu {
                ItemMenu(item: item)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.brand)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .opacity(hover ? 1 : 0)
        }
        .opacity(isHidden && !hover ? 0.45 : 1)
        .animation(.soft, value: isHidden)
        .padding(.horizontal, 10)
        .frame(height: showArtwork ? d.trackRow : d.trackRowPlain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? Color.primary.opacity(0.09) : (striped ? Color.primary.opacity(0.035) : .clear))
        )
        .contentShape(Rectangle())
        .scrollAwareHover($hover)
        .onTapGesture(count: 2) { primaryAction() }
        .contextMenu { ItemMenu(item: item) }
    }

    @ViewBuilder
    private var leading: some View {
        if hover && item.isTrack {
            Button { primaryAction() } label: {
                Image(systemName: isCurrent && app.engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.brand)
            }
            .buttonStyle(.plain)
        } else if isCurrent {
            EqualizerIcon(animating: app.engine.isPlaying)
        } else if let index {
            Text("\(index)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func primaryAction() {
        if !item.isTrack {
            app.open(item)
        } else if isCurrent {
            app.engine.togglePlay()
        } else {
            app.play(item, context: context)
        }
    }
}

// MARK: - Categories

struct CategoryGrid: View {
    let section: Shelf
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !section.title.isEmpty {
                SectionTitle(title: section.title)
                    .padding(.horizontal, d.pad)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: CategoryTile.minWidth(d), maximum: 300), spacing: d.v(10, 14))],
                      spacing: d.v(10, 14)) {
                ForEach(section.items) { CategoryTile(item: $0) }
            }
            .padding(.horizontal, d.pad)
        }
    }
}

/// A mood or genre, as in Spotify's "browse all": the category's own colour (YouTube's),
/// its name at the top left, and the cover of its first list — what YouTube Music shows
/// for it in your region — tilted at the bottom right, partly off the card. The cover's own
/// colour glows out around it and melts into the card's, so the two make one picture. On
/// hover the next two lists of the category fan out from under it to the left, like a hand
/// of cards.
struct CategoryTile: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @ViewState var cover: CategoryCover? = nil
    /// The covers stepped aside while a panel moves (AppModel.layoutSettling).
    @ViewState var away = false
    /// Back in place: the hand opens once, then closes to its resting peek.
    @ViewState var dealing = false
    @Environment(\.density) private var d

    static func minWidth(_ d: Density) -> CGFloat { d.v(180, 210) }
    static let aspect: CGFloat = 1.75

    var body: some View {
        let color = Color(hexString: item.color) ?? Palette.color(for: item.title)
        GeometryReader { g in
            // Big, and mostly inside the card: the category's face.
            let side = (g.size.height * 0.88).rounded()
            let center = CGPoint(x: g.size.width - side * 0.36, y: g.size.height - side * 0.28)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [color, color.scaledBrightness(0.72)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // The cover's colour, spreading from under it into the card's.
                if let tint = cover?.tint, !away {
                    RadialGradient(colors: [tint.opacity(0.95), tint.opacity(0.45), tint.opacity(0)],
                                   center: UnitPoint(x: center.x / max(g.size.width, 1), y: center.y / max(g.size.height, 1)),
                                   startRadius: side * 0.2, endRadius: g.size.width * 0.72)
                }
                if let cover {
                    // The next lists peek out from behind the first; on hover they fan out to
                    // the left like a hand of cards. Stepped aside, they gather under it.
                    let fanned = (hover || dealing) && !away
                    ForEach(Array(cover.more.enumerated().reversed()), id: \.element) { i, url in
                        let step = CGFloat(i + 1)
                        let spread: CGFloat = away ? 0 : (fanned ? 0.38 : 0.11)
                        Artwork(url: url, cornerRadius: 7, placeholder: "music.note.list")
                            .frame(width: side * 0.9, height: side * 0.9)
                            .shadow(color: .black.opacity(fanned ? 0.35 : 0.25), radius: fanned ? 10 : 6, x: -2, y: 3)
                            .rotationEffect(.degrees(away ? 24 : (fanned ? 24 - 11 * Double(step) : 24 - 5 * Double(step))))
                            .position(x: center.x - side * spread * step,
                                      y: center.y + side * (fanned ? 0.04 : 0.02) * step)
                            .opacity(away ? 0 : 1)
                    }
                    Artwork(url: cover.url, cornerRadius: 7, placeholder: "music.note.list")
                        .frame(width: side, height: side)
                        .shadow(color: (cover.tint ?? .black).opacity(0.55), radius: 14, x: -3, y: 4)
                        .rotationEffect(.degrees(fanned ? 28 : 24))
                        .scaleEffect(away ? 0.85 : (fanned ? 1.04 : 1))
                        .position(center)
                        .opacity(away ? 0 : 1)
                }
                Text(item.title)
                    .font(.system(size: d.v(15, 17), weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.3), radius: 4)
                    .frame(width: max(70, g.size.width - side * 1.02 - 14), alignment: .topLeading)
                    .padding(.leading, 14)
                    .padding(.top, 12)
            }
            // The cover and its glow come in together, once, softly.
            .animation(.easeOut(duration: 0.45), value: cover?.url)
            // The fan opens and closes with a soft spring.
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: hover)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dealing)
            // Stepping aside is quick; coming back is soft.
            .animation(away ? .easeIn(duration: 0.15) : .easeOut(duration: 0.4), value: away)
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        // Drawn as one picture: the tilted, glowing cover costs nothing while scrolling.
        .drawingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(hover ? 1.02 : 1)
        .shadow(color: .black.opacity(hover ? 0.22 : 0.08), radius: hover ? 10 : 3, y: 2)
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .soft)
        .onTapGesture { app.open(item) }
        .task(id: item.id) {
            guard cover == nil else { return }
            cover = await CategoryCovers.shared.cover(for: item)
        }
        // A panel moves: the covers step aside; once the cards are in their new places the
        // covers come back and the hand opens once, then settles.
        .onChange(of: app.layoutSettling) { _, settling in
            if settling {
                away = true
            } else {
                away = false
                dealing = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 550_000_000)
                    dealing = false
                }
            }
        }
    }
}

/// A mood or genre's picture and its main colour.
struct CategoryCover: Equatable {
    let url: String
    let tint: Color?
    /// The next two lists' covers, for the fan on hover.
    var more: [String] = []
}

/// The covers of the moods and genres: looked up once (a few at a time, as tiles come into
/// view), with their main colour, kept in memory and for three days on this Mac, per
/// language. The picture is downloaded before the tile is told, so it appears whole.
@MainActor
final class CategoryCovers {
    static let shared = CategoryCovers()
    private static let key = "categoryCovers3"
    private static let life: TimeInterval = 3 * 24 * 3600

    private var memory: [String: CategoryCover?] = [:]
    private var running: [String: Task<CategoryCover?, Never>] = [:]
    private var busy = 0

    private init() {
        let now = Date().timeIntervalSince1970
        let kept = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [String: Any]] ?? [:]
        for (k, v) in kept {
            guard let url = v["url"] as? String, let at = v["at"] as? Double, now - at < Self.life else { continue }
            memory[k] = CategoryCover(url: url, tint: (v["tint"] as? String).flatMap { Color(hexString: $0) },
                                      more: v["more"] as? [String] ?? [])
        }
    }

    func cover(for item: MediaItem) async -> CategoryCover? {
        guard let id = item.browseId else { return nil }
        let key = "\(M.turkish ? "tr" : "en")|\(id)|\(item.params ?? "")"
        if let known = memory[key] {
            if let known = known {
                for url in [known.url] + known.more { _ = await ImageLoader.shared.load(url, maxPixel: 320) }
            }
            return known
        }
        if let task = running[key] { return await task.value }
        let task = Task<CategoryCover?, Never> { [weak self] in
            guard let self else { return nil }
            // Four at a time, so a page of tiles doesn't fire forty requests at once.
            while self.busy >= 4 { try? await Task.sleep(nanoseconds: 60_000_000) }
            self.busy += 1
            defer { self.busy -= 1 }
            let urls = (try? await YTMusic.shared.call("categoryCovers", ["browseId": id, "params": item.params ?? ""],
                                                        as: [String].self)) ?? []
            guard let url = urls.first else {
                self.memory[key] = .some(nil)
                return nil
            }
            async let picture = ImageLoader.shared.load(url, maxPixel: 320)
            let tint = await ColorExtractor.color(for: url)
            _ = await picture
            for extra in urls.dropFirst() { _ = await ImageLoader.shared.load(extra, maxPixel: 320) }
            let cover = CategoryCover(url: url, tint: tint, more: Array(urls.dropFirst()))
            self.store(cover, for: key)
            return cover
        }
        running[key] = task
        let cover = await task.value
        running[key] = nil
        return cover
    }

    private func store(_ cover: CategoryCover, for key: String) {
        memory[key] = cover
        var kept = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [String: Any]] ?? [:]
        var entry: [String: Any] = ["url": cover.url, "at": Date().timeIntervalSince1970, "more": cover.more]
        if let hex = cover.tint.flatMap(Self.hex) { entry["tint"] = hex }
        kept[key] = entry
        UserDefaults.standard.set(kept, forKey: Self.key)
    }

    private static func hex(_ color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let v = [c.redComponent, c.greenComponent, c.blueComponent].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}

/// Wrapping grid of cards (library, filtered search, "see all" pages).
/// A CardGrid shown a few rows at a time: "Daha Fazla Göster" adds two rows, bringing in
/// more cards when the ones at hand run out — the row's "see all" page first, then its
/// following pages — until there are none left; then "Daha Az Göster" folds it back.
struct PagedCardGrid: View {
    let items: [MediaItem]
    let startRows: Int
    /// The row's "see all" page, read when the cards at hand run out.
    var moreLink: MoreLink? = nil
    var title: String = ""
    /// The next page of these cards.
    var continuation: String? = nil

    @ViewState var width: CGFloat = 900
    /// Rows shown (0: `startRows`).
    @ViewState var rowsShown = 0
    @ViewState var extra: [MediaItem] = []
    /// Where the next cards come from, once the given `continuation` has been used.
    @ViewState var token: String? = nil
    @ViewState var tokenTaken = false
    @ViewState var linkRead = false
    @ViewState var loading = false
    @Environment(\.density) private var d
    @Environment(AppModel.self) private var app

    static let step = 2

    private var all: [MediaItem] {
        var seen = Set<String>()
        return (items + extra).filter { seen.insert($0.recommendationKey).inserted }
    }

    private var canFetch: Bool {
        (moreLink?.browseId != nil && !linkRead) || (tokenTaken ? token : continuation) != nil
    }

    var body: some View {
        let cards = all
        let perRow = CardGrid.metrics(cards, width: width, d: d).perRow
        let rows = rowsShown == 0 ? startRows : rowsShown
        let hasMore = cards.count > perRow * rows || canFetch
        VStack(alignment: .leading, spacing: d.v(12, 16)) {
            CardGrid(items: cards, rows: rows)
            if hasMore || rows > startRows {
                MoreButton(expand: hasMore, loading: loading) {
                    if hasMore {
                        showMore(rows: rows + Self.step, perRow: perRow)
                    } else {
                        withAnimation(.soft) { rowsShown = startRows }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, d.pad)
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
    }

    private func showMore(rows: Int, perRow: Int) {
        let needed = rows * perRow
        guard all.count < needed, canFetch else {
            withAnimation(.soft) { rowsShown = rows }
            return
        }
        loading = true
        Task {
            // A few pages at most, until the new rows are full or nothing is left.
            for _ in 0..<3 where all.count < needed && canFetch {
                await fetch()
            }
            loading = false
            withAnimation(.soft) { rowsShown = rows }
        }
    }

    private func fetch() async {
        if let link = moreLink, let id = link.browseId, !linkRead {
            linkRead = true
            let target = BrowseTarget(browseId: id, params: link.params, kind: "browse", title: title)
            if let page = try? await app.page(for: target) {
                extra += page.sections.flatMap(\.items)
                token = page.sections.compactMap(\.continuation).first
                tokenTaken = true
            }
            return
        }
        let next = tokenTaken ? token : continuation
        tokenTaken = true
        token = nil
        guard let next, let more = try? await app.engine.more(next) else { return }
        extra += more.items
        token = more.continuation == next ? nil : more.continuation
    }
}

/// "Daha Fazla Göster" / "Daha Az Göster": a pill like the filter chips, under the cards
/// at their right.
struct MoreButton: View {
    let expand: Bool
    var loading = false
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(expand ? M.t("Daha Fazla Göster", "Show More") : M.t("Daha Az Göster", "Show Less"))
                    .font(.system(size: 12, weight: .semibold))
                Group {
                    if loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: expand ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9.5, weight: .bold))
                    }
                }
                .frame(width: 12)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(Color.primary.opacity(hover ? 0.12 : 0.07)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(loading)
        .onHover { h in withAnimation(.soft) { hover = h } }
    }
}

/// The app's one grid of cards (library, "see all" pages, search filters, thin artist
/// pages). Cards keep the size they have in the rows of the home page and search — a cover
/// as wide as a row's cover, a video 16:9 at a row's video height — as many a row as fit,
/// then widened to fill the row exactly. `rows`: only the first rows (nil: all).
struct CardGrid: View {
    let items: [MediaItem]
    var rows: Int? = nil
    @ViewState var width: CGFloat = 900
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    struct Metrics {
        let perRow: Int
        let card: CGFloat
        let image: CGFloat
    }

    /// How cards of `items` lay out in `width` (the grid's whole width, margins included).
    nonisolated static func metrics(_ items: [MediaItem], width: CGFloat, d: Density) -> Metrics {
        let wide = !items.isEmpty && items.filter(\.wide).count * 2 >= items.count
        let base: CGFloat = wide ? (d.cardMixed * 16 / 9).rounded() : d.gridCard
        let inner = max(base, width - d.pad * 2)
        let perRow = max(1, Int((inner + d.cardGap) / (base + d.cardGap)))
        let card = ((inner - d.cardGap * CGFloat(perRow - 1)) / CGFloat(perRow)).rounded(.down)
        return Metrics(perRow: perRow, card: card, image: wide ? (card * 9 / 16).rounded() : card)
    }

    var body: some View {
        // What the user said not to recommend leaves at once; the cards after it move up.
        let hidden = app.hiddenKeys
        let all = hidden.isEmpty ? items : items.filter { !hidden.contains($0.recommendationKey) }
        let m = Self.metrics(all, width: width, d: d)
        let shown = rows.map { Array(all.prefix(m.perRow * $0)) } ?? all
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(m.card), spacing: d.cardGap, alignment: .top), count: m.perRow),
                  alignment: .leading, spacing: d.v(16, 24)) {
            ForEach(shown) { item in
                ItemCard(item: item, width: m.card, imageHeight: m.image)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(.horizontal, d.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
    }
}

extension ItemCard {
    /// The subtitle's first part when it is the item's artists (all of them, with pages),
    /// and what follows it ("• Single • 2025"); nil otherwise.
    static func byline(_ item: MediaItem) -> (names: String, rest: String)? {
        guard !item.artists.isEmpty, item.artists.allSatisfy({ $0.id.hasPrefix("UC") }) else { return nil }
        let names = item.subtitle.components(separatedBy: " • ").first ?? ""
        guard !names.isEmpty, item.artists.allSatisfy({ names.localizedCaseInsensitiveContains($0.name) }) else { return nil }
        return (names, String(item.subtitle.dropFirst(names.count)))
    }
}
