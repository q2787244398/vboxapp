// TVS Node.js Bootstrap Template
// Shared by Android, iOS, and macOS.
// Runtime values are injected by NodeService before native launch.

// Polyfill WebAssembly for JIT-less V8 (iOS)
if (typeof globalThis.WebAssembly === 'undefined') {
    const fakeModule = { exports: { instances: {} } };
    const fakeInstance = { exports: {} };
    globalThis.WebAssembly = {
        compile: () => Promise.resolve(fakeModule),
        instantiate: (mod, imports) => Promise.resolve({ module: fakeModule, instance: fakeInstance }),
        validate: () => true,
        Module: function() { return fakeModule; },
        Instance: function() { return fakeInstance; },
        Memory: function(opts) { this.buffer = new ArrayBuffer(opts.initial * 65536); },
        Table: function() {},
    };
}

process.env.PORT = __TVS_PORT__;
process.env.DEV_HTTP_PORT = __TVS_PORT__;
process.env.DART_PORT = __TVS_DART_PORT__;
process.env.BUNDLE_PATH = __TVS_BUNDLE_PATH__;
process.env.NODE_PATH = __TVS_NODE_DIR__;

require(process.env.NODE_PATH + '/node-intl-polyfill.js');

const http = require('http');
const https = require('https');
const { AsyncLocalStorage } = require('async_hooks');

const spiderRequestContext = new AsyncLocalStorage();
const originalJsonParse = JSON.parse;
JSON.parse = function(text, reviver) {
    const context = spiderRequestContext.getStore();
    try {
        const parsed = originalJsonParse.call(this, text, reviver);
        return parsed;
    } catch (error) {
        if (!(error instanceof SyntaxError)) throw error;
        throw error;
    }
};

function fixUrl(opts) {
    if (!opts || !opts.path) return opts;
    let path = opts.path;
    let changed = false;
    if (path.includes('=undefined')) {
        path = path.replace(/[&?][^&]*=undefined/g, '');
        if (!path.includes('?') && path.includes('&')) path = path.replace('&', '?');
        changed = true;
    }
    if (changed) {
        opts.path = path;
    }
    return opts;
}

function patchRequest(mod) {
    const orig = mod.request;
    mod.request = function(...args) {
        if (typeof args[0] === 'object' && args[0] !== null) {
            args[0] = fixUrl(args[0]);
        }
        return orig.apply(this, args);
    };
}

patchRequest(http);
patchRequest(https);

globalThis.__catServers = [];
globalThis.catServerFactory = function(handler, opts) {
    const server = http.createServer((req, res) => {
        const requestPath = String(req.url || '').split('?', 1)[0];
        const pathSegments = requestPath.split('/');
        const siteKey = pathSegments.length >= 5
            && pathSegments[1] === 'spider'
            && pathSegments[3] === '3'
            ? pathSegments[2]
            : '';
        return spiderRequestContext.run({ siteKey }, () => handler(req, res));
    });
    globalThis.__catServers.push(server);
    return server;
};

globalThis.catDartServerPort = function() { return parseInt(process.env.DART_PORT) || 0; };
globalThis.jsProxy = 'http://127.0.0.1:' + process.env.PORT + '/proxy?do=js&url=';

if (!globalThis.local) {
    const _store = {};
    globalThis.local = {
        get: (key, def) => _store[key] !== undefined ? _store[key] : (def || ''),
        set: (key, val) => { _store[key] = val; },
    };
}

process.on('unhandledRejection', () => {});
process.on('uncaughtException', () => {});

const parentPid = Number.parseInt(process.env.TVS_PARENT_PID || '', 10);
if (Number.isInteger(parentPid) && parentPid > 0) {
    const parentWatchdog = setInterval(() => {
        try {
            process.kill(parentPid, 0);
        } catch (error) {
            if (error?.code === 'EPERM') return;
            process.exit(0);
        }
    }, 500);
    parentWatchdog.unref();
}

process.chdir(process.env.NODE_PATH);

const fs = require('fs');
const path = require('path');
const dbPath = path.join(process.env.NODE_PATH, 'db.json');
try {
    const existing = JSON.parse(fs.readFileSync(dbPath, 'utf8'));
    if (!existing.pans) existing.pans = { list: [] };
    if (!existing.pans.list) existing.pans.list = [];
    fs.writeFileSync(dbPath, JSON.stringify(existing));
} catch(e) {
    fs.writeFileSync(dbPath, JSON.stringify({
        pans: { list: [] },
        sites: { list: [] },
        flags: [],
    }));
}

let lastRelistenToken = '';
let relistenInFlight = false;

function parseRelistenCommand(raw) {
    try {
        const command = JSON.parse(raw);
        if (command && typeof command.token === 'string') {
            return { token: command.token, dartPort: command.dartPort || null };
        }
    } catch (_) {}
    return { token: raw, dartPort: null };
}

function writeRelistenAck(token, status, error) {
    const ack = { token, status };
    if (error) ack.error = String(error.message || error);
    fs.writeFileSync(path.join(process.env.NODE_PATH, '.relisten.ack'), JSON.stringify(ack));
}

function closeServer(server) {
    if (!server.listening) return Promise.resolve();
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('close timed out')), 4000);
        server.close((error) => {
            clearTimeout(timer);
            if (error) reject(error); else resolve();
        });
        if (server.closeAllConnections) server.closeAllConnections();
    });
}

function listenServer(server, port) {
    return new Promise((resolve, reject) => {
        const onError = (error) => {
            server.off('listening', onListening);
            reject(error);
        };
        const onListening = () => {
            server.off('error', onError);
            resolve();
        };
        server.once('error', onError);
        server.once('listening', onListening);
        server.listen(port);
    });
}

