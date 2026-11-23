import SwiftUI

/// The notifications panel under the bell (Inbox): drawn by the app inside the window, at
/// its top right corner, so it never reaches past the window. A click outside or Esc closes
/// it. A row opens its song, release or channel; the play button beside it plays it there.
struct InboxPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    let maxHeight: CGFloat

    var body: some View {
        let inbox = Inbox.shared
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(M.t("Bildirimler", "Notifications"))
                        .font(.system(size: 15, weight: .bold))
                    Text(M.t("Son \(PersonalHome.notificationDays) gün · YouTube ve YouTube Music",
                             "Last \(PersonalHome.notificationDays) days · YouTube and YouTube Music"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ToolbarIconButton(system: "arrow.clockwise", size: 12, help: M.t("Yenile", "Refresh")) {
                    Task { await inbox.refresh() }
                }
                .rotationEffect(.degrees(inbox.loading ? 360 : 0))
                .animation(inbox.loading ? .linear(duration: 1).repeatForever(autoreverses: false) : .soft,
                           value: inbox.loading)
                .disabled(inbox.loading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.6)

            content(inbox)
        }
        .frame(width: d.v(360, 400))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.thickMaterial))
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.brand.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
        // As tall as its rows, up to `maxHeight` (then the rows scroll).
        .frame(maxHeight: maxHeight, alignment: .top)
        // Esc closes it.
        .background(Button("") { app.closeInbox() }.keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false))
    }

    @ViewBuilder
    private func content(_ inbox: Inbox) -> some View {
        if !app.engine.loggedIn {
            note("bell.slash", M.t("Bildirimler için oturum aç.", "Sign in to see notifications."))
        } else if inbox.items.isEmpty && (inbox.loading || inbox.loadedAt == nil) {
            VStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08)).frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 180, height: 9)
                            Capsule().fill(Color.primary.opacity(0.06)).frame(width: 110, height: 8)
                        }
                        Spacer()
                    }
                }
            }
            .padding(12)
        } else if inbox.items.isEmpty {
            note("bell", M.t("Son \(PersonalHome.notificationDays) günde yeni bir şey yok.",
                             "Nothing new in the last \(PersonalHome.notificationDays) days."))
        } else {
            // A few rows: just the rows. More than fit: they scroll.
            ViewThatFits(in: .vertical) {
                rows(inbox)
                ScrollView { rows(inbox) }
                    .scrollIndicators(.automatic)
            }
        }
    }

    private func rows(_ inbox: Inbox) -> some View {
        VStack(spacing: 2) {
            ForEach(inbox.items) { item in
                InboxRow(item: item, isNew: inbox.isNew(item))
            }
        }
        .padding(6)
    }

    private func note(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.secondary)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

private struct InboxRow: View {
    let item: MediaItem
    let isNew: Bool
    @Environment(AppModel.self) private var app
    @ViewState var hover = false

    private var isCurrent: Bool {
        guard let v = item.videoId else { return false }
        return app.engine.track?.videoId == v
    }

    var body: some View {
        HStack(spacing: 10) {
            Artwork(url: item.thumbnail, cornerRadius: 7)
                .frame(width: 52, height: 52)
                .overlay(alignment: .bottomTrailing) {
                    // The channel's picture at the corner of the cover.
                    if let avatar = item.avatar {
                        Artwork(url: avatar, circle: true, placeholder: "person.fill")
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                            .offset(x: 5, y: 5)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: isNew ? .semibold : .medium))
                    .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            Spacer(minLength: 6)
            // Play on hover; otherwise the dot of something new. Same width either way.
            ZStack {
                if hover || (isCurrent && app.engine.isPlaying) {
                    PlayCircle(size: 28, playing: isCurrent && app.engine.isPlaying) {
                        if isCurrent { app.engine.togglePlay() } else { app.play(item) }
                    }
                    .transition(.opacity)
                } else if isNew {
                    Circle().fill(Color.brand).frame(width: 7, height: 7)
                        .transition(.opacity)
                }
            }
            .frame(width: 30)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .onTapGesture {
            app.closeInbox()
            app.open(item)
        }
        .contextMenu { ItemMenu(item: item) }
        .help(item.title)
    }
}
