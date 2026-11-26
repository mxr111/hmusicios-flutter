# 沐语 2.0.4 首页推荐各板块：REA 规格（含旧结论撤回）

> 目标：`Muyu.exe` 2.0.4（Go + mygo 原生 UI，非 Flutter）。
> 证据分级：**observed** = 二进制 / 截图 / 运行时产物直接可见；**inference** = 由符号名 + 字符串 + 端点推断，未跑通；
> **unknown** = 未找到，禁止当成事实。
> 本文件替代 2026-11-26 旧版本。旧版第 5/6 节（`contentType=998`、`serviceType=dailyrecommend/newsongrecommend/heartbeatfm/millionfavoriterecommend/favoritesrecommend`、`recommend_for_you`）在 2.0.4 二进制里**不存在**，已撤回，见 §8。

---

## 1. 结论摘要

1. 首页不是一条流，是 **1 个聚合页 + 4 条独立推荐服务**：`page/detail/all` 给栏目骨架，`privatefm` 给「现在就听/心动」队列，`musiclist/detail/bymusiclistid` 给「每日30首」（`a001`），`chart/detail/bychartid` 给榜单，「为你推荐」走 `column/detail/bycolumnid`（`recom_exclusive` / `8011`）。
2. 首页 5 张卡是**横向卡片轮播**，顺序（截图实测）：`现在就听 → 每日30首 → 心动模式 → 新歌推荐 → 热歌速递`；其下是 `为你推荐`（分页 `1/5` 的歌曲列表）、`推荐歌单`（横滑卡）、`热歌榜`（分页 `1/10` 的榜单）。
3. 「现在就听」是**独立电台队列**，不是首页歌曲：运行时 `playback.source = {"kind":"radio","id":"listen","scope":"5659a08acf137644","next":104,"more":true}`，队列 104 首以上。
4. 当前 Hmusic「除了每日三十首其他都一样」的根因已定位到行，见 §7：`contentType=998` 功能卡不存在 → `features` 恒空 → `_hydrateHomeFeatures` 永不执行 → `discover.daily` 恒为 `[]` → 只有「每日30首」能通过 `playlists` 里的真实 `a001` 取到数据，其余四张卡共用 `page/detail/all` 的同一批歌。

---

## 2. 证据来源

| 编号 | 路径 | 用途 |
| --- | --- | --- |
| E1 | `rea_evidence/_strings_204.tsv` | 2.0.4 全量字符串（Go 合并字符串块）。`off=` 为该文件第一列文件偏移；`rg -n` 行号指向整块，故用 offset 精确定位 |
| E2 | `rea_evidence/_syms_204.tsv` | 2.0.4 pclntab 符号表（33,337 条） |
| E3 | `C:\Users\Administrator\WorkBuddy\2026-11-23-15-47-13\rea-muyu\decomp_MusicHomePage.json`、`MUYU_DISCOVERY_DECOMPILED.md` §3–§5 | Ghidra 反编译 `MusicHomePage@0x1404224e0` 三层解析流程 |
| E4 | `rea_evidence/home_decomp.txt` L2 / L475 / L480 / L485 / L510 / L515 / L1235 | 首页 UI 函数反编译（部分 createFunction failed，仅能证明存在与边界） |
| E5 | `rea_evidence/HUAWEI_204_PROTOCOL.md` L5–L18、L19–L48、L57–L88 | 真实抓包：请求头、首页 GET、contentType 语义、取流 |
| E6 | `C:\沐语\independent-data\native-ui.json` | 运行时状态：`playback.source` / `queue` / `homePlatform` / `quality` |
| E7 | `rea_evidence/muyu_window.png`；用户截图 `codex-clipboard-6c171afe…png`、`codex-clipboard-5cf6ebda…png` | UI 板块顺序、卡片标题、分页器 `1/5`、`1/10` |
| E8 | `rea_evidence/MUYU_204_MODULE_MAP.md` L3、L39–L45 | 模块规模与已知缺口 |

截图说明：`muyu_window.png` 是沐语 2.0.4 主页顶部（5 卡 + 为你推荐）。两张 clipboard 截图与沐语布局一致、处于滚动中段（推荐歌单 / 热歌榜），但**未做进程归属验证**，仅作 UI 顺序辅助证据。用户给出的 5 张 `RWTemp` JPG 路径已不存在（微信临时目录已清理），**未找到**。

---

## 3. 首页版块总表（UI 顺序）