async function relistenServers(command) {
    const token = command.token;
    if (command.dartPort !== null && command.dartPort >= 0) {
        process.env.DART_PORT = String(command.dartPort);
    }
    const port = parseInt(process.env.PORT) || 0;
    const servers = globalThis.__catServers || [];
    try {
        await Promise.all(servers.map(async (server) => {
            await closeServer(server);
            await listenServer(server, port);
        }));
        writeRelistenAck(token, 'ok');
    } catch (error) {
        writeRelistenAck(token, 'error', error);
    }
}

function checkRelistenCommand() {
    if (relistenInFlight) return;
    let raw = '';
    try {
        raw = fs.readFileSync(path.join(process.env.NODE_PATH, '.relisten'), 'utf8').trim();
    } catch (_) { return; }
    const command = parseRelistenCommand(raw);
    if (!command.token || command.token === lastRelistenToken) return;
    lastRelistenToken = command.token;
    relistenInFlight = true;
    relistenServers(command).finally(() => { relistenInFlight = false; });
}

let lastBundleSwitchToken = '';
let bundleSwitchInFlight = false;

function parseBundleSwitchCommand(raw) {
    try {
        const command = JSON.parse(raw);
        if (command && typeof command.token === 'string' && typeof command.bundlePath === 'string') {
            return { token: command.token, bundlePath: command.bundlePath, dartPort: command.dartPort || null };
        }
    } catch (_) {}
    return null;
}

function writeBundleSwitchAck(token, status, error) {
    const ack = { token, status };
    if (error) ack.error = String(error.message || error);
    fs.writeFileSync(path.join(process.env.NODE_PATH, '.bundle-switch.ack'), JSON.stringify(ack));
}

async function closeServersStrictly(servers) {
    for (const server of servers) {
        await closeServer(server);
    }
}

async function switchBundle(command) {
    const previousBundlePath = process.env.BUNDLE_PATH;
    const previousDartPort = process.env.DART_PORT;
    try {
        await closeServersStrictly(globalThis.__catServers || []);
        globalThis.__catServers = [];
        if (command.dartPort !== null && command.dartPort >= 0) {
            process.env.DART_PORT = String(command.dartPort);
        }
        process.env.BUNDLE_PATH = command.bundlePath;
        await startBundle(command.bundlePath);
        writeBundleSwitchAck(command.token, 'ok');
    } catch (error) {
        try {
            await closeServersStrictly(globalThis.__catServers || []);
            globalThis.__catServers = [];
            process.env.BUNDLE_PATH = previousBundlePath;
            process.env.DART_PORT = previousDartPort;
            await startBundle(previousBundlePath);
            writeBundleSwitchAck(command.token, 'error', error);
        } catch (rollbackError) {
            writeBundleSwitchAck(command.token, 'fatal', new Error(
                String(error.message || error) + '; rollback: ' + String(rollbackError.message || rollbackError)
            ));
        }
    }
}

function checkBundleSwitchCommand() {
    if (bundleSwitchInFlight) return;
    let raw = '';
    try {
        raw = fs.readFileSync(path.join(process.env.NODE_PATH, '.bundle-switch'), 'utf8').trim();
    } catch (_) { return; }
    const command = parseBundleSwitchCommand(raw);
    if (!command || !command.token || command.token === lastBundleSwitchToken) return;
    lastBundleSwitchToken = command.token;
    bundleSwitchInFlight = true;
    switchBundle(command).finally(() => { bundleSwitchInFlight = false; });
}

try {
    const watcher = fs.watch(process.env.NODE_PATH, () => {
        checkRelistenCommand();
        checkBundleSwitchCommand();
    });
    watcher.on('error', (error) => {
        console.log('[NodeBridge] command watch error: ' + error.message);
    });
} catch (error) {
    console.log('[NodeBridge] command watch unavailable: ' + error.message);
}

setInterval(checkRelistenCommand, 500);
setInterval(checkBundleSwitchCommand, 500);

let tolerantPromiseAllInstalled = false;

async function startBundle(bundlePath) {
    const resolvedBundlePath = require.resolve(bundlePath);
    delete require.cache[resolvedBundlePath];
    const bundle = require(resolvedBundlePath);
    
    if (typeof globalThis.websiteBundle === 'function') {
        globalThis.websiteBundle = globalThis.websiteBundle();
    }
    
    if (!bundle || typeof bundle.start !== 'function') {
        throw new Error('No start() export found: ' + bundlePath);
    }
    
    const startOpts = {
        color: [],
        sites: { list: [] },
        pans: { list: [] },
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
        pikpak: { username: '', email: '', password: '', refresh_token: '', device_id: '', user_id: '' },
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
    
    await bundle.start(startOpts);
    console.log('[NodeBridge] CatVod server started on port ' + process.env.PORT);
    
    if (!tolerantPromiseAllInstalled) {
        tolerantPromiseAllInstalled = true;
        const originalAll = Promise.all.bind(Promise);
        Promise.all = function(promises) {
            const arr = Array.from(promises);
            return originalAll(arr.map(p => Promise.resolve(p).catch(e => {
                console.log('[Promise.all] tolerated:', String(e.message || e).substring(0, 100));
                return undefined;
            })));
        };
    }
}

function writeStartupAck(status, error) {
    const ack = { status };
    if (error) ack.error = String(error.message || error);
    try {
        fs.writeFileSync(path.join(process.env.NODE_PATH, '.startup.ack'), JSON.stringify(ack));
    } catch (ackError) {
        console.error('[NodeBridge] startup ack failed:', ackError.message);
    }
}

startBundle(process.env.BUNDLE_PATH)
    .then(() => writeStartupAck('ok'))
    .catch((error) => {
        writeStartupAck('error', error);
        console.error('[NodeBridge] start failed:', error.message, error.stack);
    });