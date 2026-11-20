import SwiftUI

/// Above the account card: a new version from GitHub, while it is being installed, or
/// why installing it failed.
struct UpdateCard: View {
    private var updater: Updater { Updater.shared }
    @ViewState var showNotes = false
    @ViewState var showLog = false

    var body: some View {
        if let release = updater.available, !updater.dismissed || updater.phase != .idle {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.brand)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(release))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if updater.phase == .idle {
                        Button { updater.dismissed = true } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(M.t("Sonra", "Later"))
                    }
                }
                buttons(release)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thickMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.brand.opacity(0.35), lineWidth: 0.75))
        }
    }

    private var icon: String {
        switch updater.phase {
        case .idle: return "arrow.down.circle.fill"
        case .updating: return "gearshape.2.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func title(_ release: Updater.Release) -> String {
        switch updater.phase {
        case .idle: return M.t("YT Music \(release.version) çıktı", "YT Music \(release.version) is out")
        case .updating: return M.t("Güncelleniyor…", "Updating…")
        case .failed: return M.t("Güncellenemedi", "The update failed")
        }
    }

    private var subtitle: String {
        switch updater.phase {
        case .idle:
            return M.t("Yüklü sürüm: \(Updater.current)", "Installed: \(Updater.current)")
        case .updating:
            return M.t("Derleme bir iki dakika sürer; uygulama sonra kendini yeniden açar.",
                       "Building takes a minute or two; the app then reopens by itself.")
        case .failed:
            return M.t("Eski sürüm çalışmaya devam ediyor.", "The old version keeps running.")
        }
    }

    @ViewBuilder
    private func buttons(_ release: Updater.Release) -> some View {
        switch updater.phase {
        case .idle:
            HStack(spacing: 6) {
                if updater.canUpdateHere {
                    primary(M.t("Güncelle", "Update")) { updater.update() }
                } else {
                    primary(M.t("İndir…", "Download…")) { NSWorkspace.shared.open(release.url) }
                }
                secondary(M.t("Yenilikler", "What's New")) { showNotes.toggle() }
                    .popover(isPresented: $showNotes, arrowEdge: .trailing) { NotesView(release: release) }
            }
        case .updating:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let log):
            HStack(spacing: 6) {
                primary(M.t("Tekrar Dene", "Try Again")) { updater.resetFailure(); updater.update() }
                secondary(M.t("Ayrıntılar", "Details")) { showLog.toggle() }
                    .popover(isPresented: $showLog, arrowEdge: .trailing) { LogView(log: log, url: release.url) }
            }
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(Color.brand))
        }
        .buttonStyle(PressScaleStyle())
    }

    private func secondary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

/// The release notes, as written on GitHub (Markdown).
private struct NotesView: View {
    let release: Updater.Release

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YT Music \(release.version)")
                .font(.system(size: 15, weight: .bold))
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxHeight: 320)
            Button(M.t("GitHub'da Aç", "Open on GitHub")) { NSWorkspace.shared.open(release.url) }
                .controlSize(.small)
        }
        .padding(14)
        .frame(width: 380)
    }

    /// One paragraph or list item per line; inline Markdown (bold, links, code) kept.
    private var lines: [AttributedString] {
        release.notes
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { raw in
                var line = raw
                if line.hasPrefix("### ") || line.hasPrefix("## ") { line = "**" + line.drop { $0 == "#" || $0 == " " } + "**" }
                if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "•  " + line.dropFirst(2) }
                return (try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                    ?? AttributedString(line)
            }
    }
}

/// Why the update failed: the last lines of git's and build.sh's output.
private struct LogView: View {
    let log: String
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(M.t("Güncelleme çıktısı", "Update output"))
                .font(.system(size: 13, weight: .semibold))
            ScrollView {
                Text(log.isEmpty ? M.t("Çıktı yok.", "No output.") : log)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            Text(M.t("Elle güncellemek için Terminal'de projenin klasöründe: git pull && ./build.sh --install",
                     "To update by hand, in Terminal in the project folder: git pull && ./build.sh --install"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(M.t("GitHub'da Aç", "Open on GitHub")) { NSWorkspace.shared.open(url) }
                .controlSize(.small)
        }
        .padding(14)
        .frame(width: 420)
    }
}
