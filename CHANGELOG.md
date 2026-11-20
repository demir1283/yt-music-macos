# Changelog

## 2.7.1 — 2026-11-20

A simpler update, a clearer Settings.

- Updating: the new version's card at the bottom of the sidebar has a single **Update** button; once pressed, the same card shows the download and build progress in percent, then the app restarts. An update started from Settings shows its progress in Settings.
- Settings, redesigned in four groups — Appearance, Listening, Privacy, General — with a title and a short explanation on the left of each row and every control aligned on the right. Erasing the listening history asks first. "Check Now" dims while it checks, then says what it found under the version.
- Rows that appear with a choice (pattern intensity, restart after a language change, the update's progress) open and close with a soft fade and slide.
- A song started from a card keeps the title and artists the card showed: a regular YouTube upload (notifications, long sets) no longer turns into YouTube Music's own title with a single artist in the player and the side panel.

## 2.7.0 — 2026-11-20

Updates from inside the app.

- The app checks GitHub for a new version at launch and once a day. When there is one, a card above the account card shows it, with its notes; **Update** runs `git pull` and `build.sh` in the folder the app was built from, and the new version opens by itself. If a step fails, the old version keeps running and shows why.
- Settings → Updates: turn the check off, or check now. The app menu has **Check for Updates…**.
- Every version is now published as a GitHub Release, with its notes from this file: watch the repository for releases (Watch → Custom → Releases) to be notified by GitHub.

## 2.6.0 — 2026-11-19

The whole app in English.

- Every text the app writes itself — sidebar, home page rows, player bar, menus, settings, sheets, errors — is now in English on a Mac set to any language other than Turkish, and in Turkish on a Turkish Mac. Before, only the menus followed the system language.
- New in Settings: **Language** (System, Türkçe, English). The choice applies after a restart (a Restart button appears), switches the system menus too, and asks YouTube for its texts — row titles, release dates, view counts — in the same language.
- The like button shows a song as liked when it is in Liked Music — under the same id or as its song or video version — even when YouTube's queue data doesn't say so. Liked Music is read at launch, like the playlists, and kept in step with every like and unlike made in the app.

## 2.5.0 — 2026-11-19

A new search, a new "New releases" page, and one rule for what a click does.

### Search suggestions
- Suggestions appear under the search field as you type, from YouTube Music and YouTube, with your recent searches first and covers for songs, artists and albums.
- Hover a song for a play button; an artist's play button plays their popular songs. Clicking a song opens its album.
- ↑↓ picks a suggestion, ↩ searches and leaves the field, Esc closes the list. Clicking back into the field shows the list again.
- On macOS 26 the field uses the system's own glass capsule (no double bar).

### Search page
- Filters: All, Songs, Artists, Albums, Playlists, Videos, Podcasts. Community playlists and profiles are left out.
- "All": a top result card (always an official artist when there is one) with four songs beside it, then artists and albums in one row, playlists, and videos in their wide format.
- The top result card is tinted in a few soft tones of your accent colour, for light and dark mode.
- All sections are fetched together and shown at once, with a loading preview until then: results no longer reshuffle after appearing.
- When the search is an artist's name, "Songs" lists that artist's popular songs first.

### New releases
- The sidebar page is rebuilt in five rows: from the artists you follow (their last 20 releases), from the artists you listen to, new for you, new on YouTube Music, and new music videos. Every card names its artist.
- The home page's "New releases" row shows the same releases as the page.

### One rule for clicks
- Clicking a cover or title opens its page: a song opens its album, an artist radio opens the artist, a song without a known album is looked up and opens its album, or else its artist or channel. Only mixes play on click; everything else plays from its play button.
- Notification cards follow the same rule, and their channel names are links.
- A joint upload by several channels links every channel name to its own page.

### Look
- No round cards anywhere: artists are rounded squares too.
- Artist pictures are always the artist's own photo, never a cropped video thumbnail; with no photo, the name alone is shown.

### Player bar
- The volume slider narrows on small windows, so the controls never overlap the time readout.

## 2.1.0 — 2026-11-19

Where the sound goes, and songs that start at once.

### Player bar
- New layout: the song's progress runs along the bottom edge of the glass capsule. It thickens under the pointer and while dragged, to seek.
- Elapsed and total time ("1:23 / 3:45") at the right of the now-playing block; while seeking it shows the time you'd jump to. Title and artist have the two lines to themselves.

### Sound output and AirPlay
- New output button in the player bar. Play to the Mac's speakers, Bluetooth, USB or a display's speakers — for YT Music only, the system output stays as it is. The choice is remembered; while the device is unplugged the system output is used, and the app goes back to it once it's connected again.
- AirPlay: Apple TV, HomePod, AirPlay TVs and speakers, through the system AirPlay menu. macOS gives apps no way to pick an AirPlay receiver by themselves, so that choice isn't remembered.

### Starts at once
- Long recordings start in about a second and seek instantly. YouTube's audio files carry an index of their ~10-second pieces; AVPlayer now gets a playlist written from that index (same file, same quality, nothing re-encoded) instead of the file itself, which it read almost in full before starting: an hour-long set took 12–30 seconds and 50–60 MB before the first note, now about 150 KB. If the index can't be read, the file is played as before.

### Smoother
- YouTube's answers (up to 3 MB of JSON each, a dozen at once at launch) are read on a queue of their own instead of the main thread. The longest hitch while scrolling the freshly loaded home page went from about half a second to under 80 ms.
- Card shadows are cast by a plain shape instead of the cover, so they aren't redrawn while covers load, fade in or scroll by; covers that arrive mid-scroll appear without fading.

### Under the hood
- Diagnostic log (off by default) shows the stages of starting a song: stream, player ready, why it waits, download rate, first sound.

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
