# Changelog

## 3.4.0 — 2026-11-27

Artist pages redesigned, open any YouTube Music or YouTube link from the search field, Moods & Genres as cards with their lists' covers, a Plays column, albums, playlists and podcasts saved from their page, and podcasts that open with their covers, dates and lengths.

- **Open a link from the search field.** Paste a YouTube Music or YouTube link into the search field — a song, video, playlist, album, artist, channel, podcast or search — and press Enter: songs and videos play, everything else opens its page. While a link is in the field, a small tag beside it says what Enter will do ("Albüm ↩", "Çal ↩"), and the field's hint now says links can be pasted.
- **Moods & Genres, redesigned.** Each mood or genre is now a wider card in its own colour (the one YouTube gives it), its name at the top left and, tilted at the bottom right, the cover of its first list — what YouTube Music shows for it in your region, so the cards change with it; the cover's own colour glows out around it and melts into the card's. Covers (and their colours) are looked up once, a few at a time, kept for three days, and appear whole, in one soft fade; each card is drawn as one picture, so the page scrolls smoothly. On hover the category's next two lists fan out from under the first to the left, like a hand of cards.
- **Cards dealt again.** When the side panel or the menu opens or closes, the covers on Moods & Genres step aside, the cards move to their new places, and then the covers come back and fan out once, like a hand of cards dealt on the table.
- **Save albums and playlists from their page.** An album's or someone else's playlist's page now has an "Add to Library" button next to Play and Shuffle; once saved it reads "In Library", and a click takes it out again. It shows the state YouTube Music gives for the page.
- **Podcasts open again, and can be kept.** Some podcast pages came back from YouTube empty ("No songs here yet"); such a page is now read again, and if it is still empty, opened as the list of its episodes. A show's page always has its cover (the card's, when the page has none) and the same "Add to Library" button as albums; the shows you keep are in the Library, under a new Podcasts list, and the ••• menu of a show's card adds or removes it too.
- **A date column for episodes and videos.** Lists of podcast episodes and videos had an empty Album column; it now shows when each came out ("11 Eyl 2025"), and the column beside the title keeps just the play count. Lists of songs without any album lose the empty column, leaving the titles more room.
- **Episode lengths.** A podcast's page now shows how long each episode is ("3:26:23"); YouTube leaves the lengths out of the page, so the show's play queue is read at the same time and the page arrives with them; episodes further down get theirs as they load.
- **Every pick with its artist.** Some playlists in Picked for you (editors' playlists such as Kafe Müziği) came without an artist's picture: when the first song's artist has no picture, or the list was looked up by the wrong address, the card now tries the next artists of the list. Artists' pictures are also no longer lost when many are asked for at once (past thirty, the rest were wrongly remembered as having none).
- **A Plays column.** Albums and playlists show how often each song was played in a column of its own, beside the artist. An album's songs that named no artist now show the album's artist, and a soundtrack's songs by other artists, which YouTube names without a link, link to their pages (taken from the album's play queue); a playlist's page, which has no play counts on YouTube Music, gets them from the same list on YouTube, read at the same time.
- **Artist pages, redesigned.** The banner now sits on the right and melts softly leftwards and downwards into the page, with a wash of its colours across the top; on the open left, the artist's round photo beside their name and subscribers, with the play, subscribe and radio buttons under them; the banner comes in softly and the rest floats up into place. Subscribe is a quiet button (a tinted one with a tick once subscribed), so Play is the one that stands out. On an artist's own page their songs' Artist column names the others on a song (features) and the artist alone on songs of their own, and goes when no song has anyone else. Artists without a banner get the same layout in their own colour.
- An artist's top songs always show their lengths: when the list behind them has none either, they come from its play queue.
- **Column titles with icons.** Every song list's column titles (title, artist, album, plays, published, year and length) have a small icon before them, in the accent colour of the left menu's.
- For contributors: GitHub Actions use actions/checkout v5 (Node 24), which ends the Node 20 deprecation warnings.

## 3.3.0 — 2026-11-26

One grid of cards everywhere, artist pages that fill the screen, a greeting that changes, a more solid player bar, and Turkish and English kept apart.

