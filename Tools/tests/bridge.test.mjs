// Tests for Tools/bridge.js, the script that reads YouTube Music's answers.
// Run with:  node --test Tools/tests/
// Each test loads the script afresh with a fake HTTP layer answering canned JSON.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = fs.readFileSync(new URL('../bridge.js', import.meta.url), 'utf8');

function loadBridge(answer, cfg) {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  delete globalThis.ytcfg;
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => ok(200, JSON.stringify(answer));
  if (cfg) globalThis.ytcfg = { get: (k) => cfg[k] };
  (0, eval)(source);
  return globalThis.__ytmusic;
}

const loggedIn = {
  INNERTUBE_CONTEXT: { client: { clientName: 'WEB_REMIX', clientVersion: '1.2', hl: 'tr' } },
  LOGGED_IN: true,
  SESSION_INDEX: 0,
};

// --- Subscriptions feed: one card per upload, with every channel of a joint upload.

const listItem = (name, id) => ({ listItemViewModel: { title: { content: name },
  rendererContext: { commandContext: { onTap: { innertubeCommand: { browseEndpoint: { browseId: id } } } } } } });

const lockup = (vid, channelText, avatarCommand) => ({ lockupViewModel: {
  contentId: vid, contentType: 'LOCKUP_CONTENT_TYPE_VIDEO',
  contentImage: { thumbnailViewModel: { image: { sources: [{ url: `https://i.ytimg.com/vi/${vid}/hq.jpg` }] },
    overlays: [{ thumbnailOverlayBadgeViewModel: { thumbnailBadges: [{ thumbnailBadgeViewModel: { text: '3:45' } }] } }] } },
  metadata: { lockupMetadataViewModel: { title: { content: `Song ${vid}` },
    image: { decoratedAvatarViewModel: { avatar: { avatarViewModel: { image: { sources: [{ url: 'https://yt3/a' }] } } },
      rendererContext: { commandContext: { onTap: { innertubeCommand: avatarCommand } } } } },
    metadata: { contentMetadataViewModel: { metadataRows: [
      { metadataParts: [{ text: { content: channelText } }] },
      { metadataParts: [{ text: { content: '12 B görüntüleme' } }, { text: { content: '2 gün önce' } }] }] } } } } } });

const feed = { contents: { x: [
  lockup('aaaaaaaaaaa', 'ARTBAT ve Afterlife', { showDialogCommand: { panelLoadingStrategy: { inlineContent: { dialogViewModel: {
    customContent: { listViewModel: { listItems: [listItem('ARTBAT', 'UCartbat'), listItem('Afterlife', 'UCafter')] } } } } } } }),
  lockup('bbbbbbbbbbb', 'Tale Of Us ve Anyma', { showDialogCommand: { x: [
    { browseEndpoint: { browseId: 'UCtale' } }, { browseEndpoint: { browseId: 'UCanyma' } }] } }),
  lockup('ccccccccccc', 'Tomorrowland', { browseEndpoint: { browseId: 'UCtml' } }),
  { videoRenderer: { videoId: 'ddddddddddd', title: { runs: [{ text: 'Old style' }] }, lengthText: { simpleText: '4:00' },
    publishedTimeText: { simpleText: '3 gün önce' },
    ownerText: { runs: [
      { text: 'Solomun', navigationEndpoint: { browseEndpoint: { browseId: 'UCsol' } } },
      { text: ' ve ' },
      { text: 'Adam Port', navigationEndpoint: { browseEndpoint: { browseId: 'UCadam' } } }] } } },
] } };

async function subscriptions() {
  const bridge = loadBridge(feed, loggedIn);
  const r = JSON.parse(await bridge.call('ytSubscriptions', '{}'));
  return Object.fromEntries(r.items.map((v) => [v.item.videoId, v.item.artists]));
}

test('a joint upload names every channel, from its dialog', async () => {
  const byVideo = await subscriptions();
  assert.deepEqual(byVideo.aaaaaaaaaaa, [{ id: 'UCartbat', name: 'ARTBAT' }, { id: 'UCafter', name: 'Afterlife' }]);
});

