# 新日志取证与首页/播放根因分析（2026-11-26）

范围：只读分析 5 份 `Hmusic log`，对照当前源码基线 `5802926ca54921c88a194aef63560186059b2741`。
未修改业务代码，未提交/推送/建分支。

日志目录：`C:/Data/xwechat_files/wxid_6kxbbz4qbmya21_6f8e/msg/file/2026-11/`

---

## 0. 结论摘要

1. **12:58 日志是新包（5802926）**；11:09 是上一版 d84ff35；08:57 与 23:06 都是更早的包。23:06 的两份日志字节完全相同。
2. **首页 6 个板块不是同一种坏法**：只有「每日30首」和「榜单 24926」有真实、稳定的专用接口；「为你推荐 8011」登录后返回 200/61B/0 首；`privatefm` 与 `recommend/playlist` 稳定 HTTP 400；「新歌/热歌/心动」是 `page/detail/all` 的标签推断或 pmf001 剩余歌曲硬切三段。
3. **榜单/搜索能打开但点歌不能播，不是 UI 没调 `state.play`，也不是 Song 缺 ID**。日志里的 ID 都是真实数字；UI 在 `secondary_pages.dart:130-135`（搜索）和 `:885`（歌单/榜单详情）都调用了 `state.play`。失败发生在 `audio.playSong -> api.audioFiles -> /music-play-service/v3/service/file/bycontentcode`：HTTP 200 + 102B + 业务码 `142411 Only super diamond vip user can play the content!`，没有返回 URL。
4. **最可能的播放根因是“高音质请求失败后没有降级”**：`audioFiles` 按 hiRes→lossless→standard 请求，但 `gateway.request` 在第一个非 `000000` 业务码就抛异常，循环内没有 try/catch，导致根本走不到 `qualityType=1` 标准档兜底。`_looksUnplayable` 又不认识 `142411`，所以不会自动跳下一首。
5. **142411 是跨版本回归，不只是真 VIP 歌**：`晴天 [1092974]` 在 08:57 旧包用 standard 完整播放（4,332,025B），在 12:58 新包连续 8 次 `142411`；`Namuuhan [110745494]` 在 11:08 旧包 standard 完整播放（3,377,098B），在 12:58 新包 `142411`。
6. **990000/冷却仍然存在，但只在 token 过期、需要重新扫码之前**。12:58 开头 5 路首页请求全部 990000，`loginex` 返回 `990006 User token expired!`；扫码后 12:56:43 起首页重新请求，990000 消失。登录后刷新在本日志中是生效的，“登录后完全不刷新”未复现；但冷却可被 `refreshHome(force:true)` 清掉，重试风暴防护实际失效。
7. **有明确的重试放大器**：12:58 的 62 秒内共 149 次 HTTP，其中 `page/detail/all` 10 次、`chart/detail/bychartid` 58 次、`privatefm` 400 8 次、`recommend/playlist` 400 8 次。空卡片点一次会 `refreshHome(force:true)`，每次强制刷新约 9–10 个请求（含 24926 榜单 4–5 页分页）。
8. **没有发现 30/60 秒试听 URL 被当完整歌曲播放**：所有成功 URL 都是 `-MP3-128K-FTD.mp3`，文件大小 3.3–5.0MB；日志中没有 `_AQ`/`_PV`/`audition`。`_isAudition` 守卫存在，但当前日志没有记录请求档位/试听标志，未来若泄漏也无法从日志判断。
9. **搜索本身没有证据**：5 份日志里没有任何 `/music-search-service/v10/service/fuzzysearch` 请求，也没有搜索后点播的 `[play]` 关联。能确认的是榜单；搜索只能确认它和榜单共用同一条取流链路。

---

## 1. 日志版本判定

