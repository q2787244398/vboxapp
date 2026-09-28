/**
 * TVS Spider Bundle
 * 
 * Main spider bundle that implements the CatVod API.
 * This is loaded by the Node.js engine to parse video sources.
 */

'use strict';

const https = require('https');
const http = require('http');
const { URL } = require('url');

// Spider state
let config = {};
let sites = [];
let pans = [];

/**
 * Initialize spider with configuration
 * @param {Object} startConfig - Configuration from Flutter
 */
async function start(startConfig) {
  config = startConfig;
  sites = startConfig.sites?.list || [];
  pans = startConfig.pans?.list || [];
  
  console.log('[Spider] Started with', sites.length, 'sites');
  console.log('[Spider] Pans:', pans.length);
  
  // Initialize site-specific data
  for (const site of sites) {
    if (site.home) {
      try {
        const homeData = await fetchUrl(site.home);
        if (homeData) {
          site.homeData = homeData;
        }
      } catch (e) {
        console.error(`[Spider] Failed to load home for ${site.key}:`, e.message);
      }
    }
  }
}

/**
 * Search for videos across sites
 * @param {Object} site - Site configuration
 * @param {string} keyword - Search keyword
 * @returns {Object} Search results
 */
async function search(site, keyword) {
  if (!site || !site.api) {
    return { list: [] };
  }

  try {
    const searchUrl = buildUrl(site.api, {
      wd: keyword,
      ...site.ext ? JSON.parse(site.ext) : {},
    });
    
    const data = await fetchUrl(searchUrl, {
      headers: {
        'User-Agent': 'Dart/2.18 (dart:io)',
        ...site.headers,
      },
    });
    
    if (!data || !data.list) {
      return { list: [] };
    }
    
    return {
      list: data.list.map(vod => ({
        vod_id: vod.vod_id || vod.id,
        vod_name: vod.vod_name || vod.name,
        vod_pic: vod.vod_pic || vod.pic,
        vod_remarks: vod.vod_remarks || vod.remarks,
        vod_year: vod.vod_year || vod.year,
        vod_area: vod.vod_area || vod.area,
        vod_director: vod.vod_director || vod.director,
        vod_actor: vod.vod_actor || vod.actor,
        vod_tag: vod.vod_tag || vod.tag,
      })),
    };
  } catch (e) {
    console.error(`[Spider] Search error for ${site.key}:`, e.message);
    return { list: [] };
  }
}

/**
 * Get video details
 * @param {Object} site - Site configuration
 * @param {string} vodId - Video ID
 * @returns {Object} Video details
 */
async function detail(site, vodId) {
  if (!site || !site.api) {
    return { list: [] };
  }

  try {
    const detailUrl = buildUrl(site.api, {
      detail: vodId,
      ...site.ext ? JSON.parse(site.ext) : {},
    });
    
    const data = await fetchUrl(detailUrl, {
      headers: {
        'User-Agent': 'Dart/2.18 (dart:io)',
        ...site.headers,
      },
    });
    
    return data || { list: [] };
  } catch (e) {
    console.error(`[Spider] Detail error for ${site.key}:`, e.message);
    return { list: [] };
  }
}

/**
 * Get play URL
 * @param {Object} site - Site configuration
 * @param {string} vodId - Video ID
 * @param {string} playFrom - Play source filter
 * @returns {string} Play URL
 */
async function playUrl(site, vodId, playFrom) {
  if (!site || !site.api) {
    return '';
  }

  try {
    const playUrl = buildUrl(site.api, {
      play: vodId,
      play_from: playFrom,
      ...site.ext ? JSON.parse(site.ext) : {},
    });
    
    const data = await fetchUrl(playUrl, {
      headers: {
        'User-Agent': 'Dart/2.18 (dart:io)',
        ...site.headers,
      },
    });
    
    if (!data) return '';
    
    // Parse play sources
    if (data.list && data.list.length > 0) {
      const source = data.list[0];
      if (source.list && source.list.length > 0) {
        return source.list[0].url;
      }
    }
    
    return data.url || '';
  } catch (e) {
    console.error(`[Spider] Play URL error for ${site.key}:`, e.message);
    return '';
  }
}

/**
 * Get home page recommendations
 * @param {Object} site - Site configuration
 * @returns {Object} Home data
 */
async function home(site) {
  if (!site) {
    return { list: [] };
  }

  try {
    const homeUrl = site.home || site.api;
    const data = await fetchUrl(homeUrl, {
      headers: {
        'User-Agent': 'Dart/2.18 (dart:io)',
        ...site.headers,
      },
    });
    
    if (!data || !data.list) {
      return { list: [] };
    }
    
    return {
      list: data.list.map(vod => ({
        vod_id: vod.vod_id || vod.id,
        vod_name: vod.vod_name || vod.name,
        vod_pic: vod.vod_pic || vod.pic,
        vod_remarks: vod.vod_remarks || vod.remarks,
      })),
    };
  } catch (e) {
    console.error(`[Spider] Home error for ${site.key}:`, e.message);
    return { list: [] };
  }
}

/**
 * Get hot videos
 * @returns {Object} Hot data
 */
async function hot() {
  const hotList = [];
  
  for (const site of sites) {
    try {
      if (site.hot) {
        const data = await fetchUrl(site.hot, {
          headers: {
            'User-Agent': 'Dart/2.18 (dart:io)',
            ...site.headers,
          },
        });
        
        if (data && data.list) {
          hotList.push(...data.list.map(vod => ({
            vod_id: vod.vod_id || vod.id,
            vod_name: vod.vod_name || vod.name,
            vod_pic: vod.vod_pic || vod.pic,
            vod_remarks: vod.vod_remarks || vod.remarks,
            site_key: site.key,
          })));
        }
      }
    } catch (e) {
      console.error(`[Spider] Hot error for ${site.key}:`, e.message);
    }
  }
  
  return { list: hotList };
}

/**
 * Get live TV sources
 * @returns {Object} Live data
 */
async function live() {
  const liveList = [];
  
  for (const site of sites) {
    try {
      if (site.live) {
        const data = await fetchUrl(site.live, {
          headers: {
            'User-Agent': 'Dart/2.18 (dart:io)',
            ...site.headers,
          },
        });
        
        if (data && data.list) {
          liveList.push(...data.list);
        }
      }
    } catch (e) {
      console.error(`[Spider] Live error for ${site.key}:`, e.message);
    }
  }
  
  return { list: liveList };
}

/**
 * Build URL with query parameters
 */
function buildUrl(baseUrl, params) {
  const url = new URL(baseUrl);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) {
      url.searchParams.set(key, String(value));
    }
  }
  return url.toString();
}

/**
 * Fetch URL with retry
 */
async function fetchUrl(url, options = {}, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      return await _fetch(url, options);
    } catch (e) {
      if (i === retries - 1) throw e;
      await new Promise(r => setTimeout(r, 1000 * (i + 1)));
    }
  }
}

function _fetch(url, options = {}) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;
    const req = protocol.get(url, {
      headers: {
        'User-Agent': 'Dart/2.18 (dart:io)',
        ...options.headers,
      },
      timeout: 10000,
    }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          resolve({ raw: data });
        }
      });
    });
    
    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });
  });
}

module.exports = {
  start,
  search,
  detail,
  playUrl,
  home,
  hot,
  live,
};