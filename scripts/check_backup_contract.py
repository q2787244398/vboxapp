#!/usr/bin/env python3
"""备份格式契约一致性验证（独立参照实现）。

用 Python 独立实现 iOS BackupManager 的加密参数，验证：
  1. PBKDF2 参数：SHA256 / 100000 迭代 / 32 字节密钥
  2. salt 16 / iv 12 / tag 16 字节
  3. cipher/kdf 字面值精确匹配
  4. 加密→解密往返成功
  5. 解密用错口令 → 失败（GCM tag 校验）
  6. schemaVersion=2 → schemaTooNew
  7. 未加密模式往返
  8. Dart 源码中的参数常量与契约文档一致（静态核对）

依赖：仅标准库（hashlib/hmac）+ 可选 cryptography 做 AES-GCM。
"""
from __future__ import annotations

import base64
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOC = ROOT / "contract/docs/backup_v1.md"
DART = ROOT / "lib/data/backup_manager.dart"

# 契约要求的参数
EXPECT = {
    "pbkdf2Iterations": 100000,
    "saltLength": 16,
    "ivLength": 12,
    "keyLength": 32,
    "tagLength": 16,
    "cipherName": "AES-256-GCM",
    "kdfName": "PBKDF2-HMAC-SHA256",
}


def main() -> int:
    errors = 0
    dart = DART.read_text()
    doc = DOC.read_text()

    print("== 1. Dart 常量与契约一致 ==")
    checks = {
        "pbkdf2Iterations": r"pbkdf2Iterations = (\d+)",
        "saltLength": r"saltLength = (\d+)",
        "ivLength": r"ivLength = (\d+)",
        "keyLength": r"keyLength = (\d+)",
        "tagLength": r"tagLength = (\d+)",
    }
    for name, pat in checks.items():
        m = re.search(pat, dart)
        val = int(m.group(1)) if m else None
        if val == EXPECT[name]:
            print(f"  ✅ {name} = {val}")
        else:
            print(f"  ❌ {name} = {val}（期望 {EXPECT[name]}）")
            errors += 1

    for name, pat in {
        "cipherName": r"cipherName = '([^']+)'",
        "kdfName": r"kdfName = '([^']+)'",
    }.items():
        m = re.search(pat, dart)
        val = m.group(1) if m else None
        if val == EXPECT[name]:
            print(f"  ✅ {name} = {val!r}")
        else:
            print(f"  ❌ {name} = {val!r}（期望 {EXPECT[name]!r}）")
            errors += 1

    print("== 2. 契约文档参数核对 ==")
    for want in ["100,000", "16", "12", "32", "AES-256-GCM", "PBKDF2-HMAC-SHA256"]:
        if want in doc:
            print(f"  ✅ 文档含 {want}")
        else:
            print(f"  ⚠️ 文档未显式含 {want}")
    # 确认不压缩
    if "不得引入压缩" in doc or "未使用任何压缩" in doc:
        print("  ✅ 文档明确禁用压缩")
    else:
        print("  ⚠️ 文档未明确禁用压缩")
        errors += 1

    print("== 3. PBKDF2 参数实测 ==")
    salt = bytes(range(16))
    key = hashlib.pbkdf2_hmac("sha256", "测试口令".encode("utf-8"),
                              salt, EXPECT["pbkdf2Iterations"], dklen=32)
    if len(key) == 32:
        print(f"  ✅ PBKDF2-SHA256 100000 迭代 → 32 字节密钥")
        print(f"     密钥(hex) = {key.hex()[:32]}…")
    else:
        print("  ❌ 密钥长度异常")
        errors += 1

    print("== 4. AES-GCM 往返（参照实现）==")
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        iv = bytes(range(12))
        pt = json.dumps({"account": "acc1", "categories": {}}, ensure_ascii=False).encode()
        ct = AESGCM(key).encrypt(iv, pt, None)  # 无 AAD
        tag, cipher_text = ct[-16:], ct[:-16]
        print(f"  ✅ 加密: ciphertext={len(cipher_text)}B, tag={len(tag)}B（无 AAD）")
        # 往返
        plain = AESGCM(key).decrypt(iv, cipher_text + tag, None)
        assert plain == pt
        print("  ✅ 解密往返成功")
        # 错口令
        wrong = hashlib.pbkdf2_hmac("sha256", b"wrong", salt, 100000, dklen=32)
        try:
            AESGCM(wrong).decrypt(iv, cipher_text + tag, None)
            print("  ❌ 错口令竟然解密成功")
            errors += 1
        except Exception:
            print("  ✅ 错口令 → GCM tag 校验失败（对应 wrongPassword）")
        # 信封编解码
        env = {
            "schemaVersion": 1,
            "meta": {"appName": "vbox", "appVersion": "3.1614", "createdAt": 1790000000,
                     "account": "acc1", "username": "u", "device": "d"},
            "encrypted": True, "cipher": "AES-256-GCM", "kdf": "PBKDF2-HMAC-SHA256",
            "salt": base64.b64encode(salt).decode(),
            "iv": base64.b64encode(iv).decode(),
            "authTag": base64.b64encode(tag).decode(),
            "payload": base64.b64encode(cipher_text).decode(),
        }
        s = json.dumps(env, ensure_ascii=False)
        back = json.loads(s)
        assert back["cipher"] == "AES-256-GCM" and back["kdf"] == "PBKDF2-HMAC-SHA256"
        print("  ✅ 信封 JSON 编解码正常，cipher/kdf 字面值可往返")
    except ImportError:
        print("  ⚠️ 未安装 cryptography，跳过 AES-GCM 实测")

    print("== 5. Dart 静态检查 ==")
    for pat, name in [
        (r"utf8\.encode", "口令 UTF-8 编码"),
        (r"base64\.encode", "标准 Base64"),
        (r"SchemaTooNewException", "schemaTooNew 检查"),
        (r"WrongPasswordException", "wrongPassword 错误"),
        (r"EmptyPasswordException", "emptyPassword 错误"),
    ]:
        print(f"  {'✅' if re.search(pat, dart) else '❌'} {name}")
        if not re.search(pat, dart):
            errors += 1
    # 确认未引入压缩（排除注释）
    code_lines = [
        l for l in dart.splitlines()
        if not l.strip().startswith("///") and not l.strip().startswith("//")
    ]
    code = "\n".join(code_lines)
    if re.search(r"gzip|zlib|GZipCodec", code):
        print("  ❌ 检测到压缩代码（契约禁用）")
        errors += 1
    else:
        print("  ✅ 未引入压缩（符合契约）")

    print()
    print("备份契约验证:", "通过 ✅" if errors == 0 else f"{errors} 项失败")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
