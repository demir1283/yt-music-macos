import AppKit
import Observation

/// New versions, from the project's GitHub Releases.
///
/// At launch and then once a day the app asks GitHub for the latest release: one public
/// request, no account, nothing sent but the app's version (in the User-Agent). When it
/// is newer than this build, the sidebar offers it. "Update" works the way the app was
/// installed:
/// - Built from source (build.sh records the folder): `git pull --ff-only`, then
///   `./build.sh` — which quits this copy and opens the new one.
/// - From the .dmg: the release's `YT-Music.dmg` is downloaded, its app copied over this
///   one, and the app opens again. Downloaded by the app itself, it isn't quarantined, so
///   macOS doesn't ask again.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let url: URL
        /// The release's disk image, when it has one.
        var dmg: URL? = nil
    }

    /// The disk image attached to a release (GitHub's `assets`), by its fixed name.
    nonisolated static let dmgName = "YT-Music.dmg"
    nonisolated static func dmgAsset(in release: [String: Any]) -> URL? {
        let assets = release["assets"] as? [[String: Any]] ?? []
        return assets.first { ($0["name"] as? String) == dmgName }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
    }

    enum Phase: Equatable {
        case idle
        /// Downloading and building: 0…1, read from git's and build.sh's output.
        case updating(Double)
        /// Built and installed; build.sh is about to quit this copy and open the new one.
        case restarting
        /// The last lines of the update's output.
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .updating, .restarting: return true
            default: return false
            }
        }
    }

    enum CheckState: Equatable {
        case none, checking, upToDate, failed
    }

    static let repo = "demir1283/yt-music-macos"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!

    private(set) var available: Release?
    private(set) var phase: Phase = .idle
    private(set) var checkState: CheckState = .none
    /// "Later": the card stays hidden until the next launch.
    var dismissed = false

    var enabled: Bool = UserDefaults.standard.object(forKey: "updateCheck") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "updateCheck")
            schedule()
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var progressTimer: Timer?

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The folder the app was built from, while it is still a git clone with build.sh.
    static var sourceFolder: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "YTMSourcePath") as? String,
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent(".git").path),
              fm.isExecutableFile(atPath: url.appendingPathComponent("build.sh").path) else { return nil }
        return url
    }

    /// This copy can be replaced in place (installed from the .dmg, in a folder the user
    /// can write to).
    static var canReplaceInPlace: Bool {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: folder)
    }

    var canUpdateHere: Bool {
        Self.sourceFolder != nil || (available?.dmg != nil && Self.canReplaceInPlace)
    }

    private init() {}

    func start() { schedule() }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            Task { await self?.check() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in await Updater.shared.check() }
        }
    }

    /// Asks GitHub for the latest release. `manual` checks even when checking is turned
    /// off and reports "up to date" / failures through `checkState`.
    @discardableResult
    func check(manual: Bool = false) async -> CheckState {
        guard enabled || manual, !phase.isBusy else { return checkState }
        if manual { checkState = .checking }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("YTMusicMac/\(Self.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                // 404: no release published yet.
                checkState = status == 404 ? .upToDate : .failed
                return checkState
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if Self.isNewer(version, than: Self.current) {
                let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.releasesPage
                let release = Release(version: version, notes: json["body"] as? String ?? "", url: page,
                                      dmg: Self.dmgAsset(in: json))
                if release != available { dismissed = false }
                available = release
            } else {
                available = nil
            }
            checkState = .upToDate
            EngineLog.write("Güncelleme denetimi: son sürüm \(version), bu sürüm \(Self.current)")
        } catch {
            checkState = .failed
            EngineLog.write("Güncelleme denetimi: \(error.localizedDescription)")
        }
        return checkState
    }

    /// The menu's "Check for Updates…": the sidebar card shows a new version; otherwise
    /// a short alert says so.
    func checkFromMenu() {
        Task {
            let state = await check(manual: true)
            if available != nil { dismissed = false; return }
            let alert = NSAlert()
            if state == .failed {
                alert.messageText = M.t("GitHub'a ulaşılamadı", "Couldn't reach GitHub")
                alert.informativeText = M.t("Bağlantını denetleyip biraz sonra yeniden dene.", "Check your connection and try again in a little while.")
            } else {
                alert.messageText = M.t("YT Music güncel", "YT Music is up to date")
                alert.informativeText = M.t("\(Self.current) en son sürüm.", "\(Self.current) is the latest version.")
            }
            alert.runModal()
        }
    }

    /// Pulls the new version and builds it. On success build.sh quits this copy and opens
    /// the new one; if a step fails, the old app keeps running and shows the output.
    func update() {
        guard !phase.isBusy else { return }
        if Self.sourceFolder == nil, let dmg = available?.dmg {
            updateFromDiskImage(dmg)
            return
        }
        guard let folder = Self.sourceFolder else { return }
        phase = .updating(0)
        let install = Bundle.main.bundlePath.hasPrefix("/Applications/") ? " --install" : ""
        let logURL = folder.appendingPathComponent(".build/update.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)

        let script = """
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin:$PATH"
        cd "$0" || exit 1
        echo "▸ git pull --ff-only"
        git pull --ff-only || exit 2
        ./build.sh\(install)
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", script, folder.path]
        task.currentDirectoryURL = folder
        if let handle = try? FileHandle(forWritingTo: logURL) {
            task.standardOutput = handle
            task.standardError = handle
        }
        task.terminationHandler = { process in
            let status = process.terminationStatus
            Task { @MainActor in
                Updater.shared.progressTimer?.invalidate()
                guard status != 0 else { return }
                let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                Updater.shared.phase = .failed(String(output.suffix(2000)))
                EngineLog.write("Güncelleme başarısız (\(status))")
            }
        }
        do {
            try task.run()
            EngineLog.write("Güncelleme başladı: \(available?.version ?? "?")")
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            Task { @MainActor in Updater.shared.readProgress(logURL) }
        }
    }

    // MARK: From the .dmg

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
    }

    /// Download progress, reported by URLSession.
    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            Task { @MainActor in Updater.shared.downloaded(fraction) }
        }
        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }

    private func downloaded(_ fraction: Double) {
        guard case .updating = phase else { return }
        phase = .updating(0.05 + 0.8 * min(1, fraction))
    }

    /// Downloads the new disk image, copies its app over this one and opens it again. If
    /// a step fails, this copy keeps running and the card says why.
    private func updateFromDiskImage(_ dmg: URL) {
        phase = .updating(0.02)
        EngineLog.write("Güncelleme başladı (dmg): \(available?.version ?? "?")")
        Task {
            do {
                var request = URLRequest(url: dmg)
                request.setValue("YTMusicMac/\(Self.current)", forHTTPHeaderField: "User-Agent")
                let (file, response) = try await URLSession.shared.download(for: request, delegate: DownloadProgress())
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError(errorDescription: M.t("Disk görüntüsü indirilemedi.", "The disk image couldn't be downloaded."))
                }
                let image = FileManager.default.temporaryDirectory.appendingPathComponent("YT-Music-update.dmg")
                try? FileManager.default.removeItem(at: image)
                try FileManager.default.moveItem(at: file, to: image)
                phase = .updating(0.9)
                let output = try await Self.install(image: image, over: Bundle.main.bundleURL)
                try? FileManager.default.removeItem(at: image)
                EngineLog.write("Güncelleme kuruldu (dmg)\(output.isEmpty ? "" : ": " + output.suffix(200))")
                phase = .restarting
                M.relaunch()
            } catch {
                phase = .failed(error.localizedDescription)
                EngineLog.write("Güncelleme başarısız (dmg): \(error.localizedDescription)")
            }
        }
    }

    /// Mounts the image, copies its app next to `target` and swaps the two (a rename on the
    /// same disk, so this copy is never half replaced), then unmounts.
    private nonisolated static func install(image: URL, over target: URL) async throws -> String {
        let script = """
        set -e
        IMAGE="$0"; TARGET="$1"
        DIR="$(dirname "$TARGET")"; NAME="$(basename "$TARGET")"
        MNT="$(mktemp -d /tmp/ytmusic-update.XXXXXX)"
        hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$IMAGE" >/dev/null
        trap 'hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true; rmdir "$MNT" 2>/dev/null || true' EXIT
        [ -d "$MNT/$NAME" ] || { echo "Disk görüntüsünde $NAME yok"; exit 3; }
        rm -rf "$DIR/.$NAME.new" "$DIR/.$NAME.old"
        ditto "$MNT/$NAME" "$DIR/.$NAME.new"
        codesign --verify "$DIR/.$NAME.new"
        mv "$TARGET" "$DIR/.$NAME.old"
        mv "$DIR/.$NAME.new" "$TARGET"
        rm -rf "$DIR/.$NAME.old"
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
        echo "kuruldu: $TARGET"
        """
        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", script, image.path, target.path]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: UpdateError(errorDescription: output.isEmpty
                        ? M.t("Yeni sürüm kurulamadı.", "The new version couldn't be installed.") : output))
                }
            }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// How far the update is, from the lines written so far: git pull, then swift build's
    /// own "[compiled/total]" counter, then build.sh's packaging and installing steps.
    private func readProgress(_ logURL: URL) {
        guard case .updating(let old) = phase,
              let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        var p = 0.02
        if text.contains("Already up to date") || text.contains("Fast-forward") || text.contains("Updating ") { p = 0.08 }
        if text.contains("Derleniyor") { p = 0.1 }
        if let range = text.range(of: #"\[(\d+)/(\d+)\]"#, options: [.regularExpression, .backwards]) {
            let nums = text[range].dropFirst().dropLast().split(separator: "/").compactMap { Double($0) }
            if nums.count == 2, nums[1] > 0 { p = max(p, 0.1 + 0.75 * min(1, nums[0] / nums[1])) }
        }
        if text.contains("paketleniyor") { p = max(p, 0.88) }
        if text.contains("İmzalanıyor") { p = max(p, 0.93) }
        if text.contains("kopyalanıyor") { p = max(p, 0.97) }
        if text.contains("✓ Hazır") {
            progressTimer?.invalidate()
            phase = .restarting
            return
        }
        phase = .updating(max(old, p))
    }

    func resetFailure() { if case .failed = phase { phase = .idle } }

    /// "2.10.0" is newer than "2.9.1": compared number by number.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
