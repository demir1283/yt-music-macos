import SwiftUI

// MARK: - Shared field

/// Size of the whole window content, so every pane (sidebar, content, side panel) draws
/// its slice of one continuous background.
private struct AmbientFieldSizeKey: EnvironmentKey {
    static let defaultValue: CGSize = .zero
}

extension EnvironmentValues {
    var ambientFieldSize: CGSize {
        get { self[AmbientFieldSizeKey.self] }
        set { self[AmbientFieldSizeKey.self] = newValue }
    }
}

/// The pattern is still: one fixed shape per song. Nothing is redrawn while a song plays;
/// when the track changes, the new shape cross-fades in once (a single redraw).
enum AmbientPhase {
    static func value(for videoId: String?) -> Double {
        guard let videoId else { return 0 }
        // FNV-1a: stable across launches (unlike hashValue), so a song always looks the same.
        var h: UInt64 = 0xcbf29ce484222325
        for b in videoId.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return Double(h % 10_000) / 10   // 0 … 1000 "seconds" into the pattern
    }
}

/// The content card's own fill. The moving background itself is drawn by the window
/// (behind the card), so the card stays a light, see-through layer above it.
struct ContentBackground: View {
    /// Draw the moving background inside this view too (used by the settings preview).
    var includeField = false

    var body: some View {
        ZStack {
            Color.primary.opacity(0.025)
            if includeField { AmbientField() }
        }
    }
}

