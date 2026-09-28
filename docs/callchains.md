# 五大模块调用链完整还原

> 来源：kstore_index.js / catpaw_index.js 静态解混淆 + 沙箱运行时探测
> 符号说明：`→` 调用方向；`(a,b)` 参数；标注 [实测] 的节点经过运行时验证

---

## 1. 网盘登录流程

### 1.1 统一入口

```
TVBox 设置页 /website
  └─→ GET /website/api/status
        └─→ providers[]  ← 14 个网盘 Provider 状态（configured / login / state / label）
  └─→ GET/PUT /website/api/credentials
        └─→ 读/写全部网盘凭据 JSON（Cookie / Token / 账号密码 / 设备指纹）
```

[实测] `/website/api/status` 返回：
`quark, uc, baidu, pan115, pan123, pan123ziyuan, pan189, new139, bili, guangya, guangyazhenying, woniu4k, emby, thunder`，
另含 `proxyMode:"legacy"`、`panPriority:"quark,uc,baidu,pan115,pan123,pan189,new139,guangya,thunder,direct"`。

### 1.2 各网盘登录调用链

| 网盘 | 登录方式 | 调用链 |
|---|---|---|
| 115 | Cookie / 扫码 | `requireCookie() → webapi.115.com/files (Cookie+Referer+Origin 注入)`；扫码走 `qrcodeapi.115.com/api/1.0/...` 换 Cookie |
| 天翼 189 | 扫码 / Cookie / 账密 | `open.e.189.cn 认证 → api.cloud.189.cn/open/file/getFileDownloadUrl.action`；指纹 appId=8025431004 clientType=10020 v=6.2 platform=web_cloud.189.cn |
| 移动 139 | 手机号验证码 | `发验证码 → 提交验证码+设备指纹 → 换取 session`；设备指纹伪造品牌/型号/OS/deviceId/deviceInfo/userAgent |
| 夸克 | Cookie 直填 | `pan.quark.cn`（内置注册分享链接 `pan.quark.cn/s/85bc20f95cbf`） |
| UC | Cookie / TV Token | 凭据三字段 `cookie + token + refreshtoken`；文件解析走 `api.open.uc.cn` |
| 百度 | Cookie 直填 | `passport.baidu.com + pan.baidu.com`（内置分享链接） |
| 123 | 账号密码 | `open-api.123pan.com` 账号体系 |
| 光鸭 | 短信 / 手动 Token | `guangyapan.com`；`guangyazhenying` 为 Cookie |
| 蜗牛 woniu4k | 账号 / Cookie | 两步：`/login` → `/verify`（探测含 woniu4k-login / woniu4k-verify） |
| 迅雷 | 手机号验证码 | 预生成 `deviceId + deviceSign + peerId + authPackage=com.xunlei.downloadprovider + authVersion=downloadprovider-25.0.6.30` |
| B 站 | 扫码 / Cookie | [实测] `POST /website/api/bili/login/start → {taskId, qrUrl, qrImage(base64 PNG)}`，qrUrl 指向 `account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=...` |

### 1.3 B 站扫码登录（实测返回）

```json
{
  "code": 0,
  "taskId": "eb3aeee5-...",
  "status": "waiting",
  "msg": "请使用哔哩哔哩 App 扫码确认",
  "qrUrl": "https://account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=db597a66...",
  "qrImage": "data:image/png;base64,iVBOR..."   // 二维码内联返回，无需二次拉取
}
```

---

## 2. Token / 凭据存储

```
设置页 UI ──PUT──→ /website/api/credentials ──→ JsonDB ──→ db.json（明文落盘）
                                        ├─→ .cache/*.json（弹幕剧集缓存）
                                        ├─→ localStorage（logvar_api_base_url / debug）
                                        └─→ persistEnvStore（环境变量 overrides + deletedKeys）
```

- **JsonDB 初始化**：`new JsonDB(new Config((process.env.NODE_PATH||".")+"/default.db.json", true, true, "/", true))`
- **db 导出/恢复**：`GET /website/api/db`（下载）、WebDAV 备份、导入 json 文件
- **凭据结构**（/website/api/credentials 实测，字段已置空）：

```json
{
  "quark":  { "cookie": "" },
  "uc":     { "cookie": "", "token": "", "refreshtoken": "" },
  "baidu":  { "cookie": "" },
  "pan115": { "cookie": "" },
  "pan123": { "account": "", "password": "" },
  "pan189": { "account": "", "password": "", "cookie": "" },
  "new139": { "session": "", "device": "{brand:HONOR, model:MAG-AN00, deviceId:...}" },
  "bili":   { "cookie": "" },
  "guangya":{ "token": "" },
  "woniu4k":{ "account": "", "password": "", "cookie": "" },
  "thunder":{ "config": "{deviceId, deviceSign, peerId, authVersion}" },
  "emby":   { "data": [] },
  "backup": { "webdav": { "server": "", "user": "", "pass": "" } }
}
```

**风险**：凭据明文存储；`/website/api/credentials` 与 `/website/api/db` 无鉴权，拿到接口地址即可导出全部网盘凭据。

---

## 3. 解析接口调用链

