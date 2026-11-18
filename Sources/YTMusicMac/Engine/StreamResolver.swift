import Foundation

/// A directly playable audio stream for one track.
struct ResolvedStream {
    let url: URL
    let headers: [String: String]
    /// Short description shown in the Oynatma menu, e.g. "AAC 128 kbps".
    let label: String
    let duration: Double
    let expires: Date
    /// "signed": the account's own stream (deciphered); "direct": anonymous app client.
    var source = "direct"
    /// Byte ranges of the file's header and of its index, when YouTube gave them.
    var initRange: ClosedRange<Int>?
    var indexRange: ClosedRange<Int>?
    /// A playlist made from that index (`DashToHLS`), so a long file starts at once.
    var playlist: URL?
    /// What the player is given.
    var playURL: URL { playlist ?? url }
}

enum StreamError: LocalizedError {
    case unplayable(String)
    case noFormat

    var errorDescription: String? {
        switch self {
        case .unplayable(let reason): return reason
        case .noFormat: return "Uygun ses akışı bulunamadı"
        }
    }
}

/// Asks YouTube for the audio stream of a video the way its own apps do, and picks the
/// best stream AVPlayer can play as-is (AAC in MP4, or HLS). Nothing is re-encoded.
enum StreamResolver {
    private struct Client {
        let name: String
        let id: String
        let version: String
        let userAgent: String
        let extra: [String: Any]
    }

    // Clients that return ready-to-play URLs (no signature deciphering needed).
    private static let clients: [Client] = [
        Client(name: "VISIONOS", id: "101", version: "1.02",
               userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
               extra: ["deviceMake": "Apple", "deviceModel": "RealityDevice17,1", "osName": "visionOS", "osVersion": "26.5.23O471"]),
        Client(name: "ANDROID_VR", id: "28", version: "1.65.10",
               userAgent: "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
               extra: ["deviceMake": "Oculus", "deviceModel": "Quest 3", "androidSdkVersion": 32, "osName": "Android", "osVersion": "12L"]),
    ]

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    // MARK: Signed-in stream (what YouTube Music's web player gets; Premium = 256 kbps)

    @MainActor
    static func resolveSigned(videoId: String, core: NativeCore, playerJS: URL?, sts: Int?) async throws -> ResolvedStream {
        var sts = sts
        if let playerJS {
            let s = try await SigSolver.shared.prepare(playerURL: playerJS)
            sts = s ?? sts
        }
        var args: [String: Any] = ["videoId": videoId]
        if let sts { args["sts"] = sts }
        let argData = try JSONSerialization.data(withJSONObject: args)
        let json = try await core.call("playerData", argsJSON: String(decoding: argData, as: UTF8.self))
        let data = try JSONDecoder().decode(PlayerData.self, from: Data(json.utf8))
        if data.status != "OK" {
            throw StreamError.unplayable(data.reason.isEmpty ? data.status : data.reason)
        }
        if let got = data.videoId, got != videoId { throw StreamError.unplayable("Farklı bir video döndü") }

        let candidates = data.formats.filter {
            $0.mimeType.hasPrefix("audio/mp4") && !$0.drc && $0.isDefault && ($0.url != nil || $0.cipher != nil)
        }.sorted { $0.bitrate > $1.bitrate }
        guard let best = candidates.first else {
            if data.sabr { throw StreamError.unplayable("YouTube bu oturum için yalnızca SABR akışı veriyor") }
            throw StreamError.noFormat
        }

        // Signature cipher: "s=…&sp=sig&url=…"
        var base = best.url
        var sig: String?
        var sp = "signature"
        if base == nil, let c = best.cipher {
            var comps = URLComponents()
            comps.percentEncodedQuery = c
            for item in comps.queryItems ?? [] {
                switch item.name {
                case "url": base = item.value
                case "s": sig = item.value
                case "sp": sp = item.value ?? sp
                default: break
                }
            }
        }
        guard let base, var comps = URLComponents(string: base) else { throw StreamError.noFormat }
        let n = comps.queryItems?.first(where: { $0.name == "n" })?.value
        if n != nil || sig != nil {
            guard playerJS != nil else { throw StreamError.unplayable("Oynatıcı betiği bulunamadı") }
            let solved = try await SigSolver.shared.solve(n: n, sig: sig)
            // Keep YouTube's own encoding for every other parameter.
            var items = comps.percentEncodedQueryItems ?? []
            if let n2 = solved.n, let i = items.firstIndex(where: { $0.name == "n" }) {
                items[i] = URLQueryItem(name: "n", value: encode(n2))
            }
            if let s2 = solved.sig { items.append(URLQueryItem(name: sp, value: encode(s2))) }
            comps.percentEncodedQueryItems = items
        }
        guard let url = comps.url else { throw StreamError.noFormat }

        var duration = data.length > 0 ? data.length + 0.9 : 0
        if let ms = best.approxDurationMs, let exact = Double(ms), exact > 0 { duration = exact / 1000 }
        let label: String
        switch best.itag {
        case 141: label = "AAC 256 kbps (Premium)"
        case 140: label = "AAC 128 kbps"
        default:
            let kbps = Int((Double(best.averageBitrate > 0 ? best.averageBitrate : best.bitrate) / 1000).rounded())
            label = "AAC \(kbps) kbps"
        }
        let headers = [
            "User-Agent": YTAuth.userAgent,
            "Origin": YTAuth.origin,
            "Referer": YTAuth.origin + "/",
        ]
        var stream = ResolvedStream(url: url, headers: headers, label: label, duration: duration,
                                    expires: expiry(of: url.absoluteString))
        stream.source = "signed"
        if let r = best.initRange, r.count == 2, r[0] <= r[1] { stream.initRange = r[0]...r[1] }
        if let r = best.indexRange, r.count == 2, r[0] <= r[1] { stream.indexRange = r[0]...r[1] }
        return stream
    }