| 编号 | 文件 | 条数/时间范围 | 版本判定 | 判定证据 |
|---|---|---|---|---|
| L1 | `hmusic-log-2026-11-26T08-57-42-665848(1).txt` | 61 条，08:55:14–08:57:32 | **早于 d84ff35**；功能特征接近 33c8fbe 或更早，不是 5802926 | 没有 `[home] ... id= count=` 分区日志；没有 `bycolumnid`/`privatefm`/`recommend/playlist`；每日走 v2 `bymusiclistid`（L1:52）；`page/detail/all` 只有 1 次成功（L1:19） |
| L2 | `hmusic-log-2026-11-24T23-06-51-782685(2).txt` | 88 条，23:02:21–23:06:26 | **11-24 旧包，33c8fbe 或更早** | 同样是 `page/detail/all` + 收藏 + v2 `bymusiclistid`，没有 8011/privatefm/recommend；990000 连续 18 次（L2:33-88） |
| L3 | `hmusic-log-2026-11-24T23-06-53-914803.txt` | 88 条 | **与 L2 字节完全相同** | SHA256 均为 `42D2BCBA0790A01B4476C276A4006E87D021B1A30E14B56A5562DB3773EC35B3`；内容、行号、时间戳一致 |
| L4 | `hmusic-log-2026-11-26T11-09-09-830292.txt` | 67 条，11:07:37–11:08:37 | **d84ff35（10:40 提交）**，不是 5802926 | 每次首页加载请求 2 次 `column/detail/bycolumnid`（L4:30-31、33-34、36-37、40-41、47-48、62-63），每次 29,568B；每日仍是 v2 `bymusiclistid`（L4:38、49）；没有 `[home]` 分区日志/privatefm/recommend；时间 11:09 晚于 10:40、早于 12:13 |
| L5 | `hmusic-log-2026-11-26T12-58-30-053439.txt` | 263 条，12:56:24–12:57:44 | **5802926（12:13 提交）新包** | 每日改为 v3 `musiclist/detail/bymusiclistid?musicListID=a001`（L5:6-7、76-77）；每次首页加载都请求 `privatefm`/`recommend/playlist`（L5:70-75 等）；出现 `[home] featuredSongs id=8011 count=...`（L5:13、73）；出现 `990000 会话刷新失败，冷却 30 秒`（L5:12、14、16、18） |

> 结论：12:58 可以用于评价当前 HEAD；11:09 只能用于评价上一版；08:57/23:06 只能作为“以前能播”的对照，不能拿来判断 5802926 的行为。

---

## 2. 时间线（L5，新包）

| 时间 | 事件 | 证据 |
|---|---|---|
| 12:56:24.266 | 8011 栏目、recommend/playlist、a001、page/detail/all 全部 990000 | L5:2-9 |
| 12:56:24.331 | `loginex -> 990006 User Authenticate failed : User token expired!` | L5:11 |
| 12:56:24.331-332 | 4 路首页并发刷新失败，同一毫秒写 4 次“冷却 30 秒” | L5:12-18 |
| 12:56:24.751 | privatefm 990000，冷却中跳过刷新，count=0 | L5:29-32 |
| 12:56:25.760 / 26.822 | 榜单 24926 count=200（未登录也能取到） | L5:60、64 |
| 12:56:42.775 | OAuth token 成功 | L5:65 |
| 12:56:43.295 | 新会话 `loginex` 200（242,008B） | L5:66 |
| 12:56:43.788 | recommend/playlist 400 0B | L5:70-71 |
| 12:56:43.807 | 8011 200 61B，`featuredSongs count=0 code=000000` | L5:72-73 |
| 12:56:43.807 | privatefm 400 499B | L5:74-75 |
| 12:56:43.856 | 每日30首 200 66,902B，count=30 | L5:76-77 |
| 12:56:44.644 | 榜单 24926 count=200 | L5:83 |
| 12:56:44.966 | page/detail/all 200 517,671B | L5:84 |
| 12:56:52 | `我喜欢你 [39190287] standard` 播放成功（3,998,597B） | L5:128-130 |
| 12:57:00.927 | `Namuuhan [110745494]` 142411，无 URL | L5:181-182 |
| 12:57:04.427 / 04.994 | `晚风 [110748855]` 142411 两次 | L5:199-203 |
| 12:57:19.102–22.007 | `晴天 [1092974]` 142411 连续 8 次 | L5:228-250 |
| 12:57:29.163 | `倒带(Live) [1270261] standard` 播放成功（4,531,712B） | L5:252-254 |

统计（L5 全文）：

- 149 次 HTTP；`chart/detail/bychartid` 58 次；`page/detail/all` 10 次；`privatefm` 400 共 8 次；`recommend/playlist` 400 共 8 次；`bycontentcode` 18 次。
- 10 次首页加载发生在 12:56:24–12:57:11 的约 47 秒内，后 8 次在登录后。

---

## 3. 首页 6 板块请求/响应/失败矩阵（以 L5 为准）

