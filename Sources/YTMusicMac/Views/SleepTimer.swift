import SwiftUI

/// The sleep timer's choices, shared by the Controls menu, the Dock menu and the
/// indicator in the player bar.
enum SleepChoices {
    static let minutes = [15, 30, 45, 60, 90]

    static func label(_ m: Int) -> String {
        switch m {
        case 60: return M.t("1 saat", "1 hour")
        case 90: return M.t("1,5 saat", "1.5 hours")
        default: return M.t("\(m) dakika", "\(m) minutes")
        }
    }

    static var endOfSong: String { M.t("Bu şarkı bitince", "End of this song") }
    static var turnOff: String { M.t("Zamanlayıcıyı kapat", "Turn off timer") }

    /// "23 dk" / "şarkı sonu": what's left, for the player bar.
    static func remaining(_ timer: YTMusic.SleepTimer, at now: Date) -> String {
        switch timer {
        case .off: return ""
        case .endOfSong: return M.t("şarkı sonu", "end of song")
        case .at(let end):
            let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
            return M.t("\(minutes) dk", "\(minutes) min")
        }
    }
}

/// The menu items: a few lengths, the end of the song, and off when it is running.
struct SleepTimerMenu: View {
    let engine: YTMusic

    var body: some View {
        ForEach(SleepChoices.minutes, id: \.self) { m in
            Button(SleepChoices.label(m)) { engine.sleep(after: m) }
        }
        Button(SleepChoices.endOfSong) { engine.sleepAtEndOfSong() }
            .disabled(engine.track == nil)
        if engine.sleepTimer != .off {
            Divider()
            Button(SleepChoices.turnOff) { engine.cancelSleep() }
        }
    }
}

/// In the player bar: a moon that opens the sleep timer's panel, like the sound output
/// button. While the timer runs the moon is filled, in the accent colour, with the time
/// left beside it.
struct SleepButton: View {
    @Environment(AppModel.self) private var app
    @ViewState var open = false

    var body: some View {
        let e = app.engine
        let on = e.sleepTimer != .off
        HStack(spacing: 0) {
            ToolbarIconButton(system: on ? "moon.zzz.fill" : "moon.zzz", size: 14, active: on,
                              help: M.t("Uyku zamanlayıcı", "Sleep timer")) { open.toggle() }
            if on {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(SleepChoices.remaining(e.sleepTimer, at: context.date))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.brand)
                }
                .padding(.trailing, 4)
                .contentShape(Rectangle())
                .onTapGesture { open.toggle() }
                .transition(.softReveal)
            }
        }
        .popover(isPresented: $open, arrowEdge: .top) { SleepPanel(engine: e) { open = false } }
        .animation(.soft, value: on)
    }
}

/// The sleep timer's panel: what it does, the lengths (the running one checked), the
/// end of the song, and Turn Off while it runs.
private struct SleepPanel: View {
    let engine: YTMusic
    let close: () -> Void

    var body: some View {
        let timer = engine.sleepTimer
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.brand)
                Text(M.t("Uyku zamanlayıcı", "Sleep timer"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 8)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(status(timer, at: context.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            Divider().padding(.vertical, 4)
            ForEach(SleepChoices.minutes, id: \.self) { m in
                OutputRow(symbol: "timer", title: SleepChoices.label(m), detail: nil,
                          selected: engine.sleepMinutes == m) { engine.sleep(after: m); close() }
            }
            OutputRow(symbol: "music.note", title: SleepChoices.endOfSong, detail: nil,
                      selected: timer == .endOfSong) { engine.sleepAtEndOfSong(); close() }
                .disabled(engine.track == nil)
            if timer != .off {
                Divider().padding(.vertical, 4)
                OutputRow(symbol: "xmark.circle", title: SleepChoices.turnOff, detail: nil, selected: false) {
                    engine.cancelSleep(); close()
                }
            }
        }
        .padding(10)
        .frame(width: 260)
    }

    private func status(_ timer: YTMusic.SleepTimer, at now: Date) -> String {
        switch timer {
        case .off:
            return M.t("Süre dolunca ses yavaşça kısılıp çalma durur.",
                       "When time is up, the sound fades out and playback stops.")
        case .endOfSong:
            return M.t("Bu şarkı bitince çalma duracak.", "Playback stops when this song ends.")
        case .at:
            return M.t("Çalma \(SleepChoices.remaining(timer, at: now)) sonra duracak.",
                       "Playback stops in \(SleepChoices.remaining(timer, at: now)).")
        }
    }
}