```
TVBox /play 请求 {flag, id}
  └─→ spider 处理器（按 flag 匹配网盘类型）
        └─→ 网盘适配器 requireCookie()（注入已存凭据）
              ├─→ 115:  webapi.115.com/share/snap → proapi.115.com/app/share/downurl
              ├─→ UC:   api.open.uc.cn 取 download_url（失败抛"UC 免登录分享直链获取失败"）
              ├─→ 夸克: 分享解析 + Cookie: qc 注入
              ├─→ 阿里: Wet("ali") → Mae(fid) 按 template_width 择优
              └─→ 天翼: api.cloud.189.cn/open/file/getFileDownloadUrl.action
        └─→ 返回播放地址列表（直链 或 /proxy/:site/... 代理地址 + header 注入）
```

UC 适配器核心（还原）：

```js
async function Mtt(e, t) {
  let r = e.body.flag, i = e.body.id.split("*");
  if (r.startsWith(getPanName("uc"))) {
    let s = EPr(e) + e.server.prefix + "/proxy/uc";
    let g = await ktt(i[0], i[1], i[2], i[3]);          // 分享直链
    if (!g?.download_url) throw new Error("UC 免登录分享直链获取失败");
    return { parse: 0, url: ["原画", g.download_url], ... };
  }
}
```

播放阶段支持多线程分片：`chunkSize: 1024*chunkKB, poolSize, timeout:10s, skipBytes`（秒开与拖动定位）。

---

## 4. 代理模块调用链

```
GET /proxy/:site/:what/:flag/:shareId/:fileId/:end
  └─→ jt 处理器（统一入口，所有站点蜘蛛注册）
        ├─→ site=ali   → /proxy/ali   字幕 /src/subt/{fid}/{cid}/.bin，模板宽度排序
        ├─→ site=quark → /proxy/quark  Cookie: qc 注入，字幕带 encodeURIComponent
        ├─→ site=uc    → /proxy/uc     shareId/fileId 解析直链后转发
        └─→ 其余        → 各网盘驱动组装上游 URL + 注入 Cookie/Referer/UA
  └─→ 流响应：Range 分片 · 多线程 chunk · 字幕 .bin · DASH 分段
```

**新增发现（本次还原）**：DASH 流代理路由
`GET /proxy/dash/:token/:quality/manifest.mpd` 与 `GET /proxy/dash/:token/:quality/:track.m4s`。
本地回退代理：`http://127.0.0.1:5321/proxy?url=<encoded>`。

路由注册（还原，duoduo 蜘蛛）：

```js
var Nat = {
  meta: { key: "duoduo", name: "「盘」多多", type: 3 },
  api: async e => {
    e.post("/init", Vt); e.post("/home", jBr); e.post("/category", HBr);
    e.post("/detail", qBr); e.post("/play", Ht); e.post("/search", zBr);
    e.get("/test", Rat);
    e.get("/proxy/:site/:what/:flag/:shareId/:fileId/:end", jt);   // 代理入口
  },
  check: DU
};
```

---

## 5. 弹幕模块调用链（catpaw 独有）

```
spider /play 命中视频
  └─→ 剧集映射表 fAe[`${flag}_${id}`]（名称/原名/集数）
  └─→ 注入 b.extra.danmaku = http://127.0.0.1:{port}/danmu-proxy?name=...&episodeNumber=...
        └─→ GET /danmu-proxy（?url, name, episodeNumber, originalName, format=json|xml）
              ├─→ 读取用户弹幕源列表 danmu.urls（autoPush 开关）
              ├─→ 并行请求各弹幕源
              │     ├─→ 腾讯: dm.video.qq.com/barrage/base/{vid} + /segment/{vid}
              │     ├─→ 爱奇艺: barrage API（durationSec + displayBarrage 校验）
              │     ├─→ 芒果TV: pcweb.api.mgtv.com/video/info → galaxy.bz.mgtv.com/getctlbarrage → /rdbarrage
              │     └─→ 人人: {TV|MAC|WIN}_DANMU_HOST/v1/produce/danmu/EPISODE/{n} + rrsp.com.cn 回退
              └─→ 输出 XML（<i/> 空弹幕约定）或 JSON（{success, comments, count}）
```

- 弹幕源管理：`GET/PUT /website/danmu/setting`、`POST /website/danmu/push`（url + previewUrl）
- 弹幕搜索地址注入：`GET /website/danmu/fe` → 写入视频站点 `danmuSearchUrl`
- 缓存：`.cache/animes.json` + `.cache/episodeIds.json`，启动 `getLocalCaches()` 预热

弹幕注入逻辑（还原）：

```js
if (f.url.endsWith("/play")) {
  let b = JSON.parse(g);
  if ((b.url || b.url?.length || b.urls?.length) && !b?.extra?.danmaku) {
    let _ = f.body || {}, S = `${_.flag}_${_.id}`, T = fAe[S] || {};
    b.extra || (b.extra = {});
    b.extra.danmaku = RHt(`http://127.0.0.1:${port}/danmu-proxy`, T, IHt(b));
  }
}
// danmu-proxy 回退：format=json → {success:false,...}；xml → <i/> 200
```

---

## 6. 远程配置中心（remoteWex）

```
OSS 图片(jpg 分片编码) ─→ wexfnwshinidie 解码 ─→ 站点列表
   siteUrl: http://103.36.222.35:9595
   wexSiteUrl: http://103.36.222.35:9595/wexfnwshinidie
   siteConfigUrl: http://oss4liview.moji.com/thd_file/2026/09/16/bb98838e...jpg
   siteConfigKeys(13): wogg, huajuan, muou, guanying, duoduo, huban, leijing,
                       123pan, shayang, jutou, qiwei, libvio, panku
分发: /config → /t4 → /uz → /full-config → TVBox
订阅校验: /index.js.md5（内容指纹，客户端决定是否重拉）
```
