/**
 * TVS Spider Bundle Template
 * 
 * This is a template for creating custom spider bundles.
 * A spider bundle implements the CatVod API to parse video sources
 * from various streaming websites.
 * 
 * Required exports:
 * - start(config) - Initialize the spider with config
 * - search(site, keyword) - Search for videos
 * - detail(site, vodId) - Get video details
 * - playUrl(site, vodId, playFrom) - Get play URL
 * - home(site) - Get home page recommendations
 * - hot() - Get hot videos
 * - live() - Get live TV sources
 */

'use strict';

const https = require('https');
const http = require('http');
const { URL } = require('url');

// Spider state
let config = {};
let sites = [];

/**
 * Initialize spider with configuration
 */
async function start(startConfig) {
  config = startConfig;
  sites = startConfig.sites?.list || [];
  console.log('[Spider] Started with', sites.length, 'sites');
}

/**
 * Search for videos
 * @param {Object} site - Site configuration
 * @param {string} keyword - Search keyword
 * @returns {Object} Search results { list: [...] }
 */
async function search(site, keyword) {
  // Implement search logic for the specific site
  // Example:
  const searchUrl = `${site.api}?search=${encodeURIComponent(keyword)}`;
  const response = await fetch(searchUrl);
  const data = await response.json();
  
  return {
    list: (data.list || []).map(vod => ({
      vod_id: vod.id,
      vod_name: vod.name,
      vod_pic: vod.pic,
      vod_remarks: vod.remarks,
    })),
  };
}

/**
 * Get video details
 * @param {Object} site - Site configuration
 * @param {string} vodId - Video ID
 * @returns {Object} Video details
 */
async function detail(site, vodId) {
  const detailUrl = `${site.api}?detail=${encodeURIComponent(vodId)}`;
  const response = await fetch(detailUrl);
  return await response.json();
}

/**
 * Get play URL
 * @param {Object} site - Site configuration
 * @param {string} vodId - Video ID
 * @param {string} playFrom - Play source (optional)
 * @returns {string} Play URL
 */
async function playUrl(site, vodId, playFrom) {
  const playUrl = `${site.api}?play=${encodeURIComponent(vodId)}`;
  const response = await fetch(playUrl);
  const data = await response.json();
  return data.url || '';
}

/**
 * Get home page recommendations
 * @param {Object} site - Site configuration
 * @returns {Object} Home data { list: [...] }
 */
async function home(site) {
  const homeUrl = site.home || site.api;
  const response = await fetch(homeUrl);
  return await response.json();
}

/**
 * Get hot videos
 * @returns {Object} Hot data { list: [...] }
 */
async function hot() {
  // Implement hot videos logic
  return { list: [] };
}

/**
 * Get live TV sources
 * @returns {Object} Live data { list: [...] }
 */
async function live() {
  // Implement live TV logic
  return { list: [] };
}

/**
 * Helper: Make HTTP request with retries
 */
async function fetch(url, options = {}, retries = 3) {
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
    const req = protocol.get(url, (res) => {
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