| 板块 | 代码实际数据源 | 本次日志结果 | 失败性质 | 证据 |
|---|---|---|---|---|
| 现在就听 | `privateFm(mode:'1')`，失败则回退 `data.listen`（page 内 pmf001 嵌入歌曲） | privatefm HTTP 400（499B），count=0；回退后的 listen 数量**未找到**（没有分区日志） | 专用接口请求体/方法被拒；回退数据未计数 | `huawei_api.dart:1715`；L5:74-75、94-95、116-117 |
| 每日30首 | `daily30(a001)` → v3 GET `musiclist/detail/bymusiclistid` | 200 66,902B，count=30 | **正常** | `huawei_api.dart:1745-1762`；L5:76-77、101、119 |
| 心动模式 | `discover.heart`：只从 pmf001 批次标签 `heart/心动` 推断，否则把剩余歌曲切块 | 专用接口没有发；`privateFm(mode:'2')` 在 UI 卡片路径从未调用；数量**未找到** | 语义推断 + 硬切，数据不可信 | `huawei_api.dart:2036-2038、2049-2075`；`home_page.dart:498-499`；`app_state.dart:646-651` |
| 新歌推荐 | `discover.newSongs = sectionSongs`（所有 contentType=96 的 child）否则 `newFromEmbedded` | 没有专用请求；数量**未找到** | 语义不匹配：sectionSongs 是“分区歌曲”，不保证是新歌 | `huawei_api.dart:1991-2003、2077`；`home_page.dart:501-502` |
| 热歌速递 | `discover.hot`：pmf001 批次标签 `hot/热歌`，否则剩余切块，最后 `.take(10)` | 24926 榜单已成功取到 200 首，但没有赋给 `discover.hot`；hot 数量**未找到** | 工作正常的榜单源被闲置，卡片用的是 ≤10 首推断数据 | `huawei_api.dart:2045-2047、2095`；`discover()` 的 `copyWith` 未设置 hot（:1711-1718）；L5:60/64/83 |
| 为你推荐 | `featuredSongs(8011)`，失败/空则回退 `data.recommended` | 200 61B，`count=0 code=000000` | 服务端成功但返回空列；回退数量**未找到** | `huawei_api.dart:1712、1734-1742`；L5:72-73、96-97、112-113 |
| 推荐歌单（首页下方） | `recommend/playlist` | HTTP 400 0B，count=0 | 请求体/方法被拒，响应体为空 | `huawei_api.dart:1815-1834`；L5:70-71、98-99 |
| 音乐厅榜单 | `charts` + `chartSongs(24926)` | 榜单详情 200，count=200；可打开 | **数据正常**；点歌播放失败见第 4 节 | `huawei_api.dart:1845-1864`；L5:60/64/83/111 |

### 3.1 为什么 6 个板块都有问题

不是 6 个接口同时坏了，而是**只有 2 个板块有可靠的专用数据源**：

1. **真正独立且本次成功的只有每日30首（a001）和榜单（24926）**。L5:76-77、60/64。
2. **8011 返回空**：11:09 旧包同一路径返回 29,568B 却解析出 0 首（L4:30-31、33-34 等，且没有 `_fetchRecommendationColumn` 成功日志）；12:58 新包直接 61B 空成功（L5:72-73）。两条都说明 8011 当前不是可靠的“为你推荐”歌曲源。
3. **privatefm 和 recommend/playlist 稳定 400**：L5:74-75、70-71，且 8 次重试全部同样失败。`AppLog` 没有记录 4xx 响应体，无法看出是字段、方法还是 content-type 问题；“未找到”具体校验错误。
4. **心动/新歌/热歌没有独立请求**：`parseDiscover` 先按标签匹配，匹配不到就把 pmf001 的剩余歌曲按顺序切成 heart/new/hot 三段（`huawei_api.dart:2049-2075`）。这不是三份真实推荐，而是同一批 pmf001 歌曲的再分配；`listen` 又等于 `embeddedAll`（:2018、2093），会与这三段重叠。
5. **热歌速递明明有 200 首可用榜单，却不用**：`discover()` 已经请求了 `chartSongs(24926)`（:1675-1679），但只更新了榜单卡片的 songCount（:1701-1708），`copyWith` 没有 `hot:`（:1711-1718）。所以热歌卡继续吃 pmf001 推断数据。
6. **回退是静默的**：`recommended: featured.isNotEmpty ? featured : data.recommended`、`listen: fm.isNotEmpty ? fm : data.listen`、`daily: daily.isNotEmpty ? daily : data.daily`（:1711-1718）。8011/privatefm 失败时 UI 看到的是 page 聚合数据，不是该板块真实数据，用户很难分辨“空”还是“回退”。

### 3.2 请求风暴的机制

