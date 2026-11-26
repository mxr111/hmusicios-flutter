# 首页接口日志取证报告（华为音乐推荐流）

日期：2026-11-26
范围：首页聚合 `page/detail/all`、五张功能卡（现在就听 / 每日30首 / 心动模式 / 新歌推荐 / 热歌速递）、「为你推荐」、推荐歌单、音乐厅榜单。
代码基线：`d84ff35`（2026-11-26 10:40:20 +0800），工作区干净。

## 0. 结论摘要

1. **首页聚合接口本身没有坏。** 11/26 登录后 `page/detail/all` 返回 200 / 514830B；11/24 也曾返回 200 / 520833B、520742B。真正的问题是聚合之后「每个板块各取各的曲库」这一层。
2. **两份日志都不能证明当前 HEAD 的修复效果。** 11/26 日志时间 08:55–08:57，而当前 `huawei_api.dart` / `home_page.dart` / `app_state.dart` 的修改时间是 09:41–09:49，提交时间是 10:40；11/24 日志则早于 11/26 的修改。日志记录的是旧构建。
3. **日志对应的旧构建只拉了首页聚合；除用户点开的 a001 外，没有 a003/a004/a006、privatefm、heartbeatfm、8011 栏目请求。** 11/26 唯一一次 `musiclist/detail/bymusiclistid` 在 08:57:22，比首页成功晚约 93 秒，且请求体未记录，不能证明是哪个 a00x（报告中凡不能证明的地方写“未找到”）。
4. **当前代码仍会确定性地造成板块重复。** 即使 a001/a003/a004/a006 全部成功，「现在就听」也会等于「为你推荐」（都用 a004），「心动模式」也会等于「热歌速递」（都用 a006）；若只有 a001 成功，则「为你推荐 / 现在就听 / 心动」全部等于 a001。见 `app_state.dart:274-282`。
5. **当前代码根本没有请求 privatefm 和 heartbeatfm。** 四路并发只包含 a001/a003/a004/a006（`app_state.dart:261-266`），而首页卡片按 `privatefm` / `heartbeatfm` 取标题和封面（`home_page.dart:317-341`），数据源不一致。
6. **当前代码在最需要「为你推荐」独立数据时反而跳过了 8011 私享好歌栏目。** `discover()` 只要解析出 998 功能卡就直接 return（`huawei_api.dart:1569`），不会执行 8011 栏目详情请求（`huawei_api.dart:1570-1578`）。
7. **登录后的首次加载可能被 30 秒冷却吞掉。** 11/26 启动失败到重新登录成功间隔 33.6 秒，刚好越过 30 秒；如果用户 30 秒内完成登录，OAuth 回调里的 `loadHome()` 会因为冷却直接 return，界面保持空/旧数据，且不会自动补拉。见 `app_state.dart:193`、`997-1001`、`oauth_webview_page.dart:91`。

## 1. 日志来源与可信度

| 文件 | 大小 / 条目 | SHA256 | 导出时间 | 说明 |
| --- | --- | --- | --- | --- |
| `C:/Data/xwechat_files/wxid_6kxbbz4qbmya21_6f8e/msg/file/2026-11/hmusic-log-2026-11-24T23-06-51-782685(1).txt` | 8293B / 88 entries | `42D2BCBA0790A01B4476C276A4006E87D021B1A30E14B56A5562DB3773EC35B3` | 2026-11-25 10:05:49 | 与无 `(1)` 的同名文件字节完全相同 |
| `C:/Data/xwechat_files/wxid_6kxbbz4qbmya21_6f8e/msg/file/2026-11/hmusic-log-2026-11-26T08-57-42-665848.txt` | 5971B / 61 entries | `08FAACF89DF68EC771F20228C47B1D8C384EC9E05848C930A9154BE079708565` | 2026-11-26 09:16:19 | 运行时 08:55–08:57，早于当前修改与提交 |

可信度限制：

- `AppLog` 明确不记录 token 与查询串（`lib/services/app_log.dart:3`）；HTTP 行只记录 `method + url.path`（`lib/protocol/huawei_gateway.dart:286-289`）。因此无法从日志读出 a001/a003/a004/a006、栏目 ID 或 POST body。
- 11/26 日志的运行时 08:55–08:57 早于 `lib/protocol/huawei_api.dart`（09:41）、`lib/widgets/home_page.dart`（09:46）、`lib/services/app_state.dart`（09:49）的修改，也早于 `d84ff35` 的提交时间 10:40。**该日志不是当前代码的验证日志。**
- 11/24 日志晚于 `33c8fbe`（2026-11-24 22:17:30）且早于 11/26 修改，最可能对应 `33c8fbe` 构建；该构建没有 `_hydrateHomeFeatures`、没有 `daily` 字段、没有 30 秒冷却。

## 2. 11/24 日志时间线

