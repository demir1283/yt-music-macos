import Foundation
import JavaScriptCore

/// Deciphers YouTube stream URLs ("n" and signature challenges) without a web page.
///
/// The player script is downloaded once per player version, pre-processed by yt-dlp's
/// challenge solver (bundled, runs in JavaScriptCore) and saved on disk (the only thing
/// the app keeps there, so playback starts at once after launch); after that
/// each track only costs two tiny function calls.
actor SigSolver {
    static let shared = SigSolver()

    private var ctx: JSContext?
    private var loadedPlayer: String?
    private(set) var sts: Int?

    /// The one thing kept on disk: the prepared solver for the current YouTube player
    /// version (≈1 MB). Older versions are deleted when a new one is saved.
    static let solverDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(AppIdentity.bundleID, isDirectory: true)
            .appendingPathComponent("solver", isDirectory: true)
    }()

    /// "/s/player/abcd1234/…/base.js" → canonical main-variant URL, as yt-dlp uses.
    static func canonicalPlayerURL(_ raw: String) -> URL? {
        guard let r = raw.range(of: #"/s/player/([0-9a-fA-F]{8,})/"#, options: .regularExpression) else { return nil }
        let id = raw[r].split(separator: "/")[2]
        return variantURL(id: String(id), variant: "main")
    }

    /// The builds of one player version YouTube serves; their "n" and signature
    /// functions are the same. Tried in this order: since players 05a4ffc0 / b485e332
    /// (November 2026) the solver can't prepare the main build (yt-dlp-ejs drops the
    /// player's class-inheritance calls, and a class is then built without its base:
    /// "a.addOnDisposeCallback is not a function"); the TV build still prepares. yt-dlp
    /// made the same switch (yt-dlp#18124, ejs#79).
    static let variants = ["tv", "main"]

    static func variantURL(id: String, variant: String) -> URL? {
        let path = variant == "tv" ? "tv-player-ias.vflset/tv-player-ias.js" : "player_ias.vflset/en_US/base.js"
        return URL(string: "https://www.youtube.com/s/player/\(id)/\(path)")
    }

    static func playerID(_ url: URL) -> String {
        let parts = url.path.split(separator: "/")
        if let i = parts.firstIndex(of: "player"), parts.indices.contains(i + 1) { return String(parts[i + 1]) }
        return String(url.path.hashValue)
    }

    /// Makes sure the solver for this player version is ready. Returns its signature timestamp.
    /// Each build of the player (TV first, then main) is tried until one prepares.
    @discardableResult
    func prepare(playerURL: URL) async throws -> Int? {
        let id = Self.playerID(playerURL)
        if loadedPlayer == id, ctx != nil { return sts }
        var failure: Error?
        for variant in Self.variants {
            guard let url = Self.variantURL(id: id, variant: variant) else { continue }
            do {
                let (f, foundSts) = try await load(id: id, variant: variant, url: url)
                ctx = f
                loadedPlayer = id
                sts = foundSts
                return foundSts
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                EngineLog.write("Çözücü (\(variant)) hazırlanamadı: \(error.localizedDescription)")
                failure = error
            }
        }
        throw failure ?? StreamError.unplayable(M.t("Çözücü hazırlanamadı", "The solver couldn't be prepared"))
    }

    /// One build of the player: from disk when it was prepared before, otherwise
    /// downloaded and pre-processed. Returns a small context holding only the two
    /// solver functions, and the signature timestamp.
    private func load(id: String, variant: String, url playerURL: URL) async throws -> (JSContext, Int?) {
        let preFile = Self.solverDir.appendingPathComponent("ejs-\(EJSScripts.version)-\(id)-\(variant).js")
        let stsFile = Self.solverDir.appendingPathComponent("ejs-\(EJSScripts.version)-\(id)-\(variant).sts")
        var pre = try? String(contentsOf: preFile, encoding: .utf8)
        var foundSts = (try? String(contentsOf: stsFile, encoding: .utf8)).flatMap { Int($0) }
        if pre != nil { EngineLog.write("Çözücü diskten yüklendi (\(id), \(variant))") }

        let c = JSContext()!
        var jsError: String?
        c.exceptionHandler = { _, e in jsError = e?.toString() }

        if pre == nil {
            EngineLog.write("Çözücü: oynatıcı betiği indiriliyor (\(id), \(variant))")
            let fetchStarted = Date()
            var req = URLRequest(url: playerURL)
            req.setValue(YTAuth.userAgent, forHTTPHeaderField: "User-Agent")
            req.timeoutInterval = 30
            let (data, _) = try await NoCacheSession.shared.data(for: req)
            let code = String(decoding: data, as: UTF8.self)
            guard code.count > 100_000 else { throw StreamError.unplayable(M.t("Oynatıcı betiği alınamadı", "Player script couldn't be loaded")) }
            if foundSts == nil, let r = code.range(of: #"(?:signatureTimestamp|sts)\s*:\s*[0-9]{5}"#, options: .regularExpression) {
                foundSts = Int(code[r].filter(\.isNumber).suffix(5))
            }
            guard let lib = EJSScripts.lib, let core = EJSScripts.core else {
                throw StreamError.unplayable(M.t("Çözücü dosyaları uygulama paketinde yok", "The solver files are missing from the app bundle"))
            }
            let started = Date()
            c.evaluateScript(lib)
            c.evaluateScript("Object.assign(globalThis, lib);")
            c.evaluateScript(core)
            c.setObject(code, forKeyedSubscript: "__player" as NSString)
            let out = c.evaluateScript("""
                (function () {
                  var r = jsc({ type: 'player', player: __player, requests: [], output_preprocessed: true });
                  __player = null;
                  return r && r.preprocessed_player ? r.preprocessed_player : null;
                })()
                """)
            guard let o = out, o.isString, let s = o.toString(), !s.isEmpty else {
                throw StreamError.unplayable(M.t("Çözücü hazırlanamadı: \(jsError ?? "bilinmeyen hata")", "The solver couldn't be prepared: \(jsError ?? "unknown error")"))
            }
            pre = s
            Self.saveSolver(s, sts: foundSts, pre: preFile, stsFile: stsFile)
            EngineLog.write(String(format: "Çözücü hazır (%@, indirme %.1f sn, hazırlama %.1f sn)", variant,
                                   started.timeIntervalSince(fetchStarted), Date().timeIntervalSince(started)))
        }

        // A fresh, small context holding only the two solver functions.
        let f = JSContext()!
        var fError: String?
        f.exceptionHandler = { _, e in fError = e?.toString() }
        f.setObject(pre!, forKeyedSubscript: "__pre" as NSString)
        f.evaluateScript("""
            var __fns = (function () {
              var r = { n: null, sig: null };
              Function('_result', __pre)(r);
              return r;
            })();
            __pre = null;
            """)
        guard f.evaluateScript("typeof __fns.n === 'function'")?.toBool() == true else {
            try? FileManager.default.removeItem(at: preFile)
            throw StreamError.unplayable(M.t("Çözücü fonksiyonları bulunamadı: \(fError ?? "")", "Solver functions not found: \(fError ?? "")"))
        }
        return (f, foundSts)
    }

    func solve(n: String?, sig: String?) throws -> (n: String?, sig: String?) {
        guard let ctx else { throw StreamError.unplayable(M.t("Çözücü hazır değil", "The solver isn't ready")) }
        var lastError: String?
        ctx.exceptionHandler = { _, e in lastError = e?.toString() }
        func run(_ fn: String, _ value: String) throws -> String {
            lastError = nil
            let r = ctx.objectForKeyedSubscript("__fns")?.objectForKeyedSubscript(fn)?.call(withArguments: [value])
            guard let r, r.isString, let s = r.toString(), lastError == nil else {
                throw StreamError.unplayable(M.t("\(fn) çözülemedi: \(lastError ?? "boş sonuç")", "\(fn) couldn't be solved: \(lastError ?? "empty result")"))
            }
            return s
        }
        let outN = try n.map { try run("n", $0) }
        let outSig = try sig.map { try run("sig", $0) }
        return (outN, outSig)
    }

    /// Forget a broken cached solver (e.g. after YouTube rejected the deciphered URL).
    func invalidate() {
        try? FileManager.default.removeItem(at: Self.solverDir)
        ctx = nil
        loadedPlayer = nil
    }
}

