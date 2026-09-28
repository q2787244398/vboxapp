/**
 * TVS CatVod Spider Server
 * 
 * HTTP API server that provides video search, detail, and play URL parsing
 * for the Flutter app. Uses CatVod spider bundles to scrape video sources
 * from various Chinese streaming sites.
 */

const http = require('http');
const https = require('https');
const path = require('path');
const fs = require('fs');
const { AsyncLocalStorage } = require('async_hooks');

// Configuration
const PORT = parseInt(process.env.PORT) || 9775;
const DART_PORT = parseInt(process.env.DART_PORT) || 9776;
const BUNDLE_PATH = process.env.BUNDLE_PATH || './spider.js';
const NODE_PATH = process.env.NODE_PATH || __dirname;

// Global state
let sites = { list: [] };
let pans = { list: [] };
let config = {};
let spiderBundle = null;
let isStarting = false;
let isStarted = false;

// Async storage for request context
const requestContext = new AsyncLocalStorage();

// Proxy URL for JS requests
const jsProxy = `http://127.0.0.1:${PORT}/proxy?do=js&url=`;

/**
 * Initialize the server
 */
async function init() {
  console.log('[TVS Spider] Initializing...');
  console.log(`[TVS Spider] Port: ${PORT}, Dart Port: ${DART_PORT}`);
  console.log(`[TVS Spider] Bundle: ${BUNDLE_PATH}`);
  console.log(`[TVS Spider] Node Path: ${NODE_PATH}`);

  // Load configuration
  await loadConfig();

  // Load spider bundle
  await loadSpiderBundle();

  // Start HTTP server
  startServer();
}

/**
 * Load app configuration from db.json
 */
async function loadConfig() {
  const dbPath = path.join(NODE_PATH, 'db.json');
  try {
    if (fs.existsSync(dbPath)) {
      const data = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
      sites = data.sites || { list: [] };
      pans = data.pans || { list: [] };
      config = data.config || {};
      console.log(`[TVS Spider] Loaded ${sites.list.length} sites`);
    }
  } catch (e) {
    console.error('[TVS Spider] Failed to load config:', e.message);
  }
}

/**
 * Load spider bundle
 */
async function loadSpiderBundle() {
  try {
    const resolvedPath = path.resolve(BUNDLE_PATH);
    delete require.cache[resolvedPath];
    spiderBundle = require(resolvedPath);
    
    if (typeof spiderBundle.start === 'function') {
      const startOpts = {
        color: [],
        sites: sites,
        pans: pans,
        ali: { token: '' },
        baidu: { cookie: '' },
        bilibili_all: { cookie: '', classes_all: '', filters_all: '' },
        cms: {},
        danmu: {},
        dudb: {},
        guazi: { url: '', token: '' },
        live: [],
        mycloud: { text: '' },
        pan123: { username: '', password: '' },
        pikpak: {
          username: '',
          email: '',
          password: '',
          refresh_token: '',
          device_id: '',
          user_id: '',
        },
        quark: { cookie: '' },
        server: {},
        sharemount: { text: '', batchTiers: {} },
        t4: {},
        tgsou: {},
        tianyi: { username: '', password: '' },
        uc: { cookie: '', token: '', ut: '' },
        xunlei: { username: '', password: '' },
        y115: { cookie: '', offline: {} },
      };
      
      await spiderBundle.start(startOpts);
      console.log('[TVS Spider] Spider bundle started');
    }
    
    isStarted = true;
  } catch (e) {
    console.error('[TVS Spider] Failed to load spider bundle:', e.message);
  }
}

/**
 * Start HTTP API server
 */
function startServer() {
  const server = http.createServer(async (req, res) => {
    // Enable CORS
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
      res.writeHead(200);
      res.end();
      return;
    }

    const url = new URL(req.url, `http://${req.headers.host}`);
    const pathname = url.pathname;
    const searchParams = url.searchParams;

    try {
      // Route: /api/sites
      if (pathname === '/api/sites') {
        return handleSites(req, res);
      }
      
      // Route: /api/search
      if (pathname === '/api/search') {
        return handleSearch(req, res, searchParams);
      }
      
      // Route: /api/detail/:siteKey/:vodId
      if (pathname.startsWith('/detail/')) {
        return handleDetail(req, res, pathname);
      }
      
      // Route: /api/play
      if (pathname === '/api/play') {
        return handlePlay(req, res, searchParams);
      }
      
      // Route: /api/home
      if (pathname === '/api/home') {
        return handleHome(req, res, searchParams);
      }
      
      // Route: /api/hot
      if (pathname === '/api/hot') {
        return handleHot(req, res);
      }
      
      // Route: /api/live
      if (pathname === '/api/live') {
        return handleLive(req, res);
      }
      
      // Route: /api/config
      if (pathname === '/api/config') {
        return handleConfig(req, res);
      }
      
      // Route: /api/proxy (JS proxy)
      if (pathname === '/proxy') {
        return handleProxy(req, res, searchParams);
      }
      
      // Route: /api/health
      if (pathname === '/api/health') {
        return sendJson(res, { status: 'ok', running: isStarted });
      }
      
      // 404
      sendJson(res, { error: 'Not found' }, 404);
      
    } catch (e) {
      console.error('[TVS Spider] Request error:', e.message);
      sendJson(res, { error: e.message }, 500);
    }
  });

  server.listen(PORT, '127.0.0.1', () => {
    console.log(`[TVS Spider] Server listening on port ${PORT}`);
  });

  server.on('error', (e) => {
    console.error('[TVS Spider] Server error:', e.message);
  });
}