| 时间 | 行号 | 事件 | 结果 |
| --- | --- | --- | --- |
| 23:02:21.872 / 23:02:21.905 | L2-L3 | GET/POST `userinfo` | 404 / 9B |
| 23:02:21.945 | L4 | GET `subscription/detail` | 200 / 2547B |
| 23:02:23.941 | L5 | GET `page/detail/all?pageType=7&hasRecommend=1` | 200 / 520833B |
| 23:02:24.919 | L6 | 同一首页接口再次请求 | 200 / 520742B |
| 23:02:25.902–23:02:30.309 | L7-L18 | `favorite/simple/all` v5 ×11 + v3 ×1 | 全部 200，37KB–113KB |
| 23:02:32.147–23:02:38.904 | L19-L31 | `file/bycontentcode` + `[play] 时光机` + 3 次音频代理 | 200 / 206 |
| 23:06:16.059–23:06:21.040 | L33-L80 | 首页接口连续 16 次 | HTTP 200 但仅 66B，业务码 `990000 System error!` |
| 23:06:25.465–23:06:26.526 | L81-L89 | 首页接口再连续 3 次 | 同上；合计 19 次 `990000` |

计数（Python 解析）：

- `page/detail/all` 共 21 次：2 次成功（520833B / 520742B）+ 19 次 `990000`（每次 HTTP 200 / 66B）。
- `990000` 共 19 次，`华为鉴权失败，请重新登录华为账号` 共 19 次；前 16 次集中在约 5 秒内，19 次总计约 10.5 秒。
- `server` 侧没有任何 `musiclist/detail/bymusiclistid`、`chart/detail/bychartid`、`privatefm`、`recommend/playlist`、`column/detail` 请求。

问题判断：

- **首页聚合成功，但没有为任何卡片发起独立请求。** 旧构建的首页卡片只能复用 `page/detail/all` 解析出来的同一批歌。
- **旧构建没有 30 秒冷却。** 鉴权失效后自动重试形成风暴（19 次 / 10.5 秒），这是 11/24 最明显的失败点。
- **旧构建也没有 `_homeLoading`。** 23:02:23.941 与 23:02:24.919 两次首页请求相隔不到 1 秒，属于启动期重复拉取。
- **未找到歌词相关请求或报错。** 11/24 日志中没有 `[lyric]`、`LRC`、`HMRC`、歌词下载失败等字样。

## 3. 11/26 日志时间线

| 时间 | 行号 | 事件 | 结果 |
| --- | --- | --- | --- |
| 08:55:14.670 | L2-L4 | GET `page/detail/all` | HTTP 200 / 66B，`990000 System error!`，`华为鉴权失败` |
| 08:55:14.727 | L5-L7 | POST `favorite/simple/all` | HTTP 200 / 66B，`990000` |
| 08:55:14.827 | L10-L11 | GET `subscription/detail` | HTTP 200 / 66B，`990000` |
| 08:55:48.302 | L12 | POST `oauth2/v3/token` | 200 / 1690B |
| 08:55:48.645 | L13 | POST `userinfo/loginex` | 200 / 239837B |
| 08:55:48.778 / 08:55:48.806 | L14-L15 | GET/POST `userinfo` | 404 / 9B |
| 08:55:49.169 | L19 | GET `page/detail/all` | **200 / 514830B（成功）** |
| 08:55:55.568–08:55:55.802 | L30-L34 | 取流 + `[play] 黄龄 逍遥 新歌-11.25上线` | 200 / 206 |
| 08:56:13.468–08:56:13.992 | L36-L40 | `chart/detail/bychartid` ×5 | 200（457KB/459KB/438KB/442KB/1284B） |
| 08:57:04.241–08:57:04.509 | L41-L43 | `chart/detail/bychartid` ×3 | 200（361KB/378KB/1038B） |
| 08:57:16.945–08:57:21.137 | L44-L51 | 同一首歌再次取流 / 播放 | 200 / 206 |
| 08:57:22.278 | L52 | POST `musiclist/detail/bymusiclistid` | 200 / 307684B（全日志唯一一次） |
| 08:57:30.416–08:57:31.091 | L53-L57 | `chart/detail/bychartid` ×5 | 200，大小与 08:56 那批一致 |
| 08:57:31.985–08:57:32.371 | L58-L62 | 取流 + `[play] 晴天` | 200 / 206 |

计数（Python 解析）：

- `page/detail/all` 共 2 次：08:55:14 失败 `990000`，08:55:49 成功 514830B。
- `990000` 共 3 次（首页、收藏、订阅），`华为鉴权失败` 2 次。
- `chart/detail/bychartid` 共 13 次，全部 200；说明音乐厅榜单链路是通的。
- `musiclist/detail/bymusiclistid` 共 1 次，08:57:22.278，200 / 307684B。
- `privatefm`、`recommend/playlist`、`column/detail`、`a001`、`a003`、`a004`、`a006`、`8011` 在日志文本中出现次数均为 **0**。

