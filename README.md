<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="YT Music app icon">
</p>

<h1 align="center">YT Music for macOS</h1>

<p align="center">
  A native YouTube Music client for the Mac, built with SwiftUI.
</p>

<p align="center">
  <img alt="Version 2.7.0" src="https://img.shields.io/badge/version-2.7.0-ff2d55">
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

## What it adds

On top of what YouTube Music offers, the app has a few things of its own:

- **Home page:** shortcuts, artist stations, quick picks and rows that follow what you listen to.
- **New releases:** the latest releases of the artists you follow and of the artists you listen to.
- **Notifications:** recent uploads from the music channels you follow, without Shorts.
- **Radio cleanup (optional):** prefers official song versions and plays each song once; DJ sets are left as they are.
- **Listening history on your Mac:** used for the recommendations above; you can turn it off or erase it.
- **Long sets:** DJ sets and live recordings from regular YouTube, in the genres you listen to.
- **Sound output:** pick a speaker, Bluetooth, USB or display output for this app only, or use AirPlay.

## What's new

- **2.7 — Updates from inside the app:** a new version shows up in the sidebar; one click pulls and builds it. See [Updating](#updating).
- **2.6 — English interface:** the whole app follows your Mac's language (English or Turkish), or the one you pick in Settings.
- **2.5 — A new “New releases” page:** the latest releases of the artists you follow and listen to; every channel of a joint upload is a link.

The full list is in the [changelog](CHANGELOG.md).

## Install

You build the app yourself. It takes about a minute and needs no Xcode:

```bash
xcode-select --install          # once, if the Command Line Tools aren't installed
git clone https://github.com/demir1283/yt-music-macos.git
cd yt-music-macos
./build.sh --install            # builds the app and copies it to /Applications
```

Then click **Sign in** in the sidebar and log in with Google. Requires macOS 14 or later.

### Updating

The app checks GitHub for a new version at launch and once a day. When one is out, the sidebar shows it: **Update** runs `git pull` and `./build.sh` in the folder you built the app from, then the new version opens. You can turn the check off in **Settings → Updates**.

By hand, in the project folder: `git pull && ./build.sh --install`. To get an e-mail for each version, use **Watch → Custom → Releases** on this page.

**Coming from 2.6 or earlier:** update by hand once; from 2.7 on the app does it.

## Why a native app

- **No browser inside.** SwiftUI interface and Apple's own audio player. No Electron, no web player.
- **Full quality.** With Premium, 256 kbps AAC, played as it is.
- **Light.** About 1.5 % CPU and ~170 MB of memory while playing in the background (measured on the author's MacBook).
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
- **No servers, analytics or tracking.** The app talks only to YouTube / Google, [LRCLIB](https://lrclib.net) (lyrics) and GitHub (to see whether a new version is out; can be turned off in Settings).
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

## Feedback

- **Found a bug or want a feature?** [Open an issue](https://github.com/demir1283/yt-music-macos/issues/new/choose); there is a short form for each.
- **A question or an idea?** Use [Discussions](https://github.com/demir1283/yt-music-macos/discussions).
- **A security problem?** Report it privately through the [Security tab](https://github.com/demir1283/yt-music-macos/security/advisories/new), not in a public issue.

Turkish and English are both welcome. Never post your account name, cookies or tokens.

## Credits

- [yt-dlp-ejs](https://github.com/yt-dlp/ejs) (public domain), with [meriyah](https://github.com/meriyah/meriyah) (ISC) and [astring](https://github.com/davidbonnet/astring) (MIT).
- [LRCLIB](https://lrclib.net) for time-synced lyrics.
- Design inspired by Apple Music, Spotify and [Kaset](https://github.com/sozercan/kaset).

## License

[MIT](LICENSE). The bundled yt-dlp-ejs keeps its own licence (`Resources/ejs/LICENSE`).
