# 听澜 Tinglan 源码级参考（对 REA 反编译的交叉验证）

> 项目：https://github.com/talongao/tinglan （Go + Viva 原生华为音乐桌面客户端）
> 本地源码：`tinglan/`（209 个 Go 文件，tarball 经 API 下载，git smart-http 被本机代理拦）
> 用途：为 MuyuFlutter 提供**源码级**的华为接口与播放器 UI 事实，替代无法在本机执行的 Ghidra 反编译。

## 0. 与沐语的关系（REA 观察 vs 源码事实交叉）

| 维度 | REA 反编译 Muyu.exe 观察 | tinglan 源码事实 | 一致性 |
| --- | --- | --- | --- |
| 技术栈 | Go + MyGo(native) 原生 | Go + Viva 原生 | ✅ 同类（MyGo/Viva 均为 Go 原生 UI 框架） |
| 主域 | api-drcn.music.dbankcloud.cn | 同 | ✅ |
| 取流接口 | `/music-play-service/v3/service/file/bycontentcode` | 同 | ✅ |
| client_id | 101444301 | 同 | ✅ |
| 回调 | hms://redirect_uri | 同 | ✅ |
| 音质 | h/sq/hr（静态字段） | 实际请求 qualityType=1/3（standard/lossless） | ⚠️ 修正 |
| 鉴权 | 观察到 Bearer（错误推测） | **Digest username=app-music-baseline,nonce,created,token** | 🔴 重大修正 |
| 播放器 | 黑胶/歌词/侧栏/音量弹层/音质菜单 | 源码 stage.go/shell.go/transport 完整实现 | ✅ 互证 |

**结论**：tinglan 是沐语的近亲实现（同为 Go 原生华为音乐客户端），它的源码填补了 REA 反编译拿不到的伪代码细节，尤其是鉴权和取流参数——这解释了之前 Flutter/iOS 版接口失败的根因。

---

## 1. 鉴权链路（源码事实，修正之前所有推测）

### 1.1 三段式登录
```
① OAuth 授权：GET https://oauth-login.platform.hicloud.com/oauth2/v3/authorize
   client_id=101444301, redirect_uri=hms://redirect_uri, response_type=code,
   access_type=offline, scope=openid, countryCode=cn, ui_locales=zh-cn,
   state=<32B random base64url>, code_challenge=S256(verifier 48B), method=S256
   ⚠️ 授权域名是 platform.hicloud.com（不是 cloud.huawei.com）

② 换账号 AT：POST https://oauth-login.cloud.huawei.com/oauth2/v3/token
   form: grant_type=authorization_code, client_id, redirect_uri, code, code_verifier
   （不传 client_secret；返回 access_token/refresh_token/expires_in=3600）

③ 换音乐会话：POST /music-odpapp-service/v5/service/userinfo/loginex
   body: {"accessToken":"<账号AT>"}  头：不含 token 的 Digest
   返回: token(音乐token), snsUserID, expireTime(yyyyMMddHHmmss)
```

### 1.2 业务请求头（🔴 关键修正）
```http
Authorization: Digest username=app-music-baseline, nonce=<24字符随机>, created=<UTC ISO8601 无毫秒>, token=<music token>
Content-Type: application/json
```
- **不是 `Bearer <OAuth access_token>`**！之前 Flutter/iOS 全用错了。
- 无会话调用（loginex）省略 token 段。
- `created` 每请求更新、nonce 每次随机；禁止硬编码抓包旧值。
- refresh_token 实测不可用（400/1101/20171），失效就重新扫码，不做定时刷新。

### 1.3 响应成功判定
HTTP 2xx 且 `result.resultCode == "000000"`（嵌套信封 `result` 对象）。
`resultMessage` 含 "token expired / 令牌已过期 / 登录已过期" 等才判过期。

---

## 2. API 契约（全部真实验证过，来自 docs/API_CONTRACT.md）