test('a joint upload without names in its dialog takes them from the label', async () => {
  const byVideo = await subscriptions();
  assert.deepEqual(byVideo.bbbbbbbbbbb, [{ id: 'UCtale', name: 'Tale Of Us' }, { id: 'UCanyma', name: 'Anyma' }]);
});

test('a single channel stays one channel', async () => {
  const byVideo = await subscriptions();
  assert.deepEqual(byVideo.ccccccccccc, [{ id: 'UCtml', name: 'Tomorrowland' }]);
});

test('the older video layout links each channel of its owner line', async () => {
  const byVideo = await subscriptions();
  assert.deepEqual(byVideo.ddddddddddd, [{ id: 'UCsol', name: 'Solomun' }, { id: 'UCadam', name: 'Adam Port' }]);
});

// --- Start-up: the language picked in Settings is the one asked of YouTube.

const page = '<script>ytcfg.set({"INNERTUBE_CONTEXT":{"client":{"clientName":"WEB_REMIX","clientVersion":"1.2","hl":"tr","gl":"TR"}},"LOGGED_IN":true});</script>';

async function languageAfterBootstrap(forceLang, ui) {
  const bridge = loadBridge({});
  await bridge.call('bootstrap', JSON.stringify({ html: page, hasAuth: true, lang: 'tr', region: 'TR', forceLang, ui }));
  return globalThis.ytcfg.get('INNERTUBE_CONTEXT').client.hl;
}

test("without a chosen language YouTube's own stays", async () => {
  assert.equal(await languageAfterBootstrap('', 'tr'), 'tr');
});

test('a chosen language replaces it', async () => {
  assert.equal(await languageAfterBootstrap('en', 'en'), 'en');
});

// --- Player data: each song's loudness reaches the app (volume leveling).

test("each format's loudness and the song's overall loudness are passed on", async () => {
  const bridge = loadBridge({
    playabilityStatus: { status: 'OK' },
    videoDetails: { videoId: 'vvvvvvvvvvv', lengthSeconds: '200' },
    playerConfig: { audioConfig: { loudnessDb: 4.5 } },
    streamingData: { adaptiveFormats: [
      { itag: 141, mimeType: 'audio/mp4; codecs="mp4a.40.2"', bitrate: 260000, url: 'https://a', loudnessDb: 5.25 },
      { itag: 140, mimeType: 'audio/mp4; codecs="mp4a.40.2"', bitrate: 130000, url: 'https://b' },
      { itag: 137, mimeType: 'video/mp4', bitrate: 4000000, url: 'https://v' },
    ] },
  }, loggedIn);
  const r = JSON.parse(await bridge.call('playerData', JSON.stringify({ videoId: 'vvvvvvvvvvv' })));
  assert.equal(r.loudnessDb, 4.5);
  assert.deepEqual(r.formats.map((f) => f.loudnessDb), [5.25, null]);
});

// --- Channel pictures: the channel's own avatar, not its banner.

test("a channel's photo is its avatar, asked for large", async () => {
  const bridge = loadBridge({
    metadata: { channelMetadataRenderer: { avatar: { thumbnails: [
      { url: 'https://yt3.ggpht.com/abc=s48-c-k-c0x00ffffff-no-rj' },
      { url: 'https://yt3.ggpht.com/abc=s176-c-k-c0x00ffffff-no-rj' }] } } },
    header: { pageHeaderRenderer: { banner: { imageBannerViewModel: { image: { sources: [{ url: 'https://yt3.ggpht.com/banner=w2560' }] } } } } },
  }, loggedIn);
  const r = JSON.parse(await bridge.call('channelPhotos', JSON.stringify({ ids: ['UCx'] })));
  assert.equal(r.UCx, 'https://yt3.ggpht.com/abc=s512-c-k-c0x00ffffff-no-rj');
});

