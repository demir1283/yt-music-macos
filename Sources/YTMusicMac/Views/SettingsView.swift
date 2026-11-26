import SwiftUI
import AppKit

/// Settings: four groups (Appearance, Listening, Privacy, General) in the style of the
/// system's own settings — a title and a short explanation on the left of each row, its
/// control on the right, every control on the same edge.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let theme = ThemeStore.shared
    @AppStorage("curateRadio") private var curateRadio = true
    @AppStorage("normalizeVolume") private var leveling = true
    @AppStorage(AppDelegate.confirmQuitKey) private var confirmQuit = true
    @AppStorage(ListeningLog.enabledKey) private var keepHistory = true
    @ViewState var historyBytes = ListeningLog.shared.byteCount
    @ViewState var language = M.chosen ?? "system"
    @ViewState var confirmErase = false
    @ViewState var showDisliked = false
    /// The groups' own height, measured; the sheet is never taller than the window.
    @ViewState var contentHeight: CGFloat = 10_000

    /// What the groups may take: the main window's height less the sheet's title row and
    /// margins.
    private var maxGroupsHeight: CGFloat {
        let window = AppDelegate.shared?.mainWindowHeight ?? (NSScreen.main?.visibleFrame.height ?? 800)
        return max(280, window - 150)
    }

    var body: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(M.t("Ayarlar", "Settings")).font(.system(size: 17, weight: .bold))
                Spacer()
                Button(M.t("Bitti", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            // Esc closes the sheet too.
            .background(Button("") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false))

            // The groups scroll when they are taller than the window allows (a laptop
            // screen, full screen); otherwise the sheet is as tall as they are.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsGroup(M.t("Görünüm", "Appearance")) {
                        SettingsRow(M.t("Tema", "Theme")) {
                            Picker("", selection: $theme.appearance) {
                                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                            }
                            .segmented()
                        }
                        RowDivider()
                        SettingsRow(M.t("Vurgu rengi", "Accent colour"), detail: theme.accent.name) {
                            HStack(spacing: 4) {
                                ForEach(ThemeStore.accents) { choice in
                                    AccentDot(choice: choice, selected: theme.accentID == choice.id) {
                                        withAnimation(.easeInOut(duration: 0.2)) { theme.accentID = choice.id }
                                    }
                                }
                            }
                        }
                        RowDivider()
                        SettingsRow(M.t("Arka plan", "Background")) {
                            Picker("", selection: $theme.background) {
                                ForEach(BackgroundStyle.allCases) { Text($0.title).tag($0) }
                            }
                            .segmented()
                        }
                        if theme.background.isAnimated {
                            RowDivider().transition(.softReveal)
                            SettingsRow(M.t("Desen yoğunluğu", "Pattern intensity")) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                                    Slider(value: $theme.ambientIntensity, in: 0.2...1)
                                        .controlSize(.small)
                                        .frame(width: 170)
                                    Image(systemName: "sun.max.fill").foregroundStyle(.secondary)
                                }
                            }
                            .transition(.softReveal)
                        }
                    }

                    SettingsGroup(M.t("Dinleme", "Listening")) {
                        SettingsRow(M.t("Ses seviyesini eşitle", "Level the volume"),
                                    detail: M.t("Şarkılar aynı seviyeye getirilir; aralarında ses sıçramaz. Uygulamanın genel sesi biraz kısılır.",
                                                "Songs are brought to the same level, so the volume doesn't jump between them. The app as a whole gets a little quieter.")) {
                            Toggle("", isOn: $leveling).switchStyle()
                                .onChange(of: leveling) { _, _ in app.engine.levelingChanged() }
                        }
                        RowDivider()
                        SettingsRow(M.t("Radyoları düzenle", "Tidy up radios"),
                                    detail: M.t("Resmî sürümler önce, her şarkı bir kez. Uzun setler ve seçtiğin listeler olduğu gibi kalır.",
                                                "Official versions first, each song once. Long sets and the lists you pick stay as they are.")) {
                            Toggle("", isOn: $curateRadio).switchStyle()
                        }
                        RowDivider()
                        SettingsRow(M.t("Ses kalitesi", "Audio quality")) {
                            Text(app.engine.streamInfo.isEmpty ? M.t("Henüz bir şey çalınmadı", "Nothing played yet") : app.engine.streamInfo)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    SettingsGroup(M.t("Gizlilik", "Privacy")) {
                        SettingsRow(M.t("Dinleme geçmişi", "Listening history"),
                                    detail: M.t("Öneriler bundan öğrenir; Mac'ten çıkmaz.", "Recommendations learn from it; it never leaves your Mac.")
                                        + " " + historySize) {
                            Toggle("", isOn: $keepHistory).switchStyle()
                        }
                        RowDivider()
                        SettingsRow(M.t("Beğenilmeyen içerik", "Disliked content"),
                                    detail: app.hiddenKeys.isEmpty
                                        ? M.t("Beğenmediğin ya da önerilmesini istemediğin bir şey yok.", "Nothing disliked or marked “Don't recommend”.")
                                        : M.t("\(app.hiddenKeys.count) öğe; tek tek geri alabilirsin.",
                                              "\(M.count(app.hiddenKeys.count, "item", "items")); you can bring them back one by one.")) {
                            Button(M.t("Göster…", "Show…")) { showDisliked = true }
                                .controlSize(.small)
                                .disabled(app.hiddenKeys.isEmpty)
                        }
                        RowDivider()
                        SettingsRow(M.t("Geçmişi sil", "Erase history")) {
                            Button(M.t("Sil…", "Erase…")) { confirmErase = true }
                                .controlSize(.small)
                                .disabled(historyBytes == 0)
                                .confirmationDialog(M.t("Dinleme geçmişi silinsin mi?", "Erase your listening history?"),
                                                    isPresented: $confirmErase) {
                                    Button(M.t("Sil", "Erase"), role: .destructive) {
                                        ListeningLog.shared.erase()
                                        historyBytes = 0
                                    }
                                    Button(M.t("Vazgeç", "Cancel"), role: .cancel) {}
                                } message: {
                                    Text(M.t("Öneriler sıfırdan öğrenmeye başlar. YouTube hesabındaki geçmişe dokunulmaz.",
                                             "Recommendations start learning from scratch. The history in your YouTube account is left untouched."))
                                }
                        }
                    }

                    SettingsGroup(M.t("Genel", "General")) {
                        SettingsRow(M.t("Dil", "Language"),
                                    detail: language != (M.launchedChoice ?? "system")
                                        ? M.t("Uygulama yeniden başlayınca geçerli olur.", "Applies when the app restarts.") : nil) {
                            Picker("", selection: $language) {
                                Text(M.t("Sistem", "System")).tag("system")
                                Text("Türkçe").tag("tr")
                                Text("English").tag("en")
                            }
                            .segmented()
                            .onChange(of: language) { _, value in M.chosen = value == "system" ? nil : value }
                        }
                        if language != (M.launchedChoice ?? "system") {
                            RowDivider().transition(.softReveal)
                            SettingsRow(M.t("Yeniden başlat", "Restart")) {
                                Button(M.t("Şimdi Yeniden Başlat", "Restart Now")) { M.relaunch() }
                                    .controlSize(.small)
                            }
                            .transition(.softReveal)
                        }
                        RowDivider()
                        SettingsRow(M.t("Çalarken çıkmadan önce sor", "Ask before quitting while playing"),
                                    detail: M.t("Müzik çalarken ⌘Q'ya basınca onay ister; böylece müzik yanlışlıkla kesilmez.",
                                                "Asks first when you press ⌘Q with music playing, so it doesn't stop by accident.")) {
                            Toggle("", isOn: $confirmQuit).switchStyle()
                        }
                        RowDivider()
                        UpdateRows()
                    }
                }
                .background(GeometryReader { g in
                    Color.clear.preference(key: SettingsContentHeight.self, value: g.size.height)
                })
            }
            .scrollIndicators(.automatic)
            .frame(height: min(contentHeight, maxGroupsHeight))
            .onPreferenceChange(SettingsContentHeight.self) { contentHeight = $0 }
        }
        .animation(.soft, value: theme.background)
        .animation(.soft, value: language)
        .padding(20)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showDisliked) {
            DislikedContentSheet()
                .environment(app)
        }
    }

    private var historySize: String {
        historyBytes == 0 ? M.t("Şu an boş.", "Empty now.")
            : M.t("Şu an ", "Now ") + ByteCountFormatter.string(fromByteCount: Int64(historyBytes), countStyle: .file) + "."
    }
}

