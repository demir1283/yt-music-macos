import SwiftUI

/// Bottom of the sidebar, above the account card: a new version, then its progress while
/// it downloads and builds. Shown only when GitHub has something newer.
struct UpdateCard: View {
    private var updater: Updater { Updater.shared }

    var body: some View {
        if let release = updater.available, !updater.dismissed || updater.phase != .idle {
            VStack(alignment: .leading, spacing: 8) {
                if updater.phase == .idle {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.brand)
                        Text(M.t("Yeni sürüm: \(release.version)", "New version: \(release.version)"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
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
                UpdateAction(release: release)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thickMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .animation(.soft, value: updater.phase)
            .transition(.softReveal)
        }
    }
}

/// The update button, or the update's progress in its place. Used by the sidebar card
/// and by Settings, so an update started in either place is followed there.
struct UpdateAction: View {
    let release: Updater.Release
    private var updater: Updater { Updater.shared }
    @ViewState var showLog = false

    var body: some View {
        switch updater.phase {
        case .idle:
            if updater.canUpdateHere {
                pill(M.t("Güncelle", "Update")) { updater.update() }
            } else {
                // Built from a folder that is gone: the release page instead.
                pill(M.t("GitHub'da Aç", "Open on GitHub")) { NSWorkspace.shared.open(release.url) }
            }
        case .updating(let progress):
            progressRow(M.t("İndiriliyor… %\(Int(progress * 100))", "Downloading… \(Int(progress * 100))%"), progress)
        case .restarting:
            progressRow(M.t("Yeniden başlatılıyor…", "Restarting…"), 1)
        case .failed(let log):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(M.t("Güncellenemedi", "Update failed"))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Button { showLog.toggle() } label: {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(M.t("Ayrıntılar", "Details"))
                .popover(isPresented: $showLog, arrowEdge: .trailing) { UpdateLog(log: log) }
                pill(M.t("Tekrar Dene", "Try Again")) { updater.resetFailure(); updater.update() }
            }
        }
    }

    private func progressRow(_ text: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(Color.brand)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
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
}

/// Why the update failed: the last lines of git's and build.sh's output.
private struct UpdateLog: View {
    let log: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(log.isEmpty ? M.t("Çıktı yok.", "No output.") : log)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            Text(M.t("Elle güncellemek için Terminal'de projenin klasöründe: git pull && ./build.sh --install",
                     "To update by hand, in Terminal in the project folder: git pull && ./build.sh --install"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 420)
    }
}