test('a channel without a picture is left empty', async () => {
  const bridge = loadBridge({ metadata: {} }, loggedIn);
  const r = JSON.parse(await bridge.call('channelPhotos', JSON.stringify({ ids: ['UCy'] })));
  assert.equal(r.UCy, null);
});

// --- Library: whether an album or someone else's playlist is kept, from its page's save button.

const albumPage = (toggled) => ({ contents: { x: { musicResponsiveHeaderRenderer: {
  title: { runs: [{ text: 'An Album' }] },
  buttons: [
    { toggleButtonRenderer: { isToggled: toggled, defaultIcon: { iconType: 'LIBRARY_ADD' }, toggledIcon: { iconType: 'LIBRARY_SAVED' } } },
  ] } } } });

test("an album page says whether it is in the library", async () => {
  for (const kept of [true, false]) {
    const bridge = loadBridge(albumPage(kept), loggedIn);
    const r = JSON.parse(await bridge.call('browse', JSON.stringify({ browseId: 'MPREb_x' })));
    assert.equal(r.header.saved, kept);
  }
});

test("a page without a save button leaves it unknown", async () => {
  const bridge = loadBridge({ contents: { x: { musicResponsiveHeaderRenderer: { title: { runs: [{ text: 'A' }] } } } } }, loggedIn);
  const r = JSON.parse(await bridge.call('browse', JSON.stringify({ browseId: 'VLPLx' })));
  assert.equal(r.header.saved, null);
});

// --- Podcasts: a show page that comes back empty is read as the playlist of its episodes.

test("an empty podcast page falls back to its episodes' playlist", async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const asked = [];
  const episodes = { header: { musicResponsiveHeaderRenderer: { title: { runs: [{ text: 'A Show' }] } } },
    contents: { x: { musicShelfRenderer: { contents: [1, 2].map((n) => ({ musicResponsiveListItemRenderer: {
      playlistItemData: { videoId: `episode000${n}` },
      flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: `Episode ${n}` }] } } }] } })) } } } };
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => {
    const b = JSON.parse(body || '{}');
    if (!url.includes('/browse')) { ok(200, '{}'); return; }
    asked.push(b.browseId + (b.params ? '+params' : ''));
    ok(200, JSON.stringify(b.browseId === 'VLPLshow' ? episodes : { microformat: { microformatDataRenderer: {} } }));
  };
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  const r = JSON.parse(await globalThis.__ytmusic.call('browse', JSON.stringify({ browseId: 'MPSPPLshow', params: 'p' })));
  assert.deepEqual(asked, ['MPSPPLshow+params', 'MPSPPLshow', 'VLPLshow']);
  assert.equal(r.header.title, 'A Show');
  assert.deepEqual(r.sections[0].items.map((i) => i.videoId), ['episode0001', 'episode0002']);
});

