# Changelog

## 2.0.0 — 2026-11-18

A recommendation layer of its own on top of YouTube Music, and a new home page.

### Home page
- Spotify-style layout: greeting with eight shortcut tiles; "Picked for you" (sliding) beside artist stations; Recently played; Quick picks; "Compiled for you"; "More like …"; Your top mixes; Jump back in; Popular playlists from YouTube Music; New releases; Long sets; Your favourite artists; living cards on artist banners.
- Quick picks are a fresh random mix each time the page is rebuilt: YouTube Music's picks, songs from saved playlists, recent plays, worldwide hits, old favourites (two songs per artist at most).
- Stations: the 15 artists heard or followed most recently and the 15 listened to longest.
- New releases: what followed artists released in the last month (found through the YouTube subscriptions feed, shown as the single or album), with popular new releases in between.
- Long sets from regular YouTube, in the genres you listen to most and from your artists.
- Editorial playlists, local and worldwide in turn. Mood pages show official playlists and songs only.
- No "Listen again" wall, no community playlists, no rows with one or two cards.
- "Don't recommend" removes an item at once on every page (animated) and keeps it out.
- Loads once the account, library and name are ready (no flash of the old layout); page-shaped loading preview.

### Notifications for you
- New row at the top of home: the regular uploads of the last 14 days from the music channels you subscribe to — artists, labels, festivals — newest first, with the channel's picture; no Shorts or Mixes. Taken from the subscriptions feed, because the bell itself carries almost only Shorts; uploads the bell announced and you haven't read carry a dot. The app only reads notifications and marks nothing on YouTube.
- A channel counts as music when you follow it as an artist on YouTube Music, when you listened to it in the app, or when YouTube files its video under Music (looked up once per channel, kept in memory for the session).
- Uploads already shown there don't repeat under "New releases".

### Faster browsing
- Pages and covers are kept in memory while the app runs (nothing on disk; quitting empties it). Going back to a page, or scrolling up again, shows it at once — no loading preview, no covers fading in again.
- Home page rebuilt every 15 minutes, after five songs heard, when you follow or unfollow an artist, or with ⌘R (View → Refresh). Artist, album and Explore pages every 15 minutes; your own playlists, liked songs and history every 5 minutes and whenever you change them; the last 10 searches for 5 minutes.
- Refreshes happen behind the page and only while the app is on screen; rows that changed fade over, the rest stay put.
- Smoother scrolling: cards and rows passing under a still pointer no longer light up one after another (shadow, play button, gradient) while the page scrolls; hover resumes once the pointer moves.
- Covers: 64 MB in memory — the downloaded files (24 MB, a few hundred covers) and the decoded pictures (40 MB, the most recent ones); a cover from memory appears without fading in. Let go under memory pressure.

### Listening
- Radio cleanup: official song versions first, music videos swapped for their song version, each song once, user uploads to the back, DJ sets left alone (Settings → Radyo).
- On-device listening history (≤ 4 MB, Settings → Geçmiş, can be turned off and erased) feeding a listening profile: finishes count for a song, early skips against it, older plays fade.
- Listening reported to the YouTube account the way the official player does (how much was heard).
- "Bana önerme" in "Up next" takes a song out of the queue and out of later radios.
- Menu bar / Control Center Now Playing stays in step with the app.

### Interface
- Playlist covers in the sidebar; scroll arrows only when a row doesn't fit.
- Space bar play / pause works reliably; the search field is one line and clears when leaving search.
- Turkish capitals in small headings; an artist's popular songs list gets a cover of its own with the artist's name, in the artist's station colour.

### Under the hood
- New app identity `io.github.demir1283.ytmusic` (sign in again after upgrading from 1.0); sources in `Sources/YTMusicMac`.
- The playlist index is built 30 seconds after launch, leaving the connection to the home page first.

## 1.0.0 — 2026-11-16

First public release.

### Listening
- Native playback with `AVPlayer`: 256 kbps AAC with YouTube Music Premium, no web player.
- Home (quick picks, mixes, category chips), Explore, New releases, Charts, Moods & genres, Podcasts.
- Album, playlist, artist, podcast and episode pages; library, liked music, history; search.
- Queue with radio and automix, shuffle, repeat; disliked songs stay out of queues.
- The last song and position are restored at launch; an empty "Up next" fills itself with the song's radio.
- The next song's first 10 seconds are loaded ahead for gapless changes.

### Library
- Create, edit, delete playlists and change their privacy; add, remove, reorder songs.
- Playlist indicator in the player when the playing song is in one of your playlists.
- Like / dislike songs; subscribe to and unsubscribe from artists.

### Lyrics and system
- Side panel with cover, time-synced lyrics (YouTube Music, LRCLIB) and the queue.
- Media keys, Control Center Now Playing, Dock menu, keyboard shortcuts.
- Menus in the system language (English, Turkish).

### Design
- Apple Music–style layout with Liquid Glass (macOS 26+), 12 accent colours, light/dark mode.
- Still "Flow" background pattern or plain background.
- Layout density adapts to the window: roomy on large displays, denser on laptops.
- Page-specific loading previews.

### Performance and privacy
- ~1.5 % CPU and ~170 MB memory while playing in the background.
- No disk cache (only the ~1 MB stream decoder); no analytics or tracking.
