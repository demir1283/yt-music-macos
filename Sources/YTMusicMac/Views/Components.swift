import SwiftUI
import AppKit

// MARK: - Buttons

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// "▶︎ Çal" / "Karıştır" style capsule buttons used on detail headers.
struct CapsuleButton: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.brand)
                .padding(.horizontal, 18)
                .frame(height: 30)
                .background(
                    Capsule().fill(prominent ? Color.brand.opacity(hover ? 0.88 : 1) : Color.primary.opacity(hover ? 0.12 : 0.07))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
    }
}

/// Round accent play button (used on artwork and artist headers).
struct PlayCircle: View {
    var size: CGFloat = 36
    var playing = false
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: playing ? 0 : size * 0.03)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.brand))
                .scaleEffect(hover ? 1.06 : 1)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct ToolbarIconButton: View {
    let system: String
    var size: CGFloat = 15
    var active = false
    /// Gives the glyph a short bounce on every tap.
    var bounce = false
    var help: String = ""
    let action: () -> Void
    @ViewState var hover = false
    @ViewState var taps = 0

    var body: some View {
        Button {
            if bounce { taps += 1 }
            action()
        } label: {
            Image(systemName: system)
                .font(.system(size: size, weight: .medium))
                .symbolEffect(.bounce, value: taps)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(active ? Color.brand : (hover ? Color.primary : Color.secondary))
                .frame(width: size + 14, height: size + 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .help(help)
    }
}

// MARK: - Text

/// Text that underlines on hover when it navigates somewhere.
struct HoverLink: View {
    let text: String
    var font: Font = .system(size: 13)
    var color: Color = .secondary
    var action: (() -> Void)?
    @ViewState var hover = false

    init(_ text: String, font: Font = .system(size: 13), color: Color = .secondary, action: (() -> Void)? = nil) {
        self.text = text
        self.font = font
        self.color = color
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) {
                Text(text)
                    .underline(hover)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { h in
                hover = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        } else {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

struct ArtistByline: View {
    let artists: [ArtistRef]
    let fallback: String
    var font: Font = .system(size: 13)
    var color: Color = .secondary
    @Environment(AppModel.self) private var app

    var body: some View {
        if artists.isEmpty {
            Text(fallback)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(artists.enumerated()), id: \.offset) { i, a in
                    HoverLink(a.name, font: font, color: color) { app.openArtist(a.id) }
                    if i < artists.count - 1 {
                        Text(", ").font(font).foregroundStyle(color)
                    }
                }
            }
            .lineLimit(1)
        }
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text("E")
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .frame(width: 13, height: 13)
            .background(RoundedRectangle(cornerRadius: 2.5).fill(Color.secondary))
    }
}

/// Animated "now playing" bars. The bars are Core Animation layers animated by the
/// render server, so SwiftUI (and the window's layout) is not touched once per frame.
struct EqualizerIcon: View {
    var animating = true
    /// nil = the current accent colour.
    var color: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let activity = AppActivity.shared
        let moving = animating && activity.isActive && activity.isVisible && !reduceMotion
        EqualizerBars(color: NSColor(color ?? Color.brand), moving: moving)
            .frame(width: 15, height: 13)
            .allowsHitTesting(false)
    }
}

private struct EqualizerBars: NSViewRepresentable {
    let color: NSColor
    let moving: Bool

    func makeNSView(context: Context) -> EqualizerBarsView { EqualizerBarsView() }
    func updateNSView(_ v: EqualizerBarsView, context: Context) { v.update(color: color, moving: moving) }
}

final class EqualizerBarsView: NSView {
    private var bars: [CALayer] = []
    private var isMoving = false
    private static let rest: CGFloat = 4.0 / 13.0
    private static let durations: [Double] = [0.42, 0.57, 0.36, 0.5]
    private static let lows: [CGFloat] = [0.25, 0.35, 0.2, 0.3]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let l = CALayer()
            l.cornerRadius = 1
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.transform = CATransform3DMakeScale(1, Self.rest, 1)
            layer?.addSublayer(l)
            bars.append(l)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w: CGFloat = 2.5, gap: CGFloat = 1.5
        var x = (bounds.width - (4 * w + 3 * gap)) / 2 + w / 2
        for l in bars {
            l.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            l.position = CGPoint(x: x, y: 0)
            x += w + gap
        }
        CATransaction.commit()
    }

    func update(color: NSColor, moving: Bool) {
        var cg = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in bars { l.backgroundColor = cg }
        CATransaction.commit()
        guard moving != isMoving else { return }
        isMoving = moving
        for (i, l) in bars.enumerated() {
            l.removeAllAnimations()
            guard moving else { continue }
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = Self.lows[i]
            a.toValue = 1.0
            a.duration = Self.durations[i]
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.timeOffset = Double(i) * 0.13
            l.add(a, forKey: "eq")
        }
    }
}

// MARK: - Artwork

struct Artwork: View {
    let url: String?
    var cornerRadius: CGFloat = 6
    var circle = false
    var placeholder: String = "music.note"

    var body: some View {
        RemoteImage(url: url, placeholderIcon: placeholder)
            .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
            .overlay {
                if circle {
                    Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                }
            }
    }
}

// MARK: - States

/// Loading previews: see PageSkeleton (Skeletons.swift).

struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("İçerik yüklenemedi")
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Tekrar Dene", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(32)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            if !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
    }
}

