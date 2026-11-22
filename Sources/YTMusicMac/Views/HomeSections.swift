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
            Artwork(url: item.thumbnail, cornerRadius: 0,
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
                    SectionTitle(title: M.t("Senin için seçildi", "Picked for you"), subtitle: nil)
                    FeaturedPick(items: picks)
                }
                .frame(width: FeaturedPick.width(card: d.card, count: picks.count), alignment: .leading)
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

/// "Senin için seçildi": a deck of tall cards (the stations' size), the next picks peeking
/// out behind the front one. Every few seconds the front card steps aside and the next one
/// comes forward; a card behind comes forward when clicked, the front one opens.
private struct FeaturedPick: View {
    let items: [MediaItem]
    @Environment(AppModel.self) private var app
    @Environment(\.density) private var d
    @ViewState var index = 0
    @ViewState var hover = false

    private static let interval: UInt64 = 8_000_000_000
    /// How far each card behind shows past the one in front, and how much smaller it is.
    private static let peek: CGFloat = 0.2
    private static let shrink: CGFloat = 0.09

    private struct Slot: Identifiable {
        let depth: Int
        let item: MediaItem
        var id: String { item.id }
    }

    static func width(card: CGFloat, count: Int) -> CGFloat {
        card + card * peek * CGFloat(max(0, min(count, 3) - 1))
    }

    var body: some View {
        let activity = AppActivity.shared
        let running = items.count > 1 && !hover && activity.isActive && activity.isVisible
        let current = items.isEmpty ? 0 : index % items.count
        let side = d.card
        let height = side * StationCard.aspect
        let slots = (0..<min(3, items.count)).map { Slot(depth: $0, item: items[(current + $0) % items.count]) }
        VStack(spacing: 6) {
            ZStack(alignment: .leading) {
                ForEach(slots) { slot in
                    DeckCard(item: slot.item, side: side, height: height, depth: slot.depth,
                             showsPlay: hover && slot.depth == 0)
                        .scaleEffect(1 - CGFloat(slot.depth) * Self.shrink, anchor: .trailing)
                        .offset(x: CGFloat(slot.depth) * side * Self.peek)
                        .zIndex(Double(10 - slot.depth))
                        .transition(.asymmetric(insertion: .opacity,
                                                removal: .opacity.combined(with: .offset(x: -side * 0.35))))
                        .onTapGesture {
                            if slot.depth == 0 { app.open(slot.item) } else { bringForward(slot.item) }
                        }
                        .contextMenu { ItemMenu(item: slot.item) }
                }
            }
            .frame(width: Self.width(card: side, count: items.count), height: height, alignment: .leading)
            // The dots sit in their own row under the deck; each one brings its pick forward.
            if items.count > 1 {
                HStack(spacing: 0) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Button {
                            withAnimation(Self.step) { index = i }
                        } label: {
                            Capsule()
                                .fill(i == current ? Color.primary : Color.primary.opacity(hover ? 0.45 : 0.3))
                                .frame(width: i == current ? 16 : 7, height: 7)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(M.t("\(i + 1). öneri", "Pick \(i + 1)"))
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
                withAnimation(Self.step) { index = (index % items.count + 1) % items.count }
            }
        }
    }

    private static let step = Animation.smooth(duration: 0.6)

    private func bringForward(_ item: MediaItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(Self.step) { index = i }
    }
}

/// One card of the deck: the cover filling it, the title and artists over its lower part,
/// a "YENİ ÇIKAN" / "EDİTÖR SEÇİMİ" tag. Cards further back are dimmed.
private struct DeckCard: View {
    let item: MediaItem
    let side: CGFloat
    let height: CGFloat
    let depth: Int
    let showsPlay: Bool
    @Environment(AppModel.self) private var app
    private static let radius: CGFloat = 12

    var body: some View {
        let official = PersonalHome.isOfficial(item)
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.35)
            Artwork(url: item.thumbnail, cornerRadius: 0)
                .frame(width: side, height: height)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.42),
                .init(color: .black.opacity(0.82), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: side * 0.1, weight: .heavy))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                Text(item.bylineText)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(12)
            .padding(.trailing, 36)

            CardTag(title: official ? M.t("EDİTÖR SEÇİMİ", "EDITORS' PICK") : M.t("YENİ ÇIKAN", "NEW"),
                    systemImage: official ? "star" : "sparkles")
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showsPlay {
                PlayCircle(size: 32) { app.play(item) }
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.opacity)
            }
            if depth > 0 {
                Color.black.opacity(0.2 * Double(depth)).allowsHitTesting(false)
            }
        }
        .frame(width: side, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .cardShadow(cornerRadius: Self.radius, opacity: depth == 0 ? 0.3 : 0.16, radius: depth == 0 ? 12 : 6, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
    }
}

/// The small tag at the top of the home page's tall cards ("RADYO", "YENİ ÇIKAN").
private struct CardTag: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.32)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
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
        .frame(height: side * StationCard.aspect + d.v(44, 50))
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

/// An artist's radio: a tall card filled by the artist's photo, washed into the artist's
/// colour towards the bottom, with the name over it and a small "RADYO" tag.
private struct StationCard: View {
    let item: MediaItem
    /// The card's width; it is `aspect` times as tall.
    let side: CGFloat
    static let aspect: CGFloat = 1.25
    private static let radius: CGFloat = 12
    @Environment(AppModel.self) private var app
    @ViewState var hover = false

    var body: some View {
        let color = HomePalette.color(for: item.title)
        let height = side * Self.aspect
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                // The artist's colour: behind the photo, and alone when there is none.
                LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                if item.thumbnail != nil {
                    Artwork(url: item.thumbnail, cornerRadius: 0, placeholder: "person.fill")
                        .frame(width: side, height: height)
                        .scaleEffect(hover ? 1.04 : 1)
                        .animation(.soft, value: hover)
                } else {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: side * 0.3, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.16))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // The colour rises from the bottom, so the name reads over any photo.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.4),
                    .init(color: color.opacity(0.3), location: 0.64),
                    .init(color: .black.opacity(0.78), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(.system(size: side * 0.12, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    Capsule().fill(color).frame(width: side * 0.16, height: 3)
                }
                .padding(12)
                .padding(.trailing, 40)

                CardTag(title: M.t("RADYO", "RADIO"), systemImage: "dot.radiowaves.left.and.right")
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if hover {
                    PlayCircle(size: 32) { app.play(item) }
                        .padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
            .cardShadow(cornerRadius: Self.radius, opacity: hover ? 0.28 : 0.14, radius: hover ? 12 : 5, y: 4)
            Text(item.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(width: side, alignment: .leading)
        }
        .contentShape(Rectangle())
        .scrollAwareHover($hover, animation: .easeOut(duration: 0.15))
        .onTapGesture { app.open(item) }
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
                if let artist = section.top, artist.thumbnail != nil {
                    Artwork(url: artist.thumbnail, cornerRadius: 6, placeholder: "person.fill")
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
                    Artwork(url: item.thumbnail, cornerRadius: 6,
                            placeholder: item.kind == "artistradio" ? "person.fill" : "music.note")
                        .frame(width: cover, height: cover)
                        .cardShadow(cornerRadius: 6, opacity: 0.4, radius: 10, y: 4)
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