- `home_page.dart:509`：卡片列表为空时直接 `await state.refreshHome(force: true)`。
- `app_state.dart:242-246`：`refreshHome` 每次先 `api.clearAuthCooldown()`，再强制 `loadHome`。
- `app_state.dart:202-207`：已有 `_homeInFlight` 时，`force` 调用不是合并，而是 `await running` 后**再递归一次**。N 次点击 = N 次完整重载排队。
- 一次完整重载 = 8011 + privatefm + recommend/playlist + a001 + 24926（4–5 页）+ page/detail/all ≈ 9–10 个请求。
- 证据：L5 中 10 次 page/detail/all、58 次 bychartid、8+8 次 400；47 秒内 10 轮。

---

## 4. 播放链路与失败矩阵

### 4.1 调用链事实

| 层 | 位置 | 事实 |
|---|---|---|
| 首页歌曲行 | `home_page.dart:93-97` | `onPlay: () => state.play(song, queue: songs)` |
| 搜索歌曲行 | `secondary_pages.dart:130-135` | `state.play(state.searchResults[i], queue: state.searchResults)` |
| 歌单/榜单详情行 | `secondary_pages.dart:882-886` | `state.play(songs[i], queue: songs)` |
| 歌手页行 | `secondary_pages.dart:929-932` | `state.play(songs[i], queue: songs)` |
| AppState | `app_state.dart:751-779` | 最多试 5 首；`audio.playSong`；`audio.error==null` 即成功；否则仅当 `_looksUnplayable` 才试下一首 |
| AudioController | `audio_controller.dart:215-221` | 华为走 `api.audioFiles(song.id, upstreamQualities: song.qualities)` |
| 取流 | `huawei_api.dart:747-824` | 按档位高→低请求 `bycontentcode`，`qualityType` 7/5/3/1 |
| 业务码 | `huawei_gateway.dart:354-372` | 非 `000000` 直接抛 `HuaweiException`；`142411` 落入通用分支 |

因此：**UI 已调用 `state.play`；Song 有真实 ID；失败在 `audio.playSong` 的取流阶段。**

### 4.2 逐曲失败矩阵

| 歌曲 | ID | 日志/版本 | 上次结果 | 本次结果 | 证据 |
|---|---|---|---|---|---|
| 晴天 | 1092974 | L1（旧包）08:57:32 | `standard` 成功，4,332,025B | — | L1:60-62 |
| 晴天 | 1092974 | L5（新包）12:57:19–22 | — | `142411` 连续 8 次，无 URL | L5:228-250 |
| Namuuhan | 110745494 | L4（上一版）11:08:18/28 | `standard` 成功，3,377,098B（xz.tingmall + dbankcdn 两个 CDN 都成功） | — | L4:43-45、54-56 |
| Namuuhan | 110745494 | L5（新包）12:57:00 | — | `142411`，无 URL | L5:181-182 |
| 晚风 | 110748855 | L5 12:57:04 | — | `142411` 两次 | L5:199-203 |
| 自娱自乐 | 39484975 | L4 11:08:25 | — | 旧包也已经 `142411`（真 VIP 专享的可能性高） | L4:51-52 |
| 我喜欢你 | 39190287 | L5 12:56:52 | — | `standard` 成功，3,998,597B | L5:128-130 |
| 倒带(Live) | 1270261 | L5 12:57:29–41 | — | `standard` 成功，4,531,712B | L5:252-254、257-259、261-263 |
| 时光机 | 1082394 | L2/L3 23:02:32–38 | `standard` 成功，5,007,964B | — | L2:20-31 |
| 逍遥 | 110728206 | L1 08:55:55 / 08:57:16 | `standard` 成功，3,337,288B | — | L1:31-33、45-47 |

### 4.3 最可能根因（按证据强度）

**根因 A（高）：高音质请求 142411 后没有回退标准档。**

- `huawei_api.dart:768-772`：`hiRes -> ['7','5','3']`，首选最高档。
- `huawei_api.dart:777-785`：每次 `gateway.request` 都没有 try/catch；`huawei_gateway.dart:354-372` 遇到 `142411` 立即抛异常。
- 结果：整个 `audioFiles` 在第一个档位就退出，`wanted` 里虽然补了 `standard`（:762-764），但永远走不到。
- 与日志吻合：`晴天`/`Namuuhan` 旧包走 standard 能播；新包失败；`我喜欢你`/`倒带` 仍显示 `standard` 成功，说明“标准档本身可用”，不是账号完全无播放权限。
- 尚未确认：日志没有记录 `qualityType`，无法证明 142411 一定来自 7/5/3 中的哪一个；“请求了高音质”是由代码顺序 + 跨版本对照推断，标记为高置信但需加日志确认。

**根因 B（高）：`_looksUnplayable` 不认识 142411，不会自动跳下一首。**

