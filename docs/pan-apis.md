# 网盘 API 端点清单（还原）

> 从 kstore_index.js / catpaw_index.js 中提取的网盘上游端点与鉴权方式。

## 115 云盘

| 端点 | 用途 | 关键参数/头 |
|---|---|---|
| `https://webapi.115.com/files` | 文件列表 | `aid=1, cid, o=user_ptime, show_dir=1, limit=115, format=json`；头注入 `Cookie` + `Referer: webapi.115.com/bridge_2.0.html?...` + `Origin: https://115.com` |
| `https://webapi.115.com/files/search` | 文件搜索 | `search_value, type=4, offset, limit=20` |
| `https://webapi.115.com/share/snap` | 分享目录快照 | `share_code, receive_code, cid, limit` |
| `https://115cdn.com/webapi/share/snap` | 分享快照（备用域） | 同上 |
| `https://proapi.115.com/app/share/downurl` | 分享下载直链 | 需 Cookie |
| `https://qrcodeapi.115.com/api/1.0/alipay_qrcode/...` | 扫码登录 | 换 Cookie |
| `https://webapi.115.com/category/get` | 分类信息 | `cid` |
| `https://webapi.115.com/files?aid=1&cid=...&o=file_name...` | 排序列表 | `o=file_name` |

UA 指纹：`Mozilla/5.0 ... Chrome/125.0.0.0 Safari/537.36 115Browser/36.0.0 Chromium/125.0`

## 天翼云 189

| 端点 | 用途 |
|---|---|
| `https://cloud.189.cn` | 主站 |
| `https://open.e.189.cn` | 登录/认证 |
| `https://api.cloud.189.cn/open/file/getFileDownloadUrl.action` | 取文件下载 URL |
| `https://upload.cloud.189.cn` | 上传 |
| `https://m.cloud.189.cn/zhuanti/2020/loginErrorPc/index.html` | 登录错误页 |

版本指纹：`appId=8025431004, clientType=10020, appVersion=6.2, platform=web_cloud.189.cn`
UA：`Mozilla/5.0 ... Chrome/131.0.0.0 Safari/537.36`

## 123 云盘

- `https://open-api.123pan.com`（开放 API 账号体系，账号密码登录）

## 夸克 / UC（阿里系）

- 夸克：`pan.quark.cn`（Cookie 直填）；注册链接 `https://pan.quark.cn/s/85bc20f95cbf`
- UC：`api.open.uc.cn`（Cookie + token + refreshtoken）；`drive.uc.cn`（注册链接 `https://drive.uc.cn/s/5d3d5918d78b4`）

## 百度

- 登录：`passport.baidu.com`
- 文件：`pan.baidu.com`（Cookie 直填）；注册链接 `https://pan.baidu.com/s/1NKUE49Xh6GLiC6MZCQpW3g?pwd=r6mq`

## 移动云盘 139

- 手机号验证码登录；需伪造设备指纹：
  `brand=HONOR, model=MAG-AN00, os=android 13, screen=1200X2664, appVersion=13.1.0, deviceId=069A0369..., deviceInfo=1|127.0.0.1|1|13.1.0|..., userAgent=android|MAG-AN00|android 13|mCloud13.1.0-000`

## 迅雷

- 登录：手机号验证码；`api-pan.xunlei.com`
- 设备预注册指纹：`deviceId + deviceSign(div101.<deviceId>...) + peerId + authPackage=com.xunlei.downloadprovider + authVersion=downloadprovider-25.0.6.30 + authClientId=Xp6vsxz_7IYVw2BB`
- 注册链接：`https://pan.xunlei.com/s/VOMABg1awQQNTnWyarNy9N0OA1?pwd=w2xh`

## B 站

- 扫码：`https://account.bilibili.com/h5/account-h5/auth/scan-web?qrcode_key=...`
- API：`api.bilibili.com`（Cookie 直填）
- 弹幕：`https://api.bilibili.com/x/v1/dm/list.so`（预留弹幕源）

## 光鸭

- 主站：`guangyapan.com`（短信登录 / 手动 Token）
- 注册链接：`https://www.guangyapan.com/s/1929945310176460834_amtV6IXLP9l33m6z`
- `guangyazhenying`：Cookie 直填

## 蜗牛 woniu4k

- 账号/Cookie；两步登录 `/login` → `/verify`（沙箱探测确认接口存在）

## Emby

- 服务器直连（用户填地址 + 凭据）；封面走 `/spider/emby/3/image?serverId=...&itemId=...`

## 弹幕源 API

| 平台 | 端点 |
|---|---|
| 腾讯视频 | `dm.video.qq.com/barrage/base/{vid}` · `dm.video.qq.com/barrage/segment/{vid}` |
| 爱奇艺 | 弹幕接口（校验 durationSec / displayBarrage） |
| 芒果 TV | `pcweb.api.mgtv.com/video/info` → `galaxy.bz.mgtv.com/getctlbarrage` → `galaxy.bz.mgtv.com/rdbarrage` |
| 人人影视 | `{TV|MAC|WIN}_DANMU_HOST/v1/produce/danmu/EPISODE/{n}`；Web 回退 `rrsp.com.cn` |

## 代理相关

- 统一入口：`/proxy/:site/:what/:flag/:shareId/:fileId/:end`
- DASH：`/proxy/dash/:token/:quality/manifest.mpd` · `/proxy/dash/:token/:quality/:track.m4s`
- 本地回退：`http://127.0.0.1:5321/proxy?url=<encoded>`