问题判断：

- **冷启动时持久化的音乐 token 已失效。** 08:55:14 三个业务接口同时 `990000`，随后 OAuth + loginex 成功，首页立即恢复 200。日志没有 token 值，但“990000 → 重新登录 → 同一接口 200”的时序足以证明旧会话失效、重新登录可恢复。
- **登录成功后的首页聚合是好的。** 514830B 响应说明旧构建拿到了完整首页 JSON。
- **首页成功后没有立刻出现任何分卡请求。** 08:55:49 之后直到 08:57:22 才有唯一一次 `musiclist/detail/bymusiclistid`，中间是 13 次榜单请求。旧构建没有 a003/a004/a006/privatefm/heartbeatfm 的取数。
- **唯一一次 a001 请求很可能是用户点了「每日30首」卡片。** 旧构建的 `DiscoverData` 没有 `daily` 字段（`git show 33c8fbe:lib/protocol/huawei_api.dart`），卡片点击会从 `discover.playlists` 找 id=`a001` 再打开歌单；`MUYU_HOME_RECOMMENDATION.md:83` 也把它解释为 a001。但日志没有记录 POST body，**无法证明 musicListID 就是 a001；这一点只能标为高概率推断，证据不足处为“未找到直接证据”。**
- **未找到歌词/播放报错。** 只有 `[play]` 和代理 206，没有歌词请求或失败日志。

## 4. 首页板块请求 / 响应矩阵

| 板块 | REA 期望的独立来源 | 当前代码动作 | 日志证据 | 是否拿到独立数据 |
| --- | --- | --- | --- | --- |
| 首页聚合 | GET `page/detail/all?pageType=7&hasRecommend=1` | `HuaweiAPI.discover()`，`huawei_api.dart:1563-1566` | 11/26 L19 200/514830B；11/24 L5-L6 200/520KB | 是（聚合数据） |
| 每日30首 | a001 歌单详情（`contentType=4`） | `app_state.dart:262` → `playlistSongs`（POST `musiclist/detail/bymusiclistid`） | 11/26 L52 有一次 200/307684B，但请求体未记录 | 旧构建仅点击时拉；当前代码启动时拉，未验证 |
| 新歌推荐 | a003（`newsongrecommend`） | `app_state.dart:263` → 同一 POST 接口 | 未找到可归属 a003 的请求 | 当前代码会拉，日志未验证 |
| 为你推荐 | `recom_exclusive` / 8011 栏目详情（GET `column/detail/bycolumnid`） | `huawei_api.dart:1569` 有 features 时直接 return；`app_state.dart:264/274` 改用 a004 | 11/26/11/24 均 0 次 `column/detail` | **否**（被 a004 替代） |
| 现在就听（Music FM） | `privatefm` / pfm001 | `app_state.dart:261-266` 没有 privatefm；`listen` 用 a004 或 fallback | 0 次 `privatefm` | **否** |
| 心动模式 | `heartbeatfm` / pfm002 | `app_state.dart:261-266` 没有 heartbeatfm；`heart` 用 a006 或 daily | 0 次 `privatefm`/`heartbeatfm` | **否** |
| 热歌速递 | a006（`millionfavoriterecommend`） | `app_state.dart:265` → 同一 POST 接口 | 未找到可归属 a006 的请求 | 当前代码会拉，日志未验证 |
| 音乐厅榜单 | GET `chart/detail/bychartid` | `HuaweiAPI.chartSongs`，`huawei_api.dart:1667-1683` | 11/26 L36-L40、L41-L43、L53-L57 共 13 次 200 | 是 |
| 推荐歌单 | 首页 `columnInfoExs` / `recommend/playlist` | `parseDiscover` 解析首页歌单 | 无独立 `recommend/playlist` 请求；首页 514830B 内含歌单 | 是（来自聚合） |
| 收藏/歌单库 | v5 `favorite/simple/all` | `loadLibrary`，`app_state.dart:611-625` | 11/26 L17-L29 共 12 次；11/24 L7-L18 共 12 次 | 是，但不属于首页卡片 |

结论：

- 日志能证明的“独立请求”只有榜单和一次歌单详情；无法证明 a003/a004/a006 或 privatefm/heartbeatfm 被请求。
- 当前代码可以证明会发 a001/a003/a004/a006 四路请求，但**不会发 privatefm/heartbeatfm/8011**；这四路中任何一路失败都会进入跨卡片回填。

## 5. 失败点（按影响排序）

### F1（P0）现在就听 / 心动没有独立数据源，且「为你推荐」被错配到 a004

证据：