| 功能 | 方法 | 路径 | 关键参数/字段 |
| --- | --- | --- | --- |
| 收藏/歌单发现 | POST | `/music-userbehavior-service/v3/service/favorite/simple/all` | `{targetSnsUserID,start,limit,contentTypes:[1,4,5,7]}` → favoriteInfos[] |
| 收藏判断 | GET | `/music-userbehavior-service/v1/service/favorite/simple/exist` | `?contentType=1&contentID=` → exist "0"/"1" |
| 收藏新增/删除 | POST | `/music-userbehavior-service/v1/service/favorite/create` / `/delete` | `{contentType:"1",contentID}` |
| 自建歌单详情 | GET | `/music-userbehavior-service/v1/service/playlist/detail/all` | `?playListID=<真实ID>&start=0&limit=50` → playListInfoEx |
| 收藏歌单详情 | POST | `/music-operation-service/v2/service/musiclist/detail/bymusiclistid` | `{musicListID,copyrightSwitch:"1",start,limit:"50"}` |
| 创建歌单 | POST | `/music-userbehavior-service/v1/service/playlist/create` | `{createTime,playListName,songCodes,shareFlag:"0"}` |
| 播放历史 | GET | `/music-userbehavior-service/v1/service/recentlyplayed/query?contentType=1` | → contentSimpleInfos[] |
| 搜索 | POST | `/music-search-service/v10/service/fuzzysearch` | `{contentType:"1",correct:"1",limit:"20",queryWord,start:"0"}` → songSimpleInfos[] |
| 专辑详情 | GET | `/music-metacontent-service/v1/service/album/detail/byalbumcode` | albumCode/start/limit |
| 歌手详情 | POST | `/music-metacontent-service/v2/service/artist/detail/byartistcode` | `{artistCode,songNum:20,albumNum:20}` |
| **取播放URL** | POST | `/music-play-service/v3/service/file/bycontentcode` | `{contentCode,contentType:"1",qualityType:"1"或"3"}` → **fileURL**(顶层!) |

曲目归一化：contentID→id、contentName→title、artistID[]/artistName→artists、picture.small/middle/bigImgURL→cover、contentExInfo（字符串JSON再解析）。

**取流关键**：
- qualityType `"1"`=standard(MP3)、`"3"`=lossless(FLAC)；标准档 code=1、无损 code=3 + codec 含 flac。
- 主音频用**顶层 `fileURL`**，不要盲用 `fileInfos[0].fileURL`（可能是 JSON 辅助描述）。
- `auditionTime` 不能单独判试听（全曲也有），只有 URL 含 `/preview/` 才是试听。
- 歌词地址：lyricAddress / contentExInfo.lyricAddres（历史拼写）/ lyrics.lineByLineLyric，可能是 JSON 字符串需二次解析。
- 逐字歌词 HMRC：`wordByWordLyric`，行级 LRC：`lineByLineLyric`。

---

## 3. 播放器 UI 源码事实（stage.go / shell.go / theme.go）

### 3.1 沉浸歌词页（stage.go，对应我们截图里的深色超大字）
- 背景：封面模糊放大铺底（`m.background` + DrawBackdrop）。
- 封面：从播放条位置**共享元素转场**放大（t=stageAmount 插值），圆角17，阴影 OffsetY28/Blur36。
- 歌词区在右侧（左封面右歌词两栏），行高 48 + 26×译行数。
- 逐字卡拉OK：当前行先画 accent 42% 底，再用 clip 叠加已唱部分（accent 全亮）；已唱宽度 `sungWidth()` 用 **smootherstep 插值**在音节间连续推进；边缘 3 段羽化（.5/.3/.15 × 3.5px）。
- 非当前行透明度 .38，手动滚动时 .68；字号基础 20.16（窄屏 18），距焦点越近越大（focus=1-distance/65，加 8×focus/2）。
- 点击歌词行 seek 到 `line.Time - lyricOffset`。
- 无歌词提示："暂无歌词 · 可在设置中开启第三方歌词匹配，或导入本地 .lrc / .ttml"。