/// This pane's slice of the background pattern (Akış). It is drawn once and then left
/// alone: no timer and no per-frame drawing, so the translucent surfaces above it (sidebar
/// material, glass player bar) never have to re-blur a moving picture.
struct AmbientField: View {
    /// Per-pane strength (the sidebar and side panel show it a little softer).
    var strength: Double = 1
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ambientFieldSize) private var fieldSize
    private let theme = ThemeStore.shared
    private static let glowScale: CGFloat = 8

    var body: some View {
        if theme.background.isAnimated {
            let k = (scheme == .dark ? 1.0 : 0.6) * min(1, max(0.2, theme.ambientIntensity)) * strength
            let palette = AmbientPalette(accent: Color.brand)
            let t = AmbientPhase.value(for: app.engine.track?.videoId)
            GeometryReader { geo in
                let frame = geo.frame(in: .global)
                let field = CGSize(width: max(fieldSize.width, frame.maxX, 1),
                                   height: max(fieldSize.height, frame.maxY, 1))
                ZStack {
                    pattern(t: t, frame: frame, field: field, size: geo.size, palette: palette, k: k)
                        .id(t)
                        .transition(.opacity)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.8), value: t)
            }
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private func pattern(t: Double, frame: CGRect, field: CGSize, size: CGSize,
                         palette: AmbientPalette, k: Double) -> some View {
        let glow = Self.glowScale
        return ZStack(alignment: .topLeading) {
            // The soft light is blurry by nature: drawn at 1/8 size (1/64 of the pixels).
            Canvas { g, _ in
                g.scaleBy(x: 1 / glow, y: 1 / glow)
                g.translateBy(x: -frame.minX, y: -frame.minY)
                AmbientPainter.light(g, field, t, palette, k * 0.3)
            }
            .frame(width: ceil(size.width / glow), height: ceil(size.height / glow))
            .scaleEffect(glow, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()

            // The faint lines are drawn at half size and doubled: 1/4 of the pixels kept in
            // memory (≈ 20 MB less on a large Retina window), barely softer on screen.
            Canvas { g, _ in
                g.scaleBy(x: 0.5, y: 0.5)
                g.translateBy(x: -frame.minX, y: -frame.minY)
                AmbientPainter.flow(g, field, CGRect(origin: frame.origin, size: size), t, palette, k * 1.15)
            }
            .frame(width: ceil(size.width / 2), height: ceil(size.height / 2))
            .scaleEffect(2, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

struct AmbientPalette {
    let a: Color, b: Color, c: Color, d: Color

    init(accent: Color) {
        a = accent
        b = accent.hueShifted(-34)
        c = accent.hueShifted(38, saturation: 0.9)
        d = accent.hueShifted(-70, saturation: 0.8)
    }
}

/// Drawing for the background pattern: sums of sines, so every song gets its own smooth,
/// never-repeating shape; only the visible slice is drawn.
enum AmbientPainter {
    // MARK: Soft colour light (the glow under the lines)

    static func light(_ g: GraphicsContext, _ field: CGSize, _ t: Double, _ p: AmbientPalette, _ k: Double) {
        struct Blob { let c: Color; let o: Double; let r: Double; let x: Double; let y: Double
                      let dx: Double; let dy: Double; let period: Double; let phase: Double }
        let blobs = [
            Blob(c: p.a, o: 0.62, r: 0.46, x: 0.16, y: 0.10, dx: 0.20, dy: 0.16, period: 34, phase: 0),
            Blob(c: p.b, o: 0.52, r: 0.42, x: 0.88, y: 0.32, dx: 0.16, dy: 0.22, period: 43, phase: 1.7),
            Blob(c: p.c, o: 0.46, r: 0.50, x: 0.52, y: 0.96, dx: 0.26, dy: 0.12, period: 52, phase: 3.1),
            Blob(c: p.d, o: 0.36, r: 0.36, x: 0.42, y: 0.48, dx: 0.28, dy: 0.24, period: 61, phase: 4.4),
        ]
        let side = max(field.width, field.height)
        for b in blobs {
            let a = (t / b.period) * 2 * .pi + b.phase
            let x = (b.x + b.dx * sin(a)) * field.width
            let y = (b.y + b.dy * sin(a * 0.73 + 1.1)) * field.height
            let r = b.r * side * (1 + 0.10 * sin(a * 1.3 + b.phase))
            let o = b.o * k
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .radialGradient(
                Gradient(stops: [.init(color: b.c.opacity(o), location: 0),
                                 .init(color: b.c.opacity(o * 0.55), location: 0.4),
                                 .init(color: b.c.opacity(0), location: 1)]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
    }

    // MARK: Akış — undulating contour lines, like a pen plotter drawing

    static func flow(_ g: GraphicsContext, _ field: CGSize, _ visible: CGRect, _ t: Double, _ p: AmbientPalette, _ k: Double) {
        let count = max(14, Int(field.height / 30))
        let gap = field.height / CGFloat(count)
        let amp = gap * 1.6
        let sample: CGFloat = 16
        for i in 0..<(count + 4) {
            let base = CGFloat(i - 2) * gap + gap / 2
            // Skip lines that can't reach the visible slice.
            if base + amp * 2 < visible.minY || base - amp * 2 > visible.maxY { continue }
            let fi = Double(i)
            var path = Path()
            var x = floor(visible.minX / sample) * sample - sample
            var first = true
            while x <= visible.maxX + sample {
                let xd = Double(x)
                let d = sin(xd * 0.0042 + t * 0.21 + fi * 0.34)
                      + 0.55 * sin(xd * 0.0091 - t * 0.29 + fi * 0.71)
                      + 0.30 * sin(xd * 0.0017 + t * 0.11 + fi * 0.19)
                let pt = CGPoint(x: x, y: base + CGFloat(d) * amp * 0.5)
                if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
                x += sample
            }
            let mix = 0.5 + 0.5 * sin(fi * 0.45 + t * 0.07)
            let color = mix > 0.66 ? p.a : (mix > 0.33 ? p.b : p.c)
            let o = (0.18 + 0.30 * mix) * k
            // Every fifth line is a heavier "index contour", like on a map.
            let w: CGFloat = i % 5 == 0 ? 1.4 : 0.8
            g.stroke(path, with: .color(color.opacity(o)), lineWidth: w)
        }
    }
}