| # | 板块 | UI 位置 | 数据来源（函数） | 端点 | 点击行为 |
| --- | --- | --- | --- | --- | --- |
| 1 | 现在就听（Music FM） | 卡片轮播第 1 张，封面为 3 首歌拼贴 | `gateway.HomeRadioSeed` / `RadioSongs` / `RadioMode`；`main.homeListenCovers` / `homeListenTriplet` / `expandHomeRadio` | `POST /music-recommend-service/v1/service/recommend/privatefm` | 播放本地电台队列（`kind=radio`），不是打开歌单 |
| 2 | 每日30首 | 轮播第 2 张，封面为「November 23」日期大字 | `gateway.EditorialDaily`；`catalog.Daily` / `normalizeDailySongs` | `GET /music-operation-service/v3/service/musiclist/detail/bymusiclistid?`，`a001` | 进每日30首歌单页 / 起播（见 §5.2） |
| 3 | 心动模式 | 轮播第 3 张，大红心封面 | `main.toggleHeart` / `activateHomeHeartQueue` / `refillHeart` / `canEnterHeart` | **未找到**（只有函数名，无独立端点常量） | 切到心动队列并续播 |
| 4 | 新歌推荐 | 轮播第 4 张，带 `New` 角标 | `main.homeSongSection` + `homeNewSongArt`；测试 id `home-editorial/new` | **未找到**（无专属端点；候选 `page/detail/all` 的 `contentType=96` 子分区或 `column/detail/bycolumnid`） | 起播「新歌」批次 |
| 5 | 热歌速递 | 轮播第 5 张（截图右侧被裁） | `main.homeHotSongArt`（`hot-mosaic-%d`）；测试 id `home-editorial/hot` | **未找到**（推断走 `chart/detail/bychartid` 热歌榜，未验证） | 起播热歌批次 |
| 6 | 为你推荐 | 卡片下方歌曲列表，右上 `1 / 5` + ← → | `gateway.FeaturedSongs`；`catalog.homeRecommendationSongs`；`main.App.HomeRecommendedSongs` / `homeRecommendedSongs` | `GET /music-operation-service/v1/service/column/detail/bycolumnid?`（`recom_exclusive` / `8011`） | 播放所点那首，队列 = 该列表 |
| 7 | 推荐歌单 | 卡片横滑，封面 + 两行标题 | `gateway.RecommendedLists`；`catalog.RecommendedLists` / `recommendedCollections` | `POST /music-recommend-service/v1/service/recommend/playlist`（兜底 `column/detail/bycolumnid`） | 打开歌单详情 |
| 8 | 热歌榜 | 列表式榜单，右上 `1 / 10` + ← → | `gateway` 榜单 + `catalog.HomeCharts`；`main.App.HomeCharts` | `GET /music-operation-service/v1/service/chart/detail/bychartid` | 打开榜单 / 点单曲播放 |

板块顺序证据：`muyu_window.png`（第 1–6 项可见）、clipboard 截图（第 7、8 项）。分页器 `1/5`、`1/10` 亦来自截图。

---

## 4. 已观测到的常量与契约

### 4.1 端点常量（E1，全部为二进制内 UTF-8 字面量）

| 端点 | 方法 | 证据 |
| --- | --- | --- |
| `/music-operation-service/v1/service/page/detail/all` | GET | `off=14981747`；实测 `?pageType=7&hasRecommend=1`，POST 返回 405（E5 L22–L27） |
| `/music-recommend-service/v1/service/recommend/privatefm` | POST | `off=14993173` |
| `/music-recommend-service/v1/service/recommend/querydaily` | POST | `off=14996586` |
| `/music-recommend-service/v1/service/recommend/playlist` | POST | `off=14987197` |
| `/music-operation-service/v1/service/column/detail/bycolumnid` | GET（字面量带 `?`） | `off=15004256` |
| `/music-operation-service/v3/service/musiclist/detail/bymusiclistid` | GET（字面量带 `?`；E5 L59 记为 POST body，冲突见 §10） | `off=15020031` |
| `/music-operation-service/v1/service/chart/detail/bychartid` | GET | E1；E5 L68 实测 GET |
| `/music-recommend-service/v2/service/recommend/querysimilar` | POST | E1（相似歌曲，非首页） |

### 4.2 首页解析契约（E3 §3、E4 L2）

`MusicHomePage@0x1404224e0` 读取顺序（Ghidra 反编译，常量长度可校验）：