- `lib/services/app_state.dart:261-266`：并发列表只有 `dailyrecommend / newsongrecommend / favoritesrecommend / millionfavoriterecommend`，没有 `privatefm`、`heartbeatfm`。
- `lib/services/app_state.dart:274-282`：`recommended` 和 `listen` 都优先取 `personal`（a004）；`heart` 优先取 `hot`（a006）。
- `lib/widgets/home_page.dart:317-341`：卡片分别按 `privatefm`（pfm001）、`heartbeatfm`（pfm002）、`dailyrecommend`（a001）、`newsongrecommend`（a003）、`millionfavoriterecommend`（a006）找 feature 标题/封面。
- `rea_evidence/MUYU_HOME_RECOMMENDATION.md:33-45`：REA 结论是「为你推荐」走 `recom_exclusive` / 8011 栏目，不是收藏推荐 a004。
- `rea_evidence/MUYU_HOME_RECOMMENDATION.md:91-96`：真实 998 功能卡的 serviceType 包含 `privatefm / dailyrecommend / newsongrecommend / heartbeatfm / millionfavoriterecommend / favoritesrecommend`。

影响：

- 即使四个 a00x 请求全部成功，「现在就听」和「为你推荐」也是同一批 a004；「心动模式」和「热歌速递」也是同一批 a006。
- 若 a004 为空，「现在就听」会退到 a006 或 a001；若 a006 也为空，「心动」退到 a001。用户看到的就是“除了每日三十首其他都一样”。

### F2（P0）跨卡片 fallback 链本身就是重复的来源

证据：

- `lib/services/app_state.dart:274-284`：

```dart
final recommended = personal.isNotEmpty
    ? personal
    : (hot.isNotEmpty ? hot : (daily.isNotEmpty ? daily : data.recommended));
final listen = personal.isNotEmpty
    ? personal
    : (hot.isNotEmpty ? hot : (daily.isNotEmpty ? daily : data.listen));
final heart = personal.isNotEmpty && hot.isNotEmpty
    ? hot
    : (daily.isNotEmpty ? daily : data.heart);
```

- 同一函数注释 `app_state.dart:239-241` 写的是“按 serviceType 并发拉取 a001/a003/a004/a006，互不复用”，但 274-282 行明确在互相复用。

确定性结果：

| 成功情况 | 现在就听 | 每日30首 | 心动模式 | 新歌推荐 | 热歌速递 | 为你推荐 |
| --- | --- | --- | --- | --- | --- | --- |
| 四路全成功 | a004 | a001 | a006 | a003 | a006 | a004 |
| 只有 a001 成功 | a001 | a001 | a001 | 首页新歌/空 | 空 | a001 |
| a004 失败、a006 成功 | a006 | a001 | a006 | a003 | a006 | a006 |
| 四路全失败 | 首页 listen/空 | 空 | 首页 heart/空 | 首页 newSongs/空 | 首页 hot/空 | 首页 recommended/空 |

这张表是“其他卡片都一样”的直接代码证据；不需要等到日志复现。

### F3（P0）有 998 功能卡时不再拉 8011 私享好歌栏目

证据：

- `lib/protocol/huawei_api.dart:1567-1569`：`if (data.features.isNotEmpty) return data;`
- `lib/protocol/huawei_api.dart:1570-1578`：只有 `features.isEmpty` 且 `recommended.isEmpty` 时才请求 `column/detail/bycolumnid`。
- `lib/protocol/huawei_api.dart:1585-1606`：8011 栏目请求实现是完整的，但当前会被上面的 early return 跳过。
- `lib/protocol/huawei_api.dart:35` 注释与 `MUYU_HOME_RECOMMENDATION.md:33-38` 都说明「为你推荐」应来自该栏目。

影响：

- 首页 JSON 一旦有 998 功能卡，「为你推荐」就永远拿不到 8011 的真实私享好歌；只能被 a004/a006/a001 顶替。
- 11/26 与 11/24 日志中 `column/detail` 出现次数均为 0，与代码路径一致（旧构建同样没有拉 8011）。

### F4（P0）30 秒冷却会吞掉登录后的首次加载和错误页“重试”

证据：

- `lib/services/app_state.dart:989-1008`：`_guard` 捕获到含 `990000` 或 `重新登录` 的错误后，把 `_homeRetryBlockedUntil` 设为当前时间 +30 秒。
- `lib/services/app_state.dart:191-195`：`loadHome()` 在冷却期内直接 `return`，不加载、不提示、不排队。
- `lib/widgets/oauth_webview_page.dart:88-92`：OAuth 成功后调用的是 `widget.state.loadHome()`，没有清冷却。
- `lib/widgets/home_page.dart:70-85`：错误面板的“重试”按钮调用 `state.loadHome`，同样会被冷却挡住；只有顶部刷新按钮 `home_page.dart:145-149` 调用 `refreshHome`，而 `refreshHome` 才会清冷却（`app_state.dart:233-236`）。

