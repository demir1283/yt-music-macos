import SwiftUI
import AppKit

/// What the search field suggests while you type: YouTube Music's suggestions (your recent
/// searches, completions, a few artists / songs / albums with covers) and regular YouTube's
/// completions, in a list that opens under the field.
@MainActor @Observable
final class SearchSuggestionModel {
    static let shared = SearchSuggestionModel()

    enum Row: Hashable {
        case text(SearchSuggestions.Suggestion)
        case item(MediaItem)
    }

    /// The text the rows are for.
    private(set) var query = ""
    private(set) var rows: [Row] = []
    /// The row picked with ↑/↓ or under the pointer.
    var selection: Int?
    /// Closed (Esc, ↩ or a pick) until the text changes again.
    private(set) var dismissed = false
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Text a pick put in the field: it opens no new list.
    @ObservationIgnored private var picked: String?

    static let textRow: CGFloat = 28
    static let itemRow: CGFloat = 46

    private init() {}

    private var textCount: Int {
        rows.reduce(0) { count, row in
            if case .text = row { return count + 1 }
            return count
        }
    }

    /// Height of the list for the current rows.
    var height: CGFloat {
        let texts = CGFloat(textCount), items = CGFloat(rows.count - textCount)
        return 12 + texts * Self.textRow + (texts > 0 && items > 0 ? 9 : 0) + items * Self.itemRow
    }

    /// Changes when the list has to open, close or change size.
    var layoutKey: String { "\(textCount)-\(rows.count)-\(dismissed)" }

    /// Whether row `i` is the first of the covers (a divider goes above it).
    func startsItems(at i: Int) -> Bool {
        guard i > 0, rows.indices.contains(i), case .item = rows[i], case .text = rows[i - 1] else { return false }
        return true
    }

    /// The field's text changed: ask for its suggestions once typing pauses (150 ms). The
    /// rows for the previous text stay until the new ones arrive.
    func update(_ text: String, engine: YTMusic) {
        let q = text.trimmingCharacters(in: .whitespaces)
        task?.cancel()
        selection = nil
        if let p = picked, p == q {
            picked = nil
            return
        }
        dismissed = false
        query = q
        guard !q.isEmpty else {
            rows = []
            return
        }
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let found: SearchSuggestions
            do {
                found = try await engine.searchSuggestions(q)
            } catch {
                EngineLog.write("Öneriler \"\(q)\": alınamadı — \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled, let self, self.query == q else { return }
            self.rows = found.suggestions.map(Row.text) + found.items.map(Row.item)
        }
    }

    func dismiss() {
        dismissed = true
        selection = nil
    }

    /// The field was clicked into again: its list opens once more, at once when its
    /// suggestions are still at hand (after opening a result), or asked for the text a
    /// picked suggestion left in the field.
    func reopen(_ text: String, engine: YTMusic) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, dismissed || rows.isEmpty || q != query else { return }
        picked = nil
        if q == query, !rows.isEmpty {
            dismissed = false
            selection = nil
        } else {
            update(text, engine: engine)
        }
    }

    /// ↑ / ↓: moves through the rows (and off the top, back to the text).
    func move(_ step: Int) {
        guard !rows.isEmpty else { return }
        if let s = selection {
            let next = s + step
            selection = next < 0 ? nil : min(next, rows.count - 1)
        } else if step > 0 {
            selection = 0
        }
    }

    /// Whether row `i` has a play button: songs and videos, artists (their popular songs),
    /// albums and playlists.
    func canPlay(_ i: Int) -> Bool {
        guard rows.indices.contains(i), case .item(let item) = rows[i] else { return false }
        return item.isTrack || item.isArtist || item.kind == "album" || item.kind == "playlist"
    }

    /// The row's play button: a song plays, an artist's popular songs play, an album or
    /// playlist plays from the start. The text in the field stays.
    func play(_ i: Int, app: AppModel) {
        guard canPlay(i), case .item(let item) = rows[i] else { return }
        dismiss()
        if item.isArtist, let id = item.browseId {
            app.playPopular(artistId: id)
        } else {
            app.play(item)
        }
    }

    /// A text searches for it; a cover opens its page: the artist, album or playlist, and
    /// for a song its album (a video without one plays).
    func pick(_ index: Int, app: AppModel) {
        guard rows.indices.contains(index) else { return }
        let row = rows[index]
        dismiss()
        switch row {
        case .text(let s):
            picked = s.text
            app.searchQuery = s.text
            if app.section != .search { app.select(.search) }
        case .item(let item):
            app.open(item)
        }
    }
}

// MARK: - The search field in AppKit

/// The toolbar's search field as AppKit sees it. SwiftUI's focus state doesn't follow a
/// text field placed in the toolbar, so whether it is being typed in is read from AppKit.
enum SearchField {
    static let placeholder = "Şarkı, sanatçı, albüm, podcast ara"

    /// Whether `object` (a text-editing notification's sender) is the search field: the
    /// one text field outside the window's content, up in the toolbar.
    static func isSearchField(_ object: Any?) -> Bool {
        guard let field = object as? NSTextField, let window = field.window else { return false }
        if field.placeholderString == placeholder || field.placeholderAttributedString?.string == placeholder { return true }
        guard let content = window.contentView else { return false }
        return !field.isDescendant(of: content)
    }