```
columnInfoExs(13) → contentSimpleInfos(18) → contentID(9) == "pmf001"
  → childSimpleInfos(16) → listRcmInfos(12)
```

- 即「栏目 → 内容 → 子内容」三层；只按扁平 key 找歌会解析出 0 张卡（E3 §3）。
- `pmf001` 是**电台种子卡**的 contentID。注意是 **pmf**，不是 Hmusic 里写的 `pfm001`（`lib/widgets/home_page.dart:319`）。

### 4.3 「为你推荐」栏目（E1 off=14795940）

同一字符串块内相邻出现：`recom_exclusive` → `8011` → `fs` → `android.kugou.com`。配套字段 `columnID` / `columnId` / `hasRecommend`；错误文案「首页未返回私享好歌列表或栏目编号」「栏目详情未返回私享好歌列表」。响应取歌字段：`columnInfoExs` / `contentSimpleInfos` / `listRcmInfos` / `songSimpleInfos`。

### 4.4 首页 UI 测试 id（E1，直接证明板块存在）

| id | offset | 说明 |
| --- | --- | --- |
| `home-feature-cards` | 14786802 | 5 张卡片的容器 |
| `home-editorial/new` | 14786802、14765302 | 新歌推荐卡 |
| `home-editorial/hot` | 14786802 | 热歌速递卡 |
| `home-section` / `listen-cover-home-section` | 14753209 | 板块容器 / 现在就听封面 |
| `hot-mosaic-%d` | 14753209 | 热歌封面拼贴 |
| `home-listencard-bottom`、`home-status`、`home-loader`、`home-retry`、`home-scroll` | 14740501 等 | 卡片底部、加载 / 重试 / 滚动 |
| `home-card-slot-`、`home-song-hover`、`home-card-press`、`打开歌单：`、`上一组歌曲`、`下一组歌曲` | 14765302 | 卡片槽位、悬停 / 按压、**换一批按钮** |
| `page-placeholder-`、`暂无推荐歌单` | 14786802 | 空态 |

### 4.5 中文标签（E1）

`现在就听`、`每日30首`（off=14740501）与 `每日 30 首`（off=14728151，带空格的另一处文案）、`心动模式`、`新歌推荐`、`热歌速递`、`为你推荐`、`猜你喜欢`、`每日推荐`、`百万收藏`、`榜单推荐`、`私人雷达`、`继续播放`。

这些标签只证明**文案存在**，不证明各自对应哪个端点；不要把标签名当 serviceType。

### 4.6 首页相关函数（E2，2.0.4 pclntab）

```
gateway.(*Connection).MusicHomePage / EditorialDaily / FeaturedSongs / Daily
gateway.(*Connection).HomeRadioSeed / RadioSongs / RadioMode / RecommendedLists
catalog.(*Library).HomeSongs / HomeSongsWithRadioMode / HomeCharts / Daily / NextRadioSongs / RecommendedLists
catalog.normalizeHomeSongs / normalizeDailySongs / homeRecommendationSongs / recommendedCollections
main.(*nativeModel).homePage / homeSections / homeSongSection / homeSong / homeSongs
main.(*nativeModel).homeFeatureCard / homeListenCovers / homeListenTriplet / homePlaylists / homeCharts
main.(*nativeModel).homeNewSongArt / homeHotSongArt / homeDestinationCard / homeDestinationHero
main.(*nativeModel).loadHomeKinds / loadPlatformHome / loadPlatformHomeSection / retryPlatformHomeSection
main.(*nativeModel).expandHomeRadio / expandPlatformHomeRadio / sharePlatformHomeRadio
main.(*nativeModel).nextPlatformHomeRadio / refreshHomeListenQueue / attachHomeRadioFeed / homeShelfArrival
main.(*nativeModel).toggleHeart / activateHomeHeartQueue / refillHeart / canEnterHeart
main.(*App).DailyRecommendations / HeartRecommendations / HomeRecommendedSongs / HomeCharts / RecommendedPlaylists
```

`main.(*App).homeRecommendedSongs@0x140b97740`、`HomeRecommendedSongs@0x140b976c0` 反编译成功（E4 L2、L471）；`homeSongSection` / `loadHomeKinds` / `DailyRecommendations` 反编译失败（E4 L480 / L510 / L515 = `!! createFunction failed`），因此三者内部字段**未找到**。

---

## 5. 逐板块细节

### 5.1 现在就听（Music FM）