- `app_state.dart:781-789` 只匹配 `142400`、`没有可用`、`无版权`、`版权`、`not available`、`不可播放`。
- `142411` / `Only super diamond vip` / `超级钻石` 都不匹配，所以 `state.play` 第一首失败就 `break`（:774），直接把错误抛给 UI。
- 证据：`晴天` 8 次连续请求更像用户反复点，而不是内部自动跳过（内部最多 5 次且这里第一次就 break）。

**根因 C（中）：`parseSong` 在缺 ID 时生成时间戳假 ID。**

- `huawei_api.dart:1385-1397`：所有字段都取不到时 `id = DateTime.now().microsecondsSinceEpoch.toString()`。
- 这类 ID 去 `bycontentcode` 必然失败，且日志里看起来像“有 ID”。
- 本次 5 份日志的所有 `[play]` 都是真实数字 ID，**未找到**假 ID 实例；列为潜在风险，不是本次已证实的根因。

**根因 D（已排除）：UI 没调用 `state.play` / Song 缺 URL。**

- UI 调用点见 4.1；`Song` 模型本来就没有 `url` 字段（`models.dart:87-121`），URL 一律实时取流，这是设计。
- 失败响应是 HTTP 200 + 业务码，不是 404/403/410，也不是 `SocketException`/`FormatException`/`RangeError`/`PlatformException`。5 份日志中**未找到**这些异常。

### 4.4 榜单/搜索单独回答

- **榜单**：`音乐厅` 的 `onTap` 是 `state.openPlaylist(chart)`（`discover_page.dart:157`），`openPlaylist` 对 `kind=='chart'` 调 `api.chartSongs`（`app_state.dart:441-442`），L5 成功 count=200。点歌后 `secondary_pages.dart:885` 调 `state.play`，随后 `晴天 [1092974]` 142411（L5:228-250）。**能打开、不能播，已证实。**
- **搜索**：5 份日志没有任何 `fuzzysearch` 请求，也没有“搜索结果 -> play”的对应记录；**未找到**直接证据。代码路径与榜单共用 `state.play`/`audioFiles`，所以如果搜索返回的 Song 也带高音质档位，会复现同一 142411。需要补一份“搜索后点歌”的日志确认。
- **搜索可诊断性缺口**：`searchAll` 对每种 contentType 的异常直接 `catch (_) { return null; }`（`huawei_api.dart:365-377`），失败时没有 `AppLog`，日志里只会看到“搜索无结果”，无法定位。

---

## 5. 990000 / 冷却 / 登录后刷新

### 5.1 仍然有 990000，但阶段明确

- L5 开头：8011、recommend/playlist、a001、page/detail/all 全部 990000（:2-9）；`loginex` 990006（:11）；favorite/subscription 也 990000（:22、27）。
- 扫码后：12:56:43 起所有首页请求重新发起（:70-84），990000 不再出现。
- L2：23:06:16–23:06:26 连续 18 次 `page/detail/all` 990000（:33-88），旧包还没有 30 秒冷却，风暴更直接。
- L4：11:07:37 同样先 990000，11:07:56 扫码后恢复（:2-15、29+）。

结论：**990000 没有消失，它对应“本地恢复的 music token 已过期”；扫码后能恢复。**

### 5.2 为什么不能自动恢复

1. `HuaweiAPI.isLoggedIn` 只判断 `gateway.session != null`（`huawei_api.dart:152-154`），不检查 `MusicSession.expireTime`（`huawei_gateway.dart:30-40`）。过期会话仍然被当成已登录，启动时 `main.dart:55-56` 直接 `loadHome()`，于是 5 路请求先打一圈 990000。
2. `restoreSession` 把 `huaweiAccountToken` 同时塞进 `refreshToken`（`app_state.dart:850-859`），而 `SessionSnapshot` 根本没有独立的 refresh token 字段（`session_store.dart:6-28`）。`gateway.refreshToken`（`huawei_gateway.dart:70-72`）也从未用于刷新。
3. `_withAuthRetry` 只能用 `gateway.accountToken` 再换一次音乐会话（`huawei_api.dart:1603-1620`）。账号 AT 也过期时，`loginex` 990006，刷新失败，只能扫码。
4. `_isAuthFailure` 只认 `990000`/`鉴权失败`/`重新登录华为账号`（`huawei_api.dart:1629-1632`），不认 `401`、`登录已失效`、`重新扫码登录`、`990006`；`gateway` 的 401 分支（`huawei_gateway.dart:328-330、363-371`）不会触发自动刷新。

### 5.3 冷却与“登录后不刷新”

