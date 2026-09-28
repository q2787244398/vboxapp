#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deobfuscation extractor for CatVodSpiderios compiled bundles.
Extracts: URLs, unicode-decoded CJK strings, route registrations,
base64 payloads, and key API endpoint patterns.
"""
import re, json, base64, sys, os
from urllib.parse import urlparse

OUT = "/workspace/tvbox-interfaces/reversed"

def load(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def dec_unicode(s):
    # decode \uXXXX escapes (raw, not via json to avoid double-processing)
    d = s.encode("utf-8").decode("unicode_escape", errors="replace")
    # strip lone surrogates that utf-8 cannot encode
    return "".join(c for c in d if not (0xD800 <= ord(c) <= 0xDFFF))

def extract_urls(text):
    urls = re.findall(r'https?://[^\s"\'`\\,;:()<>{}]+', text)
    out = []
    seen = set()
    for u in urls:
        u = u.rstrip('.,;')
        if u in seen:
            continue
        seen.add(u)
        out.append(u)
    return sorted(out)

def extract_routes(text):
    # e.post("/init", X) / e.get("/proxy/...", X) / e.register(...) / f.get(...)
    routes = []
    pat = re.compile(r'(?:e|f|api|app|server|f\.server|ln|S)\s*\.\s*(get|post|put|delete|register)\s*\(\s*["\']([^"\']+)["\']', re.I)
    for m in pat.finditer(text):
        routes.append({"method": m.group(1).upper(), "path": m.group(2)})
    # also catch plain string route registrations like "get(\"/xxx\""
    pat2 = re.compile(r'["\'](/[A-Za-z0-9_\-:{}*$]+)["\']\s*,\s*[A-Za-z_$][\w$]*\s*\)', re.I)
    for m in pat2.finditer(text):
        p = m.group(1)
        if p.startswith("/spider") or p.startswith("/proxy") or p.startswith("/website") or p.startswith("/danmu") or p.startswith("/pan") or p in ("/init","/home","/category","/detail","/play","/search","/test","/config","/t4","/uz"):
            routes.append({"method": "?", "path": p})
    # dedupe + keep real paths starting with /
    seen = set(); out = []
    for r in routes:
        if not r["path"].startswith("/"):
            continue
        k = (r["method"], r["path"])
        if k in seen:
            continue
        seen.add(k); out.append(r)
    return out

def extract_cjk(text):
    # raw CJK in source (already decoded) + \uXXXX sequences
    raw = re.findall(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]{2,}', text)
    esc = re.findall(r'(?:\\u[0-9a-fA-F]{4}){2,}', text)
    out = set(raw)
    for e in esc:
        try:
            out.add(dec_unicode(e))
        except Exception:
            pass
    return sorted(out)

def extract_base64_payloads(text):
    # base64 strings > 400 chars
    pat = re.compile(r'["\']([A-Za-z0-9+/=]{400,})["\']')
    decoded = []
    for m in pat.finditer(text):
        b = m.group(1)
        try:
            d = base64.b64decode(b, validate=False)
            # only keep if mostly printable utf-8
            s = d.decode("utf-8", errors="replace")
            printable = sum(1 for c in s if c.isprintable() or c in "\n\r\t") / max(len(s), 1)
            if printable > 0.9 and len(s) > 50:
                decoded.append(s[:500])
        except Exception:
            pass
    return decoded

def extract_hosts(urls):
    hosts = {}
    for u in urls:
        try:
            h = urlparse(u).netloc
            hosts.setdefault(h, []).append(u)
        except Exception:
            pass
    return hosts

def extract_meta(text):
    # spider meta blocks: key:"xxx", name:"xxx", type:3
    metas = re.findall(r'key\s*:\s*["\']([^"\']+)["\']\s*,\s*name\s*:\s*["\']((?:[^"\']|\\u[0-9a-fA-F]{4})+)["\']', text)
    out = []
    for k, n in metas:
        try:
            n = dec_unicode(n)
        except Exception:
            pass
        out.append({"key": k, "name": n})
    return out

def main():
    os.makedirs(OUT, exist_ok=True)
    targets = {
        "kstore": "/workspace/tvbox-interfaces/kstore_index.js",
        "catpaw": "/workspace/tvbox-interfaces/catpaw_index.js",
    }
    summary = {}
    for name, path in targets.items():
        print(f"[*] processing {name} ...")
        text = load(path)
        urls = extract_urls(text)
        routes = extract_routes(text)
        cjk = extract_cjk(text)
        b64 = extract_base64_payloads(text)
        metas = extract_meta(text)
        hosts = extract_hosts(urls)

        d = os.path.join(OUT, name)
        os.makedirs(d, exist_ok=True)

        with open(os.path.join(d, "urls.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(urls))
        with open(os.path.join(d, "routes.json"), "w", encoding="utf-8") as f:
            json.dump(routes, f, ensure_ascii=False, indent=1)
        with open(os.path.join(d, "strings_cjk.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(cjk))
        with open(os.path.join(d, "base64_payloads.txt"), "w", encoding="utf-8") as f:
            f.write("\n\n===== PAYLOAD =====\n\n".join(b64[:50]))
        with open(os.path.join(d, "spider_meta.json"), "w", encoding="utf-8") as f:
            json.dump(metas, f, ensure_ascii=False, indent=1)
        with open(os.path.join(d, "hosts.json"), "w", encoding="utf-8") as f:
            json.dump({h: len(v) for h, v in sorted(hosts.items(), key=lambda x: -len(x[1]))}, f, ensure_ascii=False, indent=1)

        summary[name] = {
            "urls": len(urls), "routes": len(routes), "cjk_strings": len(cjk),
            "base64_payloads": len(b64), "spider_meta": len(metas), "hosts": len(hosts),
        }
        print(f"    urls={len(urls)} routes={len(routes)} cjk={len(cjk)} b64={len(b64)} metas={len(metas)} hosts={len(hosts)}")

    with open(os.path.join(OUT, "extract_summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print("[+] done ->", OUT)

if __name__ == "__main__":
    main()
