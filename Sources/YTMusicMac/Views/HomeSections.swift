import SwiftUI
import AppKit

// Rows only the home page has (see PersonalHome for what fills them).

// MARK: - Colours

/// Stable colours for station cards and mix bands (the same name always gets the same one).
enum HomePalette {
    static let colors: [Color] = [
        Color(red: 0.98, green: 0.42, blue: 0.38), Color(red: 0.53, green: 0.89, blue: 0.82),
        Color(red: 0.49, green: 0.69, blue: 0.97), Color(red: 0.98, green: 0.93, blue: 0.38),
        Color(red: 0.72, green: 0.68, blue: 0.98), Color(red: 0.97, green: 0.58, blue: 0.77),
        Color(red: 0.58, green: 0.87, blue: 0.47), Color(red: 0.99, green: 0.70, blue: 0.40),
    ]

    static func color(for key: String) -> Color {
        let hash = key.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value }
        return colors[Int(hash % UInt32(colors.count))]
    }
}

/// The coloured name band on mix covers ("Techno Mix", "ARTBAT Mix").
struct MixBand: View {
    let title: String
    let width: CGFloat

    var body: some View {
        let color = HomePalette.color(for: title)
        HStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(0.25)).frame(width: 4)
            Text(title)
                .font(.system(size: max(11, width * 0.085), weight: .bold))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 7)
            Spacer(minLength: 0)
        }
        .frame(height: max(20, width * 0.15))
        .background(color)
        .padding(.bottom, width * 0.12)
        .allowsHitTesting(false)
    }
}

// MARK: - Greeting + tiles

/// "İyi akşamlar" and eight compact tiles in two rows, like the top of Spotify's home.
struct ShortcutGrid: View {
    let section: Shelf
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: d.v(10, 14)) {
            Text(section.title)
                .font(.system(size: d.v(22, 26), weight: .bold))
                .padding(.horizontal, d.pad)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: d.v(8, 10)), count: 4),
                      spacing: d.v(8, 10)) {
                ForEach(section.items) { item in
                    ShortcutTile(item: item)
                }
            }
            .padding(.horizontal, d.pad)
        }
    }
}

struct ShortcutTile: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var hover = false

    private var isCurrent: Bool {
        guard let v = item.videoId else { return false }
        return app.engine.track?.videoId == v
    }

    var body: some View {
        let side = d.v(48, 56)
        let playing = isCurrent && app.engine.isPlaying
        HStack(spacing: 10) {
            Artwork(url: item.thumbnail, cornerRadius: 0, circle: item.isArtist,
                    placeholder: item.isArtist ? "person.fill" : "music.note")
                .frame(width: side, height: side)
            Text(item.title)
                .font(.system(size: d.v(12.5, 13.5), weight: .semibold))
                .foregroundStyle(isCurrent ? Color.brand : Color.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hover || playing {
                PlayCircle(size: d.v(28, 32), playing: playing) {
                    if isCurrent { app.engine.togglePlay() } else { app.play(item) }
                }
                .padding(.trailing, 8)
                .transition(.opacity)
            }
        }
        .frame(height: side)
        .background(Color.primary.opacity(hover ? 0.12 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.12))
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

// MARK: - "Senin için seçildi" + stations

/// Left: one pick at a time (it slides to the next every few seconds). Right: artist radios.
/// Items of kind "artistradio" are the stations; the rest are the picks.
struct PicksRow: View {
    let section: Shelf
    @Environment(\.density) private var d

    var body: some View {
        let picks = section.items.filter { $0.kind != "artistradio" }
        let stations = section.items.filter { $0.kind == "artistradio" }
        HStack(alignment: .top, spacing: d.v(22, 32)) {
            if !picks.isEmpty {
                VStack(alignment: .leading, spacing: d.v(8, 10)) {
                    SectionTitle(title: "Senin için seçildi", subtitle: nil)
                    FeaturedPick(items: picks)
                }
                .frame(width: d.v(400, 480), alignment: .leading)
            }
            if !stations.isEmpty {
                VStack(alignment: .leading, spacing: d.v(8, 10)) {
                    SectionTitle(title: section.title, subtitle: section.strapline)
                    StationsCarousel(stations: stations)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, d.pad)
    }
}

private struct FeaturedPick: View {
    let items: [MediaItem]
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var index = 0
    @ViewState var hover = false

    private static let interval: UInt64 = 8_000_000_000

    var body: some View {
        let activity = AppActivity.shared
        let running = items.count > 1 && !hover && activity.isActive && activity.isVisible
        let current = min(index, max(items.count - 1, 0))
        let cover = d.v(170, 204)
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .leading) {
                if items.indices.contains(current) {
                    let item = items[current]
                    HStack(alignment: .center, spacing: d.v(16, 22)) {
                        Artwork(url: item.thumbnail, cornerRadius: 8)
                            .frame(width: cover, height: cover)
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                        VStack(alignment: .leading, spacing: 6) {
                            Text([item.typeLabel, item.bylineText].filter { !$0.isEmpty }.joined(separator: " • "))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(item.title)
                                .font(.system(size: d.v(24, 28), weight: .heavy))
                                .lineLimit(2)
                            Text(PersonalHome.isOfficial(item) ? "Editörlerin seçimi" : "Yeni çıkan")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                PlayCircle(size: d.v(36, 40)) { app.play(item) }
                                CapsuleButton(title: "Aç", systemImage: "chevron.right") { app.open(item) }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .id(item.id)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
                    .contentShape(Rectangle())
                    .onTapGesture { app.open(item) }
                    .contextMenu { ItemMenu(item: item) }
                }
            }
            .frame(height: cover, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            // The dots sit in their own row under the pick, clear of its buttons.
            if items.count > 1 {
                // Each dot picks its slide; the hit area is larger than the dot.
                HStack(spacing: 0) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Button {
                            withAnimation(.easeInOut(duration: 0.5)) { index = i }
                        } label: {
                            Capsule()
                                .fill(i == current ? Color.primary : Color.primary.opacity(hover ? 0.45 : 0.3))
                                .frame(width: i == current ? 16 : 7, height: 7)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("\(i + 1). öneri")
                    }
                }
            }
        }
        .scrollAwareHover($hover)
        .task(id: running) {
            guard running else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.interval)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.55)) { index = (min(index, items.count - 1) + 1) % items.count }
            }
        }
    }
}

