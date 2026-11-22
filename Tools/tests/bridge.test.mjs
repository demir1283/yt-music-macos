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