- **API**：`POST /music-recommend-service/v1/service/recommend/privatefm`。
- **参数**（E1 + `gateway.applicationRequest@0x1404225c0` 反编译，E3 §4）：`cadence`（构造时写空串）、`rcmMode`（仅接受 `"1"/"2"/"3"`，否则返回「私人电台推荐模式无效」）、`rcmScenario`（2 字节串，`16` 或 `21` 分支）、`refInfo`。
- **鉴权 / 头**：E5 L5–L18 —— 只带 `Host` / `User-Agent`（设备串）/ `Accept` / `Authorization: Digest` / `Content-Type` / `Accept-Encoding`；多带 `x-client-version` 等头会 990000。
- **响应字段**：取歌用 `listRcmInfos` / `songSimpleInfos` / `contentSimpleInfos`（E1、E3 §3）。
- **队列语义**（E6）：`kind=radio`、`id=listen`、`scope=5659a08acf137644`、`next=104`、`more=true`，说明是**可续播电台**，`next` 是已消费游标；`nextPlatformHomeRadio` / `expandHomeRadio` 负责补歌。
- **封面**：3 张歌封面拼贴（`homeListenCovers` / `homeListenTriplet`，E1 `listen-cover-home-section`）。
- **缓存 / 失败降级**：**未找到**专属常量；卡片下方只有通用 `home-loader` / `home-retry`。

### 5.2 每日30首

- **API**：`GET /music-operation-service/v3/service/musiclist/detail/bymusiclistid?`，`musicListID=a001`。证据：`a001` 为首页 `contentType=4` 歌单（E5 L31）；用户日志里只有一次该请求、307684B、对应 `a001`。
- **入口函数**：`gateway.EditorialDaily`、`catalog.Daily` / `normalizeDailySongs`、`main.App.DailyRecommendations`。
- **易混**：`recommend/querydaily` 是**另一个**「每日推荐」接口，2.0.4 仍存在（`off=14996586`），但实测 POST 400（E5 L61–L63、E8 L43 的 P0 缺口）。不要把 `querydaily` 当成 `a001`。
- **点击行为**：卡片有播放按钮，且存在 `main.openHomeDestination` / `refreshHomeDestination`，说明有「卡片 → 目标页 / 直接起播」两条路径；具体语义**未找到**确定证据。
- **封面**：`main.homeDestinationHero`，视觉为「月份英文 + 日期大字」（截图 November / 23）；随当天日期变化为 inference。

### 5.3 心动模式

- **函数**：`main.(*nativeModel).toggleHeart` / `activateHomeHeartQueue` / `canEnterHeart` / `refillHeart`；`main.(*App).HeartRecommendations`。
- **API**：**未找到**。二进制里没有 heart 专属路径常量；最可能是 `privatefm` 的另一个 `rcmMode` / `rcmScenario`，但 `rcmMode` 只接受 1/2/3 且无 `heart` 字样常量，无法证实。
- **队列**：`activateHomeHeartQueue` 暗示它激活**独立队列**（与 listen 并列），不是复用首页歌曲。
- **结论**：端点与参数**未找到**；实现方不得假定它等于 `privatefm`。

### 5.4 新歌推荐

- **UI**：`home-editorial/new`，`New` 角标，封面为专辑图，副标题「歌名 · 歌手」（截图）。
- **函数**：`main.homeSongSection` + `homeNewSongArt`；`catalog.normalizeHomeSongs` 兼容精简键 `ID` / `NM` / `pic`（E3 §5），说明新歌走的是**首页 content 里的 song map**，不是独立歌单接口。
- **API**：**未找到**专属端点。候选：`page/detail/all` 的 `contentType=96` 分区（E5 L31）下的 `childSimpleInfos`，或 `column/detail/bycolumnid`；两者均**未验证**。
- **换一批**：`上一组歌曲` / `下一组歌曲`（E1 off=14765302）证明按「组」翻页，组大小**未找到**。

### 5.5 热歌速递

- **UI**：`home-editorial/hot`，封面 `hot-mosaic-%d`（多图拼贴）。
- **API**：**未找到**专属端点；推断为 `chart/detail/bychartid` 的热歌榜（截图中「热歌榜」与「热歌速递」并存，且 `catalog.HomeCharts` 与 `App.HomeCharts` 共用榜单数据）。**推断，未验证**。
- **换一批**：同上，`上一组 / 下一组`。

### 5.6 为你推荐

