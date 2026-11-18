import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    /// The app's accent colour, chosen in Ayarlar (default: Apple Music's red).
    /// Read inside view bodies, so views update as soon as the setting changes.
    @MainActor static var brand: Color { ThemeStore.shared.accent.color }

    /// Neutral fill used for placeholders and subtle backgrounds; adapts to light/dark.
    static let subtleFill = Color.primary.opacity(0.07)

    /// Rotates the hue by `degrees` (for harmonious companion colours).
    func hueShifted(_ degrees: Double, saturation: Double = 1) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        var nh = h + CGFloat(degrees / 360)
        nh -= floor(nh)
        return Color(nsColor: NSColor(hue: nh, saturation: min(1, s * saturation), brightness: b, alpha: a))
    }

    /// Multiplies HSB brightness (e.g. 0.5 for a dark variant).
    func scaledBrightness(_ factor: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(nsColor: NSColor(hue: h, saturation: s, brightness: min(1, b * factor), alpha: a))
    }
}

// MARK: - Appearance settings

struct AccentChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let hex: UInt32
    var color: Color { Color(hex: hex) }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case plain
    case flow             // "Akış": still contour lines, a new shape for each song
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain: return "Sade"
        case .flow: return "Akış"
        }
    }
    var isAnimated: Bool { self == .flow }
    var caption: String {
        switch self {
        case .plain: return "Renksiz, düz arka plan."
        case .flow: return "Kâğıda kalemle çizilmiş gibi, nefes alan ince eş yükselti çizgileri."
        }
    }

    /// Older settings (Ton, Işık, Noktalar) map onto the two remaining styles.
    static func stored(_ raw: String?) -> BackgroundStyle {
        switch raw {
        case "flow", "ambient", "dots": return .flow
        default: return .plain
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Açık"
        case .dark: return "Koyu"
        }
    }
}

/// The user's look: accent colour, light/dark mode and background tint. Persisted.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    static let accents: [AccentChoice] = [
        AccentChoice(id: "apple", name: "Apple Music", hex: 0xFA2D48),
        AccentChoice(id: "youtube", name: "YouTube", hex: 0xFF0033),
        AccentChoice(id: "coral", name: "Mercan", hex: 0xFF6B5B),
        AccentChoice(id: "orange", name: "Gün Batımı", hex: 0xFF9F0A),
        AccentChoice(id: "yellow", name: "Güneş", hex: 0xF5C400),
        AccentChoice(id: "green", name: "Nane", hex: 0x30D158),
        AccentChoice(id: "teal", name: "Turkuaz", hex: 0x2EC4C6),
        AccentChoice(id: "blue", name: "Okyanus", hex: 0x0A84FF),
        AccentChoice(id: "indigo", name: "Gece", hex: 0x5E5CE6),
        AccentChoice(id: "purple", name: "Lavanta", hex: 0xBF5AF2),
        AccentChoice(id: "pink", name: "Pembe", hex: 0xFF375F),
        AccentChoice(id: "graphite", name: "Grafit", hex: 0x8E8E93),
    ]

    var accentID: String {
        didSet { UserDefaults.standard.set(accentID, forKey: "theme.accent") }
    }
    var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "theme.appearance")
            applyAppearance()
        }
    }
    /// Content background: plain, a faint accent tint, or slowly drifting colour light.
    var background: BackgroundStyle {
        didSet { UserDefaults.standard.set(background.rawValue, forKey: "theme.background") }
    }
    /// Strength of the moving background, 0.2 (barely there) … 1 (vivid).
    var ambientIntensity: Double {
        didSet { UserDefaults.standard.set(ambientIntensity, forKey: "theme.ambientIntensity") }
    }

    var accent: AccentChoice {
        Self.accents.first { $0.id == accentID } ?? Self.accents[0]
    }

    private init() {
        let d = UserDefaults.standard
        accentID = d.string(forKey: "theme.accent") ?? "apple"
        appearance = AppearanceMode(rawValue: d.string(forKey: "theme.appearance") ?? "") ?? .system
        background = BackgroundStyle.stored(d.string(forKey: "theme.background"))
        ambientIntensity = (d.object(forKey: "theme.ambientIntensity") as? Double) ?? 0.6
        applyAppearance()
    }

    /// Light/dark is applied app-wide (sidebar, materials and Liquid Glass included).
    func applyAppearance() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum Palette {
    static let tileColors: [UInt32] = [
        0xE13300, 0x1E3264, 0x8D67AB, 0xE8115B, 0x148A08, 0xBA5D07, 0x503750,
        0x477D95, 0xAF2896, 0x509BF5, 0x27856A, 0xE91429, 0x0D73EC, 0x8C1932, 0x777777,
    ]

    static func color(for key: String) -> Color {
        var hash: UInt32 = 5381
        for u in key.unicodeScalars { hash = (hash &* 33) &+ u.value }
        return Color(hex: tileColors[Int(hash % UInt32(tileColors.count))])
    }

    static let likedGradient = LinearGradient(
        colors: [Color(hex: 0xFF5E7E), Color(hex: 0xFA2D48), Color(hex: 0xB0153A)],  // "Beğenilenler" cover
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Card shadow

extension View {
    /// A picture card's drop shadow, cast by a plain shape of the same outline behind it
    /// rather than by the picture: it looks the same, but isn't redrawn while the cover
    /// loads, fades in or scrolls by (a shadow taken from the picture is, every frame).
    func cardShadow(cornerRadius: CGFloat, circle: Bool = false, opacity: Double, radius: CGFloat, y: CGFloat = 0) -> some View {
        background {
            let fill = Color(nsColor: .windowBackgroundColor)
            Group {
                if circle {
                    Circle().fill(fill)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fill)
                }
            }
            .shadow(color: .black.opacity(opacity), radius: radius, y: y)
        }
    }
}

// MARK: - Glass (Liquid Glass on macOS 26+, materials before that)

extension View {
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
    }

    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }

    /// Glass capsule washed with a colour (e.g. the current artwork's tint).
    @ViewBuilder
    func tintedGlassCapsule(_ tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.55)).interactive(), in: Capsule())
        } else {
            self
                .background(Capsule().fill(tint.opacity(0.45)))
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        }
    }

    /// Glass panel fully washed with a colour.
    @ViewBuilder
    func tintedGlassPanel(_ tint: Color, cornerRadius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint.opacity(0.7)), in: shape)
        } else {
            self
                .background(shape.fill(tint.opacity(0.65)))
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
    }

    @ViewBuilder
    func glassCircle() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
    }
}

