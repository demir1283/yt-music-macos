import SwiftUI

/// What a hidden item is, read from its id: songs and videos have 11-character ids,
/// albums MPRE…, channels UC…, playlists VL… / PL… / RD… / OLAK….
enum HiddenKind: Int, CaseIterable, Identifiable {
    case song, album, playlist, artist, other
    var id: Int { rawValue }

    static func of(_ key: String) -> HiddenKind {
        if key.hasPrefix("MPRE") { return .album }
        if key.hasPrefix("UC") { return .artist }
        if ["VL", "PL", "RD", "OLAK"].contains(where: { key.hasPrefix($0) }) { return .playlist }
        if key.count == 11 { return .song }
        return .other
    }

    var title: String {
        switch self {
        case .song: return M.t("Şarkılar ve videolar", "Songs and videos")
        case .album: return M.t("Albümler", "Albums")
        case .playlist: return M.t("Çalma listeleri", "Playlists")
        case .artist: return M.t("Sanatçılar ve kanallar", "Artists and channels")
        case .other: return M.t("Diğer", "Other")
        }
    }
}

/// Settings → Privacy → Disliked content → Show: a sheet over Settings with everything
/// disliked or marked "Don't recommend", grouped by kind, searchable, each with Bring
/// Back. Esc or Done closes it. Items hidden before 2.8 were saved by id only; their
/// names and covers are looked up when the sheet opens (placeholders until then), and kept.
struct DislikedContentSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @ViewState var query = ""
    @ViewState var confirmAll = false
    /// Older records that couldn't be looked up: shown by their id.
    @ViewState var notFound: Set<String> = []

    var body: some View {
        let keys = app.hiddenByDate.filter(matches)
        let groups = HiddenKind.allCases.compactMap { kind -> HiddenGroup? in
            let items = keys.filter { HiddenKind.of($0) == kind }
            return items.isEmpty ? nil : HiddenGroup(kind: kind, keys: items)
        }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(M.t("Beğenilmeyen içerik", "Disliked content"))
                    .font(.system(size: 17, weight: .bold))
                Spacer()
                Button(M.t("Bitti", "Done")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                TextField(M.t("Ara", "Search"), text: $query)
                    .textFieldStyle(.roundedBorder)
                Button(M.t("Tümünü Geri Al", "Bring All Back")) { confirmAll = true }
                    .disabled(app.hiddenKeys.isEmpty)
                    .confirmationDialog(M.t("Hepsi geri alınsın mı?", "Bring them all back?"), isPresented: $confirmAll) {
                        Button(M.t("Tümünü Geri Al", "Bring All Back")) { app.unhideAll() }
                        Button(M.t("Vazgeç", "Cancel"), role: .cancel) {}
                    } message: {
                        Text(M.t("Yeniden önerilebilirler; beğenmediğin şarkıların beğenmeme işareti de kalkar.",
                                 "They can be recommended again, and the songs you disliked are no longer disliked."))
                    }
            }

            Group {
                if groups.isEmpty {
                    Text(app.hiddenKeys.isEmpty
                         ? M.t("Beğenilmeyen bir şey kalmadı.", "Nothing disliked any more.")
                         : M.t("Aramaya uyan bir şey yok.", "Nothing matches the search."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.softReveal)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(groups) { group in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(group.kind.title) · \(group.keys.count)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.leading, 4)
                                    VStack(spacing: 0) {
                                        ForEach(group.keys, id: \.self) { key in
                                            HiddenRow(key: key, info: app.hiddenInfo[key], lookingUp: !notFound.contains(key))
                                            if key != group.keys.last { Divider().padding(.leading, 60) }
                                        }
                                    }
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .animation(.soft, value: keys)
        .padding(20)
        .frame(width: 560, height: 600)
        .task { await describeOlderRecords() }
    }

    private func matches(_ key: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let info = app.hiddenInfo[key]
        return [info?.title, info?.subtitle, key].compactMap { $0 }
            .contains { $0.localizedCaseInsensitiveContains(q) }
    }

    /// Names and covers for items hidden before 2.8, a few at a time.
    private func describeOlderRecords() async {
        let missing = app.hiddenByDate.filter { app.hiddenInfo[$0] == nil }
        let engine = app.engine
        for chunk in stride(from: 0, to: missing.count, by: 4).map({ Array(missing[$0..<min($0 + 4, missing.count)]) }) {
            let found = await withTaskGroup(of: (String, AppModel.HiddenInfo?).self) { group in
                for key in chunk { group.addTask { (key, await Self.lookUp(key, engine: engine)) } }
                var out: [(String, AppModel.HiddenInfo?)] = []
                for await r in group { out.append(r) }
                return out
            }
            if Task.isCancelled { return }
            for (key, info) in found {
                if let info { app.describeHidden(key, as: info) } else { notFound.insert(key) }
            }
        }
    }

    private static func lookUp(_ key: String, engine: YTMusic) async -> AppModel.HiddenInfo? {
        switch HiddenKind.of(key) {
        case .song:
            // YouTube's public oEmbed answer: the video's title and channel.
            guard let url = URL(string: "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(key)"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let title = json["title"] as? String else { return nil }
            return AppModel.HiddenInfo(title: title, subtitle: json["author_name"] as? String ?? "",
                                       thumbnail: "https://i.ytimg.com/vi/\(key)/hqdefault.jpg", date: .distantPast)
        case .album, .artist, .playlist:
            let id = ["PL", "RD", "OLAK"].contains(where: { key.hasPrefix($0) }) ? "VL" + key : key
            guard let header = try? await engine.browse(id, params: nil).header, !header.title.isEmpty else { return nil }
            // An artist or channel: its own square picture, not its page's banner.
            var picture = header.thumbnail
            if HiddenKind.of(key) == .artist { picture = await engine.channelPhotos([key])[key] }
            return AppModel.HiddenInfo(title: header.title, subtitle: header.subtitle,
                                       thumbnail: picture, date: .distantPast)
        case .other:
            return nil
        }
    }
}

private struct HiddenGroup: Identifiable {
    let kind: HiddenKind
    let keys: [String]
    var id: Int { kind.rawValue }
}

private struct HiddenRow: View {
    let key: String
    let info: AppModel.HiddenInfo?
    let lookingUp: Bool
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Artwork(url: info?.thumbnail, cornerRadius: 5, circle: false, placeholder: "hand.thumbsdown")
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                if let info {
                    Text(info.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Text(detail(info))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if lookingUp {
                    // Until the name comes: grey bars, not the id.
                    Text(String(repeating: "x", count: 24))
                        .font(.system(size: 13))
                    Text(String(repeating: "x", count: 14))
                        .font(.system(size: 11))
                }
                else {
                    Text(M.t("Bulunamadı", "Not found"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(key)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .redacted(reason: info == nil && lookingUp ? .placeholder : [])
            .animation(.soft, value: info)
            Spacer(minLength: 8)
            Button(M.t("Geri Al", "Bring Back")) { app.unhide(key: key) }
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .transition(.softReveal)
    }

    private func detail(_ info: AppModel.HiddenInfo) -> String {
        var parts: [String] = []
        if !info.subtitle.isEmpty { parts.append(info.subtitle) }
        if info.date > .distantPast { parts.append(info.date.formatted(.relative(presentation: .named))) }
        return parts.joined(separator: " · ")
    }
}