### 3.2 播放条（transport）
- 位置锚点在收起/展开两态不变，只有封面放大（`transportBounds`）。
- 进度条 `stageProgressBounds`：x=244, y=height-57, width=max(60, width-244-120), h=20。
- 控件：音源徽标、收藏、循环/随机、上一首/播放/下一首、进度、音量、歌词、队列。

### 3.3 12 款主题精确色值（theme.go）
| 主题 | base | surface | text | secondary | muted | accent | 暗色 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 晨光 light | f1f0ed | ffffff | 16181c | 5c6169 | 91969e | c8202e | 否 |
| 晴海 ocean | eaf1f5 | f6fbff | 183247 | 446277 | 6c8596 | 216b9a | 否 |
| 鼠尾草 sage | eef2e9 | f8fbf4 | 273a2b | 566854 | 7a8a73 | 42784e | 否 |
| 暖砂 sand | f3ece1 | fffaf1 | 453326 | 75634e | 97836c | a8622d | 否 |
| 蔷薇 rose | f4e9ed | fff6f8 | 442a35 | 775966 | 9b7b89 | b0446a | 否 |
| 冰川 ice | e8f2f1 | f4fcfa | 203b3a | 4c706c | 73928e | 197f79 | 否 |
| 午夜蓝 midnight | 101923 | 1b2837 | e8eff7 | bac9dc | 8da1ba | 81b5f5 | 是 |
| 深林 forest | 101d19 | 1d3028 | e7f1e9 | b5cec0 | 8ca999 | 81cba3 | 是 |
| 石墨 graphite | 19191c | 29292e | f0efed | c4c2c6 | 99969f | e3ae86 | 是 |
| 夜玫瑰 wine | 21161c | 302129 | f7e8ef | d4b8c5 | b18d9e | ee99bb | 是 |
| 咖啡 coffee | 211c18 | 302820 | f5ecdf | d2bea5 | a68e73 | e7b377 | 是 |
| 曜石 obsidian | 111314 | 1c2022 | f0f3f4 | b9c4c8 | 899a9f | a5d0d7 | 是 |

---

## 4. 对 MuyuFlutter 的落地清单（下一步写代码依据）

1. 🔴 **重写鉴权**：OAuth 域名改 platform.hicloud.com；新增 loginex 换音乐 token；业务头从 Bearer 改 Digest（nonce/created/token）。这是接口能通的前提。
2. 🔴 **修取流**：qualityType 用 "1"/"3"（不是 h/sq/hr）；用顶层 fileURL；歌词从 playback 响应取 lyricAddress/lineByLineLyric/wordByWordLyric。
3. **播放页重写**：封面模糊背景 + 共享元素放大 + 两栏（左封面右歌词）+ 逐字卡拉OK（smootherstep 插值 + 羽化）+ 点击 seek。
4. **12 主题**：theme.dart 加入全部精确色值与切换。
5. **播放条**：按 transportBounds 锚点，补齐音源徽标/循环随机/音量/队列。
6. **播放模式**：列表循环/随机/单曲（已从 REA 符号加 PlayMode 枚举）。
7. **音质徽标**：按音源显示最高档（金色）。

---

## 5. 证据边界
- tinglan 是**非官方第三方客户端**，其协议来自本人账号实验，非华为公开承诺；client_id 101444301 疑似华为音乐官方 App 身份，随时可能失效，分发涉及身份冒用风险。
- 源码事实 ≠ 沐语内部实现：两者功能高度一致但未必同一份代码。凡标「源码事实」的是 tinglan 实现，用于交叉验证 REA 对沐语的观察，不宣称沐语内部就是这么写。
- 尊重 LICENSE（GPL-3.0，见 LICENSE/NOTICE），参考协议与交互设计，不整段复制代码到 Flutter（Dart 重写）。
