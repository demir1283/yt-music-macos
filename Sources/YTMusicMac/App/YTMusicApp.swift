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
        Updater.shared.start()
        Inbox.shared.start()

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

    /// Settings → General: ask before quitting while music plays (on by default).
    nonisolated static let confirmQuitKey = "confirmQuitWhilePlaying"
    /// The app's own relaunches (an update, a language change) quit without asking.
    static var quitWithoutAsking = false

    /// While music plays: asks first (unless turned off, or the Mac is logging out,
    /// restarting or shutting down), then lets the sound fade out before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let engine = YTMusic.shared
        guard engine.isPlaying, engine.track != nil else {
            isTerminating = true
            return .terminateNow
        }
        let ask = UserDefaults.standard.object(forKey: Self.confirmQuitKey) as? Bool ?? true
        if ask, !Self.quitWithoutAsking, !Self.systemIsEndingSession, !Self.quitComesFromAnotherProgram,
           !confirmQuit() {
            return .terminateCancel
        }
        isTerminating = true
        quitReplyPending = true
        engine.fadeOutForQuit { [weak self] in self?.replyToQuit() }
        // In case the fade never reports back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated { AppDelegate.shared?.replyToQuit() }
        }
        return .terminateLater
    }

    /// Quitting waits for the sound to fade out; this lets it go on (once).
    private var quitReplyPending = false
    private func replyToQuit() {
        guard quitReplyPending else { return }
        quitReplyPending = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    private func confirmQuit() -> Bool {
        let alert = NSAlert()
        alert.messageText = M.t("Müzik çalıyor. YT Music'ten çıkılsın mı?", "Music is playing. Quit YT Music?")
        alert.informativeText = M.t("Çalan şarkı durur. Bu soruyu Ayarlar → Genel'den kapatabilirsin.",
                                    "The song playing stops. You can turn this question off in Settings → General.")
        alert.addButton(withTitle: M.t("Çık", "Quit"))
        alert.addButton(withTitle: M.t("Vazgeç", "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = M.t("Bir daha sorma", "Don't ask again")
        NSApp.activate(ignoringOtherApps: true)
        let quit = alert.runModal() == .alertFirstButtonReturn
        if quit, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(false, forKey: Self.confirmQuitKey)
        }
        return quit
    }

    /// The quit was sent by another program — a script, `build.sh` (also during an update
    /// from inside the app), an installer — rather than by the listener (⌘Q, the menu, the
    /// Dock): it isn't held up by a question.
    private static var quitComesFromAnotherProgram: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier
        else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier != "com.apple.dock"
    }

    /// The quit comes from the Mac logging out, restarting or shutting down.
    private static var systemIsEndingSession: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let reason = event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
        else { return false }
        let ending = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart, kAEShowShutdownDialog, kAEShutDown]
        return ending.contains { OSType($0) == reason }
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
        menu.addItem(.separator())
        let sleep = NSMenu()
        for m in SleepChoices.minutes {
            let item = NSMenuItem(title: SleepChoices.label(m), action: #selector(dockSleep(_:)), keyEquivalent: "")
            item.target = self
            item.tag = m
            sleep.addItem(item)
        }
        let end = NSMenuItem(title: SleepChoices.endOfSong, action: #selector(dockSleep(_:)), keyEquivalent: "")
        end.target = self
        end.tag = -1
        sleep.addItem(end)
        if engine.sleepTimer != .off {
            sleep.addItem(.separator())
            let off = NSMenuItem(title: SleepChoices.turnOff, action: #selector(dockSleep(_:)), keyEquivalent: "")
            off.target = self
            off.tag = 0
            sleep.addItem(off)
        }
        let sleepItem = NSMenuItem(title: M.t("Uyku Zamanlayıcı", "Sleep Timer"), action: nil, keyEquivalent: "")
        sleepItem.submenu = sleep
        menu.addItem(sleepItem)
        return menu
    }

    @objc private func dockSleep(_ item: NSMenuItem) {
        let engine = YTMusic.shared
        switch item.tag {
        case 0: engine.cancelSleep()
        case -1: engine.sleepAtEndOfSong()
        default: engine.sleep(after: item.tag)
        }
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

/// The app's language: Turkish when the Mac (or the choice in Settings) is Turkish,
/// otherwise English. Every piece of text the app writes itself goes through `M.t`.
///
/// The choice in Settings is stored as this app's own "AppleLanguages", the standard
/// per-app language setting, so the system's menus (Edit, View, Window, Help — through
/// the bundle's localizations, see build.sh) follow it too. It is read once at launch:
/// a change applies after a restart.
enum M {
    private static let key = "AppleLanguages"

    /// "tr" or "en" when chosen in Settings; nil follows the system.
    static var chosen: String? {
        get {
            let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            return (domain?[key] as? [String])?.first
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// The choice the app was launched with.
    static let launchedChoice: String? = chosen

    static let turkish: Bool = {
        let lang = Locale.preferredLanguages.first ?? Locale.current.identifier
        return lang.lowercased().hasPrefix("tr")
    }()

    static func t(_ tr: String, _ en: String) -> String { turkish ? tr : en }

    /// Quits the app and opens it again. A small shell waits until this copy has really
    /// quit before opening the app, so two copies are never open at once (and if quitting
    /// were refused, nothing new opens).
    @MainActor
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                          Bundle.main.bundlePath]
        do { try task.run() } catch { return }
        // macOS doesn't quit while a sheet is open on a window: close Settings first.
        AppModel.shared.showSettings = false
        AppDelegate.quitWithoutAsking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(after: .appInfo) {
            Button(M.t("Güncellemeleri Denetle…", "Check for Updates…")) { Updater.shared.checkFromMenu() }
        }
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
            Divider()
            Menu(M.t("Uyku Zamanlayıcı", "Sleep Timer")) {
                SleepTimerMenu(engine: model.engine)
            }
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
