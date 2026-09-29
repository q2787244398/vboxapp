#!/usr/bin/env python3
"""当 github.com:443 不可达时，用 GitHub REST API（api.github.com）推送提交。

流程：读本地 HEAD 的文件树 → 逐 blob 上传 → 建 tree → 建 commit（parent=远程HEAD）
     → 更新 refs/heads/main。等价于一次普通 push（快进）。
"""
from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

REPO = "q2787244398/vboxapp"
TOKEN = os.environ["GITHUB_TOKEN"]
ROOT = pathlib.Path(__file__).resolve().parent.parent
API = "https://api.github.com"


def req(method: str, url: str, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {TOKEN}")
    r.add_header("Accept", "application/vnd.github+json")
    r.add_header("User-Agent", "vbox-ci")
    if data:
        r.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(r, timeout=60) as resp:
        return json.loads(resp.read() or "null")


def main() -> int:
    # 1. 远程当前 HEAD
    ref = req("GET", f"{API}/repos/{REPO}/git/ref/heads/main")
    remote_sha = ref["object"]["sha"]
    print("远程 HEAD:", remote_sha[:8])

    # 2. 本地 HEAD 的 tree（用 git ls-tree 得到文件清单）
    out = subprocess.run(
        ["git", "ls-tree", "-r", "-z", "HEAD"],
        cwd=ROOT, capture_output=True, check=True
    ).stdout
    entries = []
    for chunk in out.split(b"\x00"):
        if not chunk:
            continue
        meta, path = chunk.split(b"\t", 1)
        mode, typ, sha = meta.decode().split()
        entries.append((mode, path.decode(), sha))
    print(f"本地 HEAD 文件数: {len(entries)}")

    # 3. 上传所有 blob（用 git cat-file 取内容）
    tree_items = []
    for i, (mode, path, sha) in enumerate(entries):
        blob = subprocess.run(
            ["git", "cat-file", "blob", sha], cwd=ROOT, capture_output=True, check=True
        ).stdout
        try:
            content = blob.decode("utf-8")
            encoding = "utf-8"
        except UnicodeDecodeError:
            content = base64.b64encode(blob).decode()
            encoding = "base64"
        res = req("POST", f"{API}/repos/{REPO}/git/blobs",
                  {"content": content, "encoding": encoding})
        tree_items.append({"path": path, "mode": mode, "type": "blob", "sha": res["sha"]})
        if (i + 1) % 50 == 0:
            print(f"  blob {i+1}/{len(entries)}")

    # 4. 建 tree
    tree = req("POST", f"{API}/repos/{REPO}/git/trees",
               {"tree": tree_items})
    print("tree:", tree["sha"][:8])

    # 5. commit message = 本地 HEAD 的完整 message
    msg = subprocess.run(
        ["git", "log", "-1", "--format=%B"], cwd=ROOT, capture_output=True, check=True
    ).stdout.decode().strip()

    # 6. 建 commit
    commit = req("POST", f"{API}/repos/{REPO}/git/commits",
                 {"message": msg, "tree": tree["sha"], "parents": [remote_sha]})
    print("commit:", commit["sha"][:8])

    # 7. 更新 ref（fast-forward）
    upd = req("PATCH", f"{API}/repos/{REPO}/git/refs/heads/main",
              {"sha": commit["sha"], "force": False})
    print("✅ 已推送:", upd["object"]["sha"][:8])
    return 0


if __name__ == "__main__":
    sys.exit(main())
