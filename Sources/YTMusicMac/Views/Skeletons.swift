import SwiftUI

/// Loading previews shaped like the page that is about to appear.
///
/// Each page shows the skeleton of its own layout (a playlist header and its rows, an
/// artist's hero, a grid of mood tiles, shelves of covers…) built from the same sizes and
/// margins as the real views. When the content arrives it takes exactly the place of the
/// shapes, so nothing jumps. The shapes are still (no shimmer: an endless animation keeps
/// the CPU busy for as long as it is visible) and fade in only if loading takes a moment.
enum SkeletonLayout: Equatable {
    /// Home: filter chips (unless already shown), the greeting with eight tiles, the pick
    /// beside the station cards, a cover shelf, quick picks, another cover shelf.
    case home(chips: Bool)
    /// A page made of cover shelves (explore, new releases, podcasts, mood categories).
    case shelves
    /// Charts: a cover shelf, a numbered song list, another cover shelf.
    case charts
    /// Moods & genres: grids of coloured tiles.
    case tiles
    /// A page that is one long song list (history).
    case songList
    /// "See all" pages and the library: a wrapping grid of covers.
    case cardGrid
    /// Playlist / album / podcast: header with cover and buttons, then the tracks.
    case collection(album: Bool)
    /// Artist: hero image, popular songs, a cover shelf.
    case artist
    /// Search results: filter chips, top result beside songs, a cover shelf.
    case search
}

struct PageSkeleton: View {
    let layout: SkeletonLayout
    @Environment(\.density) private var d
    @ViewState var visible = false

    var body: some View {
        content
            .foregroundStyle(Color.primary.opacity(0.07))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                // Fast pages simply appear; the preview only shows if loading takes a moment.
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.25)) { visible = true }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .home(let chips):
            VStack(alignment: .leading, spacing: d.sectionGap) {
                if chips { SkelChips() }
                SkelShortcutGrid()
                SkelPicksRow()
                SkelCardShelf()
                SkelSongGrid()
                SkelCardShelf()
            }
        case .shelves:
            VStack(alignment: .leading, spacing: d.sectionGap) {
                SkelCardShelf()
                SkelCardShelf()
                SkelCardShelf()
            }
        case .charts:
            VStack(alignment: .leading, spacing: d.sectionGap) {
                SkelCardShelf(wide: true)
                SkelTrackSection(rows: 10, numbered: true)
                SkelCardShelf()
            }
        case .tiles:
            VStack(alignment: .leading, spacing: d.sectionGap) {
                SkelTiles(count: 8)
                SkelTiles(count: 12)
            }
        case .songList:
            SkelTrackSection(rows: 14, numbered: false)
        case .cardGrid:
            SkelCardGrid()
        case .collection(let album):
            VStack(alignment: .leading, spacing: 0) {
                SkelCollectionHeader(album: album)
                    .padding(.horizontal, d.pad)
                    .padding(.top, d.v(12, 20))
                    .padding(.bottom, d.v(14, 24))
                SkelTrackRows(rows: 14, numbered: album, artwork: !album, header: true)
                    .padding(.horizontal, d.pad)
            }
        case .artist:
            VStack(alignment: .leading, spacing: d.sectionGap) {
                SkelHero()
                SkelTrackSection(rows: 5, numbered: false)
                SkelCardShelf()
            }
        case .search:
            VStack(alignment: .leading, spacing: d.sectionGap) {
                SkelChips()
                SkelTopResultRow()
                SkelCardShelf()
            }
        }
    }
}

// MARK: - Building blocks (sizes mirror the real views in Shelves.swift)

/// Varied line lengths, so the preview reads like real titles rather than a pattern.
private enum Widths {
    static let title: [CGFloat] = [150, 120, 170, 135, 105]
    static let byline: [CGFloat] = [90, 110, 75, 100, 85]
}

private struct Bar: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .frame(width: width, height: height)
    }
}

/// Mirrors SectionTitle + ShelfHeader.
private struct SkelTitle: View {
    var width: CGFloat = 190
    @Environment(\.density) private var d

    var body: some View {
        Bar(width: width, height: d.sectionTitle * 0.85, radius: 5)
            .padding(.vertical, d.sectionTitle * 0.12)
            .padding(.horizontal, d.pad)
    }
}

/// Mirrors FilterChips.
private struct SkelChips: View {
    @Environment(\.density) private var d
    private let widths: [CGFloat] = [54, 78, 66, 92, 58, 84, 70, 62, 88]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                Capsule().frame(width: w, height: 26)
            }
        }
        .padding(.horizontal, d.pad)
    }
}