日志对照：

- 11/26 08:55:14.670 首次 `990000` 设置冷却至约 08:55:44.670。
- OAuth token 成功是 08:55:48.302，loginex 是 08:55:48.645，首页成功是 08:55:49.293，间隔约 33.6 秒 / 34.6 秒，刚好越过 30 秒。
- 如果用户 30 秒内完成扫码登录，OAuth 回调里的 `loadHome()` 会命中 `_homeRetryBlockedUntil` 直接返回，首页保持空/旧数据；用户必须手动点顶部刷新，或等 30 秒后重新进入首页。

这不是日志里已经发生的失败，而是由时间差和代码路径共同证明的高概率缺陷；11/26 只是“刚好没撞上”。

### F5（P1）990000 不会触发一次自动换会话

证据：

- `lib/protocol/huawei_gateway.dart:210-218`：`_withSessionRetry` 只在 `statusCode == 401` 且有 `accountToken` 时才 `exchangeMusicToken` 后重试。
- `lib/protocol/huawei_gateway.dart:354-361`：业务码 `990000` 直接抛 `华为鉴权失败，请重新登录华为账号`，没有设置 `statusCode: 401`。
- `lib/services/app_state.dart:899-905`：启动恢复会话时其实已把 `huaweiAccountToken` 传给网关，具备自动换会话的条件。
- 11/26 L2-L4 → L12-L13 → L19：`990000` 后用户重新 OAuth + loginex，同一首页接口立刻 200。

影响：

- 持久化 music token 失效但 account token 仍可用时，应用不会尝试恢复，只会报“重新登录”。
- 11/26 的恢复依赖用户手动重新扫码，而不是自动重试。

### F6（P1）四路卡片请求的失败被静默吞掉，且没有分卡日志

证据：

- `lib/services/app_state.dart:252-259`：每路 `fetch` 都包在 `_soft(...)` 中。
- `lib/services/app_state.dart:603-609`：`_soft` 捕获所有异常后返回空列表，不记录错误。
- `lib/protocol/huawei_gateway.dart:286-289`：HTTP 日志只记录 `method + url.path`；a001/a003/a004/a006 都走同一个 `musiclist/detail/bymusiclistid`，日志无法区分。
- `_hydrateHomeFeatures` 内部没有 `AppLog.add`；只有 8011 的 `_fetchRecommendationColumn` 有成功/失败日志（`huawei_api.dart:1598-1602`）。

影响：

- 若首页聚合成功、四路卡片请求失败（例如 990000），`_guard` 不会看到错误，用户也看不到错误面板；只是卡片空掉或复用别的列表。
- 事后导出的日志只有 4 行相同的 POST path，无法定位是哪张卡失败、失败码是什么（除非失败码恰好让网关写了 `[api]`）。

### F7（P2）刷新/加载状态会让“换一批”看起来没反应

证据：

- `lib/services/app_state.dart:191-196`：`_homeLoading` 为 true 时 `loadHome` 直接 return；`refreshHome` 先递增 seed 再调用 `loadHome`，若此时已有加载在途，刷新会被丢弃（`app_state.dart:233-236`）。
- `lib/services/app_state.dart:297-314`：刷新只轮换部分列表；`charts` 原样保留（303 行），`hot` 原样保留（309 行）。所以「热歌速递」卡片和榜单不会因“换一批”变化。
- `lib/services/app_state.dart:224`：无论 `data` 是否为空，`discoverLoaded` 都设为 true；空结果后切回首页不会自动重试（`selectTab` 的 `!discoverLoaded` 条件见 847 行）。
- `lib/widgets/home_page.dart:145-149`：界面没有 `RefreshIndicator` / 下拉刷新，只有顶部图标；全仓库未找到 `pullToRefresh` 实现。

影响：

- 用户点“换一批”时，热歌卡和榜单第一首不变；若同时有一次加载在途，整个刷新被静默丢弃。
- 空结果被标记为已加载，回到首页不会自动再拉。

### F8（P2）解析层的跨板块别名仍然存在

证据：

- `lib/protocol/huawei_api.dart:1836-1838`：`listenFinal = listen.isNotEmpty ? listen : recommendedFinal`。
- `lib/protocol/huawei_api.dart:1855`：`heart: heart.isNotEmpty ? heart.take(30) : radioSongs`。
- `lib/protocol/huawei_api.dart:1839`：`newFinal = newOnly.isNotEmpty ? newOnly : allSongs`。

影响：

- 即使 `_hydrateHomeFeatures` 不运行（例如 998 解析失败、features 为空），解析层也会让「现在就听」复制「为你推荐」、「心动」复制电台、「新歌」复制全部首页歌曲。
- 这与 F1/F2 叠加，造成“解析层 + 状态层”双重复用。

### 非根因项