- 冷却本身在 L5 生效：12:56:24 四路并发失败后写 4 次“冷却 30 秒”（:12-18）；12:56:24.751 privatefm 命中“冷却中，跳过会话刷新”（:31）。
- 但 `refreshHome(force:true)` 每次都 `clearAuthCooldown()`（`app_state.dart:243-244`），而空卡片点击和所有重试按钮都用 `force:true`（`home_page.dart:79、88、113、135、509`）。**冷却保护会被用户点一下就直接清掉**，这是 990000 风暴可能复发的结构性原因。
- **“登录后不刷新”在 L5 未复现**：`oauth_webview_page.dart:92` 明确 `await refreshHome(force:true)`，日志 12:56:43 起确实重新请求了首页。残留风险是其他登录路径（直接 `signInWithSession`/`restoreSession`）不会 `clearAuthCooldown`，若 30 秒内进入首页，`loadHome()` 会被 `_homeRetryBlockedUntil` 挡住（`app_state.dart:208-213`）。

### 5.4 并发细节

- 12:56:24 只出现 1 次 `loginex`（:11），说明 `_sessionRefresh` 单飞生效。
- 但四路 `_withAuthRetry` 各自进入 catch、各自写冷却和日志（:12-18），其中 `at==null` 的分支（:1604-1606）甚至不等待单飞，直接设冷却。功能上可接受，日志上会造成“4 次刷新失败”的误导。

---

## 6. 30/60 秒试听检查

- 成功 URL 全部是完整 MP3：
  - `39190287-MP3-128K-FTD.mp3` 3,998,597B（L5:128-130）
  - `1270261-MP3-128K-FTD.mp3` 4,531,712B（L5:252-254）
  - `1092974-MP3-128K-FTD.mp3` 4,332,025B（L1:60-62）
  - `110745494-MP3-128K-FTD.mp3` 3,377,098B（L4:43-45）
- 日志中**未找到** `_AQ`、`_PV`、`audition`、`playFragmentFlag`、30 秒/60 秒标记。
- `_isAudition`（`huawei_api.dart:841-858`）会拒绝 `_AQ/_PV` 后缀以及 `playFragmentFlag=1`/`fragmentInfo.hasFragement=1`。
- 结论：**没有证据表明试听 URL 被当成完整歌曲**。但 `audioFiles` 不记录请求/返回的 `qualityType`、`playFragmentFlag`、URL 后缀，因此“未来是否泄漏”当前不可观测；建议补日志。

---

## 7. 歌词/UI 报错

- 5 份日志的 tag 统计：`http/api/home/state/proxy/play`，**没有 `lyrics` 或 UI 异常 tag**。
- L5 只有首页/取流相关 `[state]`、`[home]`、`[play]`；**未找到**歌词或 UI 崩溃片段。
- 因此本报告不把歌词/UI 问题列为本轮播放/首页根因。

---

## 8. 当前代码对应位置与必须修改的函数/字段

### P0（直接决定“能不能播”）

| 文件/函数 | 现状 | 必须改什么 |
|---|---|---|
| `lib/protocol/huawei_api.dart` `audioFiles()`（747-824） | 每个档位的 `gateway.request` 无 try/catch；142411 直接终止；永远到不了 standard 兜底 | 每个 `qualityType` 请求单独 try/catch；`142411/142400/该档位不可用` 时 `continue` 下一档；确保最后一定尝试 `qualityType=1`；全部失败再抛“超级钻石 VIP 专享/无可用档位”；日志记录 `songCode/typeCode/code/urlSuffix/fragmentFlag` |
| `lib/protocol/huawei_api.dart` `_isAudition()`（841-858） | 只判断 URL 后缀和两个标志 | 保留；增加对 `142411` 响应“无 URL”场景的显式处理（当前走不到这里） |
| `lib/services/app_state.dart` `_looksUnplayable()`（781-789） | 不认 `142411`/超级钻石/VIP | 增加 `142411`、`super diamond`、`超级钻石`、`VIP 专享`；让 `state.play` 能跳到下一首而不是第一首就 break |
| `lib/protocol/huawei_gateway.dart` `_decodeJson()`（327-387） | 142411 落入通用异常；4xx 不记录响应体 | 为 `142411` 建明确异常类型/可识别文案；4xx 时 `AppLog` 记录截断后的响应体（脱敏 token） |

### P0（直接决定首页板块是否有真实数据）