// MARK: - Helpers

func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let s = Int(seconds.rounded(.down))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

/// Pulls the playlistId out of a raw YouTube Music endpoint JSON string.
func playlistId(inEndpoint json: String?) -> String? {
    guard let json, let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    for key in ["watchEndpoint", "watchPlaylistEndpoint"] {
        if let ep = obj[key] as? [String: Any], let id = ep["playlistId"] as? String { return id }
    }
    return nil
}

func watchPlaylistEndpoint(_ playlistId: String, params: String? = nil) -> String {
    var ep: [String: Any] = ["playlistId": playlistId]
    if let params { ep["params"] = params }
    let data = (try? JSONSerialization.data(withJSONObject: ["watchPlaylistEndpoint": ep])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

func watchEndpoint(videoId: String, playlistId: String? = nil) -> String {
    var ep: [String: Any] = ["videoId": videoId]
    if let playlistId { ep["playlistId"] = playlistId }
    let data = (try? JSONSerialization.data(withJSONObject: ["watchEndpoint": ep])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

/// The material macOS uses for sidebars (blends with what is behind the window), so a
/// panel can look exactly like the sidebar.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

// MARK: - App activity

/// Whether anyone can see the app. Apple's energy guidance: stop animations and UI
/// updates when the app isn't frontmost, and all drawing when no window is on screen.
@MainActor
@Observable
final class AppActivity {
    static let shared = AppActivity()

    /// The app is the frontmost app.
    private(set) var isActive = true
    /// At least part of a window is on screen (not hidden, minimised or fully covered).
    private(set) var isVisible = true

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didChangeOcclusionStateNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in AppActivity.shared.refresh() }
            })
        }
        refresh()
    }

    private func refresh() {
        let app = NSApplication.shared
        let active = app.isActive
        let visible = app.occlusionState.contains(.visible) && !app.isHidden
        if active != isActive { isActive = active }
        if visible != isVisible { isVisible = visible }
    }
}

// MARK: - Playback schedule