- **UI**：歌曲列表，右上 `1 / 5` + ← →（截图）。
- **API**：`GET /music-operation-service/v1/service/column/detail/bycolumnid?columnId=...&start=0&limit=30&hasRecommend=1`，栏目 `recom_exclusive`，兜底栏目号 `8011`（§4.3）。
- **响应取歌**：`columnInfoExs` / `contentSimpleInfos` / `listRcmInfos` / `songSimpleInfos`。
- **分页**：`1/5` 是服务端 `start/limit` 分页还是前端切组，**未找到**确定证据。
- **点击**：`main.openHomeCard` / `homePlay`；点某首 → 以当前列表为队列播放（队列 = 该批歌曲，inference）。
- **失败降级**：文案「首页未返回私享好歌列表或栏目编号」「栏目详情未返回私享好歌列表」→ 空态，不伪造成新歌。

### 5.7 推荐歌单

- **API**：`POST /music-recommend-service/v1/service/recommend/playlist`；兜底 `column/detail/bycolumnid`。
- **函数**：`gateway.RecommendedLists`、`catalog.recommendedCollections`、`main.App.RecommendedPlaylists`（E4 L1235 反编译成功）。
- **响应字段**：`playListInfos` / `playListName` / `picture` / `songNum` / `miniMusicListInfoEx`（E1、E2）。
- **点击**：`main.openPlatformHomePlaylist` → 歌单详情页；空态 `暂无推荐歌单`。

### 5.8 热歌榜

- **UI**：列表行（封面 / 歌名 / 歌手 / 收藏 / 加歌单），右上 `1 / 10`（截图），即 10 个榜单轮换。
- **API**：`GET /music-operation-service/v1/service/chart/detail/bychartid?chartID=&chartId=&contentType=1&start=&limit=`（E5 L68）。
- **字段**：`chartInfos` / `chartID` / `currentCount`；首页 `contentType=7` 即榜单（E5 L31，热歌榜 `24926`）。
- **点击**：`main.openHomeDestination` / `platformHomeCollectionPage`。

---

## 6. 数据 → 卡片 / 队列 / 刷新 / 降级的统一规则

| 维度 | 沐语做法 | 证据 |
| --- | --- | --- |
| 卡片取「第一首」做预览副标题 | 每张卡副标题为「歌名 · 歌手」 | 截图 |
| 卡片封面 | 每日30首 = 日期大字；心动 = 心形；现在就听 = 3 封面拼贴；热歌 = 拼贴 | 截图 + `hot-mosaic-%d` / `listen-cover-home-section` |
| 起播队列 | 卡片各自独立队列（电台 / 每日 / 心动 / 新歌 / 热歌互不复用） | `attachHomeRadioFeed`、`activateHomeHeartQueue`、`nextPlatformHomeRadio` 等独立队列函数（E2） |
| 换一批 | `上一组歌曲` / `下一组歌曲`，按「组」翻 | E1 off=14765302 |
| 分页器 | 为你推荐 `1/5`、热歌榜 `1/10` | 截图 |
| 刷新 | 主页 `刷新主页` / `home-retry` / `刷新当前页面`；电台 `refreshHomeListenQueue` | E1、E2 |
| 缓存 | `nativecache`（图片）、`catalog` 内存态；首页 JSON 是否落盘**未找到** | E8 L13 |
| 鉴权失败 | 990000 → 「登录授权已失效，请点击头像重新授权」；`EnableReadRecovery` / `retryFailedHomeAfterRecovery` 自动重试 | E5 L19–L30、E2 |

---

## 7. 「除了每日三十首其他都是一样的」根因（当前 Hmusic）

