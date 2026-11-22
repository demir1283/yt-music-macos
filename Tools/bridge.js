(() => {
  'use strict';
  if (window.__ytmusic) return;

  // Runs inside the app's own JavaScript engine (JavaScriptCore) — there is no web
  // page. The app supplies HTTP (with the account's cookies) through __nativeHttp.
  const location = { origin: 'https://music.youtube.com', hostname: 'music.youtube.com' };
  const http = (url, method, headers, body, auth) => new Promise((resolve, reject) => {
    // auth: the origin to sign the request for ('' = no Authorization header).
    window.__nativeHttp(url, method, JSON.stringify(headers || {}), body || '', auth || '',
      (status, text) => resolve({ status, body: text }), (m) => reject(new Error(String(m))));
  });

  // ───────────────────────────── helpers ─────────────────────────────
  const SALT = Math.random().toString(36).slice(2, 7);
  let counter = 0;
  // The app's own language, for the few messages written here (set by bootstrap).
  let uiTurkish = true;
  const nextId = (p) => `${p}${SALT}${++counter}`;
  const num = (x) => (Number.isFinite(x) ? x : 0);

  const text = (t) => {
    if (!t) return '';
    if (typeof t === 'string') return t;
    if (t.simpleText != null) return String(t.simpleText);
    if (Array.isArray(t.runs)) return t.runs.map((r) => r.text || '').join('');
    return '';
  };

  const SKIP = new Set(['responseContext', 'frameworkUpdates', 'trackingParams', 'clickTrackingParams']);

  function findKey(obj, key, depth = 0) {
    if (!obj || typeof obj !== 'object' || depth > 45) return null;
    if (Array.isArray(obj)) {
      for (const x of obj) { const r = findKey(x, key, depth + 1); if (r) return r; }
      return null;
    }
    if (Object.prototype.hasOwnProperty.call(obj, key)) return obj[key];
    for (const k in obj) {
      if (SKIP.has(k)) continue;
      const r = findKey(obj[k], key, depth + 1);
      if (r) return r;
    }
    return null;
  }

  function upgradeThumb(url, size = 544) {
    if (!url) return null;
    if (url.startsWith('//')) url = 'https:' + url;
    if (/googleusercontent\.com|ggpht\.com/.test(url)) {
      url = url.replace(/=w\d+-h\d+/, `=w${size}-h${size}`).replace(/=s\d+/, `=s${size}`);
    }
    return url;
  }

  function bestThumb(obj, size = 544) {
    const t = findKey(obj, 'thumbnails');
    if (!Array.isArray(t) || !t.length) return null;
    const last = t[t.length - 1];
    let url = last.url || null;
    if (!url) return null;
    if (url.startsWith('//')) url = 'https:' + url;
    if (last.width && last.height && last.width === last.height && last.width < size) url = upgradeThumb(url, size);
    return url;
  }

  const PT = {
    MUSIC_PAGE_TYPE_ALBUM: 'album',
    MUSIC_PAGE_TYPE_AUDIOBOOK: 'album',
    MUSIC_PAGE_TYPE_PLAYLIST: 'playlist',
    MUSIC_PAGE_TYPE_ARTIST: 'artist',
    MUSIC_PAGE_TYPE_USER_CHANNEL: 'artist',
    MUSIC_PAGE_TYPE_LIBRARY_ARTIST: 'artist',
    MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE: 'podcast',
    MUSIC_PAGE_TYPE_NON_MUSIC_AUDIO_TRACK_PAGE: 'episode',
  };

  const pageTypeOf = (ep) =>
    ep?.browseEndpoint?.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType || '';

  function videoKind(we) {
    const t = we?.watchEndpointMusicSupportedConfigs?.watchEndpointMusicConfig?.musicVideoType || '';
    if (t.includes('ATV')) return 'song';
    if (t.includes('PODCAST')) return 'episode';
    if (t) return 'video';
    return 'song';
  }

  const fixArtistId = (id) => (id && id.startsWith('MPLA') ? id.slice(4) : id);

  function links(runs) {
    const out = [];
    for (const r of runs || []) {
      const be = r.navigationEndpoint?.browseEndpoint;
      if (!be?.browseId) continue;
      if (PT[pageTypeOf({ browseEndpoint: be })] === 'artist') out.push({ name: r.text || '', id: fixArtistId(be.browseId) });
    }
    return out;
  }

  function albumLink(runs) {
    for (const r of runs || []) {
      const be = r.navigationEndpoint?.browseEndpoint;
      if (be?.browseId && PT[pageTypeOf({ browseEndpoint: be })] === 'album') return { name: r.text || '', id: be.browseId };
    }
    return null;
  }

  function findEndpoint(obj) {
    const w = findKey(obj, 'watchEndpoint');
    if (w) return { watchEndpoint: w };
    const wp = findKey(obj, 'watchPlaylistEndpoint');
    if (wp) return { watchPlaylistEndpoint: wp };
    return null;
  }

  const clean = (ep) => {
    if (!ep) return null;
    if (ep.watchEndpoint) return JSON.stringify({ watchEndpoint: ep.watchEndpoint });
    if (ep.watchPlaylistEndpoint) return JSON.stringify({ watchPlaylistEndpoint: ep.watchPlaylistEndpoint });
    return null;
  };

  function mk(o) {
    return Object.assign({
      uid: nextId('i'), kind: 'unknown', title: '', subtitle: '', thumbnail: null,
      videoId: null, browseId: null, params: null, playlistId: null,
      artists: [], album: null, duration: null, explicit: false,
      play: null, wide: false, color: null, setVideoId: null,
    }, o);
  }

  function setBrowse(it, be, pt) {
    it.kind = PT[pt] || 'unknown';
    let id = be.browseId || null;
    if (pt === 'MUSIC_PAGE_TYPE_LIBRARY_ARTIST') id = fixArtistId(id);
    it.browseId = id;
    it.params = be.params || null;
    if (it.kind === 'playlist' && id && id.startsWith('VL')) it.playlistId = id.slice(2);
  }

  const isExplicit = (badges) =>
    !!(badges || []).some((b) => b.musicInlineBadgeRenderer?.icon?.iconType === 'MUSIC_EXPLICIT_BADGE');

  const DUR = /^\d{1,2}:\d{2}(:\d{2})?$/;

  // ───────────────────────────── item parsers ─────────────────────────────
  function parseTwoRow(r) {
    const nav = r.navigationEndpoint || {};
    const titleRuns = r.title?.runs || [];
    const be = nav.browseEndpoint || titleRuns[0]?.navigationEndpoint?.browseEndpoint;
    const playEp = r.thumbnailOverlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer?.playNavigationEndpoint || null;
    const it = mk({
      title: text(r.title),
      subtitle: text(r.subtitle),
      thumbnail: bestThumb(r.thumbnailRenderer),
      artists: links(r.subtitle?.runs),
      wide: String(r.aspectRatio || '').includes('16_9'),
      explicit: isExplicit(r.subtitleBadges),
    });
    if (nav.watchEndpoint) {
      it.kind = videoKind(nav.watchEndpoint);
      it.videoId = nav.watchEndpoint.videoId || null;
      it.playlistId = nav.watchEndpoint.playlistId || null;
      it.play = clean({ watchEndpoint: nav.watchEndpoint });
    } else if (be) {
      setBrowse(it, be, pageTypeOf({ browseEndpoint: be }));
      it.play = clean(playEp);
      asEpisode(it, playEp);
    }
    return it;
  }

  // Podcast / long-form episodes link to an episode page ("MPED…"), which has nothing to
  // show; they are really videos, so make them play directly.
  function asEpisode(it, playEp) {
    const id = it.browseId || '';
    if (it.kind !== 'episode' && !id.startsWith('MPED')) return;
    const vid = playEp?.watchEndpoint?.videoId || (id.startsWith('MPED') ? id.slice(4) : null);
    if (!vid) return;
    it.kind = 'episode';
    it.videoId = vid;
    it.browseId = null;
    it.play = clean(playEp?.watchEndpoint ? playEp : { watchEndpoint: { videoId: vid } });
  }

  function parseListItem(r) {
    const cols = (r.flexColumns || []).map((c) => c.musicResponsiveListItemFlexColumnRenderer?.text?.runs || []);
    const titleRuns = cols[0] || [];
    const rest = cols.slice(1).flat();
    const fixed = (r.fixedColumns || []).map((c) => text(c.musicResponsiveListItemFixedColumnRenderer?.text)).filter(Boolean);
    const playEp = r.overlay?.musicItemThumbnailOverlayRenderer?.content?.musicPlayButtonRenderer?.playNavigationEndpoint || null;
    const titleNav = titleRuns[0]?.navigationEndpoint;
    const watch = playEp?.watchEndpoint || titleNav?.watchEndpoint || null;
    const videoId = r.playlistItemData?.videoId || watch?.videoId || null;
    const setVideoId = r.playlistItemData?.playlistSetVideoId || null;

    const it = mk({
      title: titleRuns.map((x) => x.text || '').join(''),
      thumbnail: bestThumb(r.thumbnail, 226),
      artists: links(rest),
      album: albumLink(rest),
      explicit: isExplicit(r.badges),
      setVideoId,
    });

    let dur = fixed.find((t) => DUR.test(t)) || null;
    if (!dur) dur = rest.map((x) => (x.text || '').trim()).find((t) => DUR.test(t)) || null;
    it.duration = dur;

    if (videoId) {
      it.kind = videoKind(watch);
      it.videoId = videoId;
      it.playlistId = watch?.playlistId || null;
      it.play = clean(playEp?.watchEndpoint ? playEp : { watchEndpoint: watch || { videoId } });
    } else {
      const be = r.navigationEndpoint?.browseEndpoint || titleNav?.browseEndpoint;
      if (be) setBrowse(it, be, pageTypeOf({ browseEndpoint: be }));
      it.play = clean(playEp);
      asEpisode(it, playEp);
    }

    const parts = [];
    for (const c of cols.slice(1)) {
      const t = c.map((x) => x.text || '').join('').trim();
      if (t && !DUR.test(t)) parts.push(t);
    }
    it.subtitle = parts.join(' • ').replace(/\s*•\s*\d{1,2}:\d{2}(:\d{2})?\s*$/, '');
    return it;
  }

  function parseNavButton(r) {
    const be = r.clickCommand?.browseEndpoint;
    const c = r.solid?.leftStripeColor;
    return mk({
      kind: 'category',
      title: text(r.buttonText),
      browseId: be?.browseId || null,
      params: be?.params || null,
      color: c != null ? '#' + ((Number(c) >>> 0) & 0xffffff).toString(16).padStart(6, '0') : null,
    });
  }

  function parseMultiRow(r) {
    const ep = r.onTap?.watchEndpoint ? { watchEndpoint: r.onTap.watchEndpoint } : findEndpoint(r.overlay);
    const it = mk({ kind: 'episode', title: text(r.title), subtitle: text(r.subtitle), thumbnail: bestThumb(r.thumbnail, 226) });
    if (ep?.watchEndpoint) { it.videoId = ep.watchEndpoint.videoId || null; it.play = clean(ep); }
    return it;
  }

  function parseCard(c) {
    const titleRun = c.title?.runs?.[0];
    const nav = titleRun?.navigationEndpoint || c.onTap || {};
    const it = mk({
      title: text(c.title),
      subtitle: text(c.subtitle),
      thumbnail: bestThumb(c.thumbnail, 544),
      artists: links(c.subtitle?.runs),
    });
    if (nav.watchEndpoint) {
      it.kind = videoKind(nav.watchEndpoint);
      it.videoId = nav.watchEndpoint.videoId || null;
      it.play = clean({ watchEndpoint: nav.watchEndpoint });
    } else if (nav.browseEndpoint) {
      setBrowse(it, nav.browseEndpoint, pageTypeOf(nav));
    }
    if (!it.play) {
      const p = findKey(c.thumbnailOverlay, 'playNavigationEndpoint') || findKey(c.buttons, 'playNavigationEndpoint');
      it.play = clean(p) || clean(findEndpoint(c.buttons));
    }
    return it;
  }

  function parseEntry(e) {
    if (!e || typeof e !== 'object') return null;
    if (e.musicTwoRowItemRenderer) return parseTwoRow(e.musicTwoRowItemRenderer);
    if (e.musicResponsiveListItemRenderer) return parseListItem(e.musicResponsiveListItemRenderer);
    if (e.musicNavigationButtonRenderer) return parseNavButton(e.musicNavigationButtonRenderer);
    if (e.musicMultiRowListItemRenderer) return parseMultiRow(e.musicMultiRowListItemRenderer);
    return null;
  }

  // ───────────────────────────── shelves ─────────────────────────────
  const SHELVES = new Set([
    'musicCarouselShelfRenderer', 'musicImmersiveCarouselShelfRenderer', 'musicShelfRenderer',
    'musicPlaylistShelfRenderer', 'gridRenderer', 'musicCardShelfRenderer',
  ]);

  function parseShelf(key, s) {
    const h = s.header || {};
    const hh = h.musicCarouselShelfBasicHeaderRenderer || h.musicImmersiveCarouselShelfBasicHeaderRenderer
      || h.gridHeaderRenderer || h.musicCardShelfHeaderBasicRenderer || {};
    const isCard = key === 'musicCardShelfRenderer';
    const title = isCard ? text(hh.title) : (text(hh.title) || text(s.title));
    const moreEp = hh.moreContentButton?.buttonRenderer?.navigationEndpoint || s.bottomEndpoint
      || hh.title?.runs?.[0]?.navigationEndpoint || (isCard ? null : s.title?.runs?.[0]?.navigationEndpoint) || null;

    const sec = {
      id: nextId('s'), title, strapline: text(hh.strapline) || null, layout: 'cards',
      items: [], more: null, continuation: null, top: null,
    };
    if (moreEp?.browseEndpoint?.browseId) {
      sec.more = { browseId: moreEp.browseEndpoint.browseId, params: moreEp.browseEndpoint.params || null, pageType: pageTypeOf(moreEp) || null, query: null };
    } else if (moreEp?.searchEndpoint) {
      sec.more = { browseId: null, params: moreEp.searchEndpoint.params || null, pageType: null, query: moreEp.searchEndpoint.query || null };
    }

    if (isCard) { sec.layout = 'top'; sec.top = parseCard(s); }

    const entries = s.contents || s.items || [];
    for (const e of entries) {
      if (e.continuationItemRenderer) {
        sec.continuation = e.continuationItemRenderer.continuationEndpoint?.continuationCommand?.token || null;
        continue;
      }
      const it = parseEntry(e);
      if (it) sec.items.push(it);
    }
    if (!sec.continuation) sec.continuation = s.continuations?.[0]?.nextContinuationData?.continuation || null;

    if (!isCard) {
      const first = entries.find((e) => !e.continuationItemRenderer) || {};
      if (first.musicResponsiveListItemRenderer || first.musicMultiRowListItemRenderer) sec.layout = 'list';
      else if (first.musicNavigationButtonRenderer) sec.layout = 'nav';
      else sec.layout = 'cards';
    }
    return sec;
  }

  function extractSections(root) {
    const out = [];
    (function walk(n, d) {
      if (!n || typeof n !== 'object' || d > 60) return;
      if (Array.isArray(n)) { for (const x of n) walk(x, d + 1); return; }
      for (const k in n) {
        if (SKIP.has(k)) continue;
        if (d === 0 && k === 'header') continue;
        if (SHELVES.has(k)) {
          const s = parseShelf(k, n[k]);
          if (s.items.length || s.top) out.push(s);
          continue;
        }
        walk(n[k], d + 1);
      }
    })(root, 0);
    return out;
  }

  function collectItems(root) {
    const out = [];
    (function walk(n, d) {
      if (!n || typeof n !== 'object' || d > 60) return;
      if (Array.isArray(n)) { for (const x of n) walk(x, d + 1); return; }
      if (n.musicResponsiveListItemRenderer || n.musicTwoRowItemRenderer || n.musicMultiRowListItemRenderer) {
        const it = parseEntry(n);
        if (it) out.push(it);
        return;
      }
      for (const k in n) { if (!SKIP.has(k)) walk(n[k], d + 1); }
    })(root, 0);
    return out;
  }

  function anyToken(root) {
    const c = findKey(root, 'continuationCommand');
    if (c?.token) return c.token;
    const n = findKey(root, 'nextContinuationData');
    return n?.continuation || null;
  }

  function sectionListToken(r) {
    const sl = findKey(r, 'sectionListContinuation') || findKey(r, 'sectionListRenderer');
    return sl?.continuations?.[0]?.nextContinuationData?.continuation || null;
  }

  function chipsOf(r) {
    const cc = findKey(r, 'chipCloudRenderer');
    const out = [];
    for (const c of cc?.chips || []) {
      const x = c.chipCloudChipRenderer;
      if (!x) continue;
      // The endpoint may sit in navigationEndpoint or in a select/deselect command.
      const se = x.navigationEndpoint?.searchEndpoint || findKey(x, 'searchEndpoint');
      const be = x.navigationEndpoint?.browseEndpoint || findKey(x, 'browseEndpoint');
      out.push({ title: text(x.text), params: se?.params || be?.params || null, browseId: be?.browseId || null, selected: !!x.isSelected });
    }
    return out;
  }

  function collectButtons(h) {
    const found = {};
    (function walk(n, d) {
      if (!n || typeof n !== 'object' || d > 25) return;
      if (Array.isArray(n)) { n.forEach((x) => walk(x, d + 1)); return; }
      if (n.musicPlayButtonRenderer?.playNavigationEndpoint && !found.PLAY_ARROW) {
        found.PLAY_ARROW = clean(n.musicPlayButtonRenderer.playNavigationEndpoint);
      }
      const icon = n.icon?.iconType;
      if (icon && !found[icon]) {
        const ep = n.navigationEndpoint || n.command || n.onTap || n.serviceEndpoint;
        const e = ep ? clean(ep.watchEndpoint || ep.watchPlaylistEndpoint ? ep : findEndpoint(ep)) : null;
        if (e) found[icon] = e;
      }
      for (const k in n) { if (!SKIP.has(k)) walk(n[k], d + 1); }
    })(h, 0);
    return found;
  }

  function parseHeader(resp) {
    const keys = ['musicResponsiveHeaderRenderer', 'musicDetailHeaderRenderer', 'musicImmersiveHeaderRenderer', 'musicVisualHeaderRenderer', 'musicHeaderRenderer'];
    let h = null, hk = null;
    for (const k of keys) { h = findKey(resp, k); if (h) { hk = k; break; } }
    if (!h) return null;
    const style = (hk === 'musicImmersiveHeaderRenderer' || hk === 'musicVisualHeaderRenderer') ? 'artist'
      : (hk === 'musicHeaderRenderer' ? 'plain' : 'collection');
    const btns = collectButtons(h);
    const sub = h.subscriptionButton?.subscribeButtonRenderer;
    return {
      style,
      title: text(h.title),
      subtitle: text(h.subtitle),
      secondSubtitle: text(h.secondSubtitle),
      strapline: text(h.straplineTextOne),
      description: text(h.description?.musicDescriptionShelfRenderer?.description) || text(h.description),
      thumbnail: style === 'artist' ? bestThumb(h.thumbnail || h.foregroundThumbnail, 1200) : bestThumb(h.thumbnail, 800),
      strapThumb: bestThumb(h.straplineThumbnail, 96),
      subscribers: text(sub?.longSubscriberCountText) || text(sub?.subscriberCountText) || text(h.monthlyListenerCount) || '',
      play: btns.PLAY_ARROW || null,
      shuffle: btns.MUSIC_SHUFFLE || null,
      radio: btns.MIX || null,
      artists: links(h.straplineTextOne?.runs).concat(links(h.subtitle?.runs)),
      ...subscription(sub),
      ...editInfo(resp),
    };
  }

  // Artist channels: whether the account is subscribed, and what (un)subscribing needs.
  function subscription(sub) {
    if (!sub) return { channelId: null, subscribed: null };
    return {
      channelId: sub.channelId || findKey(sub, 'channelIds')?.[0] || null,
      subscribed: !!sub.subscribed,
      subscriberShort: text(sub.shortSubscriberCountText) || text(sub.subscriberCountText) || null,
      subscribeParams: findKey(sub, 'subscribeEndpoint')?.params || null,
      unsubscribeParams: findKey(sub, 'unsubscribeEndpoint')?.params || null,
    };
  }

  // Playlists the account owns come with an edit header (name, description, privacy).
  function editInfo(resp) {
    const ed = findKey(resp, 'musicEditablePlaylistDetailHeaderRenderer');
    if (!ed) return { editable: false, privacy: null, playlistId: null, rawDescription: null };
    const eh = findKey(ed.editHeader || ed, 'musicPlaylistEditHeaderRenderer') || {};
    const playlistId = eh.playlistId || findKey(ed, 'playlistId') || null;
    return {
      editable: true,
      privacy: eh.privacy || null,
      playlistId: playlistId ? String(playlistId).replace(/^VL/, '') : null,
      rawDescription: text(eh.editDescription) || null,
    };
  }

  const plId = (id) => String(id || '').replace(/^VL/, '');

  async function editPlaylist(playlistId, actions) {
    const r = await api('browse/edit_playlist', { playlistId: plId(playlistId), actions });
    const status = r.status || '';
    if (status && status !== 'STATUS_SUCCEEDED') throw new Error((uiTurkish ? 'YouTube Music değişikliği kabul etmedi (' : 'YouTube Music did not accept the change (') + status + ')');
    return r;
  }

  // ───────────────────────────── InnerTube ─────────────────────────────
  async function api(endpoint, body, query = '') {
    const cfg = window.ytcfg;
    const key = cfg.get('INNERTUBE_API_KEY');
    const headers = {
      'Content-Type': 'application/json',
      'X-Goog-AuthUser': String(cfg.get('SESSION_INDEX') ?? 0),
      'X-Origin': location.origin,
      'X-Youtube-Client-Name': String(cfg.get('INNERTUBE_CONTEXT_CLIENT_NAME') ?? 67),
      'X-Youtube-Client-Version': String(cfg.get('INNERTUBE_CLIENT_VERSION') || ''),
      Origin: location.origin,
      Referer: location.origin + '/',
    };
    const visitor = cfg.get('VISITOR_DATA');
    if (visitor) headers['X-Goog-Visitor-Id'] = visitor;
    const pageId = cfg.get('DELEGATED_SESSION_ID');
    if (pageId) headers['X-Goog-PageId'] = pageId;

    const url = `${location.origin}/youtubei/v1/${endpoint}?prettyPrint=false${key ? '&key=' + key : ''}${query}`;
    const out = await http(url, 'POST', headers,
      JSON.stringify(Object.assign({ context: cfg.get('INNERTUBE_CONTEXT') }, body || {})),
      cfg.get('LOGGED_IN') ? location.origin : '');
    if (out.status < 200 || out.status >= 300) throw new Error(`YouTube Music ${out.status} hatası (${endpoint})`);
    return JSON.parse(out.body);
  }

  const ctokenQuery = (t) => `&ctoken=${encodeURIComponent(t)}&continuation=${encodeURIComponent(t)}&type=next`;

  // ───────────────────────────── native queue ─────────────────────────────
  function matchBrace(s, start) {
    let depth = 0, inStr = false;
    for (let i = start; i < s.length; i++) {
      const c = s[i];
      if (inStr) {
        if (c === '\\') i++;
        else if (c === '"') inStr = false;
      } else if (c === '"') inStr = true;
      else if (c === '{') depth++;
      else if (c === '}') { depth--; if (depth === 0) return i; }
    }
    return -1;
  }

  // Every playable row of a watch queue: the version that plays and, for song/video
  // pairs, its counterpart (the app can then prefer the song over the music video).
  function panelRows(root) {
    const out = [];
    (function walk(n) {
      if (!n || typeof n !== 'object') return;
      if (Array.isArray(n)) { n.forEach(walk); return; }
      const w = n.playlistPanelVideoWrapperRenderer;
      const p = n.playlistPanelVideoRenderer || w?.primaryRenderer?.playlistPanelVideoRenderer;
      if (p) {
        if (p.videoId) {
          const alt = w?.counterpart?.[0]?.counterpartRenderer?.playlistPanelVideoRenderer;
          out.push({ p, alt: alt?.videoId ? alt : null });
        }
        return;
      }
      for (const k in n) { if (!SKIP.has(k)) walk(n[k]); }
    })(root);
    return out;
  }

  const rowsToEntries = (rows) => rows.map((x, i) => queueEntry(x.p, i, x.alt));

  // Radios and mixes YouTube Music builds on its own (not its editorial "RDCLAK" lists).
  const isRadio = (id) => /^RD/.test(id || '') && !/^RDCLAK/.test(id || '');

  function panelToken(root) {
    const p = findKey(root, 'playlistPanelRenderer') || findKey(root, 'playlistPanelContinuation');
    const c = p?.continuations?.[0];
    return c?.nextRadioContinuationData?.continuation || c?.nextContinuationData?.continuation || null;
  }

  function queueEntry(p, i, alt) {
    const runs = p.longBylineText?.runs || [];
    const seen = new Set();
    const we = p.navigationEndpoint?.watchEndpoint;
    return {
      videoType: we?.watchEndpointMusicSupportedConfigs?.watchEndpointMusicConfig?.musicVideoType || null,
      alt: alt ? [queueEntry(alt, i, null)] : null,
      index: i,
      title: text(p.title),
      subtitle: text(p.shortBylineText) || text(p.longBylineText),
      duration: text(p.lengthText),
      thumbnail: bestThumb(p.thumbnail, 120),
      art: bestThumb(p.thumbnail, 544),
      selected: !!p.selected,
      videoId: p.videoId,
      endpoint: JSON.stringify({ watchEndpoint: we || { videoId: p.videoId } }),
      artists: links(runs).filter((a) => !seen.has(a.id) && seen.add(a.id)),
      album: albumLink(runs),
      like: findKey(p.menu, 'likeStatus') || 'INDIFFERENT',
    };
  }

  // ───────────────────────────── YouTube (www) ─────────────────────────────
  // The same account on regular YouTube: its home feed and "up next" are where DJ sets,
  // live recordings and mixes get recommended. Same cookies, YouTube's WEB client.
  const WEB_ORIGIN = 'https://www.youtube.com';
  const WEB_VERSION = '2.20251114.01.00';

  async function webApi(endpoint, body) {
    const cfg = window.ytcfg;
    const base = cfg.get('INNERTUBE_CONTEXT') || {};
    const client = Object.assign({}, base.client || {}, { clientName: 'WEB', clientVersion: WEB_VERSION, originalUrl: WEB_ORIGIN + '/' });
    delete client.musicAppInfo;
    const context = Object.assign({}, base, { client });
    const headers = {
      'Content-Type': 'application/json',
      'X-Goog-AuthUser': String(cfg.get('SESSION_INDEX') ?? 0),
      'X-Origin': WEB_ORIGIN,
      'X-Youtube-Client-Name': '1',
      'X-Youtube-Client-Version': WEB_VERSION,
      Origin: WEB_ORIGIN,
      Referer: WEB_ORIGIN + '/',
    };
    const visitor = cfg.get('VISITOR_DATA');
    if (visitor) headers['X-Goog-Visitor-Id'] = visitor;
    const pageId = cfg.get('DELEGATED_SESSION_ID');
    if (pageId) headers['X-Goog-PageId'] = pageId;
    const out = await http(`${WEB_ORIGIN}/youtubei/v1/${endpoint}?prettyPrint=false`, 'POST', headers,
      JSON.stringify(Object.assign({ context }, body || {})), cfg.get('LOGGED_IN') ? WEB_ORIGIN : '');
    if (out.status < 200 || out.status >= 300) {
      // YouTube's own reason ("Request contains an invalid argument." …), for the log.
      let reason = '';
      try { reason = JSON.parse(out.body)?.error?.message || ''; } catch (e) { /* not JSON */ }
      throw new Error(`YouTube ${out.status} hatası (${endpoint})${reason ? ': ' + reason : ''}`);
    }
    return JSON.parse(out.body);
  }

  // "1:02:33" → 3753; anything else (live, premieres, "Mix") → 0.
  function clockSeconds(t) {
    const m = String(t || '').trim().match(/^(\d+):(\d{2})(?::(\d{2}))?$/);
    if (!m) return 0;
    return m[3] != null ? (+m[1] * 3600 + +m[2] * 60 + +m[3]) : (+m[1] * 60 + +m[2]);
  }

  // "3 gün önce", "2 weeks ago" → days (0 for minutes and hours); null when not shown.
  function ageDays(t) {
    const m = String(t || '').toLowerCase()
      .match(/(\d+)\s*(saniye|dakika|saat|gün|hafta|ay|yıl|second|minute|hour|day|week|month|year)/);
    if (!m) return null;
    const unit = { saniye: 0, dakika: 0, saat: 0, second: 0, minute: 0, hour: 0, 'gün': 1, day: 1,
      hafta: 7, week: 7, ay: 30, month: 30, 'yıl': 365, year: 365 }[m[2]];
    return unit == null ? null : +m[1] * unit;
  }

  // The channels behind a video: several for a collaboration ("A ve B"), from the parts of
  // the byline that link to a channel or the dialog YouTube opens to list them; failing
  // names there, the text is split and matched to the channel ids in order. When unsure,
  // just the first channel, named by the whole text.
  function channelsOf(root, label, firstId) {
    const out = [];
    const add = (id, name) => {
      if (!id || !/^UC/.test(id)) return;
      const known = out.find((c) => c.id === id);
      if (known) { if (!known.name && name) known.name = name; } else out.push({ id, name: name || '' });
    };
    (function walk(n) {
      if (!n || typeof n !== 'object') return;
      if (Array.isArray(n)) { n.forEach(walk); return; }
      if (n.listItemViewModel) add(findKey(n.listItemViewModel, 'browseEndpoint')?.browseId, n.listItemViewModel.title?.content || '');
      if (typeof n.text === 'string' && n.navigationEndpoint?.browseEndpoint) add(n.navigationEndpoint.browseEndpoint.browseId, n.text);
      if (n.browseEndpoint) add(n.browseEndpoint.browseId, '');
      for (const k in n) walk(n[k]);
    })(root);
    const single = firstId ? [{ id: firstId, name: label }] : [];
    if (out.length < 2) return single;
    const parts = String(label).split(/\s*(?:,|&| ve | and | x )\s*/i).filter(Boolean);
    out.forEach((c, i) => { if (!c.name && parts.length === out.length) c.name = parts[i]; });
    const named = out.filter((c) => c.name);
    return named.length >= 2 ? named : single;
  }

  function ytVideo(id, title, channel, channelId, length, thumb, age, avatar, channels) {
    const seconds = clockSeconds(length);
    if (!id || !title || !seconds) return null;
    return {
      channel, channelId: channelId || null, seconds, mix: false, ageDays: ageDays(age), avatar: avatar || null,
      item: {
        uid: nextId('yt'), kind: 'video', title, subtitle: [channel, length].filter(Boolean).join(' • '),
        thumbnail: thumb || `https://i.ytimg.com/vi/${id}/mqdefault.jpg`, videoId: id, browseId: null, params: null,
        playlistId: null, artists: channels || (channelId ? [{ id: channelId, name: channel }] : []), album: null,
        duration: length, explicit: false,
        play: JSON.stringify({ watchEndpoint: { videoId: id } }), wide: true, color: null,
      },
    };
  }

  // A YouTube Mix (an "RD…" list YouTube builds around a song or artist).
  function ytMix(listId, firstVideo, title, channel, thumb) {
    if (!listId || !firstVideo || !title) return null;
    return {
      channel: channel || '', channelId: null, seconds: 0, mix: true, ageDays: null,
      item: {
        uid: nextId('ytmix'), kind: 'mix', title, subtitle: channel || 'YouTube Mix',
        thumbnail: thumb || `https://i.ytimg.com/vi/${firstVideo}/mqdefault.jpg`, videoId: null, browseId: null, params: null,
        playlistId: listId, artists: [], album: null, duration: null, explicit: false,
        play: JSON.stringify({ watchEndpoint: { videoId: firstVideo, playlistId: listId } }), wide: true, color: null,
      },
    };
  }

  function fromVideoRenderer(v) {
    const owner = v.ownerText || v.shortBylineText || v.longBylineText;
    const length = text(v.lengthText) || text(findKey(v.thumbnailOverlays, 'thumbnailOverlayTimeStatusRenderer')?.text);
    const firstId = owner?.runs?.[0]?.navigationEndpoint?.browseEndpoint?.browseId;
    return ytVideo(v.videoId, text(v.title), text(owner), firstId, length, bestThumb(v.thumbnail, 720),
      text(v.publishedTimeText), bestThumb(v.channelThumbnailSupportedRenderers || v.channelThumbnail, 176),
      channelsOf(owner, text(owner), firstId));
  }

  function fromLockup(l) {
    const meta = l.metadata?.lockupMetadataViewModel;
    const title = meta?.title?.content || '';
    const rows = meta?.metadata?.contentMetadataViewModel?.metadataRows || [];
    const parts = rows.flatMap((r) => (r.metadataParts || []).map((p) => p.text?.content || '')).filter(Boolean);
    const thumb = bestThumb(l.contentImage, 720);
    if (l.contentType === 'LOCKUP_CONTENT_TYPE_VIDEO') {
      const badge = findKey(l.contentImage, 'thumbnailBadgeViewModel');
      // The channel's picture: view models list it under "sources" (largest last).
      const sources = findKey(meta?.image, 'sources');
      const avatar = Array.isArray(sources) && sources.length ? sources[sources.length - 1].url : null;
      const firstId = findKey(meta, 'browseEndpoint')?.browseId;
      return ytVideo(l.contentId, title, parts[0] || '', firstId, badge?.text || '', thumb,
        parts.find((p) => ageDays(p) != null) || '', avatar, channelsOf(meta, parts[0] || '', firstId));
    }
    if (l.contentType === 'LOCKUP_CONTENT_TYPE_PLAYLIST' && /^RD/.test(l.contentId || '')) {
      return ytMix(l.contentId, findKey(l, 'watchEndpoint')?.videoId, title, parts[0] || '', thumb);
    }
    return null;
  }

  // Videos and YouTube Mixes in a response; Shorts, ads, live streams and the rest left out.
  const YT_SKIP = ['reelShelfRenderer', 'reelItemRenderer', 'shortsLockupViewModel', 'adSlotRenderer',
    'promotedSparklesWebRenderer', 'feedFilterChipBarRenderer', 'chipCloudRenderer', 'statementBannerRenderer',
    'brandVideoShelfRenderer', 'movieRenderer', 'radioRenderer'];

  function ytItems(root) {
    const out = [];
    (function walk(n) {
      if (!n || typeof n !== 'object') return;
      if (Array.isArray(n)) { n.forEach(walk); return; }
      for (const k of YT_SKIP) if (n[k]) return;
      const v = n.videoRenderer || n.compactVideoRenderer || n.gridVideoRenderer;
      if (v && v.videoId) { const it = fromVideoRenderer(v); if (it) out.push(it); return; }
      if (n.lockupViewModel && n.lockupViewModel.contentId) { const it = fromLockup(n.lockupViewModel); if (it) out.push(it); return; }
      for (const k in n) { if (!SKIP.has(k)) walk(n[k]); }
    })(root);
    return out;
  }

  // One entry of the bell menu. kind: video (an upload, premiere or live stream), short,
  // comment (a reply or mention under a video), post (community) or other.
  function fromNotification(n) {
    const ep = n.navigationEndpoint || {};
    const url = ep.commandMetadata?.webCommandMetadata?.url || '';
    const videoId = ep.watchEndpoint?.videoId || (url.match(/[?&]v=([\w-]{11})/) || [])[1] || null;
    let kind = 'other';
    if (ep.reelWatchEndpoint || /\/shorts\//.test(url)) kind = 'short';
    else if (videoId && /[?&]lc=/.test(url)) kind = 'comment';
    else if (videoId) kind = 'video';
    else if (ep.browseEndpoint || /\/post\//.test(url)) kind = 'post';
    // "Tomorrowland yükledi: Title" → lead "Tomorrowland yükledi", title "Title".
    const message = text(n.shortMessage);
    const sep = message.indexOf(': ');
    const age = text(n.sentTimeText);
    return {
      kind, videoId: kind === 'video' ? videoId : null,
      title: sep > 0 ? message.slice(sep + 2) : message, lead: sep > 0 ? message.slice(0, sep) : '',
      ageDays: ageDays(age), ageText: age, read: !!n.read,
      thumbnail: bestThumb(n.videoThumbnail, 720), avatar: bestThumb(n.thumbnail, 176),
    };
  }

  const ytKey = (x) => x.item.videoId || x.item.playlistId;
  function uniqueYt(list) {
    const seen = new Set();
    return list.filter((x) => !seen.has(ytKey(x)) && seen.add(ytKey(x)));
  }

  const MUSIC_CHIP = /^(müzik|music|musik|musique|música|musica|muziek|muzyka)$/i;

  function ytChipToken(r, re) {
    const bar = findKey(r, 'feedFilterChipBarRenderer');
    for (const c of bar?.contents || []) {
      const ch = c.chipCloudChipRenderer;
      if (ch && re.test(text(ch.text).trim())) return findKey(ch.navigationEndpoint, 'continuationCommand')?.token || null;
    }
    return null;
  }

  const ytNextToken = (r) => findKey(findKey(r, 'continuationItemRenderer'), 'continuationCommand')?.token || null;

  // Listening sessions: report id (cpn) → the song's watchtime address.
  const listens = new Map();

  function statsPing(base, extra) {
    const cfg = window.ytcfg;
    return http(`${base}&ver=2&c=WEB_REMIX${extra}`, 'GET',
      { 'X-Goog-AuthUser': String(cfg.get('SESSION_INDEX') ?? 0), Origin: location.origin, Referer: location.origin + '/' }, '', location.origin);
  }

  const E = {
    // Regular YouTube's home feed, with its "Müzik" filter when YouTube offers it.
    async ytHome() {
      let r = await webApi('browse', { browseId: 'FEwhat_to_watch' });
      let musicOnly = false;
      const token = ytChipToken(r, MUSIC_CHIP);
      if (token) {
        try { r = await webApi('browse', { continuation: token }); musicOnly = true; } catch (e) { /* unfiltered */ }
      }
      const items = ytItems(r);
      let next = ytNextToken(r);
      for (let i = 0; i < 4 && next && items.length < 120; i++) {
        try {
          const c = await webApi('browse', { continuation: next });
          items.push(...ytItems(c));
          next = ytNextToken(c);
        } catch (e) { break; }
      }
      return { items: uniqueYt(items), musicOnly };
    },

    // Latest uploads of the channels this account follows, newest first (YouTube's
    // subscriptions feed): shows which followed artists put out something lately.
    async ytSubscriptions() {
      const r = await webApi('browse', { browseId: 'FEsubscriptions' });
      const items = ytItems(r);
      let next = ytNextToken(r);
      // More pages until the uploads are over a month old.
      for (let i = 0; i < 3 && next; i++) {
        const last = items[items.length - 1];
        if (last && last.ageDays != null && last.ageDays > 31) break;
        try {
          const c = await webApi('browse', { continuation: next });
          items.push(...ytItems(c));
          next = ytNextToken(c);
        } catch (e) { break; }
      }
      return { items: uniqueYt(items), musicOnly: false };
    },

    // The bell's notifications, newest first, back to `days` days (the home page marks the
    // uploads they announce as unread). Only read: nothing is marked as seen or read.
    // `summary`: what came back (counts and field names, no content), for the diagnostic log.
    async ytNotifications({ days }) {
      const endpoint = 'notification/get_notification_menu';
      const request = { notificationsMenuRequestType: 'NOTIFICATIONS_MENU_REQUEST_TYPE_INBOX' };
      const items = [];
      const kinds = {};
      let fields = '';
      let pages = 0;
      const collect = (root) => {
        (function walk(n) {
          if (!n || typeof n !== 'object') return;
          if (Array.isArray(n)) { n.forEach(walk); return; }
          if (n.notificationRenderer) {
            const r = n.notificationRenderer;
            if (!fields) fields = Object.keys(r).sort().join(',');
            const it = fromNotification(r);
            kinds[it.kind] = (kinds[it.kind] || 0) + 1;
            items.push(it);
            return;
          }
          for (const k in n) { if (!SKIP.has(k)) walk(n[k]); }
        })(root);
        pages++;
      };
      const tokenOf = (r) => findKey(r, 'getNotificationMenuEndpoint')?.ctoken
        || findKey(findKey(r, 'continuationItemRenderer'), 'continuationCommand')?.token || null;
      let r = await webApi(endpoint, request);
      collect(r);
      let next = tokenOf(r);
      for (let i = 0; i < 5 && next; i++) {
        const last = items[items.length - 1];
        if (last && last.ageDays != null && last.ageDays > days) break;
        try {
          r = await webApi(endpoint, Object.assign({ ctoken: next }, request));
          collect(r);
          const after = tokenOf(r);
          next = after === next ? null : after;
        } catch (e) { break; }
      }
      const summary = `${items.length} bildirim, ${pages} sayfa, türler ${JSON.stringify(kinds)}, alanlar [${fields}]`;
      return { items: items.filter((x) => x.ageDays == null || x.ageDays <= days), summary };
    },

    // A video's channel and YouTube category (one request): tells music channels (artists,
    // labels, festivals) from the rest.
    async ytVideoInfo({ videoId }) {
      const r = await webApi('player', { videoId });
      const d = r.videoDetails || {};
      const m = r.microformat?.playerMicroformatRenderer || {};
      return {
        channelId: d.channelId || m.externalChannelId || null, channel: d.author || m.ownerChannelName || '',
        category: m.category || null, seconds: +(d.lengthSeconds || 0) || 0,
      };
    },

    // Regular YouTube search; `long`: only videos over 20 minutes (sets, live recordings).
    async ytSearch({ query, long }) {
      const body = { query };
      if (long) body.params = 'EgIYAg%3D%3D';
      const r = await webApi('search', body);
      return { items: uniqueYt(ytItems(r)), musicOnly: false };
    },

    // What regular YouTube suggests next to a video (where similar sets cluster).
    async ytRelated({ videoId }) {
      const r = await webApi('next', { videoId });
      return { items: uniqueYt(ytItems(findKey(r, 'secondaryResults') || {})), musicOnly: false };
    },

    async home({ params, browseId }) {
      const id = browseId || 'FEmusic_home';
      const r = await api('browse', params ? { browseId: id, params } : { browseId: id });
      const page = { header: null, chips: chipsOf(r), sections: extractSections(r), continuation: sectionListToken(r) };
      for (let i = 0; i < 3 && page.continuation; i++) {
        try {
          const c = await api('browse', {}, ctokenQuery(page.continuation));
          page.sections.push(...extractSections(c));
          page.continuation = sectionListToken(c);
        } catch (e) { break; }
      }
      return page;
    },


    async browse({ browseId, params }) {
      const r = await api('browse', params ? { browseId, params } : { browseId });
      return { header: parseHeader(r), chips: chipsOf(r), sections: extractSections(r), continuation: sectionListToken(r) };
    },

    async more({ token }) {
      let r = await api('browse', { continuation: token });
      let items = collectItems(r);
      if (!items.length) {
        r = await api('browse', {}, ctokenQuery(token));
        items = collectItems(r);
      }
      return { items, continuation: anyToken(r) };
    },

    async search({ query, params }) {
      const r = await api('search', params ? { query, params } : { query });
      return { header: null, chips: chipsOf(r), sections: extractSections(r), continuation: null };
    },

    // As-you-type suggestions for the search field: YouTube Music's (your recent searches,
    // completions, a few artists / songs / albums with covers) and regular YouTube's
    // completions. Either source may fail; whatever came back is used.
    async searchSuggestions({ query }) {
      const q = String(query || '').trim();
      if (!q) return { suggestions: [], items: [] };
      const hl = window.ytcfg.get('INNERTUBE_CONTEXT')?.client?.hl || 'en';
      const [music, tube] = await Promise.allSettled([
        api('music/get_search_suggestions', { input: q }),
        http('https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=' + encodeURIComponent(hl)
          + '&q=' + encodeURIComponent(q), 'GET', {}, '', ''),
      ]);
      const suggestions = [];
      const seen = new Set();
      const add = (t, source) => {
        const s = String(t || '').trim();
        // "tiesto" and "Tiësto" are the same suggestion.
        const key = s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase();
        if (!s || seen.has(key)) return;
        seen.add(key);
        suggestions.push({ text: s, source });
      };
      const items = [];
      if (music.status === 'fulfilled') {
        const history = [];
        const found = [];
        for (const sec of music.value.contents || []) {
          for (const e of sec.searchSuggestionsSectionRenderer?.contents || []) {
            const s = e.historySuggestionRenderer || e.searchSuggestionRenderer;
            if (s) {
              (e.historySuggestionRenderer ? history : found).push(s.navigationEndpoint?.searchEndpoint?.query || text(s.suggestion));
            } else if (e.musicResponsiveListItemRenderer) {
              const it = parseListItem(e.musicResponsiveListItemRenderer);
              if (it && it.title) items.push(it);
            }
          }
        }
        history.slice(0, 3).forEach((t) => add(t, 'history'));
        found.forEach((t) => add(t, 'music'));
      }
      if (tube.status === 'fulfilled' && tube.value.status === 200) {
        try {
          const list = JSON.parse(tube.value.body);
          (Array.isArray(list?.[1]) ? list[1] : []).forEach((t) => add(t, 'youtube'));
        } catch (e) { /* not JSON */ }
      }
      return { suggestions: suggestions.slice(0, 8), items: items.slice(0, 5) };
    },

    async searchMore({ token }) {
      let r = await api('search', {}, ctokenQuery(token));
      let items = collectItems(r);
      if (!items.length) {
        r = await api('search', { continuation: token });
        items = collectItems(r);
      }
      const next = anyToken(r);
      return { items, continuation: next === token ? null : next };
    },

    // Artist + album of a track from the watch queue (reliable, unlike the DOM byline).
    async trackMeta({ videoId }) {
      const r = await api('next', { videoId, isAudioOnly: true });
      let found = null;
      (function walk(n) {
        if (found || !n || typeof n !== 'object') return;
        if (Array.isArray(n)) { n.forEach(walk); return; }
        const p = n.playlistPanelVideoRenderer;
        if (p && p.videoId === videoId) { found = p; return; }
        for (const k in n) { if (!SKIP.has(k)) walk(n[k]); }
      })(r.contents);
      const runs = (found?.longBylineText?.runs || []).concat(found?.shortBylineText?.runs || []);
      const seen = new Set();
      const artists = links(runs).filter((a) => !seen.has(a.id) && seen.add(a.id));
      return { artists, album: albumLink(runs) };
    },

    async lyrics({ videoId }) {
      const r = await api('next', { videoId, isAudioOnly: true });
      let id = null;
      (function walk(n) {
        if (id || !n || typeof n !== 'object') return;
        if (Array.isArray(n)) { n.forEach(walk); return; }
        const be = n.browseEndpoint;
        if (be?.browseId && be.browseId.startsWith('MPLYt')) { id = be.browseId; return; }
        for (const k in n) walk(n[k]);
      })(r.contents);
      if (!id) return { text: null, source: null };
      const l = await api('browse', { browseId: id });
      const d = findKey(l, 'musicDescriptionShelfRenderer');
      return { text: d ? (text(d.description) || null) : null, source: d ? (text(d.footer) || null) : null };
    },

    async account() {
      const r = await api('account/account_menu', {});
      const h = findKey(r, 'activeAccountHeaderRenderer');
      if (!h) return null;
      return {
        name: text(h.accountName),
        handle: text(h.channelHandle) || text(h.email) || '',
        photo: bestThumb(h.accountPhoto, 96),
      };
    },

    // A page as YouTube Music shows it in another country (gl), e.g. the US explore page.
    async browseIn({ browseId, params, gl }) {
      const base = window.ytcfg.get('INNERTUBE_CONTEXT') || {};
      const context = Object.assign({}, base, { client: Object.assign({}, base.client || {}, { gl }) });
      const body = params ? { context, browseId, params } : { context, browseId };
      const r = await api('browse', body);
      return { header: parseHeader(r), chips: chipsOf(r), sections: extractSections(r), continuation: sectionListToken(r) };
    },

    // The artists this account is subscribed to.
    async subscriptions() {
      const r = await api('browse', { browseId: 'FEmusic_library_corpus_artists' });
      const items = [];
      for (const s of extractSections(r)) items.push(...s.items);
      return items.filter((i) => i.browseId);
    },

    // YouTube Music's charts for the whole world ("ZZ") instead of the account's country.
    async globalCharts() {
      const r = await api('browse', { browseId: 'FEmusic_charts', formData: { selectedValues: ['ZZ'] } });
      return { header: null, chips: [], sections: extractSections(r), continuation: null };
    },

    async library() {
      const load = async (id) => {
        try {
          const r = await api('browse', { browseId: id });
          const items = [];
          for (const s of extractSections(r)) items.push(...s.items);
          return items.filter((i) => i.browseId);
        } catch (e) { return []; }
      };
      const [playlists, albums, artists] = await Promise.all([
        load('FEmusic_liked_playlists'), load('FEmusic_liked_albums'), load('FEmusic_library_corpus_track_artists'),
      ]);
      return { playlists, albums, artists };
    },




    bootstrap({ html, hasAuth, lang, region, forceLang, ui }) {
      uiTurkish = ui === 'tr';
      const cfg = {};
      let parsed = false, i = 0;
      while ((i = html.indexOf('ytcfg.set(', i)) >= 0) {
        i += 10;
        if (html[i] !== '{') continue;
        const end = matchBrace(html, i);
        if (end < 0) break;
        try { Object.assign(cfg, JSON.parse(html.slice(i, end + 1))); parsed = true; } catch (e) {}
        i = end;
      }
      if (!cfg.INNERTUBE_CONTEXT || !cfg.INNERTUBE_CONTEXT.client) {
        parsed = false;
        const d = new Date();
        const p2 = (n) => String(n).padStart(2, '0');
        const ver = `1.${d.getUTCFullYear()}${p2(d.getUTCMonth() + 1)}${p2(d.getUTCDate())}.01.00`;
        cfg.INNERTUBE_CONTEXT = { client: { clientName: 'WEB_REMIX', clientVersion: ver, hl: lang || 'en', gl: region || 'US' }, user: {} };
        cfg.INNERTUBE_CLIENT_VERSION = ver;
        cfg.INNERTUBE_CONTEXT_CLIENT_NAME = 67;
        cfg.LOGGED_IN = !!hasAuth;
      }
      if (cfg.LOGGED_IN == null) cfg.LOGGED_IN = !!hasAuth;
      // A language picked in the app's Settings: YouTube's texts in that language too.
      if (forceLang && cfg.INNERTUBE_CONTEXT.client) cfg.INNERTUBE_CONTEXT.client.hl = forceLang;
      window.ytcfg = { get: (k) => cfg[k] };
      let playerJs = cfg.PLAYER_JS_URL || null;
      if (!playerJs) {
        const w = cfg.WEB_PLAYER_CONTEXT_CONFIGS || {};
        for (const k in w) { if (w[k] && w[k].jsUrl) { playerJs = w[k].jsUrl; break; } }
      }
      if (!playerJs) {
        const m = html.match(/\/s\/player\/[0-9a-fA-F]{8,}\/[^"'\s]*base\.js/);
        if (m) playerJs = m[0];
      }
      return {
        loggedIn: !!cfg.LOGGED_IN && !!hasAuth,
        visitorData: cfg.VISITOR_DATA || cfg.INNERTUBE_CONTEXT.client.visitorData || null,
        parsed,
        playerJs,
        sts: Number(cfg.STS) || null,
        premium: null,
      };
    },

    // The streams YouTube Music's own web player gets for this video (signed-in session,
    // so Premium accounts receive their 256 kbps stream). URLs may still be ciphered.
    async playerData({ videoId, sts }) {
      const ctx = { contentPlaybackContext: { html5Preference: 'HTML5_PREF_WANTS' } };
      if (sts) ctx.contentPlaybackContext.signatureTimestamp = sts;
      const r = await api('player', { videoId, playbackContext: ctx, contentCheckOk: true, racyCheckOk: true });
      const ps = r.playabilityStatus || {};
      const sd = r.streamingData || {};
      return {
        status: ps.status || '',
        reason: ps.reason || text(ps.errorScreen?.playerErrorMessageRenderer?.reason) || '',
        videoId: r.videoDetails?.videoId || null,
        length: Number(r.videoDetails?.lengthSeconds) || 0,
        formats: (sd.adaptiveFormats || []).filter((f) => String(f.mimeType || '').startsWith('audio/')).map((f) => ({
          itag: f.itag || 0,
          mimeType: f.mimeType || '',
          bitrate: f.bitrate || 0,
          averageBitrate: f.averageBitrate || 0,
          url: f.url || null,
          cipher: f.signatureCipher || f.cipher || null,
          approxDurationMs: f.approxDurationMs || null,
          // Where the file's header and its index (time → byte table) sit.
          initRange: f.initRange ? [Number(f.initRange.start), Number(f.initRange.end)] : null,
          indexRange: f.indexRange ? [Number(f.indexRange.start), Number(f.indexRange.end)] : null,
          drc: !!f.isDrc,
          isDefault: f.audioTrack ? f.audioTrack.audioIsDefault !== false : true,
          // How much louder than YouTube's reference level this file is (dB).
          loudnessDb: typeof f.loudnessDb === 'number' ? f.loudnessDb : null,
        })),
        loudnessDb: typeof r.playerConfig?.audioConfig?.loudnessDb === 'number' ? r.playerConfig.audioConfig.loudnessDb : null,
        hls: sd.hlsManifestUrl || null,
        sabr: !!sd.serverAbrStreamingUrl,
      };
    },

    // The queue YouTube Music would build for this endpoint (playlist, album, radio…).
    async watchQueue({ endpoint, context }) {
      const ep = typeof endpoint === 'string' ? JSON.parse(endpoint) : endpoint;
      const w = Object.assign({}, ep.watchEndpoint || ep.watchPlaylistEndpoint || {});
      if (ep.watchEndpoint && context && !w.playlistId) w.playlistId = context;
      const body = { isAudioOnly: true, enablePersistentPlaylistPanel: true, tunerSettingValue: 'AUTOMIX_SETTING_NORMAL' };
      for (const k of ['videoId', 'playlistId', 'params', 'index', 'playlistSetVideoId', 'watchEndpointMusicSupportedConfigs']) {
        if (w[k] != null) body[k] = w[k];
      }
      let r = await api('next', body);
      let rows = panelRows(r.contents);
      if (w.videoId && rows.length <= 1) {
        // A single song: continue with YouTube Music's automix (radio), like the web player.
        const wpe = findKey(r, 'automixPlaylistVideoRenderer')?.navigationEndpoint?.watchPlaylistEndpoint;
        const pl = wpe?.playlistId || ('RDAMVM' + w.videoId);
        try {
          const r2 = await api('next', Object.assign({}, body, { playlistId: pl, params: wpe?.params || body.params }));
          const more = panelRows(r2.contents);
          if (more.length > rows.length) { rows = more; r = r2; }
        } catch (e) { /* keep the single song */ }
      }
      let current = rows.findIndex((x) => x.p.selected);
      if (current < 0 && w.videoId) current = rows.findIndex((x) => x.p.videoId === w.videoId);
      if (current < 0) current = 0;
      const listId = findKey(r, 'playlistPanelRenderer')?.playlistId || body.playlistId || '';
      return {
        items: rowsToEntries(rows), current, continuation: panelToken(r),
        radio: isRadio(listId),
      };
    },

    async queueMore({ token }) {
      const r = await api('next', { isAudioOnly: true, enablePersistentPlaylistPanel: true }, ctokenQuery(token));
      const next = panelToken(r.continuationContents);
      return { items: rowsToEntries(panelRows(r.continuationContents)), current: 0, continuation: next === token ? null : next };
    },

    // ── playlists ──
    async addToPlaylistOptions({ videoId }) {
      const r = await api('playlist/get_add_to_playlist', { videoIds: [videoId], excludeWatchLater: true });
      const out = [], seen = new Set();
      (function walk(n) {
        if (!n || typeof n !== 'object') return;
        if (Array.isArray(n)) { n.forEach(walk); return; }
        const o = n.playlistAddToOptionRenderer;
        if (o && o.playlistId) {
          if (!seen.has(o.playlistId)) {
            seen.add(o.playlistId);
            const c = String(o.containsSelectedVideos || '').toUpperCase();
            out.push({
              playlistId: o.playlistId,
              title: text(o.title),
              thumbnail: bestThumb(o.thumbnail || o.thumbnailRenderer || o.playlistThumbnail, 120),
              // "ALL" (or "SOME" for several songs) = already in this playlist.
              contains: c === 'ALL' || c === 'SOME' || o.isSelected === true,
              privacy: o.privacy || null,
              raw: c || null,
            });
          }
          return;
        }
        for (const k in n) walk(n[k]);
      })(r);
      return out;
    },

    // Every song of one playlist (ids, titles, first artist): the app builds its own
    // "which of my playlists contain this song" index from these, because YouTube's
    // add-to-playlist data lists only a few recent playlists and no membership.
    async playlistIndex({ playlistId }) {
      const r = await api('browse', { browseId: 'VL' + plId(playlistId) });
      const header = parseHeader(r);
      const main = extractSections(r).find((s) => s.items.some((i) => i.videoId));
      const items = main ? main.items.slice() : [];
      let token = main ? main.continuation : null;
      for (let i = 0; i < 40 && token; i++) {
        let m;
        try { m = await E.more({ token }); } catch (e) { break; }
        if (!m.items.length) break;
        items.push(...m.items);
        token = m.continuation === token ? null : m.continuation;
      }
      return {
        editable: editInfo(r).editable,
        title: header?.title || '',
        thumbnail: header?.thumbnail || null,
        tracks: items.filter((i) => i.videoId).map((i) => ({
          v: i.videoId, t: i.title, a: i.artists[0]?.name || (i.subtitle || '').split(' • ')[0] || '',
        })),
      };
    },

    async createPlaylist({ title, description, privacy, videoIds }) {
      const body = { title, description: description || '', privacyStatus: privacy || 'PRIVATE' };
      if (videoIds && videoIds.length) body.videoIds = videoIds;
      const r = await api('playlist/create', body);
      if (!r.playlistId) throw new Error(uiTurkish ? 'Çalma listesi oluşturulamadı' : 'The playlist could not be created');
      return r.playlistId;
    },

    async addToPlaylist({ playlistId, videoId }) {
      await editPlaylist(playlistId, [{ action: 'ACTION_ADD_VIDEO', addedVideoId: videoId, dedupeOption: 'DEDUPE_OPTION_SKIP' }]);
      return true;
    },

    async removeFromPlaylist({ playlistId, videoId, setVideoId }) {
      await editPlaylist(playlistId, [{ action: 'ACTION_REMOVE_VIDEO', setVideoId, removedVideoId: videoId }]);
      return true;
    },

    // Moves an entry before another one (or to the end when `beforeSetVideoId` is empty).
    async movePlaylistItem({ playlistId, setVideoId, beforeSetVideoId }) {
      const a = { action: 'ACTION_MOVE_VIDEO_BEFORE', setVideoId };
      if (beforeSetVideoId) a.movedSetVideoIdSuccessor = beforeSetVideoId;
      await editPlaylist(playlistId, [a]);
      return true;
    },

    async updatePlaylist({ playlistId, title, description, privacy }) {
      const actions = [];
      if (title != null) actions.push({ action: 'ACTION_SET_PLAYLIST_NAME', playlistName: title });
      if (description != null) actions.push({ action: 'ACTION_SET_PLAYLIST_DESCRIPTION', playlistDescription: description });
      if (privacy) actions.push({ action: 'ACTION_SET_PLAYLIST_PRIVACY', playlistPrivacy: privacy });
      if (actions.length) await editPlaylist(playlistId, actions);
      return true;
    },

    async deletePlaylist({ playlistId }) {
      await api('playlist/delete', { playlistId: plId(playlistId) });
      return true;
    },

    // Subscribe to / unsubscribe from an artist's channel (YouTube Music's Abone ol button).
    async subscribe({ channelId, on, params }) {
      const body = { channelIds: [channelId] };
      if (params) body.params = params;
      await api(on ? 'subscription/subscribe' : 'subscription/unsubscribe', body);
      return true;
    },

    async rate({ videoId, status }) {
      const ep = status === 'LIKE' ? 'like/like' : (status === 'DISLIKE' ? 'like/dislike' : 'like/removelike');
      await api(ep, { target: { videoId } });
      return true;
    },

    // Listening reports, as the official player sends them, so the account's history and
    // recommendations know what was really listened to: a "playback" report once a song has
    // been heard for a while, then "watchtime" reports with the stretches actually heard
    // (a song skipped after 20 seconds reads as skipped, not as listened).
    async trackStart({ videoId }) {
      const cfg = window.ytcfg;
      if (!cfg.get('LOGGED_IN')) return { session: null };
      const r = await api('player', { videoId, playbackContext: { contentPlaybackContext: { html5Preference: 'HTML5_PREF_WANTS' } } });
      const pt = r.playbackTracking || {};
      const base = pt.videostatsPlaybackUrl?.baseUrl;
      if (!base) return { session: null };
      const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
      let cpn = '';
      for (let i = 0; i < 16; i++) cpn += A[Math.floor(Math.random() * 64)];
      await statsPing(base, `&cpn=${cpn}`);
      const watch = pt.videostatsWatchtimeUrl?.baseUrl;
      if (watch) {
        listens.set(cpn, watch);
        while (listens.size > 6) listens.delete(listens.keys().next().value);
      }
      return { session: cpn };
    },

    async trackWatch({ session, st, et }) {
      const watch = listens.get(session);
      if (!watch) return false;
      const f = (x) => Math.max(0, Number(x) || 0).toFixed(3);
      await statsPing(watch, `&cpn=${session}&cmt=${f(et)}&st=${f(st)}&et=${f(et)}`);
      return true;
    },

  };

  window.__ytmusic = {
    async call(name, argsJSON) {
      const fn = E[name];
      if (!fn) throw new Error('Bilinmeyen komut: ' + name);
      const res = await fn(argsJSON ? JSON.parse(argsJSON) : {});
      return JSON.stringify(res === undefined ? null : res);
    },
  };
})();