- **缓存：未找到华为首页缓存实现。** `rg cache|缓存` 在 `app_state.dart` / `huawei_api.dart` / `huawei_gateway.dart` / `home_page.dart` 中只命中一条“与网易云不共用缓存”的注释（`app_state.dart:145`）。缓存不是本次重复/不刷新的原因。
- **去重：只在单列表内去重。** `_dedupeSongs`（`huawei_api.dart:1863-1873`）按 song id 去重，但不去重不同卡片之间；跨卡片复用后仍然重复。
- **并发：不是重复的直接原因，但放大了鉴权问题。** 四路 `Future.wait`（`app_state.dart:267-269`）在 401 时可能各自触发一次 `exchangeMusicToken`，当前没有 single-flight；日志未观察到该场景，标为风险。
- **`homeSongs.first`：当前首页五张卡不再直接使用它。** `home_page.dart:34-36` 的「为你推荐」主列表用 `discover.recommended` 再退 `homeSongs`；`player_bar.dart:188-189` 的全局播放仍用 `homeSongs.first`。旧构建的卡片 fallback 到 `state.homeSongs`（`git show 33c8fbe:lib/widgets/home_page.dart` 的 `_cards`），这是旧日志症状的直接来源，但不是当前代码的主要重复路径。

## 6. 最可能的根因

**根因 A（首页“其他都一样”）：卡片数据源建模错误 + 跨卡片回填。**

当前实现把 6 个 998 serviceType 压缩成 4 个 a00x 请求，漏掉 `privatefm` 和 `heartbeatfm`；再用 a004 填「为你推荐/现在就听」、用 a006 填「心动/热歌」、用 a001 填所有剩余空位。只要任意一路为空，就会把同一批歌复制到其他卡片。`app_state.dart:274-282` 是确定性的代码证据。

**根因 B（“为你推荐”不是私享好歌）：8011 栏目被 features 短路。**

`huawei_api.dart:1569` 的 early return 使 `recom_exclusive / 8011` 永远不请求；`app_state.dart:264/274` 用 `favoritesrecommend`（a004）替代。REA 文档明确 8011 才是私享好歌来源。

**根因 C（登录后不刷新/空首页）：30 秒冷却不区分“鉴权失败”和“刚登录成功”。**

`app_state.dart:193/997-1001` 的冷却在登录回调里没有清除；OAuth 成功后的 `loadHome()`（`oauth_webview_page.dart:91`）可能直接 return。11/26 的 34 秒时间差只是刚好绕过，不能证明用户每次都能绕过。

**根因 D（鉴权恢复弱）：990000 不触发自动换会话。**

`huawei_gateway.dart:210-218` 只处理 401；`990000` 在 359-361 被直接抛成“重新登录”。11/26 日志证明重新登录可以恢复，但应用没有自动利用已保存的 account token。

## 7. 当前代码对应位置

| 文件 / 函数 | 行号 | 作用 / 问题 |
| --- | --- | --- |
| `lib/services/app_state.dart` `loadHome` | 178-229 | 首页入口；191-196 `_homeLoading` / 冷却；199 `discover()`；200-202 features 才 hydrate；217-221 `homeSongs` 单一 fallback；224 无条件 `discoverLoaded=true` |
| `lib/services/app_state.dart` `refreshHome` | 233-237 | 清冷却、seed++、再 `loadHome`；加载中会被丢弃 |
| `lib/services/app_state.dart` `_hydrateHomeFeatures` | 242-295 | **核心问题函数**；261-266 只拉 a001/a003/a004/a006；274-282 跨卡片 fallback |
| `lib/services/app_state.dart` `_rotateDiscover` | 297-314 | 303 charts 不轮换；309 hot 不轮换 |
| `lib/services/app_state.dart` `_soft` | 603-609 | 吞掉四路卡片异常，无日志 |
| `lib/services/app_state.dart` `_guard` | 989-1008 | 997-1001 对 `990000`/`重新登录` 设 30 秒冷却 |
| `lib/protocol/huawei_api.dart` `discover` | 1563-1580 | **1569 有 features 直接 return**；1570-1578 才拉 8011 |
| `lib/protocol/huawei_api.dart` `_fetchRecommendationColumn` | 1585-1606 | 8011 栏目实现；当前被短路 |
| `lib/protocol/huawei_api.dart` `parseDiscover` | 1713-1860 | 1798-1801 解析 998；1836-1838 listen 复制 recommended；1855 heart 复制 radio；1857 默认 8011；1859 daily 恒空 |
| `lib/protocol/huawei_api.dart` `_featureFrom` | 1909-1965 | 从 `contentExInfo.realContentInfo` 取 id；从 `realContentInfo.extendInfo.serviceType` 取 serviceType；1941-1957 只处理 extendInfo 为 Map/String，未处理 realContentInfo 本身为字符串 |
| `lib/widgets/home_page.dart` `_cards` | 305-428 | 五张卡按 privatefm/dailyrecommend/heartbeatfm/newsongrecommend/millionfavoriterecommend 找 feature；数据却来自 app_state 的 4 路 |
| `lib/widgets/home_page.dart` `_playCard` | 456-527 | 卡片点击直接播 `discover.*`；daily 特例找 a001 playlist |
| `lib/protocol/huawei_gateway.dart` `_withSessionRetry` | 210-218 | 只对 401 自动换会话 |
| `lib/protocol/huawei_gateway.dart` `_decodeJson` | 327-387 | 354-361 `990000` 不设置 401 |
| `lib/protocol/huawei_gateway.dart` `_send` | 286-289 | HTTP 日志只记 path，不记 query/body |
| `lib/widgets/oauth_webview_page.dart` `_exchange` | 88-92 | 登录成功后调用 `loadHome()`，不清冷却 |
| `lib/protocol/endpoints.dart` | 28-33 | home/daily/recommendPlaylist/privateFm/chartDetail 路径 |

