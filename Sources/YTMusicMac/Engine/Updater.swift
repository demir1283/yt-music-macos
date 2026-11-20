import AppKit
import Observation

/// New versions, from the project's GitHub Releases.
///
/// At launch and then once a day the app asks GitHub for the latest release: one public
/// request, no account, nothing sent but the app's version (in the User-Agent). When it
/// is newer than this build, the sidebar offers it. "Update" runs the two steps of a
/// manual update in the folder the app was built from (build.sh records it):
/// `git pull --ff-only`, then `./build.sh` — which quits this copy and opens the new one.
@MainActor @Observable
final class Updater {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let url: URL
    }

    enum Phase: Equatable {
        case idle
        case updating
        /// The last lines of the update's output.
        case failed(String)
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

    var canUpdateHere: Bool { Self.sourceFolder != nil }

    private init() {}

    func start() { schedule() }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
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
        guard enabled || manual, phase != .updating else { return checkState }
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
                let release = Release(version: version, notes: json["body"] as? String ?? "", url: page)
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
        guard let folder = Self.sourceFolder, phase != .updating else { return }
        phase = .updating
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
        }
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