1. `lib/protocol/huawei_api.dart:1563` `discover()` 有 `if (data.features.isNotEmpty) return data;`，而 `features` 只在 `parseDiscover` 的 `case '998'`（`huawei_api.dart:1798`）产生。
2. `contentType=998` 在 2.0.4 二进制中**不存在**（§8）。实测 content 类型只有 1/2/4/6/7/10/11/12/20/96（`HUAWEI_204_PROTOCOL.md` L31–L41）。于是 `features` 恒空，`_hydrateHomeFeatures` **永不执行**（`app_state.dart:200–202`）。
3. `_hydrateHomeFeatures`（`app_state.dart:242`）里的 `idFor('dailyrecommend','a001')` … `idFor('millionfavoriterecommend','a006')`（`app_state.dart:262–265`）依赖同样虚构的 5 个 serviceType；即便执行，`idFor` 也只会命中 fallback 常量，等于硬编码 `a001/a003/a004/a006`。
4. `parseDiscover` 返回时 `daily: const <Song>[]` 写死（`huawei_api.dart:1859`）→ `discover.daily` 永远为空。
5. 其余四张卡靠**中文标签模糊匹配**（`_isListenLabel` / `_isRecommendedLabel` 等）填充，匹配不到就退化到 `recommendedFinal` / `radioSongs` / `allSongs`（`huawei_api.dart:1846–1857`）——**同一批歌**。
6. 首页渲染时：`每日30首` 有独立兜底，从 `discover.playlists` 找 `id == 'a001'`（`home_page.dart:343–346`、`:476`）→ **唯一有真实内容的卡**；`现在就听/心动/新歌/热歌` 分别读 `discover.listen/heart/newSongs/hot`（`home_page.dart:306–312`），而这四个值同源 → 看起来一模一样；副标题取 `list.first`（`home_page.dart:312–315`）→ 五张卡首曲名相同，进一步放大「都一样」。
7. `homeSongs = discover.recommended ?? radio ?? newSongs`（`app_state.dart:217–221`）又让「为你推荐」与卡片共享同一批歌，`_rotateDiscover`（`app_state.dart:297`）只换顺序不换内容 → 刷新也「一样」。

**一句话**：`每日30首` 走的是 `playlists` 里的真实 `a001`；另外四张卡没有各自的取数路径，全部落在 `page/detail/all` 解析出的同一批歌上，所以只有「每日30首」不同。

---

## 8. 撤回：旧版本里没有证据的说法

在 `_strings_204.tsv`（6.7 MB，含全部 Go 字面量）中逐个检索，以下字符串**全部 NOT FOUND**：

| 旧说法 | 检索结果 |
| --- | --- |
| `contentType=998` 功能卡 | 不存在（`998` 仅出现在无关数字里） |
| `serviceType` = `dailyrecommend` / `newsongrecommend` / `heartbeatfm` / `millionfavoriterecommend` / `favoritesrecommend` | 全部 NOT FOUND |
| 栏目 `recommend_for_you` | NOT FOUND |
| 栏目 id `a003` / `a004` / `a006` | NOT FOUND（`a002` 等命中的是 sha256 噪声） |

同时 `serviceType` 这个**字段名**在二进制里只出现在 DLNA 的 `<serviceType>%s</serviceType>` 模板（off=15076932），与首页推荐无关。

结论：旧版 §5/§6 的「6 个 serviceType 功能卡」方案是推测，不是 REA 事实。任何实现若继续依赖它，都会得到 `features.isEmpty == true`，永远走不到分卡取数分支。

保留有效的旧结论：旧版 §1（首页不是新歌流）、§2（`recom_exclusive` / `8011` / `column/detail/bycolumnid`）、§3（音质策略）。

---

## 9. 实现子代理必须修改的函数 / 字段 / 测试

### 9.1 `lib/protocol/huawei_api.dart`

| 位置 | 现状问题 | 必须改成 |
| --- | --- | --- |
| `discover()` L1563 | `if (data.features.isNotEmpty) return data;` 依赖不存在的 998 | 删除该早退；改为按「栏目骨架」驱动：`page/detail/all` → 识别 `contentType=4` 的 `a001`、`contentType=7` 的榜单、`contentType=96` 子分区、`contentType=12` 功能卡 |
| `parseDiscover()` L1798 | `case '998'` 死分支 | 用真实类型 1/2/4/6/7/10/11/12/20/96（E5 L31–L41） |
| `parseDiscover()` L1859 | `daily: const <Song>[]` 写死 | 由真实 `a001` 歌单填充（`EditorialDaily` 语义），或在 `AppState` 单独 fetch 后 `copyWith(daily:)` |
| L1846–1857 | `newFinal` / `listen` / `heart` 互相 fallback 到 `allSongs` / `radioSongs` | **禁止跨板块 fallback**；每块空就是空 |
| `_fetchRecommendationColumn()` L1585 | 只在 `recommended.isEmpty` 时触发，且用于给 `listen` 兜底（L1573–1576） | 保留为「为你推荐」的唯一来源；不再给 `listen` 兜底 |
| 新增 | 无 | `featuredSongs()`（`recom_exclusive` / `8011`）、`editorialDaily()`（`a001`）、`privateFm(mode)`、`recommendedPlaylists()`、`chartSongs(chartId)` 五个独立入口 |
| 新增 | 无 | 组翻页 `newSongGroup(index)` / `hotSongGroup(index)`，对应 `上一组 / 下一组` |

