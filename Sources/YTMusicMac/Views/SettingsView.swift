import SwiftUI

/// Ayarlar: appearance, accent colour and background — one compact, scroll-free sheet.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let theme = ThemeStore.shared
    @AppStorage("curateRadio") private var curateRadio = true
    @AppStorage(ListeningLog.enabledKey) private var keepHistory = true
    @ViewState var historyBytes = ListeningLog.shared.byteCount
    @ViewState var language = M.chosen ?? "system"

    var body: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(M.t("Ayarlar", "Settings")).font(.system(size: 17, weight: .bold))
                Spacer()
                Button(M.t("Bitti", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 16) {
                GridRow {
                    label(M.t("Görünüm", "Appearance"))
                    Picker("", selection: $theme.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                GridRow(alignment: .top) {
                    label(M.t("Renk", "Colour")).padding(.top, 3)
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
                    label(M.t("Arka plan", "Background"))
                    Picker("", selection: $theme.background) {
                        ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                GridRow {
                    label(M.t("Yoğunluk", "Intensity"))
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
                    label(M.t("Radyo", "Radio")).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(M.t("Resmi sürümler önce, kullanıcı yüklemeleri sona", "Official versions first, user uploads last"), isOn: $curateRadio)
                        Text(M.t("Klibi olan şarkılar şarkı sürümüyle çalar, aynı şarkı bir kez çalar. 20 dakikadan uzun setler ve mix'ler olduğu gibi kalır. Seçtiğin listelere ve albümlere dokunulmaz.",
                                 "Songs with a music video play as the song version, and each song plays once. Sets and mixes longer than 20 minutes stay as they are. Playlists and albums you pick are left untouched."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                GridRow(alignment: .top) {
                    label(M.t("Geçmiş", "History")).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(M.t("Dinleme geçmişini bu Mac'te tut", "Keep listening history on this Mac"), isOn: $keepHistory)
                        HStack(spacing: 10) {
                            Text(M.t("Öneriler bundan öğrenir; Mac'ten çıkmaz.", "Recommendations learn from it; it never leaves your Mac.") + " " + historySize)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Button(M.t("Geçmişi Sil", "Erase History")) {
                                ListeningLog.shared.erase()
                                historyBytes = 0
                            }
                            .controlSize(.small)
                            .disabled(historyBytes == 0)
                        }
                    }
                }

                GridRow {
                    label(M.t("Ses", "Audio"))
                    Text(app.engine.streamInfo.isEmpty ? M.t("Henüz bir şey çalınmadı", "Nothing played yet") : app.engine.streamInfo)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                GridRow(alignment: .top) {
                    label(M.t("Dil", "Language")).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("", selection: $language) {
                            Text(M.t("Sistem", "System")).tag("system")
                            Text("Türkçe").tag("tr")
                            Text("English").tag("en")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: language) { _, value in M.chosen = value == "system" ? nil : value }
                        if language != (M.launchedChoice ?? "system") {
                            HStack(spacing: 10) {
                                Text(M.t("Uygulama yeniden başlayınca geçerli olur.", "Applies when the app restarts."))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Button(M.t("Yeniden Başlat", "Restart")) { M.relaunch() }
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                GridRow(alignment: .top) {
                    label(M.t("Güncelleme", "Updates")).padding(.top, 1)
                    UpdateSettings()
                }
            }

            PalettePreview()
        }
        .padding(22)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var historySize: String {
        historyBytes == 0 ? M.t("Şu an boş.", "Empty now.")
            : M.t("Şu an ", "Now ") + ByteCountFormatter.string(fromByteCount: Int64(historyBytes), countStyle: .file) + "."
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 80, alignment: .trailing)
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
                    Text(M.t("Çalan şarkı", "Playing song")).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.brand)
                    Text(M.t("Sanatçı", "Artist")).font(.system(size: 12)).foregroundStyle(.secondary)
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

/// Settings → Updates: check GitHub for new versions, once a day or now. "Check Now"
/// dims while it asks, then says what it found beside it.
private struct UpdateSettings: View {
    @ViewState var checking = false
    @ViewState var result: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(M.t("Yeni sürümleri GitHub'da denetle", "Check GitHub for new versions"),
                   isOn: Binding(get: { Updater.shared.enabled }, set: { Updater.shared.enabled = $0 }))
            HStack(spacing: 10) {
                Button(M.t("Şimdi Denetle", "Check Now")) { Task { await checkNow() } }
                    .controlSize(.small)
                    .disabled(checking)
                if let result {
                    Text(result)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: result)
        }
    }

    @MainActor
    private func checkNow() async {
        checking = true
        result = nil
        let state = await Updater.shared.check(manual: true)
        Updater.shared.dismissed = false
        checking = false
        if let release = Updater.shared.available {
            result = M.t("\(release.version) çıktı; kenar çubuğundan güncelleyebilirsin.",
                         "\(release.version) is out; update it from the sidebar.")
        } else if state == .failed {
            result = M.t("GitHub'a ulaşılamadı.", "Couldn't reach GitHub.")
        } else {
            result = M.t("Uygulama güncel!", "The app is up to date!")
        }
    }
}