/// The stations, scrolled like every other row: by trackpad, or with the arrows that show
/// on hover when the cards don't all fit.
private struct StationsCarousel: View {
    let stations: [MediaItem]
    @Environment(\.density) private var d
    @ViewState var hover = false
    @ViewState var position: String? = nil
    @ViewState var viewport: CGFloat = 0

    var body: some View {
        let side = d.card
        let content = CGFloat(stations.count) * side + d.cardGap * CGFloat(max(stations.count - 1, 0)) + d.pad
        let overflows = content > viewport + 1
        let index = position.flatMap { p in stations.firstIndex { $0.id == p } } ?? 0
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: d.cardGap) {
                ForEach(stations) { station in
                    StationCard(item: station, side: side)
                        .id(station.id)
                }
            }
            .scrollTargetLayout()
            .padding(.trailing, d.pad)
        }
        .scrollPosition(id: $position, anchor: .leading)
        .frame(height: side + d.v(44, 50))
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
            if hover && overflows && index < stations.count - 3 {
                CarouselArrow(system: "chevron.right") { move(3) }
                    .padding(.trailing, 10)
            }
        }
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
    }

    private func move(_ delta: Int) {
        guard !stations.isEmpty else { return }
        let current = position.flatMap { p in stations.firstIndex { $0.id == p } } ?? 0
        let target = max(0, min(stations.count - 1, current + delta))
        withAnimation(.easeInOut(duration: 0.4)) { position = stations[target].id }
    }
}

