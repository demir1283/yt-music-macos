<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="YT Music app icon">
</p>

<h1 align="center">YT Music for macOS</h1>

<p align="center">
  A native YouTube Music client for the Mac, with a smarter home page, search and radio<br>
  than YouTube Music itself.
</p>

<p align="center">
  <img alt="Version 2.5.0" src="https://img.shields.io/badge/version-2.5.0-ff2d55">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-3c8dbc">
</p>

<p align="center">
  <b>English</b> · <a href="README.tr.md">Türkçe</a>
</p>

<p align="center">
  <img src="docs/screenshots/home.png" alt="The home page">
</p>

> **Unofficial.** Not affiliated with YouTube or Google. “YouTube” and “YouTube Music” are trademarks of Google LLC. You need your own YouTube Music account; Premium unlocks the best audio quality.

## What you get that YouTube Music doesn't have

| | YouTube Music | YT Music for macOS |
|---|---|---|
| **New releases** | One general page | The last 20 releases of the artists you follow, plus new music from the artists you listen to |
| **Notifications** | The bell, mostly Shorts | Recent uploads from the music channels you follow, no Shorts |
| **Radio** | Song versions, music videos and re-uploads mixed | Official song versions first, each song once, DJ sets left alone |
| **Learning from you** | Hidden on the server | A listening profile kept on your Mac, which you can read and erase |
| **DJ sets** | Rarely shown | “Long sets” from regular YouTube, in the genres you play |
| **Sound output** | Only the system output | Choose speakers, Bluetooth, USB or a display for this app alone, or AirPlay |
| **Long recordings** | Can take a while to start | Hour-long sets start in about a second and seek at once |

## What's new in 2.5

- **A new “New releases” page:** the last 20 releases of the artists you follow, new music from the artists you listen to, picks for you, what's new on YouTube Music and new music videos. The home page row shows the same releases.
- **Joint uploads:** every channel's name is a link to its own page.
- Plus search suggestions, a clearer search page and many smaller fixes; the full list is in the [changelog](CHANGELOG.md).

## Install

You build the app yourself. It takes about a minute and needs no Xcode:

```bash
xcode-select --install          # once, if the Command Line Tools aren't installed
git clone https://github.com/demir1283/yt-music-macos.git
cd yt-music-macos
./build.sh --install            # builds the app and copies it to /Applications
```

Then click **Sign in** in the sidebar and log in with Google. Requires macOS 14 or later.

## Why a native app

- **No browser inside.** SwiftUI interface and Apple's own audio player. No Electron, no web player.
- **Full quality.** With Premium, 256 kbps AAC, played as it is.
- **Light.** About 1.5 % CPU and ~170 MB of memory while playing in the background.
- **At home on macOS.** Liquid Glass on macOS 26, media keys, Control Center, Dock menu, light and dark mode.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| Space | Play / pause |
| ⌥⌘→ / ⌥⌘← | Next / previous song |
| ⌘↑ / ⌘↓ | Volume up / down |
| ⌥⌘L | Like |
| ⌘F | Search (↑↓ to pick a suggestion, Esc to close) |
| ⌘1 … ⌘4 | Home, Explore, Library, Liked music |
| ⌘[ | Back |
| ⇧⌘L | Lyrics |
| ⌘, | Settings |

## Privacy

- **Your password never touches the app.** You sign in on Google's own page; the app keeps only the session cookies, on your Mac. **Sign out** removes them.
- **No servers, analytics or tracking.** The app talks only to YouTube / Google and [LRCLIB](https://lrclib.net) (lyrics).
- **Your listening history stays on your Mac** (at most 4 MB). Turn it off or erase it in Settings.
- **No keys or tokens in this repository.** Everything is read at runtime from your own session.

<details>
<summary><b>How it works</b></summary>

```
Google sign-in ─▶ session cookies ─▶ URLSession
                                       │
YouTube Music + YouTube data ◀── bridge.js in JavaScriptCore
                                       │
Listening history ─▶ ListeningProfile ─▶ home page · radio cleanup · new releases
                                       │
Stream address ──▶ yt-dlp-ejs (solves YouTube's stream challenge)
                                       │
          DashToHLS (a playlist from the audio file's own index)
                                       │
                 AVPlayer ──▶ chosen output or AirPlay
```

If you edit `Tools/bridge.js`, copy it into `Sources/YTMusicMac/Engine/BridgeScript.swift` as well.
</details>

<details>
<summary><b>Troubleshooting</b></summary>

- **Pages stay empty:** use **Reconnect** in the View menu. If YouTube shows a consent page, open YouTube Music in the browser once (⇧⌘Y).
- **Diagnostic log:** `defaults write io.github.demir1283.ytmusic diagnosticLog -bool true` writes `YT Music.log` next to the app; `defaults delete io.github.demir1283.ytmusic diagnosticLog` turns it off. Read the log before sharing it.
- **Upgrading from 1.0:** sign in once more; settings start fresh.
</details>

## Credits

- [yt-dlp-ejs](https://github.com/yt-dlp/ejs) (public domain), with [meriyah](https://github.com/meriyah/meriyah) (ISC) and [astring](https://github.com/davidbonnet/astring) (MIT).
- [LRCLIB](https://lrclib.net) for time-synced lyrics.
- Design inspired by Apple Music, Spotify and [Kaset](https://github.com/sozercan/kaset).

## License

[MIT](LICENSE). The bundled yt-dlp-ejs keeps its own licence (`Resources/ejs/LICENSE`).