| 文件/函数 | 现状 | 必须改什么 |
|---|---|---|
| `lib/protocol/huawei_api.dart` `discover()`（1657-1719） | 已取 24926 的 200 首，却不赋给 `hot`；每次首页都全量分页取榜单 | `hot: hotChartSongs.take(10)`（或按产品定义取前 N）；`chartSongs` 改为懒加载/缓存，首页只取榜单元数据；不要每次 `discover()` 都发 4–5 页 |
| `lib/protocol/huawei_api.dart` `parseDiscover()`（2035-2075、2077、2095） | heart/new 靠标签，缺失时把 pmf001 剩余歌曲硬切三段；hot 上限 10 | 明确每个板块的真实 column/接口；在拿到证据前不要用“剩余切三段”冒充三个推荐；至少给 `listen/heart/new/hot` 加 count 日志 |
| `lib/protocol/huawei_api.dart` `featuredSongs()`（1734-1742） | 只试 `columnId=8011`；200/61B 空成功也返回空 | 先探测 8011 的真实结构（11:09 的 29,568B 为何解析 0）；同时试 `columnID`/真实 column id；空成功时记录 body 长度/原始 item 数；不要把 `count=0` 记成 `code=000000` 就结束 |
| `lib/protocol/huawei_api.dart` `privateFm()`（1788-1810） | POST body 固定；400 时无 body 日志 | 记录 4xx body；用运行中的沐语/真机对比 method/body/header；确认是否需要 GET 或额外字段；失败后不要静默回退成 pmf001 并当作“现在就听” |
| `lib/protocol/huawei_api.dart` `recommendedPlaylists()`（1815-1834） | POST body 固定；400 0B | 同上，先抓 400 body；尝试 GET/query 或正确 contentType；失败时日志不要只写“空响应” |

### P1（重试风暴/鉴权）

| 文件/函数 | 现状 | 必须改什么 |
|---|---|---|
| `lib/services/app_state.dart` `loadHome()`/`refreshHome()`（185-247） | `force` 时清冷却；in-flight 时 force 调用排队递归；N 次点击 = N 次全量刷新 | force 只保留“一次重跑”标志；区分“登录后强制刷新”和“UI 重试”；UI 重试不清 auth 冷却；加重试最小间隔/单飞 |
| `lib/services/app_state.dart` `_guard()`（943-964） | 990000 时设 30 秒 `_homeRetryBlockedUntil` | 保留；但确保所有登录成功路径调用 `api.clearAuthCooldown()`；错误文案区分“token 过期需扫码”和“网络失败” |
| `lib/protocol/huawei_api.dart` `_isAuthFailure()`（1629-1632） | 只认 990000/鉴权失败/重新登录华为账号 | 增加 `401`、`登录已失效`、`重新扫码登录`、`token expired`、`990006` |
| `lib/protocol/huawei_api.dart` `signInWithSession()`/`signInWithCode()`（172-207） | 登录后不主动清冷却 | 设置 session 后 `clearAuthCooldown()`；或由 gateway 的 `onSessionChanged` 统一清 |
| `lib/services/app_state.dart` `restoreSession()`（846-896） | `refreshToken: huaweiAccountToken`；不检查 `expireTime` | `SessionSnapshot` 增加独立 `huaweiRefreshToken` 字段；不要把 accountToken 冒充 refreshToken；`expireTime` 过期时不要先发 5 路业务请求，直接进入“需重新登录”状态 |

### P1（诊断/防假 ID）

| 文件/函数 | 现状 | 必须改什么 |
|---|---|---|
| `lib/protocol/huawei_api.dart` `parseSong()`（1385-1397） | 缺 ID 时生成时间戳假 ID | 改为空字符串/`unknown`，UI 对空 ID 禁用播放并提示；避免拿假 ID 请求 `bycontentcode` |
| `lib/protocol/huawei_api.dart` `_homeSoft()`（1641-1654） | 空列表也记 `code=000000`，没有字节数/原始条数 | 记录 `bytes/rawCount/parsedCount`，区分“空成功”和“有数据但解析 0” |
| `lib/protocol/huawei_api.dart` `searchAll()`（360-411） | 每种 contentType 异常被 `catch (_) return null` 吞掉 | 每种类型记录 `AppLog`（成功条数/异常码）；搜索后点播失败才能定位 |
| `lib/services/app_log.dart` | 只存 2000 条，环形覆盖 | 对取流/首页关键路径保留更久或单独 ring；至少保证一次完整“首页 6 板块 + 3 次播放”不被冲掉 |

---

## 9. 实现子代理的文件边界

### 优先只改（本轮）

- `lib/protocol/huawei_api.dart`
- `lib/protocol/huawei_gateway.dart`
- `lib/services/app_state.dart`
- `lib/services/audio_controller.dart`（仅在需要把 142411 映射成“可跳过”错误时）