    /// After ↩ the search is made: the field lets go of the keyboard, as search fields do
    /// (no caret blinking on, no text left selected; the space bar plays and pauses again).
    /// A click or ⌘F types in it again.
    static func endEditing() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow,
                  let editor = window.firstResponder as? NSTextView,
                  isSearchField(editor.delegate) else { return }
            window.makeFirstResponder(nil)
        }
    }
}

// MARK: - The list's window

/// A small window under the search field. It never takes the keyboard (typing stays in
/// the field), sits above the main window and moves with it. While it is shown, ↑/↓/↩/Esc
/// go to the list.
@MainActor
final class SuggestionPanel {
    static let shared = SuggestionPanel()
    private var panel: NSPanel?
    private var keys: Any?
    private var clicks: Any?
    private weak var app: AppModel?

    private init() {}

    func show(height: CGFloat, app: AppModel) {
        guard let (window, field) = Self.searchField() else { return }
        self.app = app
        let panel = self.panel ?? make(app: app)
        // The text field sits in a 30 pt capsule, with the magnifier left of it and the
        // clear button right: the list goes under the capsule, at least as wide.
        let width = max(field.width + 60, 380)
        let frame = NSRect(x: field.midX - width / 2, y: field.midY - 15 - 6 - height, width: width, height: height)
        panel.setFrame(frame, display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        watchKeys()
    }

    /// The search field being typed in (the window's field editor belongs to it), and its
    /// frame on screen.
    private static func searchField() -> (NSWindow, NSRect)? {
        guard let window = NSApp.keyWindow,
              let editor = window.firstResponder as? NSTextView,
              let field = editor.delegate as? NSTextField, SearchField.isSearchField(field) else { return nil }
        return (window, window.convertToScreen(field.convert(field.bounds, to: nil)))
    }

    func hide() {
        guard let panel, panel.isVisible || panel.parent != nil else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    private func make(app: AppModel) -> NSPanel {
        let p = KeylessPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = true
        p.isReleasedWhenClosed = false
        p.contentView = FirstClickHostingView(rootView: SuggestionRoot(app: app))
        panel = p
        return p
    }

    /// Calls `onFieldClick` after a click that leaves the search field being typed in,
    /// i.e. the field was clicked into. Clicks in the list itself don't count.
    func watchClicks(_ onFieldClick: @escaping () -> Void) {
        guard clicks == nil else { return }
        clicks = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if event.window == nil || event.window !== self?.panel {
                // After the click is handled, when the field has taken the keyboard.
                Task { @MainActor in
                    if Self.searchField() != nil { onFieldClick() }
                }
            }
            return event
        }
    }

    /// ↑/↓ move, ↩ picks the chosen row (with none chosen the field searches as usual),
    /// Esc closes the list (a second Esc leaves the field).
    private func watchKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let app = self.app, self.panel?.isVisible == true,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            let model = SearchSuggestionModel.shared
            switch event.keyCode {
            case 125: model.move(1); return nil                     // ↓
            case 126: model.move(-1); return nil                    // ↑
            case 53: model.dismiss(); return nil                    // Esc
            case 36, 76:                                            // ↩, enter
                guard let s = model.selection else { model.dismiss(); return event }
                model.pick(s, app: app)
                return nil
            default: return event
            }
        }
    }
}

private final class KeylessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a row act at once (the list's window is never active).
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct SuggestionRoot: View {
    let app: AppModel
    var body: some View {
        SearchSuggestionList().environment(app)
    }
}

// MARK: - The list

private struct SearchSuggestionList: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = SearchSuggestionModel.shared
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { i, row in
                if model.startsItems(at: i) {
                    Divider().padding(.vertical, 4)
                }
                SuggestionRow(row: row, query: model.query, selected: model.selection == i,
                              play: model.canPlay(i) ? { model.play(i, app: app) } : nil)
                    .onHover { if $0 { model.selection = i } }
                    .onTapGesture { model.pick(i, app: app) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

private struct SuggestionRow: View {
    let row: SearchSuggestionModel.Row
    let query: String
    let selected: Bool
    /// The play button shown on the right while the row is under the pointer (or chosen).
    let play: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            switch row {
            case .text(let s):
                Image(systemName: s.source == "history" ? "clock.arrow.circlepath" : "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                highlighted(s.text)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if s.source == "youtube" {
                    Text("YouTube")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            case .item(let item):
                Artwork(url: item.thumbnail, cornerRadius: 4,
                        placeholder: item.isArtist ? "person.fill" : "music.note")
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if selected, let play {
                    PlayCircle(size: 26, action: play)
                        .help(item.isArtist ? "Popüler şarkılarını çal" : "Çal")
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(height: isItem ? SearchSuggestionModel.itemRow : SearchSuggestionModel.textRow)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(selected ? Color.brand.opacity(0.18) : Color.clear))
        .contentShape(Rectangle())
    }

    private var isItem: Bool {
        if case .item = row { return true }
        return false
    }

    /// What you typed in normal weight, the rest of the suggestion in bold.
    private func highlighted(_ s: String) -> Text {
        guard !query.isEmpty,
              let r = s.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) else {
            return Text(s)
        }
        return Text(s[r]).foregroundStyle(.secondary) + Text(s[r.upperBound...]).fontWeight(.semibold)
    }
}
