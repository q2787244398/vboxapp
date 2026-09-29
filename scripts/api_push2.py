#!/usr/bin/env python3
"""基于远程真实 HEAD，用 API 只提交「本地相对远程的变更文件」。

与 api_push.py 的区别：不重建整棵树，只上传变更文件并用
Git Trees API 的 base_tree 叠加，因此不会丢远程内容，
且 parent 直接指向远程真实 SHA → 保证 fast-forward。
"""
from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys
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


# 需要提交的文件（相对远程 b37ca01 的新增/修改）
FILES = [
    "contract/docs/prefs_keys_revision_v1.1.md",
    "contract/schema/prefs_keys_v1.json",
    "lib/contract/prefs_keys.dart",
    "lib/contract/schema.dart",
    "lib/data/models/apiyuan.dart",
    "lib/data/models/db_model.dart",
    "lib/data/models/download.dart",
    "lib/data/models/favorite.dart",
    "lib/data/models/history.dart",
    "lib/data/models/jiexisetting.dart",
    "lib/data/models/models.dart",
    "lib/data/models/search_history.dart",
    "lib/data/models/setting.dart",
    "lib/data/models/subscription.dart",
    "lib/data/models/zhanyuan.dart",
    "lib/data/database_manager.dart",
    "pubspec.yaml",
    "docs/PROJECT_LAYOUT.md",
    "scripts/check_contract_sync.py",
    "scripts/check_migration_chain.py",
    "scripts/check_models_roundtrip.py",
    "scripts/check_prefs_manager.py",
    "scripts/revise_prefs_keys.py",
    "scripts/api_push2.py",
    "lib/data/prefs_manager.dart",
    "scripts/fetch_mpv_dependencies.sh",
    "scripts/install_mpv_dependencies.sh",
    "scripts/build_lxml_ios.sh",
    "scripts/pack_python_artifacts.sh",
    "scripts/version_bump.sh",
    "scripts/add_to_xcode.sh",
    "contract/docs/stage_check_report_stage0.yaml",
]


def main() -> int:
    # 动态获取远程真实 HEAD
    ref = req("GET", f"{API}/repos/{REPO}/git/ref/heads/main")
    BASE_SHA = ref["object"]["sha"]
    print("远程 HEAD:", BASE_SHA[:8])

    # 用 base_tree = 远程 tree，只叠加变更文件
    base_tree = req("GET", f"{API}/repos/{REPO}/git/commits/{BASE_SHA}")["tree"]["sha"]
    items = []
    for path in FILES:
        p = ROOT / path
        if not p.exists():
            print("  跳过(不存在):", path)
            continue
        blob = p.read_bytes()
        try:
            content = blob.decode("utf-8")
            enc = "utf-8"
        except UnicodeDecodeError:
            content = base64.b64encode(blob).decode()
            enc = "base64"
        mode = "100755" if path.endswith(".sh") else "100644"
        res = req("POST", f"{API}/repos/{REPO}/git/blobs",
                  {"content": content, "encoding": enc})
        items.append({"path": path, "mode": mode, "type": "blob", "sha": res["sha"]})
        print("  ✅ blob:", path)

    tree = req("POST", f"{API}/repos/{REPO}/git/trees",
               {"base_tree": base_tree, "tree": items})
    print("tree:", tree["sha"][:8])

    msg = (
        "feat(stage-1): prefs_manager.dart — 53 键偏好读写 + 5 敏感键 secure storage\n\n"
        "- lib/data/prefs_manager.dart\n"
        "  · 通用 get/set 走 findPrefsKey 按契约 type 分派（覆盖全部 53 键）\n"
        "  · 5 敏感键走 flutter_secure_storage\n"
        "  · 7 个 JSON 列表键便捷读写（getJsonList/setJsonList）\n"
        "  · 契约语义方法：needSqliteMigration/markSqliteMigrationDone 等\n"
        "- scripts/check_prefs_manager.py  契约一致性校验（4 项）\n"
        "- scripts/api_push2.py            github.com:443 不可达时的 API 推送工具\n\n"
        "第 1 轮进度：契约镜像 ✅ 模型 ✅ database_manager ✅ prefs_manager ✅\n"
        "验证：check_prefs_manager 4 项全通过"
    )
    commit = req("POST", f"{API}/repos/{REPO}/git/commits",
                 {"message": msg, "tree": tree["sha"], "parents": [BASE_SHA]})
    print("commit:", commit["sha"][:8])

    upd = req("PATCH", f"{API}/repos/{REPO}/git/refs/heads/main",
              {"sha": commit["sha"], "force": False})
    print("✅ 已推送:", upd["object"]["sha"][:8])
    return 0


if __name__ == "__main__":
    sys.exit(main())
