import Foundation

/// Cleans up radio queues (the songs YouTube Music adds on its own): official versions
/// first, each song once, user uploads to the back.
///
/// - A music video is swapped for its song version when YouTube Music pairs the two.
/// - The same song in several uploads plays once, in its best version.
/// - User uploads keep their order but come after the official songs.
/// - Long recordings (DJ sets, mixes, radio shows) are their own kind: they are never
///   swapped, merged or pushed back.
///
/// Lists and albums the user picked are not touched; only radios are arranged.
enum QueueCurator {
    /// Recordings at least this long count as sets.
    static let setSeconds: Double = 20 * 60

    static let song = "MUSIC_VIDEO_TYPE_ATV"
    static let musicVideo = "MUSIC_VIDEO_TYPE_OMV"
    static let upload = "MUSIC_VIDEO_TYPE_UGC"

    static func isSet(_ e: QueueEntry) -> Bool { e.seconds >= setSeconds }

    /// 0: official (or a set), 1: user upload.
    static func tier(_ e: QueueEntry) -> Int {
        if isSet(e) { return 0 }
        return e.videoType == upload ? 1 : 0
    }

    /// The song version instead of the music video, when YouTube Music offers it.
    static func preferSong(_ e: QueueEntry) -> QueueEntry {
        guard e.videoType == musicVideo, !isSet(e), let alt = e.alt?.first,
              alt.videoType == song, alt.videoId != nil else { return e }
        var s = alt
        s.index = e.index
        s.selected = e.selected
        if s.like == nil { s.like = e.like }
        var video = e
        video.alt = nil
        s.alt = [video]
        return s
    }

    /// Arranges `pending` (the rows still to come). `fixed` are the rows already played and
    /// the one playing: nothing in `pending` repeats them.
    static func arrange(pending: [QueueEntry], fixed: [QueueEntry]) -> [QueueEntry] {
        let before = fixed.map(Ident.init)
        var ids = Set(fixed.compactMap(\.videoId))
        var out: [QueueEntry] = []
        var outIdents: [Ident] = []
        for raw in pending {
            let e = preferSong(raw)
            guard let vid = e.videoId, !ids.contains(vid) else { continue }
            let ident = Ident(e)
            if let j = outIdents.firstIndex(where: { $0.sameSong(as: ident) }) {
                // Already coming up: keep the better version, where the first one stood.
                if tier(e) < tier(out[j]) {
                    out[j] = e
                    outIdents[j] = ident
                    ids.insert(vid)
                }
                continue
            }
            if before.contains(where: { $0.sameSong(as: ident) }) { continue }
            ids.insert(vid)
            out.append(e)
            outIdents.append(ident)
        }
        return out.filter { tier($0) == 0 } + out.filter { tier($0) == 1 }
    }

    /// What a row is, for spotting the same song in different uploads: the song title
    /// without decorations ("(Official Video)", "[Lyrics]"…) and the artists, including the
    /// "Artist - Song" form user uploads use.
    struct Ident {
        let song: String
        let artists: Set<String>
        let isSet: Bool
        let videoId: String?

        init(_ e: QueueEntry) {
            videoId = e.videoId
            isSet = QueueCurator.isSet(e)
            var title = QueueCurator.stripDecorations(e.title)
            var names = Set((e.artists ?? []).map { QueueCurator.normalize($0.name) })
            if names.isEmpty, let first = e.subtitle.components(separatedBy: " • ").first {
                names.insert(QueueCurator.normalize(first))
            }
            if let r = title.range(of: " - ") {
                let left = String(title[..<r.lowerBound])
                for part in left.components(separatedBy: CharacterSet(charactersIn: ",&")) {
                    names.insert(QueueCurator.normalize(part))
                }
                title = String(title[r.upperBound...])
            }
            song = QueueCurator.normalize(title)
            artists = names.filter { !$0.isEmpty }
        }

        func sameSong(as other: Ident) -> Bool {
            if isSet || other.isSet { return videoId != nil && videoId == other.videoId }
            return !song.isEmpty && song == other.song && !artists.isDisjoint(with: other.artists)
        }
    }

    private static let decorationWords = [
        "official", "video", "audio", "lyric", "lyrics", "visualizer", "visualiser", "hd", "hq",
        "4k", "mv", "clip", "klip", "resmi", "sözleri", "sozleri", "feat", "ft", "with",
    ]

    /// Drops bracketed decorations and "feat." credits; keeps what tells versions apart
    /// (remix, live, edit, extended…).
    static func stripDecorations(_ title: String) -> String {
        var t = title
            .replacingOccurrences(of: " – ", with: " - ")
            .replacingOccurrences(of: " — ", with: " - ")
        if let re = try? NSRegularExpression(pattern: #"\s*[\(\[]([^\)\]]*)[\)\]]"#) {
            let ns = t as NSString
            var keep = ""
            var last = 0
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: m.range(at: 1)).lowercased()
                let words = inner.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                let decorative = words.contains { decorationWords.contains($0) }
                keep += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                if !decorative { keep += ns.substring(with: m.range) }
                last = m.range.location + m.range.length
            }
            keep += ns.substring(from: last)
            t = keep
        }
        // "Song ft. X" / "Song feat. X" without brackets.
        if let re = try? NSRegularExpression(pattern: #"\s+(feat\.?|ft\.?)\s+.*$"#, options: .caseInsensitive) {
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }
}