/// Mirrors ItemCard: cover, title line, subtitle line.
private struct SkelCard: View {
    let width: CGFloat
    let imageHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Bar(width: width, height: imageHeight, radius: 8)
            VStack(alignment: .leading, spacing: 5) {
                Bar(width: width * 0.78, height: 10)
                Bar(width: width * 0.52, height: 9)
            }
            .padding(.top, 2)
        }
    }
}

/// Mirrors CardCarousel: title, then a row of covers that runs off the edge.
private struct SkelCardShelf: View {
    var wide = false
    @Environment(\.density) private var d

    var body: some View {
        let imageH = wide ? d.cardMixed : d.card
        let cardW = wide ? (imageH * 16 / 9).rounded() : imageH
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            SkelTitle()
            HStack(alignment: .top, spacing: d.cardGap) {
                ForEach(0..<12, id: \.self) { _ in
                    SkelCard(width: cardW, imageHeight: imageH)
                }
            }
            .padding(.leading, d.pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: imageH + d.v(44, 50), alignment: .top)
            .clipped()
        }
    }
}

/// Mirrors ShortcutGrid: the greeting, then two rows of four tiles (cover + title).
private struct SkelShortcutGrid: View {
    @Environment(\.density) private var d

    var body: some View {
        let side = d.v(48, 56)
        VStack(alignment: .leading, spacing: d.v(10, 14)) {
            Bar(width: 170, height: d.v(22, 26) * 0.85, radius: 5)
                .padding(.vertical, 3)
                .padding(.horizontal, d.pad)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: d.v(8, 10)), count: 4),
                      spacing: d.v(8, 10)) {
                ForEach(0..<8, id: \.self) { i in
                    HStack(spacing: 10) {
                        Rectangle().frame(width: side, height: side)
                        Bar(width: Widths.title[i % 5], height: 11)
                        Spacer(minLength: 0)
                    }
                    .frame(height: side)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.horizontal, d.pad)
        }
    }
}

/// Mirrors PicksRow: the pick (cover, lines, buttons) beside a row of station squares.
private struct SkelPicksRow: View {
    @Environment(\.density) private var d

    var body: some View {
        let cover = d.v(170, 204)
        HStack(alignment: .top, spacing: d.v(22, 32)) {
            VStack(alignment: .leading, spacing: d.v(8, 10)) {
                Bar(width: 150, height: d.sectionTitle * 0.85, radius: 5)
                    .padding(.vertical, d.sectionTitle * 0.12)
                HStack(spacing: d.v(16, 22)) {
                    Bar(width: cover, height: cover, radius: 8)
                    VStack(alignment: .leading, spacing: 9) {
                        Bar(width: 130, height: 10)
                        Bar(width: 180, height: d.v(20, 24), radius: 5)
                        Bar(width: 120, height: 10)
                        HStack(spacing: 10) {
                            Circle().frame(width: d.v(36, 40), height: d.v(36, 40))
                            Capsule().frame(width: 64, height: 28)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .frame(width: d.v(400, 480), alignment: .leading)
            VStack(alignment: .leading, spacing: d.v(8, 10)) {
                Bar(width: 210, height: d.sectionTitle * 0.85, radius: 5)
                    .padding(.vertical, d.sectionTitle * 0.12)
                HStack(alignment: .top, spacing: d.cardGap) {
                    ForEach(0..<8, id: \.self) { _ in
                        SkelCard(width: d.card, imageHeight: d.card)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: d.card + d.v(44, 50), alignment: .top)
                .clipped()
            }
        }
        .padding(.leading, d.pad)
    }
}

/// Mirrors SongGrid / CompactSongRow (quick picks).
private struct SkelSongGrid: View {
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            SkelTitle(width: 150)
            HStack(alignment: .top, spacing: d.v(18, 24)) {
                ForEach(0..<5, id: \.self) { c in
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { r in
                            HStack(spacing: 10) {
                                Bar(width: d.songArt, height: d.songArt, radius: 4)
                                VStack(alignment: .leading, spacing: 5) {
                                    Bar(width: Widths.title[(r + c) % 4], height: 10)
                                    Bar(width: Widths.byline[(r + c) % 4], height: 9)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: d.songColumn, height: d.songRow)
                        }
                    }
                }
            }
            .padding(.leading, d.pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 4 * d.songRow, alignment: .top)
            .clipped()
        }
    }
}

/// Mirrors TrackList rows (with the header line when the real list has one).
private struct SkelTrackRows: View {
    let rows: Int
    let numbered: Bool
    let artwork: Bool
    var header = true
    @Environment(\.density) private var d

    var body: some View {
        VStack(spacing: 0) {
            if header {
                HStack(spacing: 12) {
                    Bar(width: 60, height: 8)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: d.v(24, 28))
                Rectangle().frame(height: 0.5).padding(.bottom, 4)
            }
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 12) {
                    if numbered || !artwork {
                        Bar(width: 12, height: 9).frame(width: 26)
                    }
                    if artwork {
                        Bar(width: d.trackArt, height: d.trackArt, radius: 4)
                    }
                    Bar(width: Widths.title[i % 5] + 40, height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Bar(width: Widths.byline[i % 5] + 10, height: 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Bar(width: 32, height: 9)
                        .frame(width: 48, alignment: .trailing)
                    Color.clear.frame(width: 22, height: 1)
                }
                .padding(.horizontal, 10)
                .frame(height: artwork ? d.trackRow : d.trackRowPlain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .opacity(i % 2 == 0 ? 0.45 : 0)
                )
            }
        }
    }
}

/// Mirrors TrackListSection: title, then rows.
private struct SkelTrackSection: View {
    let rows: Int
    let numbered: Bool
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkelTitle(width: 140)
            SkelTrackRows(rows: rows, numbered: numbered, artwork: true)
                .padding(.horizontal, d.pad)
        }
    }
}

/// Mirrors CategoryGrid / CategoryTile.
private struct SkelTiles: View {
    let count: Int
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkelTitle(width: 160)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: d.v(140, 170), maximum: 240), spacing: d.v(10, 14))],
                      spacing: d.v(10, 14)) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .frame(height: d.tileHeight)
                }
            }
            .padding(.horizontal, d.pad)
        }
    }
}