/// An artist's radio: coloured square, the artist's portrait, "RADYO".
private struct StationCard: View {
    let item: MediaItem
    let side: CGFloat
    @Environment(AppModel.self) private var app
    @ViewState var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                HomePalette.color(for: item.title)
                Artwork(url: item.thumbnail, circle: true, placeholder: "person.fill")
                    .frame(width: side * 0.56, height: side * 0.56)
                    .offset(y: -side * 0.05)
                Text("RADYO")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.black.opacity(0.75))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                Text(item.title)
                    .font(.system(size: side * 0.13, weight: .heavy))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                if hover {
                    PlayCircle(size: 32) { app.play(item) }
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(hover ? 0.25 : 0.12), radius: hover ? 10 : 4, y: 3)
            Text(item.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: side, alignment: .leading)
        }
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
        .onTapGesture { app.play(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

// MARK: - "X ile benzer diğer müzikler"

/// A row headed by an artist's portrait (`section.top`).
struct SimilarRow: View {
    let section: Shelf
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d

    var body: some View {
        VStack(alignment: .leading, spacing: d.v(8, 10)) {
            HStack(spacing: 12) {
                if let artist = section.top {
                    Artwork(url: artist.thumbnail, circle: true, placeholder: "person.fill")
                        .frame(width: d.v(40, 48), height: d.v(40, 48))
                        .onTapGesture { app.open(artist) }
                }
                SectionTitle(title: section.title, subtitle: section.strapline)
            }
            .padding(.horizontal, d.pad)
            CardCarousel(section: Shelf(id: section.id + "-row", title: "", strapline: nil, layout: "cards",
                                        items: section.items, more: nil, continuation: nil, top: nil))
        }
    }
}

// MARK: - Living cards

/// Wide cards in two columns, each with its own heading above it (the lines of
/// `section.strapline`, one per card), on the artist's banner drifting slowly behind.
struct SpotlightGrid: View {
    let section: Shelf
    @Environment(\.density) private var d

    var body: some View {
        let captions = (section.strapline ?? "").components(separatedBy: "\n")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: d.v(14, 20), alignment: .top), count: 2),
                  spacing: d.v(20, 28)) {
            ForEach(Array(section.items.enumerated()), id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(i < captions.count ? captions[i] : "")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    SpotlightCard(item: item)
                        .frame(height: d.v(220, 260))
                }
            }
        }
        .padding(.horizontal, d.pad)
    }
}

private struct SpotlightCard: View {
    let item: MediaItem
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var hover = false

    var body: some View {
        let activity = AppActivity.shared
        let cover = d.v(84, 100)
        ZStack(alignment: .topLeading) {
            DriftingArtwork(url: item.banner ?? item.thumbnail, moving: activity.isActive && activity.isVisible)
            LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.35), .black.opacity(0.1)],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    Artwork(url: item.thumbnail, cornerRadius: 6, circle: item.kind == "artistradio",
                            placeholder: item.kind == "artistradio" ? "person.fill" : "music.note")
                        .frame(width: cover, height: cover)
                        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.system(size: d.v(24, 30), weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                        Text(item.typeLabel.isEmpty ? "YouTube Music" : "\(item.typeLabel) • YouTube Music")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    Text(item.subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if hover {
                        PlayCircle(size: 44) { app.play(item) }
                            .transition(.opacity)
                    }
                }
            }
            .padding(d.v(18, 24))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
        .onTapGesture { app.open(item) }
        .contextMenu { ItemMenu(item: item) }
    }
}

/// A cover that slowly zooms and pans, back and forth. The motion is a Core Animation
/// animation, run by the system's compositor rather than by the app (the app does no work
/// per frame); it stops when the app isn't in front or the card scrolls away.
struct DriftingArtwork: NSViewRepresentable {
    let url: String?
    let moving: Bool

    func makeNSView(context: Context) -> DriftView { DriftView() }

    func updateNSView(_ view: DriftView, context: Context) {
        view.load(url)
        view.moving = moving
    }

    static func dismantleNSView(_ view: DriftView, coordinator: ()) {
        view.stop()
    }
}

final class DriftView: NSView {
    private let imageLayer = CALayer()
    private var url: String?
    private var loadTask: Task<Void, Never>?

    var moving = false {
        didSet { if moving != oldValue { updateAnimation(restart: false) } }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        // A little larger than the card, so the drift never shows an edge.
        imageLayer.frame = bounds.insetBy(dx: -bounds.width * 0.1, dy: -bounds.height * 0.1)
        updateAnimation(restart: true)
    }

    func load(_ url: String?) {
        guard url != self.url else { return }
        self.url = url
        loadTask?.cancel()
        imageLayer.contents = nil
        guard let url else { return }
        loadTask = Task { [weak self] in
            guard let image = await ImageLoader.shared.load(url, maxPixel: 640), !Task.isCancelled else { return }
            self?.imageLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    func stop() {
        loadTask?.cancel()
        imageLayer.removeAllAnimations()
    }

    private func updateAnimation(restart: Bool) {
        if restart || !moving { imageLayer.removeAnimation(forKey: "drift") }
        guard moving, bounds.width > 0, imageLayer.animation(forKey: "drift") == nil else { return }
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        a.toValue = NSValue(caTransform3D: CATransform3DConcat(
            CATransform3DMakeScale(1.1, 1.1, 1),
            CATransform3DMakeTranslation(-bounds.width * 0.05, bounds.height * 0.04, 0)))
        a.duration = 16
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageLayer.add(a, forKey: "drift")
    }
}