### 9.2 `lib/services/app_state.dart`

| 位置 | 现状问题 | 必须改成 |
| --- | --- | --- |
| `loadHome()` L178–230 | 只 `await api.discover()` 一次，`_hydrateHomeFeatures` 永不执行 | 改成 5 路并发：`discover()`（骨架）+ `featuredSongs` + `editorialDaily(a001)` + `privateFm` + `recommendedPlaylists` + `charts`，各自 `_soft` 容错 |
| `_hydrateHomeFeatures()` L242–295 | 依赖虚构 serviceType | 删除，或重写为「按真实栏目 id 取数」 |
| `idFor()` L243–252 | 匹配不存在的字段 | 删除 |
| L262–265 | `a003` / `a004` / `a006` 无证据 | 删除；换成有证据的 `a001` + `recom_exclusive/8011` + chart id |
| `homeSongs` L217–221 | 三选一 fallback，导致「为你推荐」与卡片同源 | 拆成独立字段：`featuredSongs` / `listenQueue` / `heartQueue` / `newGroup` / `hotGroup` |
| `_rotateDiscover()` L297 | 刷新只换顺序 | 换一批要重新请求对应接口（对齐 `refreshHomeListenQueue` 语义），或按 group index 前进 |

### 9.3 `lib/widgets/home_page.dart`

| 位置 | 现状问题 | 必须改成 |
| --- | --- | --- |
| `_cards()` L305–430 | 5 卡数据源同源 | 每卡绑定独立字段；`subtitle` 用各自 `first` |
| L319 `ids: ['pfm001']` | **常量拼写错误**：二进制是 `pmf001`（E4 L2 反编译校验 `0x306d6670` + `0x3130` = `pmf001`） | 改 `pmf001` |
| L330 `ids: ['pfm002']` | `pfm002` **未找到**于二进制 | 删除，或标注待验证 |
| L317–341 | `_featureFor` 依赖 `features` | 5 卡不再依赖 `DiscoverFeature`；该类型只留给 `contentType=12` 真功能卡 |
| `_playCard()` L456–530 | `daily` 分支 `play` 与 `openPlaylist` 混用；`hot` 用通用 `hot` 列表 | 每日30首统一为「打开 a001 歌单或按 hero 起播」；hot 绑定具体 chart id |
| 新增 | 无 | 卡片区 `上一组 / 下一组` 按钮；`为你推荐` 的 `1/5` 分页器；热歌榜 `1/10` 分页器 |

### 9.4 测试（只跑这些，不要全量 `flutter test`）

- `parseDiscover` 分化测试：真实首页 JSON 样例（contentType 1/2/4/6/7/10/11/12/20/96），断言 `daily` 只来自 4 的 `a001`、`charts` 只来自 7、`albums` 只来自 2 与 96-child-2，不出现跨类型串味。
- 独立性测试：输入只含一种内容时，`listen/heart/daily/newSongs/hot` 中另外四个必须为空（禁止 fallback）。
- `pmf001` 常量测试：`contentID='pmf001'` 的 `childSimpleInfos → listRcmInfos` 能取到电台歌；`contentID='pfm001'` 不应命中。
- `_fetchRecommendationColumn` 测试：`recommendedColumnId='8011'` 拼出 `columnId=8011&start=0&limit=30&hasRecommend=1`；无栏目号时不发请求。
- 降级测试：`page/detail/all` 返回空结构时 `discoverLoaded` 为 false 但不写假数据；990000 进入冷却且主动刷新可清。
- 回归测试（关键）：构造 5 个互不相同的列表，断言 5 张卡 `subtitle` 各不相同 —— 直接锁死「除每日30首其他都一样」的回归。

---

## 10. 未找到清单（明确留白，禁止编造）

1. 「心动模式」端点与参数（只有函数名）。
2. 「新歌推荐」「热歌速递」的专属端点与组大小。
3. `为你推荐` 的 `1/5` 是服务端 `start/limit` 分页还是前端切组。
4. 首页 JSON 是否落盘缓存（`nativecache` 只确认图片缓存）。
5. `musiclist/detail/bymusiclistid` 究竟 GET 还是 POST：字面量带 `?`（E1 off=15020031）与 E5 L59 记录的 POST body 冲突。
6. 5 张 `RWTemp` 用户截图：目录已被微信清理，**未找到**。
7. `main.homeSongSection` / `loadHomeKinds` / `DailyRecommendations` 的内部字段：Ghidra `createFunction failed`（E4 L480 / L510 / L515）。