### 本轮不要改（避免和并行 UI/歌词子代理冲突）

- `lib/widgets/home_page.dart`
- `lib/widgets/discover_page.dart`
- `lib/pages/secondary_pages.dart`
- `lib/widgets/player_bar.dart`
- `lib/widgets/immersive_player.dart`（歌词/播放器 UI 正在并行改）

> 说明：热歌卡改用 24926、心动卡改用 privatefm(mode 2)、空卡片不再全量刷新，这三件事都能在 `huawei_api.discover()` / `app_state` 层完成，不必动 UI。若必须改 `home_page.dart:486-535`（`_playCard`）或 `:79/88/113/135`（重试按钮），先与父代理串行合入，避免和 UI 子代理互相覆盖。

---

## 10. 验证方法（实现后按顺序跑）

### 10.1 窄单元测试（不跑全量 flutter test）

1. **取流降级**：fake gateway 对 `qualityType=7` 返回 142411，对 `qualityType=1` 返回 200 + 合法 URL；断言 `audioFiles('1092974')` 返回 `standard` 文件而不是抛异常。
2. **全部档位失败**：所有 qualityType 都 142411；断言抛出可识别的“VIP 专享/无可用档位”，且 `state.play` 能跳到下一首（`_looksUnplayable` 为 true）。
3. **首页 hot 映射**：fake `chartSongs(24926)` 返回 200 首；断言 `discover.hot` 非空且来自榜单，不再来自 pmf001 切块。
4. **8011 空成功**：fake 61B/`000000`；断言 `featuredSongs` 返回空、日志包含 `bytes=61/rawCount=0`，且不把 `data.recommended` 静默当成 8011 成功。
5. **重试合并**：连续 5 次 `refreshHome(force:true)`，断言底层 `discover()` 只执行 1–2 次，不产生 5 轮 9 请求。
6. **鉴权分类**：401/`登录已失效`/990006 都进入刷新分支；刷新失败后 30 秒内不再发业务请求。

### 10.2 真机/联调探针（必须记录 body）

1. 用同一账号对 `110745494`、`1092974` 分别请求 `qualityType=1/2/3/5/7`，记录每个业务码；确认 standard 是否可播。这是判定“142411 是档位问题还是整曲权限”的唯一硬证据。
2. 抓 `privatefm` 400 的 499B body 和 `recommend/playlist` 400 的 0B 响应头；对比沐语真实请求的方法/body/Content-Type。
3. 抓 8011 的 61B body；同时用 `columnID=8011`、`columnId=recom_exclusive`、以及 page/detail/all 里的真实 column id 各试一次，记录原始条数与结构。
4. 搜索一次并点歌，确认 `fuzzysearch` 返回的 `contentID` 与 `qualityType` 请求；当前 5 份日志没有搜索证据。

### 10.3 手工回归

1. 冷启动且本地 token 已过期：不应先发 5 路首页请求再报 990000；应直接提示重新登录，或只发一次轻量校验。
2. 扫码登录后：首页只重载一次；`每日30首` 30 首、榜单 200 首仍正常；8011/privatefm/recommend 的失败有明确分区错误，不互相回退冒充。
3. 连续点 5 张空卡片：请求数应有上限（例如 ≤2 轮），不应出现 10 轮 page/detail/all + 58 次榜单分页。
4. 播放 `晴天/1092974`：若 standard 可用则必须出声；若确实 VIP 专享，提示“超级钻石 VIP 专享”，且不连续打 8 次取流。

---

## 11. 证据缺口（明确写“未找到”）

- **listen/heart/new/hot 的具体条数**：日志没有这四个分区的 `[home] ... count=`，**未找到**。只能确认 privatefm=0、8011=0、daily=30、chart=200。
- **8011 的 29,568B 响应体**：只有大小，没有 body；无法判断是解析器不匹配还是空栏目。
- **privatefm 400 / recommend 400 的响应体**：`AppLog` 未记录；无法给出确定字段修复。
- **`bycontentcode` 的 `qualityType`**：日志只记录成功后的档位名，不记录请求参数；142411 对应哪个档位是推断，**未找到**直接字段。
- **搜索请求/搜索点播**：5 份日志均无 `fuzzysearch`，**未找到**。
- **歌词/UI 异常**：日志无 `lyrics`/UI tag，**未找到**。
- **30/60 秒试听泄漏**：无 `_AQ/_PV/audition`，**未找到**；但当前日志也不足以证明未来不会发生。