extension SigSolver {
    /// Writes the prepared solver, keeping only this player version on disk.
    static func saveSolver(_ code: String, sts: Int?, pre: URL, stsFile: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: solverDir)
        try? fm.createDirectory(at: solverDir, withIntermediateDirectories: true)
        try? code.write(to: pre, atomically: true, encoding: .utf8)
        if let sts { try? String(sts).write(to: stsFile, atomically: true, encoding: .utf8) }
    }
}

/// Diagnostics go to the system log. A file ("YT Music.log" next to the app) is written
/// only while troubleshooting is switched on:
///   defaults write io.github.demir1283.ytmusic diagnosticLog -bool true   (off: delete instead of write)
enum EngineLog {
    static let enabled = UserDefaults.standard.bool(forKey: "diagnosticLog")
    private static let url: URL = Bundle.main.bundleURL.deletingLastPathComponent()
        .appendingPathComponent("YT Music.log")
    /// The session before this one, kept so that a problem isn't lost by restarting.
    private static let previousURL: URL = url.deletingLastPathComponent()
        .appendingPathComponent("YT Music (önceki).log")
    private static let queue = DispatchQueue(label: "ytmusic.log")

    /// A new session: the last one's log becomes "YT Music (önceki).log", this one starts empty.
    static func reset() {
        guard enabled else { return }
        queue.async {
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: previousURL)
                try? fm.moveItem(at: url, to: previousURL)
            }
            try? Data().write(to: url)
        }
    }

    static func write(_ message: String) {
        NSLog("YT Music: %@", message)
        guard enabled else { return }
        let stamp = Date().formatted(date: .omitted, time: .standard)
        guard let data = "\(stamp)  \(message)\n".data(using: .utf8) else { return }
        queue.async {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
