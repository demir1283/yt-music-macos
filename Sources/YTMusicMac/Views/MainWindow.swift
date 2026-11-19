import SwiftUI
import AppKit

struct MainWindow: View {
    @Environment(AppModel.self) private var app
    /// One strength for every surface, so the sidebar and side panel look the same.
    static let paneStrength = 0.7

    var body: some View {
        @Bindable var app = app
        @Bindable var engine = app.engine

        GeometryReader { root in
        let density = Density.forWindow(root.size)
        ZStack(alignment: .bottomLeading) {
            // The side panel is a window column next to the split view (not inside the
            // navigation stack's area), so it gets its own clicks and the content resizes.
            HStack(spacing: 0) {
                NavigationSplitView {
                    Sidebar()
                        .navigationSplitViewColumnWidth(min: 180, ideal: density.sidebar, max: 300)
                        .background(AmbientField(strength: Self.paneStrength).ignoresSafeArea())
                } detail: {
                    // A plain page stack instead of NavigationStack: AppKit's stack paints an
                    // opaque window-coloured background behind pushed pages, which hid the
                    // moving background (and the toolbar strip) on artist / album pages.
                    PageStack(section: app.section, path: app.path)
                    .background(ContentBackground())
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 4)
                    .padding(.leading, density.gutter)
                    .padding(.trailing, density.gutter)
                    .padding(.bottom, density.gutter)
                    // The window's own surface (gutters and the toolbar strip with the search
                    // field) carries the moving background; the card above is see-through.
                    .background(AmbientField(strength: Self.paneStrength).ignoresSafeArea())
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if !app.path.isEmpty {
                            Button { app.back() } label: {
                                Image(systemName: "chevron.left")
                            }
                            .help(M.t("Geri (⌘[)", "Back (⌘[)"))
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        ToolbarSearchField()
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { app.togglePanel() } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .help(app.isPanelVisible ? M.t("Sözleri ve sırayı gizle (⌥⌘P)", "Hide lyrics and queue (⌥⌘P)") : M.t("Sözleri ve sırayı göster (⌥⌘P)", "Show lyrics and queue (⌥⌘P)"))
                    }
                }

                if app.isPanelVisible {
                    SidePanel()
                        .frame(width: density.sidePanel)
                        .padding(.top, 4)
                        .padding(.trailing, density.gutter)
                        .padding(.bottom, density.gutter)
                        .background(AmbientField(strength: Self.paneStrength).ignoresSafeArea())
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: app.isPanelVisible)


            if !engine.booted && engine.loadError != nil {
                BootOverlay().zIndex(3)
            }
        }
        .sheet(item: $engine.webSheet) { kind in
            WebSheet(kind: kind)
        }
        .sheet(isPresented: $app.showSettings) {
            SettingsView()
        }
        .sheet(item: $app.addToPlaylistTarget) { song in
            AddToPlaylistSheet(song: song)
        }
        .sheet(item: $app.playlistEditor) { mode in
            PlaylistEditorSheet(mode: mode)
        }
        .task(id: engine.track?.videoId) {
            await LyricsCenter.shared.load(engine.track)
        }
        .environment(\.density, density)
        .environment(\.ambientFieldSize, root.frame(in: .global).size == .zero ? root.size
                     : CGSize(width: root.frame(in: .global).maxX, height: root.frame(in: .global).maxY))
        }
        .tint(Color.brand)
    }
}