---

## 11. 复现方式

- 反编译工具：`rea_evidence/tools/DecompileRanges.java`、`PrintFunctionAt.java`、`symbol_at.py`、`json_shape.py`
- 反编译全文：`rea_evidence/home_decomp.txt`、`home_decomp2.txt`、`home_decomp3.txt`、`decomp_204.txt`、`radio_decomp.txt`
- 符号查询：`rg 'gateway\.\(\*Connection\)' rea_evidence/_syms_204.tsv`
- 端点枚举：`rg -o '/music-[a-z\-]+/v[0-9]+/service/[A-Za-z0-9/_\-]+' rea_evidence/_strings_204.tsv`
- 字符串定位：按 §4 的 `off=` 值在 `_strings_204.tsv` 第一列查找，再取该行第三列（单个超长合并串）

---

## 12. 证据索引（路径 + 行号 / offset）

| 结论 | 证据 |
| --- | --- |
| 首页 5 卡顺序 + 为你推荐 1/5 | `rea_evidence/muyu_window.png` |
| 推荐歌单 + 热歌榜 1/10 | 用户截图 `codex-clipboard-6c171afe-c79f-45d8-be4c-0cb6fbfd6b9b.png`、`codex-clipboard-5cf6ebda-17ef-423d-9436-32844282aee8.png`（归属未验证） |
| `columnInfoExs → contentSimpleInfos → pmf001 → childSimpleInfos → listRcmInfos` | `C:\Users\Administrator\WorkBuddy\2026-11-23-15-47-13\rea-muyu\MUYU_DISCOVERY_DECOMPILED.md` §3；`rea_evidence/home_decomp.txt:2` |
| `recom_exclusive` / `8011` | `rea_evidence/_strings_204.tsv` off=14795940 |
| `home-feature-cards` / `home-editorial/new` / `home-editorial/hot` | `_strings_204.tsv` off=14786802 |
| `上一组歌曲` / `下一组歌曲` / `home-card-slot-` | `_strings_204.tsv` off=14765302 |
| `home-section` / `listen-cover-home-section` / `hot-mosaic-%d` | `_strings_204.tsv` off=14753209 |
| `每日30首` / `home-status` / `home-loader` | `_strings_204.tsv` off=14740501 |
| `page/detail/all` GET | `_strings_204.tsv` off=14981747；`HUAWEI_204_PROTOCOL.md:22-27` |
| `privatefm` / `querydaily` / `recommend/playlist` | `_strings_204.tsv` off=14993173 / 14996586 / 14987197 |
| `column/detail/bycolumnid?` | `_strings_204.tsv` off=15004256 |
| `musiclist/detail/bymusiclistid?` | `_strings_204.tsv` off=15020031；`HUAWEI_204_PROTOCOL.md:59` |
| contentType 语义 1/2/4/6/7/10/11/12/20/96 | `HUAWEI_204_PROTOCOL.md:31-41` |
| 真实请求头（990000 根因） | `HUAWEI_204_PROTOCOL.md:5-18` |
| `playback.source = radio / listen / next=104` | `C:\沐语\independent-data\native-ui.json` → `playback.source` |
| 首页 / 推荐函数清单 | `rea_evidence/_syms_204.tsv`（`gateway.(*Connection)` / `catalog.` / `main.(*nativeModel)`） |
| `HomeRecommendedSongs@0x140b976c0` / `homeSongs@0x140bdd800` | `rea_evidence/home_decomp.txt:2`、`:475` |
| `homeSongSection` / `loadHomeKinds` / `DailyRecommendations` 反编译失败 | `rea_evidence/home_decomp.txt:480`、`:510`、`:515` |
| `RecommendedPlaylists` 反编译成功 | `rea_evidence/home_decomp.txt:1235` |
| 当前 Hmusic 根因链 | `lib/protocol/huawei_api.dart:1563,1798,1846-1859`；`lib/services/app_state.dart:200-202,242,262-265,297`；`lib/widgets/home_page.dart:305-315,319,330,343-346,456-530` |
| 未知 serviceType / 998 不存在 | 本文件 §8（`_strings_204.tsv` 全量检索 NOT FOUND） |