/// Mirrors CardGrid.
private struct SkelCardGrid: View {
    @Environment(\.density) private var d

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: d.gridCard, maximum: d.gridCard + 40), spacing: d.cardGap, alignment: .top)],
                  alignment: .leading, spacing: d.v(16, 24)) {
            ForEach(0..<15, id: \.self) { _ in
                SkelCard(width: d.gridCard, imageHeight: d.gridCard)
            }
        }
        .padding(.horizontal, d.pad)
    }
}

/// Mirrors CollectionView's header: cover, title, artist, meta line, buttons.
private struct SkelCollectionHeader: View {
    let album: Bool
    @Environment(\.density) private var d

    var body: some View {
        HStack(alignment: .bottom, spacing: d.v(18, 26)) {
            Bar(width: d.headerArt, height: d.headerArt, radius: 10)
            VStack(alignment: .leading, spacing: d.v(6, 9)) {
                Bar(width: 260, height: d.headerTitle * 0.8, radius: 6)
                if album { Bar(width: 160, height: d.headerStrap * 0.75, radius: 5) }
                Bar(width: 200, height: 9)
                Bar(width: 320, height: 9).opacity(0.7)
                HStack(spacing: 10) {
                    Capsule().frame(width: 74, height: 30)
                    Capsule().frame(width: 96, height: 30)
                    Capsule().frame(width: 82, height: 30)
                }
                .padding(.top, d.v(6, 10))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Mirrors ArtistView's hero.
private struct SkelHero: View {
    @Environment(\.density) private var d

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
            HStack(alignment: .bottom, spacing: 16) {
                Circle().frame(width: d.v(42, 50), height: d.v(42, 50))
                VStack(alignment: .leading, spacing: 8) {
                    Bar(width: 280, height: d.heroTitle * 0.8, radius: 8)
                    Bar(width: 120, height: 10)
                }
            }
            .opacity(0.9)
            .padding(d.v(16, 24))
        }
        .frame(height: d.heroHeight)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0,
                                          bottomTrailingRadius: 0, topTrailingRadius: 20, style: .continuous))
    }
}

/// Mirrors SearchView's overview: "top result" card beside the first songs.
private struct SkelTopResultRow: View {
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            HStack(spacing: d.v(16, 24)) {
                Bar(width: 150, height: d.sectionTitle * 0.85, radius: 5).frame(width: d.topResult, alignment: .leading)
                Bar(width: 110, height: d.sectionTitle * 0.85, radius: 5)
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: d.v(16, 24)) {
                VStack(alignment: .leading, spacing: d.v(10, 14)) {
                    Bar(width: d.v(76, 100), height: d.v(76, 100), radius: 8)
                    Bar(width: 170, height: d.v(15, 18), radius: 5)
                    Bar(width: 110, height: 9)
                }
                .padding(d.v(14, 18))
                .frame(width: d.topResult, alignment: .topLeading)
                .frame(minHeight: d.v(160, 210), alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).opacity(0.5))
                SkelTrackRows(rows: 5, numbered: false, artwork: true, header: false)
            }
        }
        .padding(.horizontal, d.pad)
    }
}
