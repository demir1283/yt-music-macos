import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let engine = app.engine
        List {
            Section {
                row(.search)
                row(.home)
            }

            Section(M.t("Keşfet", "Explore")) {
                row(.explore)
                row(.charts)
                row(.moods)
                row(.newReleases)
                row(.podcasts)
            }

            if engine.loggedIn {
                Section(M.t("Koleksiyon", "Collection")) {
                    row(.library)
                    row(.liked)
                    row(.history)
                    row(.summary)
                }

                Section {
                    ForEach(engine.library.playlists.filter { $0.browseId != "VLLM" && $0.browseId != "VLSE" }) { item in
                        let target = BrowseTarget(browseId: item.browseId ?? "", params: item.params,
                                                  kind: "playlist", title: item.title)
                        SidebarRow(title: item.title, systemImage: "music.note.list", artwork: item.thumbnail,
                                   isSelected: app.section == .playlist(target)) {
                            app.select(.playlist(target))
                        }
                        .contextMenu { ItemMenu(item: item) }
                    }
                    if engine.libraryLoading && engine.library.playlists.isEmpty {
                        ProgressView().controlSize(.small)
                    }
                } header: {
                    HStack {
                        Text(M.t("Çalma Listeleri", "Playlists"))
                        Spacer()
                        Button { app.playlistEditor = .create(firstVideoId: nil) } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(M.t("Yeni çalma listesi", "New playlist"))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(ThemeStore.shared.background.isAnimated ? .hidden : .automatic)
        .modifier(SidebarFooterBar())
    }

    private func row(_ item: SidebarItem) -> some View {
        SidebarRow(title: item.title, systemImage: item.icon, isSelected: app.section == item) {
            app.select(item)
            if item == .search { app.searchFocusToken += 1 }
        }
    }
}

/// Plain-button sidebar row with a neutral selection pill and an accent-coloured icon or,
/// for playlists, a small cover (as in Apple Music). Every row has the same height, so
/// covers and icons line up.
struct SidebarRow: View {
    let title: String
    let systemImage: String
    /// A playlist's cover; without one the icon is shown.
    var artwork: String? = nil
    let isSelected: Bool
    let action: () -> Void

    private static let artSide: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                leading
                    .frame(width: 22, height: Self.artSide, alignment: .center)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
        .listRowBackground(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                }
            }
        )
    }

    @ViewBuilder private var leading: some View {
        if let artwork, !artwork.isEmpty {
            RemoteImage(url: artwork, placeholderIcon: systemImage, placeholderSize: 10)
                .frame(width: Self.artSide, height: Self.artSide)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.brand)
        }
    }
}

struct AccountFooter: View {
    @Environment(AppModel.self) private var app
    @ViewState var showMenu = false
    @ViewState var hover = false

    var body: some View {
        let engine = app.engine
        if engine.loggedIn {
            Button { showMenu.toggle() } label: {
                HStack(spacing: 10) {
                    Artwork(url: engine.account?.photo ?? engine.avatarURL, circle: true, placeholder: "person.fill")
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.account?.name ?? M.t("Hesabım", "My Account"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        if let handle = engine.account?.handle, !handle.isEmpty {
                            Text(handle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thickMaterial))
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hover ? 0.1 : 0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .popover(isPresented: $showMenu, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    menuButton(M.t("Kitaplığı Yenile", "Refresh Library"), "arrow.clockwise") { Task { await engine.loadLibrary() } }
                    menuButton(M.t("Bağlantıyı Yeniden Kur", "Reconnect"), "bolt.horizontal") { engine.reloadHome() }
                    Divider().padding(.vertical, 4)
                    menuButton(M.t("Ayarlar…", "Settings…"), "gearshape") { app.showSettings = true }
                    Divider().padding(.vertical, 4)
                    menuButton(M.t("Oturumu Kapat", "Sign Out"), "rectangle.portrait.and.arrow.right") { engine.signOut() }
                }
                .padding(6)
                .frame(width: 250)
            }
        } else if engine.booted {
            VStack(alignment: .leading, spacing: 8) {
                Text(M.t("Kitaplığın, beğendiklerin ve kişisel öneriler için oturum aç.", "Sign in for your library, your likes and personal recommendations."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { engine.showLogin() } label: {
                    Text(M.t("Oturum Aç", "Sign In"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.brand))
                }
                .buttonStyle(PressScaleStyle())
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thickMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private func menuButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        MenuRowButton(title: title, icon: icon) {
            showMenu = false
            action()
        }
    }
}

private struct MenuRowButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.brand : .clear))
            .foregroundStyle(hover ? Color.white : Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Pins the account card to the bottom of the sidebar. On macOS 26+ it is a safe-area
/// *bar*, so the list fades out under it instead of showing through.
private struct SidebarFooterBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.hard, for: .bottom)
                .safeAreaBar(edge: .bottom) {
                    footer
                }
        } else {
            content.safeAreaInset(edge: .bottom) {
                footer
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            UpdateCard()
            AccountFooter()
        }
        .animation(.soft, value: Updater.shared.available)
        .animation(.soft, value: Updater.shared.dismissed)
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }
}
