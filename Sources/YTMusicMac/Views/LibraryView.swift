import SwiftUI

/// Kitaplık: the account's playlists, albums and artists, as tiles or rows, in the order
/// chosen for each list.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var layouts: [LibraryFilter: LibraryLayout] =
        Dictionary(uniqueKeysWithValues: LibraryFilter.allCases.map { ($0, LibraryLayout.saved($0)) })

    private var list: LibraryFilter { app.libraryFilter }
    private var layout: LibraryLayout { layouts[list] ?? .grid }

    var body: some View {
        let engine = app.engine
        let items = engine.library[list]
        ScrollView {
            VStack(alignment: .leading, spacing: d.v(14, 20)) {
                bar(count: items.count, paging: engine.libraryPaging.contains(list))

                Group {
                    if engine.libraryLoading && items.isEmpty {
                        PageSkeleton(layout: layout == .grid ? .cardGrid : .songList)
                    } else if items.isEmpty {
                        EmptyStateView(systemImage: "square.stack", title: M.t("Burada henüz bir şey yok", "Nothing here yet"))
                    } else if layout == .grid {
                        CardGrid(items: items)
                    } else {
                        LibraryRows(items: items)
                    }
                }
                .animation(.soft, value: items.map(\.id))
                .id("\(list.rawValue)-\(layout.rawValue)")
                .transition(.opacity)
            }
            .padding(.vertical, d.pageTop)
        }
        .animation(.soft, value: list)
        .animation(.soft, value: layout)
        .navigationTitle(M.t("Kitaplık", "Library"))
        .pageChrome()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await app.engine.loadLibrary() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(M.t("Kitaplığı yenile", "Refresh library"))
            }
        }
    }

    /// The lists as chips (like the home page's), then the count, the order and the layout.
    private func bar(count: Int, paging: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(LibraryFilter.allCases) { f in
                ChipButton(title: f.title, isOn: list == f) { app.libraryFilter = f }
            }
            Spacer(minLength: 12)
            if count > 0 {
                HStack(spacing: 6) {
                    if paging {
                        ProgressView().controlSize(.mini)
                            .help(M.t("Kalanı yükleniyor", "Loading the rest"))
                    }
                    Text(M.t("\(count) öğe", count == 1 ? "1 item" : "\(count) items"))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .transition(.opacity)
            }
            LibrarySortMenu(sort: app.engine.librarySorts[list] ?? .recent) { app.engine.sortLibrary(list, $0) }
            LibraryLayoutSwitch(layout: layout) { new in
                layouts[list] = new
                new.save(for: list)
            }
        }
        .padding(.horizontal, d.pad)
    }
}

/// "Son eklenen": the order of the list, in a chip.
private struct LibrarySortMenu: View {
    let sort: LibrarySort
    let choose: (LibrarySort) -> Void
    @ViewState var hover = false

    var body: some View {
        Menu {
            ForEach(LibrarySort.allCases) { s in
                Button { choose(s) } label: {
                    if s == sort { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(sort.title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(Capsule().fill(Color.primary.opacity(hover ? 0.11 : 0.07)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hover = $0 }
        .help(M.t("Sırala", "Sort"))
    }
}

/// Tiles or rows: two small glyphs in one capsule.
private struct LibraryLayoutSwitch: View {
    let layout: LibraryLayout
    let choose: (LibraryLayout) -> Void

    var body: some View {
        HStack(spacing: 2) {
            glyph(.grid, "square.grid.2x2", M.t("Kutucuk", "Tiles"))
            glyph(.list, "list.bullet", M.t("Liste", "List"))
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
    }

    private func glyph(_ value: LibraryLayout, _ icon: String, _ help: String) -> some View {
        let on = layout == value
        return Button { choose(value) } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? Color.white : Color.secondary)
                .frame(width: 30, height: 22)
                .background(Capsule().fill(on ? Color.brand : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }
}

/// The list as rows: picture, name, what it is, and play on hover.
private struct LibraryRows: View {
    let items: [MediaItem]
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        let hidden = app.hiddenKeys
        let shown = hidden.isEmpty ? items : items.filter { !hidden.contains($0.recommendationKey) }
        LazyVStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, item in
                LibraryRow(item: item, striped: i % 2 == 0)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, d.pad - 10)
    }
}

private struct LibraryRow: View {
    let item: MediaItem
    let striped: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var hover = false

    private var canPlay: Bool {
        item.play != nil || item.videoId != nil || item.playlistId != nil || item.kind == "album"
    }

    var body: some View {
        let art = d.v(40, 48)
        HStack(spacing: 12) {
            Artwork(url: item.thumbnail, cornerRadius: 5, circle: item.isArtist,
                    placeholder: item.isArtist ? "person.fill" : "music.note")
                .frame(width: art, height: art)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                Text(item.subtitle.isEmpty ? item.typeLabel : item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canPlay {
                PlayCircle(size: 28) { app.play(item) }
                    .opacity(hover ? 1 : 0)
                    .help(M.t("Çal", "Play"))
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
        .padding(.horizontal, 10)
        .frame(height: d.v(54, 62))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hover ? Color.primary.opacity(0.09) : (striped ? Color.primary.opacity(0.035) : .clear))
        )
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .soft)
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}
