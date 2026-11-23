import SwiftUI

/// Crossfade in the player bar: each click lengthens it (3, 6, 9, 12 seconds), the next
/// turns it off. While on, the glyph is in the accent colour with the length at its corner.
struct CrossfadeButton: View {
    @Environment(AppModel.self) private var app
    @AppStorage(YTMusic.crossfadeKey) private var seconds = 0
    @ViewState var hover = false

    var body: some View {
        let on = seconds > 0
        let next = Self.step(after: seconds)
        Button {
            withAnimation(.soft) { seconds = next }
            app.engine.crossfadeChanged()
        } label: {
            // The glyph alone, the size of the bar's other icons; while on, the length as
            // a small figure at its corner (like the "1" of repeat one).
            CrossfadeGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 15, height: 10)
                .overlay(alignment: .bottomTrailing) {
                    if on {
                        Text("\(seconds)")
                            .font(.system(size: 7.5, weight: .bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .offset(x: 6, y: 6)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(on ? Color.brand : (hover ? Color.primary : Color.secondary))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .help(on
              ? M.t("Şarkılar arası geçiş: \(seconds) sn — tıkla: \(next == 0 ? "kapat" : "\(next) sn")",
                    "Crossfade: \(seconds) s — click: \(next == 0 ? "turn off" : "\(next) s")")
              : M.t("Şarkılar arası geçiş kapalı — tıkla: \(next) sn", "Crossfade off — click: \(next) s"))
        .accessibilityLabel(M.t("Şarkılar arası geçiş", "Crossfade"))
        .accessibilityValue(on ? M.t("\(seconds) saniye", "\(seconds) seconds") : M.t("Kapalı", "Off"))
    }

    /// Off → 3 → 6 → 9 → 12 → off.
    static func step(after seconds: Int) -> Int {
        let choices = YTMusic.crossfadeChoices
        guard let i = choices.firstIndex(of: seconds) else { return choices[1] }
        return choices[(i + 1) % choices.count]
    }
}

/// The crossfade sign: one curve falling as the other rises, crossing in the middle.
struct CrossfadeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                   control1: CGPoint(x: r.midX, y: r.minY), control2: CGPoint(x: r.midX, y: r.maxY))
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY),
                   control1: CGPoint(x: r.midX, y: r.maxY), control2: CGPoint(x: r.midX, y: r.minY))
        return p
    }
}