test("a podcast without a cover in its header takes the page's microformat picture", async () => {
  const bridge = loadBridge({
    header: { musicResponsiveHeaderRenderer: { title: { runs: [{ text: 'A Show' }] } } },
    microformat: { microformatDataRenderer: { thumbnail: { thumbnails: [{ url: 'https://yt3/show=s544', width: 544, height: 544 }] } } },
    contents: { x: { musicShelfRenderer: { contents: [{ musicResponsiveListItemRenderer: {
      playlistItemData: { videoId: 'episode0001' },
      flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Episode' }] } } }] } }] } } },
  }, loggedIn);
  const r = JSON.parse(await bridge.call('browse', JSON.stringify({ browseId: 'MPSPPLshow' })));
  assert.ok(r.header.thumbnail.startsWith('https://yt3/show'));
});

test('a podcast is kept in the library by its episodes playlist', async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const bodies = [];
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => { bodies.push([url, JSON.parse(body || '{}')]); ok(200, '{}'); };
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  await globalThis.__ytmusic.call('saveToLibrary', JSON.stringify({ browseId: 'MPSPPLshow', playlistId: '', play: '', on: true }));
  const like = bodies.find(([url]) => url.includes('like/like'));
  assert.equal(like[1].target.playlistId, 'PLshow');
});

// --- Lengths: episodes' lengths come from the list's play queue, across its pages.

test("missing lengths are read from the list's play queue", async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const row = (v, l) => ({ playlistPanelVideoRenderer: { videoId: v, lengthText: { runs: [{ text: l }] } } });
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => {
    const page = url.includes('ctoken') || url.includes('continuation')
      ? { continuationContents: { playlistPanelContinuation: { contents: [row('bbbbbbbbbbb', '3:26:23')] } } }
      : { contents: { x: { playlistPanelRenderer: { contents: [row('aaaaaaaaaaa', '1:02:03')],
          continuations: [{ nextContinuationData: { continuation: 'more' } }] } } } };
    ok(200, JSON.stringify(page));
  };
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  const r = JSON.parse(await globalThis.__ytmusic.call('lengths',
    JSON.stringify({ playlistId: 'PLshow', videoIds: ['aaaaaaaaaaa', 'bbbbbbbbbbb'] })));
  assert.deepEqual(r, { aaaaaaaaaaa: '1:02:03', bbbbbbbbbbb: '3:26:23' });
});

test("a podcast's page comes with its episodes' lengths", async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const page = { header: { musicResponsiveHeaderRenderer: { title: { runs: [{ text: 'A Show' }] } } },
    contents: { x: { musicShelfRenderer: { contents: [{ musicResponsiveListItemRenderer: {
      playlistItemData: { videoId: 'aaaaaaaaaaa' },
      flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Episode' }] } } }] } }] } } } };
  const queue = { contents: { x: { playlistPanelRenderer: { contents: [
    { playlistPanelVideoRenderer: { videoId: 'aaaaaaaaaaa', lengthText: { runs: [{ text: '2:25:28' }] } } }] } } } };
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => ok(200, JSON.stringify(url.includes('/next') ? queue : page));
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  const r = JSON.parse(await globalThis.__ytmusic.call('browse', JSON.stringify({ browseId: 'MPSPPLshow' })));
  assert.equal(r.sections[0].items[0].duration, '2:25:28');
});

// --- Links: what YouTube says a link leads to.

test('a channel handle link resolves to its page', async () => {
  const bridge = loadBridge({ endpoint: { browseEndpoint: { browseId: 'UCchannel',
    browseEndpointContextSupportedConfigs: { browseEndpointContextMusicConfig: { pageType: 'MUSIC_PAGE_TYPE_ARTIST' } } } } }, loggedIn);
  const r = JSON.parse(await bridge.call('resolveLink', JSON.stringify({ url: 'https://www.youtube.com/@someone' })));
  assert.deepEqual(r, { browseId: 'UCchannel', pageType: 'MUSIC_PAGE_TYPE_ARTIST' });
});

test('a video link resolves to the video', async () => {
  const bridge = loadBridge({ endpoint: { watchEndpoint: { videoId: 'aaaaaaaaaaa' } } }, loggedIn);
  const r = JSON.parse(await bridge.call('resolveLink', JSON.stringify({ url: 'https://youtube.com/x' })));
  assert.deepEqual(r, { videoId: 'aaaaaaaaaaa', playlistId: null });
});

// --- Play counts: on album rows, and for playlists from the same list on YouTube.

test("an album row's play count is kept on its own", async () => {
  const bridge = loadBridge({ contents: { x: { musicShelfRenderer: { contents: [{ musicResponsiveListItemRenderer: {
    playlistItemData: { videoId: 'aaaaaaaaaaa' },
    flexColumns: [
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Song' }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Justice' }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: '4,3 Mn dinlenme' }] } } }] } }] } } } }, loggedIn);
  const r = JSON.parse(await bridge.call('browse', JSON.stringify({ browseId: 'MPREb_x' })));
  assert.equal(r.sections[0].items[0].plays, '4,3 Mn');
});

test("a playlist's play counts come from the same list on YouTube", async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const page = { contents: { x: { musicShelfRenderer: { contents: [{ musicResponsiveListItemRenderer: {
    playlistItemData: { videoId: 'aaaaaaaaaaa' },
    flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Song' }] } } }] } }] } } } };
  const web = { contents: { x: { playlistVideoRenderer: { videoId: 'aaaaaaaaaaa',
    videoInfo: { runs: [{ text: '12 Mn görüntüleme' }, { text: ' • ' }, { text: '2 yıl önce' }] } } } } };
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) =>
    ok(200, JSON.stringify(url.includes('music.youtube.com') ? page : web));
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  const r = JSON.parse(await globalThis.__ytmusic.call('browse', JSON.stringify({ browseId: 'VLPLlist' })));
  assert.equal(r.sections[0].items[0].plays, '12 Mn');
});

test("an album's songs by other artists get links to them from the album's queue", async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const page = { contents: { x: { musicShelfRenderer: { contents: [{ musicResponsiveListItemRenderer: {
    playlistItemData: { videoId: 'aaaaaaaaaaa' },
    overlay: { musicItemThumbnailOverlayRenderer: { content: { musicPlayButtonRenderer: { playNavigationEndpoint: {
      watchEndpoint: { videoId: 'aaaaaaaaaaa', playlistId: 'OLAK5uy_album' } } } } } },
    flexColumns: [
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Song' }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Justice' }] } } },
      { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: '4,3 Mn dinlenme' }] } } }] } }] } } } };
  const artistRun = { text: 'Justice', navigationEndpoint: { browseEndpoint: { browseId: 'UCjustice',
    browseEndpointContextSupportedConfigs: { browseEndpointContextMusicConfig: { pageType: 'MUSIC_PAGE_TYPE_ARTIST' } } } } };
  const queue = { contents: { x: { playlistPanelRenderer: { contents: [
    { playlistPanelVideoRenderer: { videoId: 'aaaaaaaaaaa', longBylineText: { runs: [artistRun] } } }] } } } };
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => ok(200, JSON.stringify(url.includes('/next') ? queue : page));
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  const r = JSON.parse(await globalThis.__ytmusic.call('browse', JSON.stringify({ browseId: 'MPREb_x' })));
  assert.deepEqual(r.sections[0].items[0].artists, [{ name: 'Justice', id: 'UCjustice' }]);
});

