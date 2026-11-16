# Changelog

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
