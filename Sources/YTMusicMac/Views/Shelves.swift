import SwiftUI

/// Renders any YouTube Music shelf in the matching style.
struct ShelfView: View {
    let section: Shelf
    var trackLimit = 6

    var body: some View {
        Group {
            switch section.layout {
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

private struct ShelfHeader: View {
    let section: Shelf
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        if !section.title.isEmpty {
            SectionTitle(title: section.title, subtitle: section.strapline,
                         action: section.more.map { more in { app.openMore(more, title: section.title) } })
                .padding(.horizontal, d.pad)
        }
    }
}

// MARK: - Card carousel

struct CardCarousel: View {
    let section: Shelf
    @ViewState var hover = false
    @ViewState var position: String? = nil
    @Environment(\.density) private var d

    private var index: Int {
        guard let p = position, let i = section.items.firstIndex(where: { $0.id == p }) else { return 0 }
        return i
    }

    var body: some View {
        // Mixed shelves (square covers + 16:9 videos) share one image height so every
        // card's title sits on the same line and nothing gets clipped.
        let mixed = section.items.contains { $0.wide }
        let imageH: CGFloat = mixed ? d.cardMixed : d.card
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            ShelfHeader(section: section)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: d.cardGap) {
                    ForEach(section.items) { item in
                        ItemCard(item: item, width: item.wide ? imageH * 16 / 9 : imageH, imageHeight: imageH)
                            .id(item.id)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, d.pad, for: .scrollContent)
            .scrollPosition(id: $position, anchor: .leading)
            .frame(height: imageH + d.v(44, 50))
            .overlay(alignment: .leading) {
                if hover && index > 0 {
                    CarouselArrow(system: "chevron.left") { move(-3) }
                        .padding(.leading, 10)
                }
            }
            .overlay(alignment: .trailing) {
                if hover && index < section.items.count - 3 {
                    CarouselArrow(system: "chevron.right") { move(3) }
                        .padding(.trailing, 10)
                }
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }

    private func move(_ delta: Int) {
        guard !section.items.isEmpty else { return }
        let target = max(0, min(section.items.count - 1, index + delta))
        withAnimation(.easeInOut(duration: 0.4)) {
            position = section.items[target].id
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
                Artwork(url: item.thumbnail, cornerRadius: 8, circle: false,
                        placeholder: item.isArtist ? "person.fill" : "music.note")
                    .frame(width: width, height: imageHeight ?? (item.wide ? width * 9 / 16 : width))
                    .shadow(color: .black.opacity(hover ? 0.25 : 0.12), radius: hover ? 10 : 4, y: 3)

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

            VStack(alignment: item.isArtist ? .center : .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.title)
                        .font(.system(size: d.v(12.5, 13), weight: .medium))
                        .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                        .lineLimit(1)
                    if item.explicit { ExplicitBadge() }
                }
                if !item.isArtist {
                    Text(item.subtitle)
                        .font(.system(size: d.v(11, 12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: item.isArtist ? .center : .leading)
        }
        .contentShape(Rectangle())
        // Continuous hover: plain onHover can miss cards that scrolled under the pointer
        // (carousel arrows), so their play button never showed.
        .onContinuousHover { phase in
            let inside: Bool
            switch phase {
            case .active: inside = true
            case .ended: inside = false
            }
            if inside != hover { withAnimation(.easeOut(duration: 0.15)) { hover = inside } }
        }
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

// MARK: - Song grid (quick picks)

struct SongGrid: View {
    let section: Shelf
    @ViewState var hover = false
    @ViewState var position: Int? = nil
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
            .overlay(alignment: .leading) {
                if hover && index > 0 {
                    CarouselArrow(system: "chevron.left") { move(-2, cols.count) }
                        .padding(.leading, 10)
                        .offset(y: 22)
                }
            }
            .overlay(alignment: .trailing) {
                if hover && index < cols.count - 2 {
                    CarouselArrow(system: "chevron.right") { move(2, cols.count) }
                        .padding(.trailing, 10)
                        .offset(y: 22)
                }
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
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
        .onHover { hover = $0 }
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
                Button(expanded ? "Daha Az Göster" : "Tümünü Göster") {
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
        VStack(spacing: 0) {
            if showHeader {
                TrackListHeader(numbered: numbered, showArtwork: showArtwork, showAlbum: albumColumn,
                                secondTitle: Self.secondColumnTitle(items))
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    TrackRow(item: item, index: numbered ? i + 1 : nil, showArtwork: showArtwork,
                             showAlbum: albumColumn, striped: i % 2 == 0, context: context)
                        .onAppear { if i >= items.count - 4 { onReachEnd?() } }
                }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    }

    /// Album pages list play counts ("28 Mn dinlenme") where other lists show artists.
    static func secondColumnTitle(_ items: [MediaItem]) -> String {
        let tracks = items.filter(\.isTrack)
        guard !tracks.isEmpty, tracks.allSatisfy({ $0.artists.isEmpty }) else { return "Sanatçı" }
        let words = ["dinlenme", "plays", "play", "görüntüleme", "views"]
        let counts = tracks.filter { t in
            let s = t.subtitle.lowercased()
            return words.contains { s.contains($0) }
        }
        return counts.count * 2 >= tracks.count ? "Dinlenme" : "Sanatçı"
    }
}

/// Column titles; mirrors TrackRow's layout exactly so the columns line up.
struct TrackListHeader: View {
    let numbered: Bool
    let showArtwork: Bool
    let showAlbum: Bool
    var secondTitle = "Sanatçı"
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
                Text("Başlık").frame(maxWidth: .infinity, alignment: .leading)
                Text(secondTitle).frame(maxWidth: .infinity, alignment: .leading)
                if showAlbum {
                    Text("Albüm").frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "clock")
                    .frame(width: 48, alignment: .trailing)
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
    var striped = false
    var context: String?

    @Environment(AppModel.self) private var app
    @ViewState var hover = false
    @Environment(\.density) private var d

    private var isCurrent: Bool { item.videoId != nil && app.engine.track?.videoId == item.videoId }

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

            Text(item.duration ?? "")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)

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
        .padding(.horizontal, 10)
        .frame(height: showArtwork ? d.trackRow : d.trackRowPlain)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hover ? Color.primary.opacity(0.09) : (striped ? Color.primary.opacity(0.035) : .clear))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
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
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture { app.open(item) }
    }
}

/// Wrapping grid of cards (library, filtered search, "see all" pages).
struct CardGrid: View {
    let items: [MediaItem]
    @Environment(\.density) private var d

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: d.gridCard, maximum: d.gridCard + 40), spacing: d.cardGap, alignment: .top)],
                  alignment: .leading, spacing: d.v(16, 24)) {
            ForEach(items) { ItemCard(item: $0, width: d.gridCard) }
        }
        .padding(.horizontal, d.pad)
    }
}
