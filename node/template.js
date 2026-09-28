// CatVod Spider DB template — matches the real runtime schema observed in
// the reversed bundle (node/db.json + node/default.db.json).
//
// Structure:
//   pans.list      — 网盘 Provider 凭据条目（14 个平台）
//   sites.list     — 站源（spider）开关与排序
//   flags          — 功能开关
//   spider.douban  — 默认 spider 设备配置（default.db.json）
'use strict';

const path = require('path');
const fs = require('fs');

const DB_PATH = path.join(__dirname, 'db.json');

// 14 个网盘 Provider 的凭据字段模板（与 bundle startOpts 对齐）
const PAN_PROVIDERS = {
    y115:    { cookie: '', offline: {} },
    tianyi:  { username: '', password: '' },
    new139:  { phone: '', captcha: '' },
    quark:   { cookie: '' },
    uc:      { cookie: '', token: '', ut: '' },
    baidu:   { cookie: '' },
    pan123:  { username: '', password: '' },
    guangya: { url: '', token: '' },
    guangyazhenying: { cookie: '' },
    woniu4k: { username: '', password: '' },
    xunlei:  { username: '', password: '' },
    bilibili_all: { cookie: '', classes_all: '', filters_all: '' },
    emby:    { list: [] },
    pikpak:  { username: '', email: '', password: '', refresh_token: '', device_id: '', user_id: '' },
    ali:     { token: '' },
};

const DEFAULT_DB = {
    pans: { list: Object.entries(PAN_PROVIDERS).map(([key, cfg]) => ({ key, ...cfg })) },
    sites: { list: [] },
    flags: [],
};

const DEFAULT_SPIDER_DB = {
    spider: {
        douban: {
            key: 'nodejs_douban',
            name: '豆瓣|首页',
            type: 3,
            enable: true,
            searchable: 1,
            quickSearch: 1,
            filterable: 1,
        },
    },
};

function load() {
    try {
        const raw = fs.readFileSync(DB_PATH, 'utf8');
        const parsed = JSON.parse(raw);
        if (!parsed.pans) parsed.pans = { list: [] };
        if (!parsed.pans.list) parsed.pans.list = [];
        if (!parsed.sites) parsed.sites = { list: [] };
        if (!parsed.flags) parsed.flags = [];
        return parsed;
    } catch (e) {
        return JSON.parse(JSON.stringify(DEFAULT_DB));
    }
}

function save(db) {
    fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2));
}

function reset() {
    fs.writeFileSync(DB_PATH, JSON.stringify(DEFAULT_DB, null, 2));
}

function getPans() {
    return load().pans.list;
}

function setPans(list) {
    const db = load();
    db.pans.list = list;
    save(db);
    return db;
}

function getCredential(provider, field) {
    const item = load().pans.list.find(p => p.key === provider);
    return item ? item[field] : undefined;
}

function setCredential(provider, field, value) {
    const db = load();
    let item = db.pans.list.find(p => p.key === provider);
    if (!item) {
        item = { key: provider };
        db.pans.list.push(item);
    }
    item[field] = value;
    save(db);
    return item;
}

function deleteCredential(provider, field) {
    const db = load();
    const item = db.pans.list.find(p => p.key === provider);
    if (item) {
        delete item[field];
        save(db);
    }
}

function exportDb() {
    return load();
}

function importDb(obj) {
    const db = obj && typeof obj === 'object' ? obj : DEFAULT_DB;
    if (!db.pans) db.pans = { list: [] };
    if (!db.sites) db.sites = { list: [] };
    if (!db.flags) db.flags = [];
    save(db);
    return db;
}

module.exports = {
    DEFAULT_DB,
    DEFAULT_SPIDER_DB,
    PAN_PROVIDERS,
    load,
    save,
    reset,
    getPans,
    setPans,
    getCredential,
    setCredential,
    deleteCredential,
    exportDb,
    importDb,
};