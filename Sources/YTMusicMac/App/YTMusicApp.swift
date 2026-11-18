import SwiftUI
import AppKit
import WebKit

@main
struct YTMusicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("YT Music", id: "main") {
            MainWindow()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .background(WindowRegistrar())
        }
        .defaultSize(width: 1320, height: 860)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) weak var shared: AppDelegate?
    private weak var mainWindow: NSWindow?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var isTerminating = false

    override init() {
        super.init()
        // Set as early as possible: the window registers itself before launch finishes.
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        ThemeStore.shared.applyAppearance()
        StorageCleanup.run()
        _ = YTMusic.shared   // start loading YouTube Music right away

        // Space bar = play/pause, unless the user is typing somewhere.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled: Bool = MainActor.assumeIsolated {
                guard event.keyCode == 49 else { return false }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .subtracting([.capsLock, .numericPad, .function])
                guard flags.isEmpty else { return false }
                let engine = YTMusic.shared
                if engine.webSheet != nil { return false }
                guard AppDelegate.shared?.isTyping(in: event.window) != true else { return false }
                engine.togglePlay()
                return true
            }
            return handled ? nil : event
        }

        // A click anywhere outside the search field ends typing there (as in Music), so the
        // space bar is play/pause again.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { AppDelegate.shared?.endTextEditing(clickedAt: event) }
            return event
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        YTMusic.shared.prepareToQuit()
    }

    func register(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        mainWindow = window
        window.delegate = self
        // AppKit gives the first text field (the toolbar search) the keyboard focus when the
        // window opens, which would swallow the space bar: start with nothing focused.
        Task { @MainActor [weak window] in
            for wait: UInt64 in [0, 300_000_000] {
                try? await Task.sleep(nanoseconds: wait)
                guard let window else { return }
                if let text = window.firstResponder as? NSText, text.string.isEmpty {
                    window.makeFirstResponder(nil)
                }
            }
        }
    }

    /// Whether a key typed in `window` should go to a text field instead of the player.
    /// In the main window an empty field doesn't count: a leading space means nothing there,
    /// and the search field can hold the focus without the user typing in it.
    func isTyping(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder is WKWebView { return true }
        guard let text = responder as? NSText else { return false }
        if window === mainWindow { return !text.string.isEmpty }
        return true
    }

    func endTextEditing(clickedAt event: NSEvent) {
        guard let window = event.window, window === mainWindow,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor else { return }
        if let field = editor.delegate as? NSView {
            let frame = field.convert(field.bounds, to: nil).insetBy(dx: -6, dy: -6)
            if frame.contains(event.locationInWindow) { return }
        }
        window.makeFirstResponder(nil)
    }

    func showMainWindow() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window only hides it, so the music keeps playing. ⌘Q quits.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isTerminating { return true }
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let engine = YTMusic.shared
        let menu = NSMenu()
        if let t = engine.track {
            let info = NSMenuItem(title: "\(t.title) — \(t.artist)", action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: engine.isPlaying ? M.t("Duraklat", "Pause") : M.t("Çal", "Play"), action: #selector(dockToggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: M.t("Sonraki", "Next"), action: #selector(dockNext), keyEquivalent: "").target = self
        menu.addItem(withTitle: M.t("Önceki", "Previous"), action: #selector(dockPrevious), keyEquivalent: "").target = self
        return menu
    }

    @objc private func dockToggle() { YTMusic.shared.togglePlay() }
    @objc private func dockNext() { YTMusic.shared.next() }
    @objc private func dockPrevious() { YTMusic.shared.previous() }
}

/// Hands the hosting NSWindow to the app delegate (for hide-on-close).
struct WindowRegistrar: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            MainActor.assumeIsolated { AppDelegate.shared?.register(window) }
        }
    }

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Menu text in the system language: Turkish when the Mac is set to Turkish, otherwise
/// English. (The system's own menus — Edit, View, Window, Help — follow the same language
/// through the bundle's localizations; see build.sh.)
enum M {
    static let turkish: Bool = {
        let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
        return lang.lowercased().hasPrefix("tr")
    }()
    static func t(_ tr: String, _ en: String) -> String { turkish ? tr : en }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appSettings) {
            Button(M.t("Ayarlar…", "Settings…")) { model.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu(M.t("Oynatma", "Controls")) {
            Button(M.t("Çal / Duraklat", "Play / Pause")) { model.engine.togglePlay() }
            Button(M.t("Sonraki", "Next")) { model.engine.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button(M.t("Önceki", "Previous")) { model.engine.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button(M.t("Sesi Aç", "Increase Volume")) { model.engine.setVolume(model.engine.volume + 10) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button(M.t("Sesi Kıs", "Decrease Volume")) { model.engine.setVolume(model.engine.volume - 10) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button(M.t("Beğen", "Like")) { model.engine.like() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button(M.t("Karıştır", "Shuffle")) { model.engine.shuffle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button(M.t("Tekrarlama Modu", "Repeat Mode")) { model.engine.cycleRepeat() }
                .keyboardShortcut("r", modifiers: [.command, .control])
            if !model.engine.streamInfo.isEmpty {
                Divider()
                Text(M.t("Kaynak: ", "Source: ") + model.engine.streamInfo)
            }
        }

        CommandMenu(M.t("Git", "Go")) {
            Button(M.t("Ara", "Search")) { model.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
            Button(M.t("Ana Sayfa", "Home")) { model.select(.home) }
                .keyboardShortcut("1", modifiers: .command)
            Button(M.t("Keşfet", "Explore")) { model.select(.explore) }
                .keyboardShortcut("2", modifiers: .command)
            Button(M.t("Kitaplık", "Library")) { model.select(.library) }
                .keyboardShortcut("3", modifiers: .command)
            Button(M.t("Beğenilen Müzikler", "Liked Music")) { model.select(.liked) }
                .keyboardShortcut("4", modifiers: .command)
            Divider()
            Button(M.t("Geri", "Back")) { model.back() }
                .keyboardShortcut("[", modifiers: .command)
            Divider()
            Button(M.t("Yan Paneli Göster/Gizle", "Show/Hide Side Panel")) { model.togglePanel() }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button(M.t("Şarkı Sözleri", "Lyrics")) { model.toggleLyrics() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandGroup(after: .toolbar) {
            Divider()
            Button(M.t("Yenile", "Refresh")) { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button(M.t("YouTube Music'i Tarayıcıda Aç", "Open YouTube Music in Browser")) { NSWorkspace.shared.open(YTMusic.homeURL) }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            Button(M.t("Kitaplığı Yenile", "Refresh Library")) { Task { await model.engine.loadLibrary() } }
            Button(M.t("Bağlantıyı Yeniden Kur", "Reconnect")) { model.engine.reloadHome() }
        }
    }
}