/**
 * Handle /api/sites
 */
function handleSites(req, res) {
  sendJson(res, { list: sites.list });
}

/**
 * Handle /api/search
 */
async function handleSearch(req, res, params) {
  const keyword = params.get('text') || '';
  const siteKey = params.get('siteKey') || '';
  
  if (!keyword) {
    return sendJson(res, { error: 'Missing text parameter' }, 400);
  }

  try {
    let searchSites = sites.list;
    if (siteKey) {
      searchSites = sites.list.filter(s => s.key === siteKey);
    }

    const results = [];
    for (const site of searchSites) {
      try {
        if (spiderBundle && typeof spiderBundle.search === 'function') {
          const result = await spiderBundle.search(site, keyword);
          if (result && result.list) {
            results.push(...result.list);
          }
        }
      } catch (e) {
        console.error(`[TVS Spider] Search error for ${site.key}:`, e.message);
      }
    }

    sendJson(res, { list: results });
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Handle /detail/:siteKey/:vodId
 */
async function handleDetail(req, res, pathname) {
  const parts = pathname.split('/');
  const siteKey = parts[2];
  const vodId = parts[3];

  if (!siteKey || !vodId) {
    return sendJson(res, { error: 'Missing siteKey or vodId' }, 400);
  }

  try {
    const site = sites.list.find(s => s.key === siteKey);
    if (!site) {
      return sendJson(res, { error: 'Site not found' }, 404);
    }

    let detail = {};
    if (spiderBundle && typeof spiderBundle.detail === 'function') {
      detail = await spiderBundle.detail(site, vodId);
    }

    sendJson(res, detail);
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Handle /api/play
 */
async function handlePlay(req, res, params) {
  const siteKey = params.get('siteKey') || '';
  const vodId = params.get('vodId') || '';
  const playFrom = params.get('playFrom') || '';

  if (!siteKey || !vodId) {
    return sendJson(res, { error: 'Missing siteKey or vodId' }, 400);
  }

  try {
    const site = sites.list.find(s => s.key === siteKey);
    if (!site) {
      return sendJson(res, { error: 'Site not found' }, 404);
    }

    let playUrl = '';
    if (spiderBundle && typeof spiderBundle.playUrl === 'function') {
      playUrl = await spiderBundle.playUrl(site, vodId, playFrom);
    }

    sendJson(res, { url: playUrl });
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Handle /api/home
 */
async function handleHome(req, res, params) {
  const siteKey = params.get('siteKey') || '';
  
  try {
    let homeData = { list: [] };
    
    if (spiderBundle && typeof spiderBundle.home === 'function') {
      const site = siteKey 
        ? sites.list.find(s => s.key === siteKey)
        : sites.list[0];
      
      if (site) {
        homeData = await spiderBundle.home(site);
      }
    }

    sendJson(res, homeData);
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Handle /api/hot
 */
async function handleHot(req, res) {
  try {
    let hotData = { list: [] };
    
    if (spiderBundle && typeof spiderBundle.hot === 'function') {
      hotData = await spiderBundle.hot();
    }

    sendJson(res, hotData);
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Handle /api/live
 */
async function handleLive(req, res) {
  try {
    let liveData = { list: [] };
    
    if (spiderBundle && typeof spiderBundle.live === 'function') {
      liveData = await spiderBundle.live();
    }

    sendJson(res, liveData);
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Handle /api/config
 */
function handleConfig(req, res) {
  sendJson(res, config);
}

/**
 * Handle /proxy (JS proxy for spider requests)
 */
async function handleProxy(req, res, params) {
  const targetUrl = params.get('url') || '';
  
  if (!targetUrl) {
    return sendJson(res, { error: 'Missing url parameter' }, 400);
  }

  try {
    const response = await fetch(targetUrl, {
      headers: {
        'User-Agent': 'Dart/2.18 (dart:io)',
      },
    });

    const text = await response.text();
    res.writeHead(response.status, {
      'Content-Type': response.headers.get('content-type') || 'text/plain',
    });
    res.end(text);
  } catch (e) {
    sendJson(res, { error: e.message }, 500);
  }
}

/**
 * Send JSON response
 */
function sendJson(res, data, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

/**
 * Initialize
 */
init().catch(e => {
  console.error('[TVS Spider] Fatal error:', e.message);
  process.exit(1);
});

// Handle parent process exit
const parentPid = parseInt(process.env.TVS_PARENT_PID || '');
if (parentPid > 0) {
  const watchdog = setInterval(() => {
    try {
      process.kill(parentPid, 0);
    } catch (e) {
      if (e.code === 'EPERM') return;
      console.log('[TVS Spider] Parent process exited, stopping');
      process.exit(0);
    }
  }, 500);
  watchdog.unref();
}