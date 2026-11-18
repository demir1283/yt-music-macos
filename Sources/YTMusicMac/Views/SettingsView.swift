import SwiftUI

/// Ayarlar: appearance, accent colour and background — one compact, scroll-free sheet.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let theme = ThemeStore.shared
    @AppStorage("curateRadio") private var curateRadio = true
    @AppStorage(ListeningLog.enabledKey) private var keepHistory = true
    @ViewState var historyBytes = ListeningLog.shared.byteCount

    var body: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ayarlar").font(.system(size: 17, weight: .bold))
                Spacer()
                Button("Bitti") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
                GridRow {
                    label("Görünüm")
                    Picker("", selection: $theme.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                GridRow(alignment: .top) {
                    label("Renk").padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            ForEach(ThemeStore.accents) { choice in
                                AccentDot(choice: choice, selected: theme.accentID == choice.id) {
                                    withAnimation(.easeInOut(duration: 0.2)) { theme.accentID = choice.id }
                                }
                            }
                        }
                        Text(theme.accent.name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    label("Arka plan")
                    Picker("", selection: $theme.background) {
                        ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                GridRow {
                    label("Yoğunluk")
                    HStack(spacing: 8) {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: $theme.ambientIntensity, in: 0.2...1)
                            .controlSize(.small)
                            .frame(width: 200)
                        Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                    }
                    .disabled(!theme.background.isAnimated)
                    .opacity(theme.background.isAnimated ? 1 : 0.4)
                }

                GridRow(alignment: .top) {
                    label("Radyo").padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Resmi sürümler önce, kullanıcı yüklemeleri sona", isOn: $curateRadio)
                        Text("Klibi olan şarkılar şarkı sürümüyle çalar, aynı şarkı bir kez çalar. 20 dakikadan uzun setler ve mix'ler olduğu gibi kalır. Seçtiğin listelere ve albümlere dokunulmaz.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GridRow(alignment: .top) {
                    label("Geçmiş").padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Dinleme geçmişini bu Mac'te tut", isOn: $keepHistory)
                        HStack(spacing: 10) {
                            Text("Öneriler bundan öğrenir; Mac'ten çıkmaz. \(historySize)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Button("Geçmişi Sil") {
                                ListeningLog.shared.erase()
                                historyBytes = 0
                            }
                            .controlSize(.small)
                            .disabled(historyBytes == 0)
                        }
                    }
                }

                GridRow {
                    label("Ses")
                    Text(app.engine.streamInfo.isEmpty ? "Henüz bir şey çalınmadı" : app.engine.streamInfo)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            PalettePreview()
        }
        .padding(22)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var historySize: String {
        historyBytes == 0 ? "Şu an boş."
            : "Şu an " + ByteCountFormatter.string(fromByteCount: Int64(historyBytes), countStyle: .file) + "."
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }
}

/// One accent colour: a small dot, ringed when selected; the name shows as a tooltip.
private struct AccentDot: View {
    let choice: AccentChoice
    let selected: Bool
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(choice.color)
                .frame(width: 20, height: 20)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(choice.color.opacity(selected ? 0.9 : (hover ? 0.4 : 0)), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(choice.name)
    }
}

/// A miniature player bar in the current palette and background.
private struct PalettePreview: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Color.brand.opacity(0.9), Color.brand.scaledBrightness(0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Çalan şarkı").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.brand)
                    Text("Sanatçı").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.15))
                        Capsule().fill(Color.brand).frame(width: g.size.width * 0.38)
                    }
                }
                .frame(height: 3)
            }
            Image(systemName: "heart.fill").foregroundStyle(Color.brand)
            Image(systemName: "pause.fill").font(.system(size: 15))
        }
        .padding(12)
        .background(ContentBackground(includeField: true).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