/// Section title in the Apple Music style ("Başlık  ›").
struct SectionTitle: View {
    let title: String
    var subtitle: String?
    var action: (() -> Void)?
    @ViewState var hover = false
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle.uppercased(with: Locale(identifier: M.turkish ? "tr_TR" : "en_US")))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: d.sectionTitle, weight: .bold))
                    .lineLimit(1)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(hover ? Color.primary : Color.secondary)
                }
            }
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture { action?() }
        }
    }
}

struct FilterChips: View {
    let chips: [FilterChip]
    let selected: FilterChip?
    let onSelect: (FilterChip?) -> Void
    @Environment(\.density) private var d

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tümü", isOn: selected == nil) { onSelect(nil) }
                ForEach(chips) { c in
                    chip(c.title, isOn: selected?.id == c.id) {
                        onSelect(selected?.id == c.id ? nil : c)
                    }
                }
            }
            .padding(.horizontal, d.pad)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(isOn ? Color.brand : Color.primary.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Context menu

struct ItemMenu: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @Environment(\.playlistEdit) private var playlistEdit

    var body: some View {
        Button("Çal") { app.play(item) }
        if item.playlistId != nil {
            Button("Karışık Çal") { app.shuffle(item) }
        }
        if item.isTrack {
            Button("Şarkı Radyosunu Başlat") { app.startRadio(item) }
        }
        if item.isTrack, let v = item.videoId, app.engine.loggedIn {
            Divider()
            Button("Çalma Listesine Ekle…") { app.addToPlaylist(item) }
            if let edit = playlistEdit {
                Button(edit.removeLabel) { edit.remove(item) }
                if edit.canMove, item.setVideoId != nil {
                    Button("Yukarı Taşı") { edit.move(item, -1) }
                    Button("Aşağı Taşı") { edit.move(item, 1) }
                }
            }
            Button("Beğen") { app.engine.rate(videoId: v, status: "LIKE") }
            if app.engine.isDisliked(v) {
                Button("Beğenmemeyi Geri Al") {
                    app.engine.rate(videoId: v, status: "INDIFFERENT")
                    app.unhide(item)
                }
            } else {
                Button("Beğenmedim (bana önerme)") {
                    app.engine.rate(videoId: v, status: "DISLIKE")
                    app.hide(item)
                }
            }
        } else if !item.isTrack, item.kind != "category" {
            Divider()
            Button("Bana önerme") { app.hide(item) }
        }
        if !item.artists.isEmpty {
            Divider()
            ForEach(item.artists, id: \.id) { a in
                Button("Sanatçıya Git: \(a.name)") { app.openArtist(a.id) }
            }
        }
        if let album = item.album {
            Button("Albüme Git") { app.openAlbum(album.id) }
        }
        Divider()
        Button("Bağlantıyı Kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(shareLink, forType: .string)
        }
    }

    private var shareLink: String {
        if let v = item.videoId { return "https://music.youtube.com/watch?v=\(v)" }
        if let p = item.playlistId { return "https://music.youtube.com/playlist?list=\(p)" }
        if let id = item.browseId {
            return item.isArtist ? "https://music.youtube.com/channel/\(id)" : "https://music.youtube.com/browse/\(id)"
        }
        return "https://music.youtube.com"
    }
}