- **Turkish and English, consistently.** YouTube's own texts (row titles such as "Videos", dates) now always come in the app's language, so a Turkish Mac with an English YouTube account no longer mixes the two. Error messages from YouTube follow the app's language too. In Turkish one word for each thing: "Çalma listesi" (YouTube's "Oynatma listesi" included), "Abonelikten çık", "Beğenmedim", "Çalınamadı", "Yeniden dene"; the Controls menu is "Denetimler", as in Apple Music, and the side panel's menu item names what it shows. In English, "1 song", "1 item" instead of "1 songs", "1 items".
- **A greeting that changes.** The home page still greets you by the time of day at launch; then every ten minutes the line changes, with a soft cross-fade, to one of a hundred short lines from the world of music, in Turkish or English, each with its emoji (night lines only at night, morning lines only in the morning).
- **"Show More", two rows at a time.** Grids of cards ("see all" pages, thin artist pages) show a screenful, and "Show More" — now a pill like the filter chips — adds two rows each time, bringing in the next cards (the "see all" page, then its following pages) until there are none left.
- **Artist pages that fill the screen.** An artist page with little on it — only a row of long videos, say — no longer leaves one row to scroll sideways under an empty screen: its card rows wrap into a grid (three rows when there is one, two each when there are two), the cards widened to fill each row, with "Show More" for the rest and for what the row's "see all" page holds (all of a channel's videos). Full pages keep their rows to scroll.
- **One grid everywhere.** Every grid of cards — the library, "see all" pages, search filters, thin artist pages — now lays out like the rows of the home page and search: covers at a row's cover size, videos 16:9 at a row's video size (no more small boxes), as many as fit and widened to fill each row. "Show More" sits under the cards, at their right.
- **Fixed: a channel's "Videos" page could be empty.** When YouTube Music sends a "see all" page with its cards outside any row, they are gathered into one; when it sends a channel's videos page empty, the channel's videos come from YouTube instead.
- **A more solid player bar.** At rest the bar now has a wash of the window's colour under its glass, so its buttons, title and times stay readable over busy covers; on hover it turns more solid still.

## 3.2.1 — 2026-11-25

Wide cards for Picked for you, notifications newest first, a roomier player bar on laptop screens, and fixes.

- **Picked for you, in wide cards.** The deck still slides from pick to pick, now with cards wider than tall: the cover, blurred, colours the card, the artist's own picture fills its left and melts into that colour, and the cover floats sharp over the seam. The name and artists use the card's width. Ten picks instead of five, and a sideways two-finger swipe on the trackpad moves to the next or the previous one.
- **Home: the picks above the notifications.** Senin için seçildi and the stations now come right under the greeting, the notifications after them; the loading placeholders follow the new order and sizes. A playlist's pick shows the picture of its first song's artist.
- **The player bar on a laptop screen.** When the bar is too narrow to keep the cover and title in the middle without cutting the title short, they move left, next to the play buttons, and take the room that was empty there. Wide windows keep the centred layout.
- **Fixed: the same old song at every launch.** The player bar was given the top of the account's YouTube history whenever it differed from what the app played last — and that top often lags behind (a play reaches it late, or not at all), so one old song kept coming back. Now the song this Mac played last comes back, where it was left; the history takes over only when it is plainly newer: something played today, on another device, while this Mac last played on an earlier day.
- **Fixed: "Up Next" could run dry.** Picking a song near the end of the list from Up Next left nothing after it, and nothing new came: more was asked for only when the list had a next page. Now the next page comes first and, when there is none (or it brings nothing new), the song's radio follows, as at the end of any list. A next page made only of songs already listed no longer stops it either.
- Picked for you: the artists' names on a card open their pages.
- **Fixed: album and single pages linked all their artists as one.** "Miss Monique & Paradoks" was a single link to the first artist; now each name opens its own page and the "&" between them is plain. When YouTube joins several names into one link, the songs' credits tell them apart.
- **Notifications newest first.** The bell's list mixed YouTube Music's new releases (on top, in their page's order) with uploads; now everything is in one order by date. An upload goes by when it went up — hours count too, not just days; a release by the day it came out (its first song's publish date, looked up once and kept on this Mac), or, when YouTube doesn't say, by when the bell first listed it.
- **No "Search" in the sidebar.** Its page, before typing anything, was the same as Moods & Genres. Search is the field at the top of the window (⌘F), as before.
- **Fixed: a video's preview in the side panel started square.** At launch it took its 16:9 shape only once the picture had downloaded. A video is now 16:9 from the start and a song square; moving from one video to the next no longer shows the previous video's frame for a moment, and a song after a video no longer appears wide first.

## 3.2.0 — 2026-11-24

Install from a disk image, a new Library, and song lengths on artist pages.