test("an artist's top songs get their lengths from the list's queue when its page has none", async () => {
  globalThis.window = globalThis;
  delete globalThis.__ytmusic;
  const song = { musicResponsiveListItemRenderer: { playlistItemData: { videoId: 'aaaaaaaaaaa' },
    flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: 'Song' }] } } }] } };
  const artist = { contents: { x: { musicShelfRenderer: { contents: [song],
    bottomEndpoint: { browseEndpoint: { browseId: 'VLPLtop' } },
    title: { runs: [{ text: 'Top songs', navigationEndpoint: { browseEndpoint: { browseId: 'VLPLtop' } } }] } } } } };
  const queue = { contents: { x: { playlistPanelRenderer: { contents: [
    { playlistPanelVideoRenderer: { videoId: 'aaaaaaaaaaa', lengthText: { runs: [{ text: '4:25' }] } } }] } } } };
  globalThis.__nativeHttp = (url, method, headers, body, auth, ok) => {
    const b = JSON.parse(body || '{}');
    if (url.includes('/next')) return ok(200, JSON.stringify(queue));
    ok(200, JSON.stringify(b.browseId === 'VLPLtop' ? { contents: { x: { musicShelfRenderer: { contents: [song] } } } } : artist));
  };
  globalThis.ytcfg = { get: (k) => loggedIn[k] };
  (0, eval)(source);
  const r = JSON.parse(await globalThis.__ytmusic.call('browse', JSON.stringify({ browseId: 'UCartist' })));
  const item = r.sections.flatMap((s) => s.items).find((i) => i.videoId === 'aaaaaaaaaaa');
  assert.equal(item.duration, '4:25');
});