/// A TimelineView schedule tied to the song's clock: it wakes only at the playback moments
/// where what is shown changes (every whole second of the time label, or the start of the
/// next lyric line), and not at all while nothing plays. Each wake-up makes macOS lay the
/// window out again, so fewer wake-ups means less work.
struct PlaybackSchedule: TimelineSchedule {
    /// Song position at `date`.
    let position: Double
    let date: Date
    let running: Bool
    /// Wake every `step` seconds of playback…
    var step: Double? = nil
    /// …or at these playback times (sorted).
    var marks: [Double] = []

    func entries(from start: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var first = true
        guard running else {
            return AnyIterator { defer { first = false }; return first ? start : nil }
        }
        let now = position + start.timeIntervalSince(date)
        let pad = 0.02   // land just after the moment, never just before it
        let base = date, pos = position
        if let step, step > 0 {
            var k = (now / step).rounded(.down) + 1
            return AnyIterator {
                if first { first = false; return start }
                defer { k += 1 }
                return base.addingTimeInterval(k * step - pos + pad)
            }
        }
        var i = marks.firstIndex { $0 > now } ?? marks.count
        let marks = self.marks
        return AnyIterator {
            if first { first = false; return start }
            guard i < marks.count else { return nil }
            defer { i += 1 }
            return base.addingTimeInterval(marks[i] - pos + pad)
        }
    }
}

// MARK: - Density

/// How tightly the interface is laid out, from the window's size. A large external display
/// gets the roomy layout (t = 1, the original sizes); a laptop's built-in screen gets the
/// compact one (t = 0): smaller covers and rows, tighter margins, so more fits without
/// scrolling. Sizes in between scale in a few steps (not continuously, so resizing the
/// window doesn't re-lay everything out on every pixel).
struct Density: Equatable {
    var t: CGFloat = 1

    static let regular = Density(t: 1)

    static func forWindow(_ size: CGSize) -> Density {
        guard size.width > 0, size.height > 0 else { return .regular }
        // A 13–14" MacBook window is ~900–960 pt tall; a 1080p-class display ~1050 and up.
        let byHeight = (size.height - 940) / (1080 - 940)
        let byWidth = (size.width - 1300) / (1700 - 1300)
        let raw = min(1, max(0, min(byHeight, byWidth)))
        return Density(t: (raw * 4).rounded() / 4)
    }

    var isCompact: Bool { t < 0.5 }

    /// Interpolates between the compact and the roomy value (to the nearest half point).
    func v(_ compact: CGFloat, _ regular: CGFloat) -> CGFloat {
        ((compact + (regular - compact) * t) * 2).rounded() / 2
    }

    // Page structure
    var pad: CGFloat { v(16, 24) }            // left/right page margin
    var sectionGap: CGFloat { v(20, 30) }     // between shelves
    var pageTop: CGFloat { v(10, 18) }
    var gutter: CGFloat { v(6, 8) }           // around the content card
    var sectionTitle: CGFloat { v(17, 20) }

    // Cards and grids
    var card: CGFloat { v(140, 176) }
    var cardMixed: CGFloat { v(132, 169) }    // image height for shelves mixing videos
    var cardGap: CGFloat { v(12, 18) }
    var gridCard: CGFloat { v(140, 170) }
    var tileHeight: CGFloat { v(70, 96) }

    // Song rows
    var songRow: CGFloat { v(44, 52) }
    var songArt: CGFloat { v(34, 40) }
    var songColumn: CGFloat { v(264, 300) }
    var trackRow: CGFloat { v(40, 48) }
    var trackRowPlain: CGFloat { v(34, 40) }
    var trackArt: CGFloat { v(30, 36) }

    // Headers
    var headerArt: CGFloat { v(196, 230) }
    var headerTitle: CGFloat { v(22, 28) }
    var headerStrap: CGFloat { v(17, 22) }
    var heroHeight: CGFloat { v(210, 340) }
    var heroTitle: CGFloat { v(32, 46) }
    var topResult: CGFloat { v(260, 320) }

    // Chrome
    var sidebar: CGFloat { v(200, 236) }
    var sidePanel: CGFloat { v(300, 360) }
    var playerBar: CGFloat { v(54, 58) }
    var lyricsFont: CGFloat { v(16, 18) }
    var queueArt: CGFloat { v(32, 38) }
}

private struct DensityKey: EnvironmentKey {
    static let defaultValue = Density.regular
}

extension EnvironmentValues {
    var density: Density {
        get { self[DensityKey.self] }
        set { self[DensityKey.self] = newValue }
    }
}
