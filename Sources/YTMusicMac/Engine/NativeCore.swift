import Foundation
import JavaScriptCore
import CryptoKit
import WebKit

/// Runs the YouTube Music data layer without a web page.
///
/// The same script the hidden web player used (`BridgeScript.source`) is evaluated in a
/// bare JavaScriptCore context; its HTTP requests are carried out here with URLSession,
/// using the signed-in cookies. No WebKit page (and none of its memory) is involved.
///
/// The script runs on its own serial queue, never on the main thread: reading YouTube's
/// answers (up to 3 MB of JSON each, a dozen at once at launch) would otherwise hold up
/// drawing and scrolling. Everything that touches the context goes through `queue`.
final class NativeCore: @unchecked Sendable {
    private let ctx: JSContext
    private let session: URLSession
    private let queue = DispatchQueue(label: "ytmusic.script", qos: .userInitiated)

    init?() {
        guard let c = JSContext() else { return nil }
        ctx = c
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 25
        session = URLSession(configuration: cfg)
        // Loaded on the script's queue: the main thread doesn't wait. Every later use of the
        // context goes through the same queue, so it always comes after this.
        queue.async { [self] in install() }
    }

    private func install() {
        ctx.exceptionHandler = { _, error in
            NSLog("YT Music JS: %@", error?.toString() ?? "?")
        }
        let session = self.session
        let queue = self.queue
        let userAgent = YTAuth.userAgent
        let http: @convention(block) (String, String, String, String, String, JSValue, JSValue) -> Void = {
            url, method, headersJSON, body, auth, resolve, reject in
            guard let u = URL(string: url) else {
                reject.call(withArguments: [M.t("Geçersiz adres", "Invalid address")])
                return
            }
            var req = URLRequest(url: u)
            req.httpMethod = method
            req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req.setValue(YTAuth.acceptLanguage, forHTTPHeaderField: "Accept-Language")
            if let d = headersJSON.data(using: .utf8),
               let h = (try? JSONSerialization.jsonObject(with: d)) as? [String: String] {
                for (k, v) in h { req.setValue(v, forHTTPHeaderField: k) }
            }
            if !auth.isEmpty, let a = YTAuth.authorization(origin: auth) {
                req.setValue(a, forHTTPHeaderField: "Authorization")
            }
            if !body.isEmpty { req.httpBody = Data(body.utf8) }
            let task = session.dataTask(with: req) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                let message = error?.localizedDescription
                queue.async {
                    if let message {
                        reject.call(withArguments: [message])
                    } else {
                        resolve.call(withArguments: [status, text])
                    }
                }
            }
            task.resume()
        }
        ctx.setObject(unsafeBitCast(http, to: AnyObject.self), forKeyedSubscript: "__nativeHttp" as NSString)
        ctx.evaluateScript(BridgeScript.nativePrelude)
        ctx.evaluateScript(BridgeScript.source)
    }

    /// Frees what the script engine no longer needs (after loading many pages at once).
    func collectGarbage() {
        queue.async { [ctx] in
            JSGarbageCollect(ctx.jsGlobalContextRef)
            // Freed blocks otherwise stay counted against the app (≈ 40 MB after start-up).
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    /// Calls one of the script's commands and returns its JSON result.
    func call(_ name: String, argsJSON: String) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async { [ctx] in
                guard let api = ctx.objectForKeyedSubscript("__ytmusic"), !api.isUndefined,
                      let promise = api.invokeMethod("call", withArguments: [name, argsJSON]),
                      !promise.isUndefined, !promise.isNull else {
                    cont.resume(throwing: EngineError.notReady)
                    return
                }
                let ok: @convention(block) (JSValue) -> Void = { value in
                    cont.resume(returning: value.toString() ?? "null")
                }
                let fail: @convention(block) (JSValue) -> Void = { error in
                    var message = error.toString() ?? M.t("Bilinmeyen hata", "Unknown error")
                    if error.isObject, let m = error.objectForKeyedSubscript("message"), m.isString {
                        message = m.toString() ?? message
                    }
                    cont.resume(throwing: EngineError.js(message))
                }
                promise.invokeMethod("then", withArguments: [
                    unsafeBitCast(ok, to: AnyObject.self),
                    unsafeBitCast(fail, to: AnyObject.self),
                ])
            }
        }
    }

    /// Plain GET with the account cookies (used once at start to read the page's config).
    func fetchText(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(YTAuth.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(YTAuth.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        let (data, _) = try await session.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Sign-in cookies and the request signature YouTube's web clients use.
enum YTAuth {
    static let origin = "https://music.youtube.com"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"

    static var acceptLanguage: String {
        let langs = Locale.preferredLanguages.prefix(2)
        return langs.isEmpty ? "en-US" : langs.joined(separator: ",")
    }

    private static func jar() -> [String: String] {
        var out: [String: String] = [:]
        for c in HTTPCookieStorage.shared.cookies(for: URL(string: origin + "/")!) ?? [] {
            out[c.name] = c.value
        }
        return out
    }

    static var hasAuthCookies: Bool {
        let j = jar()
        return j["SAPISID"] != nil || j["__Secure-3PAPISID"] != nil
    }

    /// The `Authorization` value: a hash of the time, a cookie and the origin.
    static func authorization(origin: String = origin) -> String? {
        let j = jar()
        let ts = Int(Date().timeIntervalSince1970)
        func hash(_ secret: String) -> String {
            Insecure.SHA1.hash(data: Data("\(ts) \(secret) \(origin)".utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
        var parts: [String] = []
        if let s = j["SAPISID"] ?? j["__Secure-3PAPISID"] { parts.append("SAPISIDHASH \(ts)_\(hash(s))") }
        if let s = j["__Secure-1PAPISID"] { parts.append("SAPISID1PHASH \(ts)_\(hash(s))") }
        if let s = j["__Secure-3PAPISID"] { parts.append("SAPISID3PHASH \(ts)_\(hash(s))") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private static func isAccountCookie(_ c: HTTPCookie) -> Bool {
        c.domain.contains("youtube.com") || c.domain.contains("google.com")
    }

    /// Copies the sign-in cookies from the sign-in sheet's store (WebKit) to the app's own.
    /// Without `force` this only happens when the app has no session of its own yet.
    @MainActor
    static func syncCookies(force: Bool) async {
        if !force && hasAuthCookies { return }
        let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        let storage = HTTPCookieStorage.shared
        if force { clearCookies() }
        for c in cookies where isAccountCookie(c) { storage.setCookie(c) }
    }

    static func clearCookies() {
        let storage = HTTPCookieStorage.shared
        for c in storage.cookies ?? [] where isAccountCookie(c) { storage.deleteCookie(c) }
    }
}

/// One URLSession for small one-off requests (lyrics, player script): never caches.
enum NoCacheSession {
    static let shared: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()
}

/// Removes everything earlier versions stored and turns off system caches.
enum StorageCleanup {
    @MainActor
    static func run() {
        // No HTTP cache anywhere (memory or disk).
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)
        let fm = FileManager.default
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fm.removeItem(at: caches.appendingPathComponent("YT Music"))
            // Everything in the app's cache folder goes, except the saved stream solver.
            let own = caches.appendingPathComponent(AppIdentity.bundleID)
            for item in (try? fm.contentsOfDirectory(at: own, includingPropertiesForKeys: nil)) ?? []
            where item.lastPathComponent != SigSolver.solverDir.lastPathComponent {
                try? fm.removeItem(at: item)
            }
        }
        // Old diagnostics log next to the app.
        if !UserDefaults.standard.bool(forKey: "diagnosticLog") {
            try? fm.removeItem(at: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("YT Music.log"))
        }
        // The big saved queue of earlier versions.
        UserDefaults.standard.removeObject(forKey: "lastSession")
        // Web data left by the old hidden web player / sign-in page: keep only cookies
        // (the sign-in). Done once.
        if !UserDefaults.standard.bool(forKey: "cleanedWebData2") {
            let store = WKWebsiteDataStore.default()
            var types = WKWebsiteDataStore.allWebsiteDataTypes()
            types.remove(WKWebsiteDataTypeCookies)
            store.removeData(ofTypes: types, modifiedSince: .distantPast) {
                UserDefaults.standard.set(true, forKey: "cleanedWebData2")
            }
        }
    }

    /// After signing in: the sign-in page's cache and storage go, cookies stay.
    @MainActor
    static func clearWebCaches() {
        var types = WKWebsiteDataStore.allWebsiteDataTypes()
        types.remove(WKWebsiteDataTypeCookies)
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }
}