    // MARK: Anonymous app clients (fallback)

    static func resolve(videoId: String, visitorData: String?) async throws -> ResolvedStream {
        var lastError: Error = StreamError.noFormat
        for client in clients {
            do {
                return try await resolve(videoId: videoId, visitorData: visitorData, client: client)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func resolve(videoId: String, visitorData: String?, client: Client) async throws -> ResolvedStream {
        var clientInfo: [String: Any] = [
            "clientName": client.name,
            "clientVersion": client.version,
            "userAgent": client.userAgent,
            "hl": "en",
            "timeZone": "UTC",
            "utcOffsetMinutes": 0,
        ]
        for (k, v) in client.extra { clientInfo[k] = v }
        if let visitorData { clientInfo["visitorData"] = visitorData }
        let body: [String: Any] = [
            "context": ["client": clientInfo],
            "videoId": videoId,
            "playbackContext": ["contentPlaybackContext": ["html5Preference": "HTML5_PREF_WANTS"]],
            "contentCheckOk": true,
            "racyCheckOk": true,
        ]
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(client.id, forHTTPHeaderField: "X-YouTube-Client-Name")
        req.setValue(client.version, forHTTPHeaderField: "X-YouTube-Client-Version")
        req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        if let visitorData { req.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id") }

        let (data, _) = try await session.data(for: req)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw StreamError.noFormat
        }
        let status = root["playabilityStatus"] as? [String: Any]
        if let s = status?["status"] as? String, s != "OK" {
            throw StreamError.unplayable((status?["reason"] as? String) ?? s)
        }
        // The response must be for the video we asked for (YouTube sometimes swaps it).
        let details = root["videoDetails"] as? [String: Any]
        if let got = details?["videoId"] as? String, got != videoId {
            throw StreamError.unplayable("Farklı bir video döndü")
        }
        guard let streaming = root["streamingData"] as? [String: Any] else { throw StreamError.noFormat }
        let headers = ["User-Agent": client.userAgent]
        // Whole seconds only; padded so playback is never cut short by rounding.
        var duration = (Double((details?["lengthSeconds"] as? String) ?? "") ?? 0)
        if duration > 0 { duration += 0.9 }

        // 1) Progressive AAC (what Premium's 256 kbps and the regular 128 kbps streams are).
        let formats = (streaming["adaptiveFormats"] as? [[String: Any]]) ?? []
        let audio = formats.filter { f in
            guard let mime = f["mimeType"] as? String, mime.hasPrefix("audio/mp4"), f["url"] is String else { return false }
            if (f["isDrc"] as? Bool) == true { return false }
            if let t = f["audioTrack"] as? [String: Any], (t["audioIsDefault"] as? Bool) == false { return false }
            return true
        }.sorted { ($0["bitrate"] as? Int ?? 0) > ($1["bitrate"] as? Int ?? 0) }
        if let best = audio.first, let s = best["url"] as? String, let url = URL(string: s) {
            if let ms = best["approxDurationMs"] as? String, let exact = Double(ms), exact > 0 { duration = exact / 1000 }
            let kbps = Int((Double(best["averageBitrate"] as? Int ?? best["bitrate"] as? Int ?? 0) / 1000).rounded())
            var stream = ResolvedStream(url: url, headers: headers, label: "AAC \(kbps) kbps",
                                        duration: duration, expires: expiry(of: s))
            stream.initRange = byteRange(best["initRange"])
            stream.indexRange = byteRange(best["indexRange"])
            return stream
        }

        // 2) HLS: play only its best audio rendition.
        if let m = streaming["hlsManifestUrl"] as? String, let master = URL(string: m) {
            var req = URLRequest(url: master)
            req.setValue(client.userAgent, forHTTPHeaderField: "User-Agent")
            if let result = try? await session.data(for: req),
               let pick = bestAudioRendition(in: String(decoding: result.0, as: UTF8.self), base: master) {
                return ResolvedStream(url: pick, headers: headers, label: "AAC (HLS)",
                                      duration: duration, expires: expiry(of: m))
            }
            return ResolvedStream(url: master, headers: headers, label: "HLS",
                                  duration: duration, expires: expiry(of: m))
        }
        throw StreamError.noFormat
    }

    /// {"start": "0", "end": "722"} → 0...722
    private static func byteRange(_ value: Any?) -> ClosedRange<Int>? {
        guard let d = value as? [String: Any],
              let start = Int("\(d["start"] ?? "")"), let end = Int("\(d["end"] ?? "")"), start <= end else { return nil }
        return start...end
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    /// Stream URLs carry their expiry time ("expire=…" or "/expire/…/").
    private static func expiry(of url: String) -> Date {
        for marker in ["expire=", "/expire/"] {
            if let r = url.range(of: marker) {
                let digits = url[r.upperBound...].prefix { $0.isNumber }
                if let t = Double(digits), t > 0 { return Date(timeIntervalSince1970: t - 600) }
            }
        }
        return Date().addingTimeInterval(4 * 3600)
    }

    private static func attributes(_ line: String) -> [String: String] {
        var out: [String: String] = [:]
        var key = "", value = "", inKey = true, inQuotes = false
        func flush() {
            if !key.isEmpty { out[key.trimmingCharacters(in: .whitespaces)] = value }
            key = ""; value = ""; inKey = true
        }
        guard let colon = line.firstIndex(of: ":") else { return out }
        for ch in line[line.index(after: colon)...] {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == "," && !inQuotes { flush(); continue }
            if ch == "=" && inKey && !inQuotes { inKey = false; continue }
            if inKey { key.append(ch) } else { value.append(ch) }
        }
        flush()
        return out
    }

    /// Picks the default-language audio rendition with the highest quality group.
    private static func bestAudioRendition(in manifest: String, base: URL) -> URL? {
        var best: (score: Int, url: URL)?
        for raw in manifest.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.hasPrefix("#EXT-X-MEDIA:"), line.contains("TYPE=AUDIO") else { continue }
            let a = attributes(line)
            guard let uri = a["URI"], let url = URL(string: uri, relativeTo: base)?.absoluteURL else { continue }
            var score = 0
            if a["DEFAULT"] == "YES" { score += 100_000 }
            let group = a["GROUP-ID"] ?? ""
            score += Int(group.filter(\.isNumber)) ?? 0
            if let r = uri.range(of: "/itag/") {
                score += Int(uri[r.upperBound...].prefix { $0.isNumber }) ?? 0
            }
            if best == nil || score > best!.score { best = (score, url) }
        }
        return best?.url
    }
}