- **Install from a disk image.** Each release now comes with **YT-Music.dmg**, built by GitHub for Apple Silicon and Intel: open it, drag YT Music to Applications, done — no Terminal, git or Command Line Tools. The app isn't signed with a paid Apple certificate, so the first time macOS asks you to allow it (System Settings → Privacy & Security → Open Anyway). Building from source works as before.
- **A new Library.** Playlists, Albums and Artists are chips like the home page's. Artists are the ones you follow — no longer everyone you ever played a song of. The ••• menu of an album or a saved playlist can take it out of the library (or add one from anywhere), and an artist's can unsubscribe. Each list can be shown as tiles or as rows, and sorted by recently added, A–Z or Z–A; both choices are kept per list. The lists now load in full — before, only YouTube's first page came, so Artists stopped around "A". The first page shows at once and the rest comes in behind it, with a count beside the chips.
- **Artist pages: song lengths.** Top songs often came without their lengths; the app now takes them from the artist's full song list. A list of albums and singles shows their year in that column, and a list with neither leaves the column out instead of showing it empty.
- **All followed artists.** New releases and the notifications panel now see every artist you follow, not just the first page of them.
- **Fixed: Play at launch needed two clicks.** Resuming the last song where it was left, the player first moves to that second and only then plays; meanwhile it reported itself paused, so the play button came back as if nothing had happened — and when moving took a while, a second click seemed needed. That moment now counts as loading. The diagnostic log also notes your clicks, the player stopping or starting on its own, and the move to the saved second.
- **Updates for the .dmg app.** "Update" in the sidebar downloads the new disk image, copies the app over the old one (swapped in one step, never half replaced) and opens it again; macOS doesn't ask again. Copies built from source keep updating with `git pull` and `build.sh`.

## 3.1.1 — 2026-11-24

A fix for YouTube's new player script, which kept songs from playing, and Settings that fit a laptop screen.

