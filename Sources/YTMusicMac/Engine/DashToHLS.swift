import Foundation
import AVFoundation

/// Lets long recordings start at once.
///
/// YouTube's audio files are fragmented MP4: a short header, an index (the "sidx" box:
/// how many bytes and seconds each ~10 s piece has), then the pieces. Given the file's
/// address alone, AVPlayer reads most of the file before it starts: 50 MB and 12 s for an
/// hour-long set. Instead it gets an HLS playlist written from that index, in which the
/// header and every piece are byte ranges of that very same address. AVPlayer then fetches
/// the header and the first piece, starts, and loads ahead only what it buffers. Same bytes
/// as before, nothing re-encoded.
///
/// A playlist lives only in memory (about 130 KB for an hour-long set, a few KB for a
/// song), and only the last few are kept: the current and the next song's.
final class DashToHLS: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = DashToHLS()
    static let scheme = "ytmhls"
    /// Queue the asset's resource loader calls back on.
    let queue = DispatchQueue(label: "ytmusic.hls")

    struct Piece {
        let offset: Int
        let size: Int
        let seconds: Double
    }

    private let lock = NSLock()
    private var playlists: [String: Data] = [:]
    private var order: [String] = []
    private static let keep = 6
    /// Pieces after the first are joined into parts of at most this length: a shorter
    /// playlist (each line repeats the long address), same bytes.
    static let partSeconds = 30.0

    /// Reads the file's index (one small ranged request) and returns the address of a
    /// playlist for it; nil when there is no index or it can't be read, and the file is
    /// then played as it is.
    func playlist(for stream: ResolvedStream, key: String) async -> URL? {
        guard let header = stream.initRange, let index = stream.indexRange else { return nil }
        var req = URLRequest(url: stream.url)
        for (k, v) in stream.headers { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("bytes=\(index.lowerBound)-\(index.upperBound)", forHTTPHeaderField: "Range")
        req.timeoutInterval = 8
        var data = Data()
        data.reserveCapacity(index.count)
        do {
            let (bytes, response) = try await NoCacheSession.shared.bytes(for: req)
            // Anything but the asked range (e.g. the whole file) is not read at all.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 206 else {
                bytes.task.cancel()
                EngineLog.write("HLS \(key): dizin isteği \(status) döndü; dosya doğrudan çalınacak")
                return nil
            }
            for try await byte in bytes {
                data.append(byte)
                if data.count >= index.count { break }
            }
            bytes.task.cancel()
        } catch {
            EngineLog.write("HLS \(key): dizin alınamadı (\(error.localizedDescription)); dosya doğrudan çalınacak")
            return nil
        }
        guard let pieces = Self.pieces(sidx: data, at: index.lowerBound) else {
            EngineLog.write("HLS \(key): dizin okunamadı; dosya doğrudan çalınacak")
            return nil
        }
        let parts = Self.joined(pieces)
        let text = Self.playlistText(url: stream.url, header: header, parts: parts)
        store(Data(text.utf8), for: key)
        EngineLog.write("HLS \(key): \(pieces.count) parça → \(parts.count) bölüm, liste \(text.utf8.count / 1024) KB")
        return URL(string: "\(Self.scheme)://p/\(key).m3u8")
    }

    // MARK: Index → playlist

    /// The pieces listed in a "sidx" box read from `fileOffset` of the file.
    static func pieces(sidx d: Data, at fileOffset: Int) -> [Piece]? {
        let b = [UInt8](d)
        func u32(_ i: Int) -> Int { b[i..<i + 4].reduce(0) { $0 << 8 | Int($1) } }
        guard b.count >= 32, b[4] == 0x73, b[5] == 0x69, b[6] == 0x64, b[7] == 0x78 else { return nil }   // "sidx"
        let boxSize = u32(0)
        let version = b[8]
        let timescale = Double(u32(16))
        guard boxSize >= 32, boxSize <= b.count, timescale > 0 else { return nil }
        let firstOffset: Int
        let countAt: Int
        if version == 0 {
            firstOffset = u32(24)
            countAt = 30
        } else {
            guard boxSize >= 40 else { return nil }
            firstOffset = u32(28) << 32 | u32(32)
            countAt = 38
        }
        let count = Int(b[countAt]) << 8 | Int(b[countAt + 1])
        let first = countAt + 2
        guard count > 0, first + count * 12 <= boxSize else { return nil }
        // The pieces follow the index box (plus the offset it gives), one after another.
        var offset = fileOffset + boxSize + firstOffset
        var out: [Piece] = []
        out.reserveCapacity(count)
        for k in 0..<count {
            let e = first + k * 12
            let reference = u32(e)
            // A reference to a further index box (not used by YouTube): give up.
            guard reference & 0x8000_0000 == 0 else { return nil }
            let size = reference & 0x7FFF_FFFF
            let seconds = Double(u32(e + 4)) / timescale
            guard size > 0, seconds > 0 else { return nil }
            out.append(Piece(offset: offset, size: size, seconds: seconds))
            offset += size
        }
        return out
    }

    /// The first piece stays on its own (so playback starts after one ~10 s piece); the
    /// rest are joined, back to back, into parts of up to `partSeconds`.
    static func joined(_ pieces: [Piece]) -> [Piece] {
        guard var current = pieces.first else { return [] }
        var parts = [current]
        current = Piece(offset: 0, size: 0, seconds: 0)
        for p in pieces.dropFirst() {
            if current.size > 0, current.seconds + p.seconds > partSeconds {
                parts.append(current)
                current = Piece(offset: 0, size: 0, seconds: 0)
            }
            current = current.size == 0 ? p
                : Piece(offset: current.offset, size: current.size + p.size, seconds: current.seconds + p.seconds)
        }
        if current.size > 0 { parts.append(current) }
        return parts
    }

    private static func playlistText(url: URL, header: ClosedRange<Int>, parts: [Piece]) -> String {
        let address = url.absoluteString
        let target = Int((parts.map(\.seconds).max() ?? 10).rounded(.up))
        var text = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:\(target)
            #EXT-X-PLAYLIST-TYPE:VOD
            #EXT-X-MEDIA-SEQUENCE:0
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-MAP:URI="\(address)",BYTERANGE="\(header.count)@\(header.lowerBound)"

            """
        for part in parts {
            text += String(format: "#EXTINF:%.3f,\n", part.seconds)
            text += "#EXT-X-BYTERANGE:\(part.size)@\(part.offset)\n\(address)\n"
        }
        text += "#EXT-X-ENDLIST\n"
        return text
    }

    // MARK: Store

    private func store(_ data: Data, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        playlists[key] = data
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > Self.keep { playlists[order.removeFirst()] = nil }
    }

    private func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return playlists[key]
    }

    // MARK: AVAssetResourceLoaderDelegate

    /// Hands AVPlayer the playlist from memory. The pieces themselves are fetched by
    /// AVPlayer straight from YouTube, not through here.
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = request.request.url, url.scheme == Self.scheme else { return false }
        guard let data = data(for: url.deletingPathExtension().lastPathComponent) else {
            request.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return true
        }
        if let info = request.contentInformationRequest {
            info.contentType = "public.m3u-playlist"
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = false
        }
        if let wanted = request.dataRequest {
            let start = min(Int(wanted.requestedOffset), data.count)
            let end = wanted.requestsAllDataToEndOfResource ? data.count : min(data.count, start + wanted.requestedLength)
            if start < end { wanted.respond(with: data.subdata(in: start..<end)) }
        }
        request.finishLoading()
        return true
    }
}