/// Offset reporting for "show compact header after scrolling" effects.
struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Page chrome

extension View {
    /// Floating player bar under the page (scroll content passes beneath it) and a
    /// legible scroll edge under the Liquid Glass toolbar.
    func pageChrome() -> some View {
        modifier(PageChrome())
    }
}

private struct PageChrome: ViewModifier {
    @Environment(\.density) private var d
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlayerBar()
                    .padding(.horizontal, d.v(10, 16))
                    .padding(.top, d.v(4, 6))
                    .padding(.bottom, d.v(8, 12))
            }
            .modifier(ToolbarEdge())
    }
}

/// Fades a view in when it appears. Only opacity changes, so layout never animates.
private struct FadeIn: ViewModifier {
    @ViewState var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                withAnimation(.easeOut(duration: 0.35)) { shown = true }
            }
    }
}

extension View {
    func fadeIn() -> some View { modifier(FadeIn()) }
}

/// The toolbar has no band of its own: the page is a rounded card below it.
private struct ToolbarEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

// MARK: - Marquee

/// One line that doesn't fit: shortly after it appears (and again on hover) it glides to
/// show its end, pauses, glides back and then rests at the start, with the overflow
/// softly faded out at the edge.
struct Marquee<Content: View>: View {
    /// A new value restarts the glide (e.g. the track id).
    let id: String
    @ViewBuilder let content: () -> Content

    @ViewState var contentWidth: CGFloat = 0
    @ViewState var boxWidth: CGFloat = 0
    @ViewState var offset: CGFloat = 0
    @ViewState var running = false

    private var overflow: CGFloat { max(0, contentWidth - boxWidth) }

    var body: some View {
        let over = overflow > 2
        // The box is exactly as wide as the space offered: a hidden 1-point-wide copy of
        // the line gives it the line's height without letting a long line widen it (a
        // long title used to stretch the box, so it never looked too long to scroll).
        content()
            .fixedSize()
            .hidden()
            .frame(width: 1, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { box in
                    content()
                        .fixedSize()
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { contentWidth = g.size.width }
                                .onChange(of: g.size.width) { _, w in contentWidth = w }
                        })
                        .offset(x: -offset)
                        .frame(width: box.size.width, height: box.size.height, alignment: .leading)
                        .clipped()
                        .mask {
                            // Fade the cut edge(s) instead of a hard clip.
                            LinearGradient(stops: [
                                .init(color: offset > 1 ? .clear : .black, location: 0),
                                .init(color: .black, location: over ? 0.04 : 0),
                                .init(color: .black, location: over ? 0.9 : 1),
                                .init(color: over && offset < overflow - 1 ? .clear : .black, location: 1),
                            ], startPoint: .leading, endPoint: .trailing)
                        }
                        .onAppear { boxWidth = box.size.width }
                        .onChange(of: box.size.width) { _, w in boxWidth = w }
                }
            }
            .onHover { inside in
                if inside { Task { await glide() } }
            }
            .task(id: id) {
                offset = 0
                running = false
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                await glide()
            }
    }

    private func glide() async {
        guard !running, overflow > 2 else { return }
        running = true
        defer { running = false }
        let distance = overflow
        let duration = max(1.2, Double(distance) / 32)
        withAnimation(.linear(duration: duration)) { offset = distance }
        try? await Task.sleep(nanoseconds: UInt64((duration + 1.3) * 1_000_000_000))
        withAnimation(.easeInOut(duration: 0.7)) { offset = 0 }
        try? await Task.sleep(nanoseconds: 800_000_000)
    }
}