- **Settings fit the window.** On a laptop screen (or in full screen) the Settings sheet grew taller than the window and its last rows went under the Dock; its groups now scroll when they don't fit, under a fixed title row with Done.
- **Songs play again with YouTube's new player.** Since November 23 YouTube has been rolling out new versions of its player script (05a4ffc0, b485e332, …) that the stream solver couldn't prepare ("a.addOnDisposeCallback is not a function"), so nothing played — or only now and then, while the rollout was partial. The app now reads the TV build of the same player version, which prepares as before, and falls back to the main build; yt-dlp made the same change (yt-dlp#18124).
- For contributors: a commit is built on GitHub once. When main is fast-forwarded to a commit that already passed on next (as a release does), a small Linux job finds that result — waiting for it if next is still building — and the Mac build is skipped.

## 3.1.0 — 2026-11-23

A notifications bell for new music from the artists and channels you follow, crossfade between songs, and nothing starting or stopping abruptly.

- **Notifications:** a bell at the top right, beside the side panel button, with a dot while something new is waiting. It opens a panel at the window's top right corner (inside the window; a click outside or Esc closes it): the latest music from the channels and artists you follow, newest first — the regular uploads of the last two weeks from the music channels you follow on YouTube (no Shorts, comments or posts, no channels that aren't music) and, first, the new singles and albums of artists you follow that YouTube Music lists as new releases (many come out there without an upload on the artist's YouTube channel); when an upload is such a release, the release shows instead of the video. The subscriptions feed is now shared for 5 minutes by the home page, the new releases page and the bell, and an empty answer from YouTube no longer empties them. Each row has the cover, the channel's picture, the title, the channel and how long ago; a dot marks what's new. Click a row to open it; the play button that appears beside it plays it right there. What you have seen is kept on this Mac only. Refreshed shortly after launch, then every 30 minutes, and on opening when older than 5 minutes. The home page's "Notifications for you" row stays.
- **Crossfade:** a new button in the player bar, beside the sleep timer. Each click makes the crossfade longer (3, 6, 9, 12 seconds) and the next one turns it off; while on, it is in the accent colour with the length as a small figure at its corner. Off by default. Near the end of a song the next one starts under it and the two overlap, one turned down as the other comes up, along an equal-power curve (no dip in the middle); each keeps its own volume leveling. The player bar, Now Playing and Control Center move to the new song as it starts. It uses the next song's opening, which the app already keeps ready, so nothing more is downloaded. Songs don't overlap within an album played in order (live and DJ albums run into each other as recorded), into or out of long sets, when one song repeats, when the sleep timer waits for the end of the song, or when you skip.
- **Nothing starts or stops abruptly:** playing comes in and pausing goes out over 0.4 seconds; a song cut short by another (a click, a skip, pausing during a crossfade) fades out while the new one comes in. A song that simply ends hands over to the next as before, so its first beat isn't softened.
- **Asks before quitting while music plays:** ⌘Q, the menu or the Dock ask first ("Don't ask again" in the question); quitting then lets the sound fade out. Not asked when another program quits the app (a script, `build.sh`, an update from inside the app) or when the Mac logs out, restarts or shuts down. Settings → General → Ask before quitting while playing (on by default).
- **Diagnostic log:** starting the app no longer erases the last session's log; it is kept as `YT Music (önceki).log` next to `YT Music.log`, so a problem isn't lost by restarting.

## 3.0.0 — 2026-11-23

Even volume between songs, a sleep timer, a summary of your listening, a redesigned home page and artist pages with the artists' own photos, mixes you can open, and a way back for what you disliked.

- **Your listening:** a new page in the sidebar (Collection), in the app's own layout, sums up the history kept on this Mac for the last 7 days, 30 days, this year or all time: period chips as on the home page; a headline with the time listened and the number of songs, artists and channels; your top 20 artists and channels as cards with their own square pictures (their avatars on YouTube, not their pages' banners) — including the YouTube channels whose sets you play — opening their pages; and your top 50 songs as a regular song list, 20 at first (play, right-click menu, how often each was played). Songs heard for at least 30 seconds count; nothing is sent anywhere.
- **Volume leveling:** YouTube measures every song's loudness; every song is now brought to a level 6 dB below YouTube's reference, so the volume no longer jumps from one song to the next (in testing, the spread between four songs went from 8.9 dB to 2.9 dB). The player can't turn a song up past its own level, so the few quieter than that stay as they are, and the app as a whole is somewhat quieter — raise the volume once. On by default; Settings → Listening → Level the volume. Turning it on or off mid-song eases over a moment.
- **Sleep timer:** a moon button in the player bar opens its panel, like the sound output button: what it does, 15, 30, 45 minutes, 1 or 1.5 hours, or the end of the song (the running choice checked), and Turn off. While it runs the moon is filled, in the accent colour, with the time left beside it; on a narrow window the button shows only then. Also in the Controls and Dock menus. When time is up the sound fades out over 8 seconds and playback stops.
- **Mixes open:** clicking an artist mix's cover (Compiled for you, Your top mixes) opens a page of the songs it starts with, as a playlist does; its play button plays it. Those mixes' covers are now the artist's picture, not the cover of the song the mix starts from.
- **Stations and picks, redesigned:** the home page's recommended stations are tall cards filled by the artist's photo, with the name over it. Beside them, "Picked for you" is now a deck of cards in the same style: the next picks peek out behind the front one, which steps aside every few seconds; click a card behind to bring it forward.
- **Artist pages:** the artist's own square photo overlaps the bottom of the banner, with their name and subscribers beside it.
- **Supermix:** mixes YouTube Music builds as you play them (My Supermix) no longer open as an empty playlist; their page lists the songs they start with.
- **Artist pictures:** wherever the app needs an artist's or channel's picture it doesn't already have as a square (the home page's artists and stations from your history, Your listening, Disliked content), it now uses the channel's own avatar from YouTube, not the wide banner of its YouTube Music page cropped to a square. The banner stays where it belongs: across the top of the artist page and behind the home page's living cards.
- **Disliked content:** Settings → Privacy → Disliked content → Show opens a sheet over Settings (Esc closes it, as it does Settings) with everything you disliked or marked "Don't recommend", grouped by kind (songs, albums, playlists, artists), searchable, with covers; bring items back one by one or all at once. Songs brought back are no longer disliked on YouTube either. Items hidden before this version were saved by id only: their names and covers are looked up when the sheet opens, with placeholders until they come.

## 2.7.2 — 2026-11-22

Search fixes, and every change now built and tested by GitHub.

- Search: "Don't recommend" on a search result (a playlist, an album, a video) takes it off the page at once, as everywhere else. Every row of cards in the app now leaves out what you said not to recommend.
- Lists: a song you dislike ("Dislike (don't recommend)") in an album or playlist now shows it — it fades and gets a thumbs-down mark, and is left out when the list plays. "Undo Dislike" brings it back.
- Search: playlists made by users are back in the results, after YouTube's and YouTube Music's own — in the overview's Playlists row and under the Playlists filter, which no longer has a separate "Community playlists" twin.
- For contributors: GitHub Actions builds the app and runs its tests on every push and pull request (Xcode 26, macOS 26). Swift tests cover the update check's version comparison, how songs and their video versions are matched, and reading an audio file's index; Node tests cover reading YouTube's subscription feed and the start-up language. `Tools/gen-bridge.sh` writes the Swift copy of `Tools/bridge.js` (build.sh runs it), so the two can't drift apart.

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