/// A titled group of rows on a soft rounded panel.
private struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }
}

/// Title (and a short explanation) on the left, the control on the right edge.
private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    var detailColor: Color = .secondary
    let control: Control

    init(_ title: String, detail: String? = nil, detailColor: Color = .secondary,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.detailColor = detailColor
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
}

private struct RowDivider: View {
    var body: some View {
        Divider().padding(.leading, 14)
    }
}

private extension View {
    func segmented() -> some View {
        pickerStyle(.segmented).labelsHidden().fixedSize()
    }

    func switchStyle() -> some View {
        toggleStyle(.switch).labelsHidden().controlSize(.small)
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
                .frame(width: 16, height: 16)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                .padding(2.5)
                .overlay(Circle().strokeBorder(choice.color.opacity(selected ? 0.9 : (hover ? 0.4 : 0)), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(choice.name)
    }
}

/// General → updates: automatic checking, then "Version x · Check Now". A check started
/// here says what it found under the version, and a new version is installed right here,
/// with its progress.
private struct UpdateRows: View {
    @ViewState var checking = false
    @ViewState var result: String? = nil
    @ViewState var upToDate = false

    var body: some View {
        let updater = Updater.shared
        VStack(spacing: 0) {
            SettingsRow(M.t("Yeni sürümleri otomatik denetle", "Check for new versions automatically")) {
                Toggle("", isOn: Binding(get: { Updater.shared.enabled }, set: { Updater.shared.enabled = $0 }))
                    .switchStyle()
            }
            RowDivider()
            SettingsRow(M.t("Sürüm \(Updater.current)", "Version \(Updater.current)"),
                        detail: result, detailColor: upToDate ? .green : .secondary) {
                Button(M.t("Şimdi Denetle", "Check Now")) { Task { await checkNow() } }
                    .controlSize(.small)
                    .disabled(checking || updater.phase.isBusy)
            }
            if let release = updater.available, result != nil || updater.phase != .idle {
                RowDivider().transition(.softReveal)
                UpdateAction(release: release)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.softReveal)
            }
        }
        .animation(.soft, value: result)
        .animation(.soft, value: updater.phase)
    }

    @MainActor
    private func checkNow() async {
        checking = true
        result = nil
        let state = await Updater.shared.check(manual: true)
        Updater.shared.dismissed = false
        checking = false
        upToDate = false
        if let release = Updater.shared.available {
            result = M.t("\(release.version) çıktı.", "\(release.version) is out.")
        } else if state == .failed {
            result = M.t("GitHub'a ulaşılamadı.", "Couldn't reach GitHub.")
        } else {
            result = M.t("Uygulama güncel!", "The app is up to date!")
            upToDate = true
        }
    }
}

/// The app's one motion for things that appear or disappear: a short, eased fade with a
/// small slide, never a jump.
extension Animation {
    static var soft: Animation { .smooth(duration: 0.35) }
}

private struct SettingsContentHeight: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension AnyTransition {
    static var softReveal: AnyTransition { .opacity.combined(with: .offset(y: -6)) }
}

