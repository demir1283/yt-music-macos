import SwiftUI

// MARK: - Playlist editing context (for track menus inside a playlist page)

/// Provided by a playlist page the account owns (or "Beğenilen Müzikler"), so a track's
/// menu can offer "remove" and "move" for that playlist.
struct PlaylistEditContext {
    let title: String
    let canMove: Bool
    let removeLabel: String
    let remove: (MediaItem) -> Void
    let move: (MediaItem, Int) -> Void
}

private struct PlaylistEditContextKey: EnvironmentKey {
    static let defaultValue: PlaylistEditContext? = nil
}

extension EnvironmentValues {
    var playlistEdit: PlaylistEditContext? {
        get { self[PlaylistEditContextKey.self] }
        set { self[PlaylistEditContextKey.self] = newValue }
    }
}

// MARK: - Add to playlist

struct AddToPlaylistSheet: View {
    let song: PlaylistTarget
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @ViewState var options: [PlaylistOption] = []
    @ViewState var loading = true
    @ViewState var error: String? = nil
    @ViewState var busy: String? = nil
    @ViewState var added: Set<String> = []
    @ViewState var filter = ""

    private var shown: [PlaylistOption] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Artwork(url: song.thumbnail, cornerRadius: 6).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Çalma listesine ekle")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(song.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if !song.subtitle.isEmpty {
                        Text(song.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Button("Kapat") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Çalma listelerinde ara", text: $filter)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 2) {
                    Button {
                        app.playlistEditor = .create(firstVideoId: song.videoId)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.brand.opacity(0.15))
                                Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.brand)
                            }
                            .frame(width: 40, height: 40)
                            Text("Yeni çalma listesi").font(.system(size: 13, weight: .semibold))
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if loading {
                        ProgressView().controlSize(.small).padding(30)
                    } else if let error {
                        Text(error).font(.system(size: 12)).foregroundStyle(.secondary).padding(30)
                    } else {
                        ForEach(shown) { p in
                            PlaylistOptionRow(option: p, isIn: p.contains || added.contains(p.playlistId),
                                              busy: busy == p.playlistId) { add(p) }
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 440, height: 520)
        .task {
            do {
                options = try await app.engine.playlistOptions(for: song.videoId, title: song.title, artist: song.subtitle)
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func add(_ p: PlaylistOption) {
        guard busy == nil, !(p.contains || added.contains(p.playlistId)) else { return }
        busy = p.playlistId
        Task {
            do {
                try await app.engine.addToPlaylist(p.playlistId, videoId: song.videoId)
                added.insert(p.playlistId)
                busy = nil
                try? await Task.sleep(nanoseconds: 450_000_000)
                dismiss()
            } catch {
                busy = nil
                self.error = error.localizedDescription
            }
        }
    }
}

private struct PlaylistOptionRow: View {
    let option: PlaylistOption
    let isIn: Bool
    let busy: Bool
    let action: () -> Void
    @ViewState var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Artwork(url: option.thumbnail, cornerRadius: 6, placeholder: "music.note.list")
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let p = option.privacy.flatMap(PlaylistPrivacy.init(rawValue:)) {
                        Label(p.title, systemImage: p.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else if isIn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.brand)
                        .transition(.scale.combined(with: .opacity))
                } else if hover {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(hover && !isIn ? 0.06 : 0)))
            .contentShape(Rectangle())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isIn)
        }
        .buttonStyle(.plain)
        .disabled(isIn)
        .onHover { hover = $0 }
        .help(isIn ? "Bu şarkı zaten listede" : "Bu listeye ekle")
    }
}

// MARK: - Create / edit playlist

struct PlaylistEditorSheet: View {
    let mode: PlaylistEditorMode
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @ViewState var title = ""
    @ViewState var details = ""
    @ViewState var privacy: PlaylistPrivacy = .PRIVATE
    @ViewState var saving = false
    @ViewState var error: String? = nil
    @ViewState var confirmDelete = false
    @ViewState var loaded = false

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEdit ? "Çalma listesini düzenle" : "Yeni çalma listesi")
                .font(.system(size: 18, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Ad").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextField("Çalma listesi adı", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Açıklama").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                TextEditor(text: $details)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                    .frame(height: 80)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Gizlilik").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker("", selection: $privacy) {
                    ForEach(PlaylistPrivacy.allCases) { p in
                        Label(p.title, systemImage: p.icon).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red)
            }

            HStack {
                if case .edit(let id, _, _, _) = mode {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Çalma listesini sil", systemImage: "trash")
                    }
                    .confirmationDialog("“\(title)” silinsin mi?", isPresented: $confirmDelete) {
                        Button("Sil", role: .destructive) { delete(id) }
                        Button("Vazgeç", role: .cancel) {}
                    } message: {
                        Text("Bu işlem YouTube Music hesabından da silinir ve geri alınamaz.")
                    }
                }
                Spacer()
                Button("Vazgeç") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEdit ? "Kaydet" : "Oluştur") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if case .edit(_, let t, let d, let p) = mode {
                title = t
                details = d
                privacy = p
            }
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        saving = true
        error = nil
        Task {
            do {
                switch mode {
                case .create(let first):
                    let id = try await app.engine.createPlaylist(title: name, description: details, privacy: privacy,
                                                                 videoIds: first.map { [$0] } ?? [])
                    dismiss()
                    let target = BrowseTarget(browseId: "VL" + id, params: nil, kind: "playlist", title: name)
                    app.select(.playlist(target))
                case .edit(let id, _, _, _):
                    try await app.engine.updatePlaylist(id, title: name, description: details, privacy: privacy)
                    dismiss()
                }
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }

    private func delete(_ id: String) {
        saving = true
        Task {
            do {
                try await app.engine.deletePlaylist(id)
                dismiss()
                app.select(.library)
            } catch {
                self.error = error.localizedDescription
            }
            saving = false
        }
    }
}
