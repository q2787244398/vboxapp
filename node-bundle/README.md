# CatVod 网盘系统 — 编译混淆版文件包

本压缩包包含从两个订阅接口逆向提取的**完整编译混淆（bundled+minified）文件**，
即网盘登录、Token 存储、资源解析、代理与弹幕模块的全部运行时代码。

## 文件清单

| 文件 | 大小 | MD5 | 说明 |
|---|---|---|---|
| `kstore_index.js` | ~6.5 MB | `6bd6e56a6de4a3084aa7be6fd890d4c3` | 9280.kstore.vip 完整版 bundle（94 站点，含配置中心/登录/凭据管理） |
| `catpaw_index.js` | ~5.9 MB | `7107c3b0829ca9df56d6053ce3e33202` | catpaw.douer.me 精简版 bundle（58 站点，含代理/弹幕） |
| `node/main.js` | 60 KB | - | CatVod Node.js 运行时引导（iOS/Android/macOS 共用） |
| `node/node-intl-polyfill.js` | - | - | ICU 国际化 polyfill |
| `node/db.json` | - | - | 运行时数据库（Token/Cookie 持久化落点） |
| `node/default.db.json` | - | - | 默认 spider 设备配置 |
| `wexfnwconfig.json` | ~118 KB | - | 94 站点真实配置（kstore 源） |
| `catpaw_wexfnwconfig.json` | - | - | catpaw 站点配置（如已提取） |

## 模块定位速查（编译后符号）

- 登录管理器（扫码）：`Kee` 类 → `start/poll/cancel`，任务存 `Pf` Map，超时 300s
- 凭据读写：`y1` 类 → `getCredential/setCredential/getCookie/setCookie`
- 凭据路径映射：`c_t` 常量表（Cookie/Token 在 db 中的落盘路径）
- 播放解析：`Ht`（spider /play 动作）→ 分派到各网盘（115/百度/迅雷/光鸭/天翼/移动/123/夸克/UC/阿里）
- 代理：`jt`（`/proxy/:site/:what/:flag/:shareId/:fileId/:end`）→ `OM`(ali)/`PM`(quark)/`Ltt`(uc)/`OU`(baidu) → `x_` 分块流式转发
- 弹幕：catpaw `/danmu-proxy`（DanDanPlay 协议匹配+评论）；kstore `/danmu*` 路由族 + `danmuPush` 推送

## 运行方式

```bash
# 需要 Node.js >= 16。两个 bundle 均可独立启动：
node main.js   # 或直接 node kstore_index.js（需注入 startOpts，见 main.js）
```

详细逆向结果见同目录 `deep-reverse-report.html`。