## 8. 建议修复点（给实现子代理）

### P0：先把五张卡的数据源拆开，禁止跨卡片回填

1. **重写 `AppState._hydrateHomeFeatures`（`app_state.dart:242-295`）。**
   - 建立 serviceType → 请求的显式映射，至少覆盖：
     - `dailyrecommend` → `daily`（a001 歌单）
     - `newsongrecommend` → `newSongs`（a003 歌单）
     - `millionfavoriterecommend` → `hot`（a006 歌单）
     - `privatefm` → `listen`（优先用该 feature 的真实 contentID/栏目详情；若确实只有功能卡，再调用 `api.privateRadio(mode: '1')`）
     - `heartbeatfm` → `heart`（优先 feature 真实 ID；否则 `api.privateRadio(mode: '2')`）
     - `favoritesrecommend` → 单独字段（如「私藏馆」），不要填「为你推荐」
     - 「为你推荐」→ `recom_exclusive` / 8011 栏目，而不是 a004
   - 每个来源独立 `try`，失败只把该列表留空并记录错误；**删除 `app_state.dart:274-282` 的跨列表 `?:` fallback**。
   - 返回 `DiscoverData` 时保持 `daily/newSongs/listen/heart/hot/recommended` 各自独立。

2. **让 `HuaweiAPI.discover()` 始终补 8011 栏目（`huawei_api.dart:1563-1580`）。**
   - 删除 1569 的 early return；有 features 时也执行 `if (data.recommended.isEmpty) _fetchRecommendationColumn(...)`。
   - 或者把 8011 拉取放到 `_hydrateHomeFeatures` 里，与四路并发同时执行。

3. **删除解析层的跨板块别名（`huawei_api.dart:1836-1839`、`1855`）。**
   - `listenFinal` 为空就保持空，不要等于 `recommendedFinal`。
   - `heart` 为空就保持空，不要等于 `radioSongs`。
   - `newFinal` 为空就保持空，不要等于 `allSongs`（避免新歌卡显示全首页）。

4. **卡片点击不要再从别的列表借歌（`home_page.dart:456-527`）。**
   - 各 card action 只读对应字段；字段为空时显示“该板块接口未返回”，不要用 `state.homeSongs` 或 `discover.recommended` 顶替。

### P0：鉴权/冷却

5. **登录成功必须强制清冷却并重新加载。**
   - 在 `signInWithCode` / `signInWithSession` 成功路径、或 `oauth_webview_page.dart:88-92` 调用 `refreshHome()` 而不是 `loadHome()`。
   - 或在 `loadHome({bool force = false})` 中，`force` 为 true 时跳过 `_homeRetryBlockedUntil` 和 `_homeLoading`（或排队一次）。
   - 错误面板的“重试”（`home_page.dart:75/84`）改用 `refreshHome` 或 `loadHome(force: true)`。

6. **`990000` 增加一次自动恢复（`huawei_gateway.dart:210-218/354-361`）。**
   - 当 `accountToken` 存在时，对 `990000` 尝试一次 `exchangeMusicToken(accountToken)` 后重试；仍失败再抛“重新登录”。
   - 给 `exchangeMusicToken` 加 single-flight（同一个 Future 复用），避免四路并发各自换 token。

### P1：可观测性与刷新

7. **补分卡日志。**
   - `_hydrateHomeFeatures` 每路记录：`serviceType`、请求 ID、返回数量、错误码/异常。
   - `huawei_gateway.dart:286-289` 的 HTTP 日志增加脱敏 query 或（对歌单 POST）`musicListID`，否则日志里 4 个相同 path 无法区分。
   - `discover()` 记录 `features.length` 和解析出的 serviceType 列表。