/// Centered, translucent search field in the window toolbar (always available).
struct ToolbarSearchField: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool
    @ViewState var hover = false
    /// Whether the field is being typed in, read from AppKit (`focused` doesn't follow a
    /// text field in the toolbar).
    @ViewState var editing = false

    private var active: Bool { focused || editing }

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(active ? Color.brand : Color.secondary)
            TextField(SearchField.placeholder, text: $app.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1)
                .focused($focused)
                .onSubmit {
                    SearchSuggestionModel.shared.dismiss()
                    SearchField.endEditing()
                    if app.section != .search { app.select(.search) }
                }
                .onExitCommand { focused = false }   // Esc: stop typing, space plays again
            if !app.searchQuery.isEmpty {
                Button {
                    app.searchQuery = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minWidth: 260, idealWidth: 420, maxWidth: 460)
        .frame(height: 30)
        .searchCapsule(active: active, hover: hover)
        .contentShape(Capsule())
        .onHover { hover = $0 }
        .onTapGesture { focused = true }
        .onChange(of: app.searchQuery) { _, q in
            // One line only: a line break (⌥↩, ⌃↩ or pasted text) becomes a space.
            if q.contains(where: \.isNewline) {
                app.searchQuery = q.split(whereSeparator: \.isNewline).joined(separator: " ")
                return
            }
            if !q.trimmingCharacters(in: .whitespaces).isEmpty && app.section != .search {
                app.select(.search)
            }
            SearchSuggestionModel.shared.update(q, engine: app.engine)
        }
        .onChange(of: app.searchFocusToken) { _, _ in focused = true }
        .onChange(of: focused) { _, _ in showSuggestions() }
        .onAppear {
            // Clicking back into the field opens its suggestions again.
            SuggestionPanel.shared.watchClicks {
                editing = true
                SearchSuggestionModel.shared.reopen(app.searchQuery, engine: app.engine)
                showSuggestions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidBeginEditingNotification)) { note in
            guard SearchField.isSearchField(note.object) else { return }
            editing = true
            showSuggestions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSControl.textDidEndEditingNotification)) { note in
            guard SearchField.isSearchField(note.object) else { return }
            editing = false
            showSuggestions()
        }
        .onChange(of: SearchSuggestionModel.shared.layoutKey) { _, _ in showSuggestions() }
    }

    /// Opens the suggestion list under the field while you type in it, closes it otherwise.
    private func showSuggestions() {
        let model = SearchSuggestionModel.shared
        if active, !model.dismissed, !model.rows.isEmpty,
           !app.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            SuggestionPanel.shared.show(height: model.height, app: app)
        } else {
            SuggestionPanel.shared.hide()
        }
    }
}

private extension View {
    /// The search field's own capsule. On macOS 26 the toolbar already sets the item on a
    /// glass capsule, so a second one would show around it: there the glass is the field.
    @ViewBuilder
    func searchCapsule(active: Bool, hover: Bool) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            self
                .background(Capsule().fill(Color.primary.opacity(active ? 0.09 : (hover ? 0.07 : 0.045))))
                .overlay(Capsule().strokeBorder(active ? Color.brand.opacity(0.6) : Color.primary.opacity(0.08),
                                                lineWidth: active ? 1.2 : 0.5))
        }
    }
}

/// Root content for a sidebar destination.
struct RootPage: View {
    let item: SidebarItem

    var body: some View {
        Group {
            switch item {
            case .home:
                HomeView()
            case .search:
                SearchView()
            case .library:
                LibraryView()
            case .liked, .playlist:
                if let t = item.browseTarget { CollectionView(target: t) }
            case .newReleases:
                NewReleasesView()
            default:
                if let t = item.browseTarget { BrowsePageView(target: t) }
            }
        }
    }
}

/// The detail column's pages: the section's root page, or the last page opened from it.
/// Only the page on screen exists; going back shows the one below from memory (PageCache).
struct PageStack: View {
    let section: SidebarItem
    let path: [BrowseTarget]

    private struct Key: Hashable {
        let section: SidebarItem
        let top: BrowseTarget?
    }

    /// The old page fades out quickly, the new one fades in just after — no spinner,
    /// no sliding, nothing overlapping for long.
    private static let fade = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.26).delay(0.05)),
        removal: .opacity.animation(.easeIn(duration: 0.12)))

    var body: some View {
        let key = Key(section: section, top: path.last)
        ZStack {
            Group {
                if let top = path.last {
                    DetailPage(target: top)
                } else {
                    RootPage(item: section)
                }
            }
            .id(key)
            .transition(Self.fade)
        }
        .animation(.easeInOut(duration: 0.26), value: key)
    }
}

/// Pushed destination (album, playlist, artist, generic page).
struct DetailPage: View {
    let target: BrowseTarget

    var body: some View {
        // Each destination is its own view: state never carries over between pages.
        Group {
            switch target.kind {
            case "artist":
                ArtistView(target: target)
            case "album", "playlist", "podcast":
                CollectionView(target: target)
            default:
                BrowsePageView(target: target)
            }
        }
        .id(target)
    }
}

struct BootOverlay: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            VStack(spacing: 16) {
                AppGlyph(size: 64)
                if let err = app.engine.loadError {
                    Text(M.t("YouTube Music'e ulaşılamadı", "Couldn't reach YouTube Music")).font(.headline)
                    Text(err).font(.callout).foregroundStyle(.secondary)
                    Button(M.t("Tekrar Dene", "Try Again")) { app.engine.reloadHome() }
                } else {
                    ProgressView().controlSize(.small)
                    Text(M.t("YouTube Music'e bağlanılıyor…", "Connecting to YouTube Music…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The app's own icon (from the bundle), used on the start screen and sign-in banner.
struct AppGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
