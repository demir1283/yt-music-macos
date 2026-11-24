import SwiftUI

/// Renders any YouTube Music shelf in the matching style.
struct ShelfView: View {
    let section: Shelf
    var trackLimit = 6
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
                CardCarousel(section: section)
            }
        }
        .fadeIn()
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

    var body: some View {
        let albumColumn = showAlbum && width > 700
        let time = TimeColumn(items)
        VStack(spacing: 0) {
            if showHeader {
                TrackListHeader(numbered: numbered, showArtwork: showArtwork, showAlbum: albumColumn,
                                secondTitle: Self.secondColumnTitle(items), time: time)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    TrackRow(item: item, index: numbered ? i + 1 : nil, showArtwork: showArtwork,
                             showAlbum: albumColumn, showTime: time != .hidden, striped: i % 2 == 0, context: context)
                        .onAppear { if i >= items.count - 4 { onReachEnd?() } }
                }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    }

    /// Album pages list play counts ("28 Mn dinlenme") where other lists show artists.
    static func secondColumnTitle(_ items: [MediaItem]) -> String {
        let tracks = items.filter(\.isTrack)
        guard !tracks.isEmpty, tracks.allSatisfy({ $0.artists.isEmpty }) else { return M.t("Sanatçı", "Artist") }
        let words = ["dinlenme", "plays", "play", "görüntüleme", "views"]
        let counts = tracks.filter { t in
            let s = t.subtitle.lowercased()
            return words.contains { s.contains($0) }
        }
        return counts.count * 2 >= tracks.count ? M.t("Dinlenme", "Plays") : M.t("Sanatçı", "Artist")
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
    let showAlbum: Bool
    var secondTitle = M.t("Sanatçı", "Artist")
    var time = TimeColumn.duration
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
                Text(M.t("Başlık", "Title")).frame(maxWidth: .infinity, alignment: .leading)
                Text(secondTitle).frame(maxWidth: .infinity, alignment: .leading)
                if showAlbum {
                    Text(M.t("Albüm", "Album")).frame(maxWidth: .infinity, alignment: .leading)
                }
                switch time {
                case .duration:
                    Image(systemName: "clock")
                        .frame(width: 48, alignment: .trailing)
                case .year:
                    Text(M.t("Yıl", "Year"))
                        .frame(width: 48, alignment: .trailing)
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

struct TrackRow: View {
    let item: MediaItem
    var index: Int?
    var showArtwork = true
    var showAlbum = true
    /// The last column: the length, or the year of a release without one.
    var showTime = true
    var striped = false
    var context: String?

    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    private var isCurrent: Bool { item.videoId != nil && app.engine.track?.videoId == item.videoId }

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

            Group {
                if item.isTrack {
                    ArtistByline(artists: item.artists, fallback: item.subtitle, font: .system(size: 13))
                } else {
                    Text(item.subtitle.isEmpty ? item.typeLabel : item.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

            if showTime {
                Text(item.duration ?? item.releaseYear ?? "")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: d.v(140, 170), maximum: 240), spacing: d.v(10, 14))],
                      spacing: d.v(10, 14)) {
                ForEach(section.items) { CategoryTile(item: $0) }
            }
            .padding(.horizontal, d.pad)
        }
    }
}

struct CategoryTile: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    var body: some View {
        let color = Color(hexString: item.color) ?? Palette.color(for: item.title)
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [color, color.scaledBrightness(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(item.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.25), radius: 4)
                .padding(12)
        }
        .frame(height: d.tileHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(hover ? 1.02 : 1)
        .shadow(color: .black.opacity(hover ? 0.2 : 0.08), radius: hover ? 8 : 3, y: 2)
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
        .onTapGesture { app.open(item) }
    }
}

/// Wrapping grid of cards (library, filtered search, "see all" pages).
struct CardGrid: View {
    let items: [MediaItem]
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        // What the user said not to recommend leaves at once; the cards after it move up.
        let hidden = app.hiddenKeys
        let shown = hidden.isEmpty ? items : items.filter { !hidden.contains($0.recommendationKey) }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: d.gridCard, maximum: d.gridCard + 40), spacing: d.cardGap, alignment: .top)],
                  alignment: .leading, spacing: d.v(16, 24)) {
            ForEach(shown) {
                ItemCard(item: $0, width: d.gridCard)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .padding(.horizontal, d.pad)
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
