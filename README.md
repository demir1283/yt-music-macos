<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="YT Music app icon">
</p>

<h1 align="center">YT Music for macOS</h1>

<p align="center">
  <b>Your YouTube Music as a native Mac app — with its own home page, its own player and its own design.</b>
</p>

<p align="center">
  <img alt="Version 3.2.1" src="https://img.shields.io/badge/version-3.2.1-ff2d55">
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

<p align="center">
  <a href="#install"><b>Install</b></a> · <a href="#features">Features</a> · <a href="#privacy">Privacy</a> · <a href="CHANGELOG.md">Changelog</a>
</p>

YT Music is a YouTube Music client for the Mac, written from scratch in SwiftUI. You sign in with your own account and play your own library and YouTube Music's whole catalogue — but what you see is not YouTube Music's web page in a window. The app decides for itself what goes on the home page, what a radio plays next and what is new for you, from what you listen to on this Mac, and plays it with Apple's own audio player.

> **Unofficial.** Not affiliated with YouTube or Google. “YouTube” and “YouTube Music” are trademarks of Google LLC. You need your own YouTube Music account; Premium unlocks the best audio quality.

## What makes it different

<table>
<tr>
<td width="33%" valign="top">

### Its own algorithm

The home page isn't YouTube Music's feed. It is put together on your Mac each time you open it, from your listening history, the artists you follow, YouTube Music's catalogue and regular YouTube: artist stations, quick picks, mixes around the artists you play most, artists like the ones you love, long sets in the genres you listen to. Radios are tidied up — official versions first, each song once — and new releases and notifications come only from the artists and channels you follow.

</td>
<td width="33%" valign="top">

### Its own design

Designed and built for the Mac from the first line: a slowly moving ambient background, tall station cards with the artists' own photos, a deck of picks that turns by itself, artist pages with the artist's portrait, a summary of your listening and a side panel for lyrics and the queue. Nothing jumps: views fade in, and songs ease in and out. Liquid Glass on macOS 26, light and dark mode, a choice of accent colours.

</td>
<td width="33%" valign="top">

### Its own player

No browser and no web player inside: the stream YouTube serves is played as it is by Apple's AVPlayer — 256 kbps AAC with Premium. Even volume between songs, crossfade, a sleep timer, and a sound output of its own (a speaker, Bluetooth, USB, a display, or AirPlay). About 1.5 % CPU and ~170 MB of memory while playing in the background.

</td>
</tr>
</table>

## A closer look

<table>
<tr>
<td width="75%"><img src="docs/screenshots/artist.png" alt="An artist page with the artist's own photo, lyrics beside it"></td>
<td width="25%"><img src="docs/screenshots/notifications.png" alt="New music from the artists you follow"></td>
</tr>
<tr>
<td align="center"><sub>Artist pages with the artist's own photo · time-synced lyrics and the queue beside the music</sub></td>
<td align="center"><sub>New music from the artists and channels you follow</sub></td>
</tr>
</table>

## Features

**Listening**
- Even volume between songs, measured by YouTube for every song.
- Crossfade of 3 to 12 seconds, from a button in the player bar; never within an album played in order or a DJ set.
- Playing, pausing and changing songs ease in and out; a song that simply ends hands over to the next as it is.
- Sleep timer: after 15 minutes to 1.5 hours, or at the end of the song, fading out.
- Time-synced lyrics and the queue in a side panel, and a sound output for this app only.

**Discovery**
- A home page built for you, with artist stations, quick picks, mixes, similar artists and long sets.
- New releases from the artists you follow and the ones you listen to.
- A bell with the latest music from the artists and channels you follow — singles, albums and uploads, no Shorts.
- Your listening: your top artists, channels and songs of the week, month, year or all time.

**Your library**
- Playlists, albums, artists, liked music and history; create, edit and reorder playlists.
- Search with suggestions as you type.
- Disliked content in one place, ready to bring back.

**On the Mac**
- Media keys, Control Center, the Dock menu and keyboard shortcuts.
- English or Turkish, following your Mac or your choice.
- Updates from inside the app, and a question before quitting while music plays.

## What's new

- **3.2 — A disk image and a new Library:** install by dragging the app from YT-Music.dmg, no Terminal needed; a Library of chips, tiles or rows and three orders, with every followed artist, album and playlist, and removing from it in the ••• menu; song lengths and release years on artist pages. 3.2.1 turns Picked for you into wide cards you swipe through and puts the notifications newest first.
- **3.1 — Notifications and crossfade:** a bell with the new singles, albums and uploads of the artists and channels you follow; crossfade from the player bar; playing and pausing ease in and out. 3.1.1 keeps songs playing with YouTube's new player.
- **3.0 — Even volume, sleep timer, your listening:** a summary of your listening, a redesigned home page and artist pages with the artists' own photos, mixes you can open, and disliked content you can bring back.
- **2.7 — Updates from inside the app:** a new version shows up in the sidebar; one click pulls and builds it.

The full list is in the [changelog](CHANGELOG.md).

## Install

<p>
  <a href="https://github.com/demir1283/yt-music-macos/releases/latest/download/YT-Music.dmg"><b>⬇︎ Download YT Music (.dmg)</b></a> — macOS 14 or later, Apple Silicon and Intel
</p>

1. Open **YT-Music.dmg** and drag **YT Music** onto **Applications**.
2. Open YT Music. The first time, macOS says it can't verify the app — the app isn't signed with a paid Apple developer certificate. Click **Done**.
3. Open **System Settings → Privacy & Security**, scroll down to **Security** and click **Open Anyway** next to YT Music, then confirm with your password. This is needed only once.
4. Click **Sign in** in the sidebar and log in with Google.

### Updating

The app checks GitHub for a new version at launch and once a day. When one is out, the sidebar shows it, and **Update** downloads it, puts it in place and opens it again — no questions from macOS this time. You can turn the check off in **Settings → Updates**. To get an e-mail for each version, use **Watch → Custom → Releases** on this page.

### Building from source

If you'd rather build it yourself (about a minute, no Xcode needed):

```bash
xcode-select --install          # once, if the Command Line Tools aren't installed
git clone https://github.com/demir1283/yt-music-macos.git
cd yt-music-macos
./build.sh --install            # builds the app and copies it to /Applications
```

A copy built this way updates itself from the same folder: **Update** runs `git pull` and `./build.sh` there. By hand: `git pull && ./build.sh --install`.

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

If you edit `Tools/bridge.js`, `./build.sh` (or `Tools/gen-bridge.sh`) writes its Swift copy. Tests: `swift test` (needs Xcode) and `node --test "Tools/tests/*.test.mjs"`; GitHub Actions runs both on every push.
</details>

<details>
<summary><b>Troubleshooting</b></summary>

- **Pages stay empty:** use **Reconnect** in the View menu. If YouTube shows a consent page, open YouTube Music in the browser once (⇧⌘Y).
- **Diagnostic log:** `defaults write io.github.demir1283.ytmusic diagnosticLog -bool true` writes `YT Music.log` next to the app (the previous session's is kept as `YT Music (önceki).log`); `defaults delete io.github.demir1283.ytmusic diagnosticLog` turns it off. Read the log before sharing it.
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
- [Kaset](https://github.com/sozercan/kaset), for showing early on what a native YouTube Music client on the Mac could be.

## License

[MIT](LICENSE). The bundled yt-dlp-ejs keeps its own licence (`Resources/ejs/LICENSE`).