8. **修刷新语义（`app_state.dart:191-196/224/297-314`）。**
   - `_homeLoading` 期间收到 force refresh 时设置 pending，当前加载结束后再跑一次，或直接 await 当前 Future。
   - 只有 `data` 非空才把 `discoverLoaded` 设为 true。
   - `_rotateDiscover` 也轮换 `hot` 和 `charts`（至少 hot 首曲），否则“换一批”对热歌卡无效。

## 9. 验证方法

### 9.1 先跑现有窄测试（本轮已跑）

```powershell
cd C:\Dev\hmusic
flutter test test\discover_test.dart test\home_ui_test.dart --reporter compact
```

结果：25 项全部通过。但要注意：

- `test/home_ui_test.dart:117-183` 是**手工预填** `DiscoverData` 的五个不同列表，不经过 `_hydrateHomeFeatures`，所以不会发现 fallback 复用。
- `test/discover_test.dart:196-239` 只验证一张 998 卡能被解析，不验证四路取数与失败回填。
- 通过不等于首页正确；需要新增针对 `_hydrateHomeFeatures` 的部分失败测试。

### 9.2 新增回归测试（建议实现子代理补）

1. 假 gateway：`features` 包含 6 个 serviceType；只让 a001 返回 30 首，a003/a004/a006/privatefm/heartbeatfm 返回空。
   - 断言：`daily.length == 30`，`listen.isEmpty`，`heart.isEmpty`，`recommended.isEmpty`，`hot.isEmpty`。
   - 禁止断言 `listen == daily`。
2. 假 gateway：四路全成功。
   - 断言：`listen.first.id != recommended.first.id`，`heart.first.id != hot.first.id`。
3. 假 gateway：a004 返回 10 首、a006 返回 10 首、a001 返回 30 首。
   - 断言：`recommended == a004`、`listen == privatefm`（不是 a004）、`heart == heartbeatfm`（不是 a006）。
4. 冷启动 990000 后 5 秒内登录：
   - 断言：登录后的 `loadHome` 不被 30 秒冷却挡住，最终 `discoverLoaded == true` 且有数据。
5. 990000 且存在 accountToken：
   - 断言：网关触发一次 `exchangeMusicToken`，成功后原请求重试一次。

### 9.3 真机日志验证

1. 设置 `MUYU_HUAWEI_TOKEN` 后运行：

```powershell
cd C:\Dev\hmusic
$env:MUYU_HUAWEI_TOKEN='security:...'
flutter test test\live_home_dump_test.dart
```

期望输出至少包含：

- `HOME columns=...`，且能看到 `contentType=998` 的功能卡；
- `DISCOVER new=... rec=... listen=... heart=... hot=...`，其中各字段数量不必相等，但不应出现多个字段引用同一份列表；
- `PLAYLIST a001/a003/a004/a006 count=...` 四行都有独立数量。

2. 重新构建运行后导出日志，期望首页成功（`page/detail/all 200 ...B`）后 1–2 秒内出现：

- 四路 a00x 的 `musiclist/detail/bymusiclistid`（或 privatefm 对应请求）；
- 每路一条 `[home]`/`[api]` 分卡日志，包含 serviceType、ID、数量；
- 「现在就听」「心动模式」的请求与 a004/a006 可区分；
- 如果只有 a001 成功，另外三路应有明确失败日志，而不是静默空列表。

3. 鉴权回归：

- 故意使用过期 music token、保留 accountToken，启动；
- 期望：`990000` 后自动 `loginex` 一次并重试成功，而不是直接提示重新登录；
- 若自动恢复失败，再手动登录，且登录后 5 秒内首页必须加载成功（不被冷却挡住）。

## 10. 未找到 / 不确定

- **未找到 11/26 `514830B` 首页响应的原始 JSON 落盘。** 因此无法复核 998 功能卡在真实响应中的确切层级、`contentExInfo.realContentInfo` 是 Map 还是 String，以及 feature.id 到底是 a001/a003/a004/a006 还是数字歌单 ID。当前代码的 998 解析只经过单元测试构造数据验证。
- **未找到 11/26 唯一一次 `musiclist/detail/bymusiclistid` 的请求体。** 日志只记录 path，不记录 `musicListID`；`MUYU_HOME_RECOMMENDATION.md:83` 说它对应 a001，但这是推断，不是日志直接证据。
- **未找到 privatefm / heartbeatfm / column/detail / 8011 的任何请求记录。** 两份日志中这些字符串出现次数均为 0。
- **未找到歌词或播放报错。** 两份日志只有 `[play]` 与代理 206，没有歌词请求/解码失败记录；本报告不展开歌词链路。
- **未找到当前 HEAD 构建运行后的新日志。** 因此“当前代码在真机上是否已经复现重复”只能由代码路径推导，不能由现有日志证明；必须按 §9.3 重新导出日志验证。
