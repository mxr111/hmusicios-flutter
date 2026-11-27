# 沐语首页五板块 / 搜索 / 播放取流：REA 证据化规格

> 目标：`Muyu.exe` 2.0.4（Go + mygo 原生 UI）。
> 本文只读对照当前 Hmusic（`C:/Dev/hmusic`），不修改业务代码。
> 证据等级：
> - **observed**：二进制字符串 / 反编译 / 抓包 / 运行时状态 / 截图直接可见。
> - **inference**：由函数名、字段名、邻近常量推断，未完成端到端验证。
> - **unknown**：现有证据不足，写“未找到”，不得当成事实实现。

---

## 0. 结论摘要

沐语首页不是一条“推荐流”，而是 **1 个聚合骨架 + 多个独立数据源**：

| # | 板块 | 沐语数据源 | 证据强度 | 当前 Hmusic |
|---|---|---|---|---|
| 1 | 现在就听 | `POST /music-recommend-service/v1/service/recommend/privatefm` | observed 端点 + 运行时队列 | 已接，但退化为单页 + 跨板块兜底 |
| 2 | 每日30首 | `GET /music-operation-service/v3/service/musiclist/detail/bymusiclistid?musicListID=a001` | observed 200 / 30 首 | 已接 |
| 3 | 心动模式 | **未找到独立端点**；只有 `toggleHeart` / `activateHomeHeartQueue` / `refillHeart` | unknown / inference | 用 `pmf001` 标签或 `privatefm(mode=2)` 推断，未证实 |
| 4 | 新歌推荐 | **未找到专属端点**；候选 `page/detail/all` 的 `contentType=96` 或 `pmf001` 子批次 | inference | 用 `contentType=96` + `pmf001` 标签 |
| 5 | 为你推荐 | `GET /music-operation-service/v1/service/column/detail/bycolumnid?columnId=8011...`（`recom_exclusive`） | observed 端点 + 空响应 | 已接，但会被 fallback 填满 |
| 6 | 搜索 | `POST /music-search-service/v10/service/fuzzysearch` | observed 端点 + contentType 语义 | 已接，只取首批 30 条 |
| 7 | 播放/取流 | `POST /music-play-service/v3/service/file/bycontentcode` | observed 请求/响应 | 已接，具备逐档降级与 MIME 修正 |

一句话差异：**当前 Hmusic 已接上大部分真实端点，但首页仍用“全局 fallbackPool + 语义标签切批”填满六个板块；沐语的真实实现是各板块独立取数、独立队列。**

---

## 1. 现在就听（Music FM）

### 1.1 UI / 入口 / 点击

- 首页 5 张横滑卡第 1 张，标题 `现在就听`，徽标 `♫ Music FM`；封面是 3 首歌封面拼贴，副标题“歌名 · 歌手”。
  - 证据：`rea_evidence/muyu_window.png`；`MUYU_HOME_RECOMMENDATION.md:13`、`:38-44`、`:126-134`。
  - 封面/容器常量：`listen-cover-home-section`、`home-listen*`、`home-feature-cards`，`_strings_204.tsv` off=14753209 / 14786802。
- 沐语点击行为：**直接播放“现在就听”的本地电台队列**，不是打开普通歌单。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:14`、`:40`、`:132`；运行时 `native-ui.json` 的 `playback.source`。
- 换批：`上一组歌曲` / `下一组歌曲`；电台另有 `expandHomeRadio` / `nextPlatformHomeRadio` / `refreshHomeListenQueue` 续播函数。
  - 证据：`_strings_204.tsv` off=14765302；`MUYU_HOME_RECOMMENDATION.md:115-116`、`:198`。

### 1.2 API

| 项 | 值 |
|---|---|
| Endpoint | `POST /music-recommend-service/v1/service/recommend/privatefm` |
| 方法 | POST JSON |
| Body | `cadence`（构造时写空串）、`rcmMode`（只接受 `"1"/"2"/"3"`）、`rcmScenario`（2 字节串，`"16"` 或 `"21"` 分支）、`refInfo`（字符串） |
| 鉴权 | `Authorization: Digest username=app-music-baseline, nonce=<24字节hex>, created=<UTC ISO8601 无毫秒>, token=<music token>` |
| 其他头 | `Host` / `User-Agent=<设备串>` / `Accept: application/json` / `Content-Type: application/json` / `Accept-Encoding: gzip`；不要额外 `x-*` 头，否则 990000 |

证据：

- 端点字面量：`_strings_204.tsv` off=14993173；`MUYU_HOME_RECOMMENDATION.md:60`、`:128-130`。
- 参数来自 `gateway.applicationRequest@0x1404225c0` 反编译：`MUYU_HOME_RECOMMENDATION.md:129`；`MUYU_FULL_FUNCTION_MAP.md:132`。
- 请求头实测：`HUAWEI_204_PROTOCOL.md:13-30`。
- `refInfo` 必须是字符串：2026-11-26 日志 L56 服务端 400 明说 `Cannot deserialize value of type java.lang.String from Array value`；见 `LOG_TRIAGE_2026-11-26T20-06.md:117`、`:168`。

### 1.3 真实 ID / 字段

- 首页种子卡 `contentID = pmf001`（注意不是 `pfm001`）。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:73-78`；`home_decomp.txt:2`。
- 取歌字段：`listRcmInfos` / `songSimpleInfos` / `contentSimpleInfos`；三层结构为 `columnInfoExs → contentSimpleInfos → pmf001 → childSimpleInfos → listRcmInfos`。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:70-82`、`:131`。
- `serviceType` 字段在二进制里只出现在 DLNA 模板，与首页推荐无关；旧版 `contentType=998` 和 `dailyrecommend/newsongrecommend/heartbeatfm/...` 全部 **未找到**。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:220-231`。

### 1.4 队列语义

- 运行时状态为独立电台队列：
  - `playback.source = {"kind":"radio","id":"listen","scope":"5659a08acf137644","next":106,"more":true}`
  - `playback.queue.length = 106`
  - `playback.index = 98`
  - `playback.position = 192.265`
  - 证据：`C:/沐语/independent-data/native-ui.json` 的 `playback.source` / `playback.queue` / `playback.index` / `playback.position`。
- 这说明队列是可续播的电台，不是“首页 5 首歌”；`next` 的精确语义（已消费游标 / 下一页起点）**未找到**逐函数证据，现有报告将其解释为已消费游标。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:132`。
- 续播函数：`expandHomeRadio` / `nextPlatformHomeRadio` / `refillHeart` 一类独立队列函数。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:115-116`；`MUYU_FULL_FUNCTION_MAP.md:67-73`。

### 1.5 音质 / 封面 / 缓存 / 失败

- 音质：走统一取流链路，见 §7；默认 `quality: hires`，实际档位可为 lossless / standard（`native-ui.json` 的 `quality` 与 `confirmedAudio`）。
- 封面：3 张歌封面拼贴 `homeListenCovers` / `homeListenTriplet`。
- 缓存：首页 JSON 是否落盘 **未找到**；只确认 `nativecache` 图片缓存。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:199`、`:289`。
- 失败降级：通用 `home-loader` / `home-retry`；没有找到“privatefm 失败后拿 24926 填充”的沐语证据。

### 1.6 当前 Hmusic 差异

- 当前 `HuaweiAPI.discover()` 先并发请求 `home`、`featuredSongs`、`daily30`、`privateFm`、`recommendedPlaylists`、`chartSongs`，再把结果合并。
  - 代码：`lib/protocol/huawei_api.dart:1866-1895`。
- `privateFm()` 固定 `rcmMode = "1"`、`rcmScenario = "16"`、`refInfo = ""`。
  - 代码：`lib/protocol/huawei_api.dart:2117-2130`。
  - 与沐语差异：沐语有 `16` / `21` 分支；`21` 何时使用 **未找到**。
- `discover()` 的 `listen` 优先 `fm`，否则 `data.listen`，再否则 `fallbackPart(0,5)`。
  - 代码：`lib/protocol/huawei_api.dart:1949-1951`。
  - 这不是沐语证据中的独立电台语义；`fallbackPart` 会把每日/热歌/8011 的歌塞进“现在就听”。
- `playCard('radio')` 在 `discover.listen` 为空时会再请求 `privateRadio(mode:'1')`，仍空则用 `discover.radio`。
  - 代码：`lib/services/app_state.dart:687-699`。
  - 这是跨板块兜底，和沐语独立队列不一致。
- 当前 `HomePage._heroCards` 点击卡片只打开 `HomeSectionPage`，不是立即起播。
  - 代码：`lib/widgets/home_page.dart:230-245`、`:438-445`、`:575-667`。
  - 沐语证据说“现在就听”点击播放本地电台队列；两者点击语义不同。
- 当前没有 `privatefm` 的 `next` / `more` / 续播游标；`MuyuAudioController.next()` 只在本地 `queue` 内循环。
  - 代码：`lib/services/audio_controller.dart:553-566`。

---

## 2. 每日30首

### 2.1 UI / 入口 / 点击

- 首页第 2 张卡，标题 `每日30首`，月历封面 `月份英文 + 日期大字`，副标题“歌名 · 歌手”；点击进入歌单页或按 hero 起播。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:13`、`:38-44`、`:136-142`；`muyu_window.png`。
  - 函数：`gateway.EditorialDaily`、`catalog.Daily` / `normalizeDailySongs`、`main.App.DailyRecommendations`。
    - `MUYU_HOME_RECOMMENDATION.md:106-117`、`:139`。
  - 点击路径有 `main.openHomeDestination` / `refreshHomeDestination`，但“卡片直接起播还是打开详情”的确定证据 **未找到**。
    - `MUYU_HOME_RECOMMENDATION.md:141`。

### 2.2 API

| 项 | 值 |
|---|---|
| Endpoint | `GET /music-operation-service/v3/service/musiclist/detail/bymusiclistid?` |
| Query | `musicListID=a001`、`copyrightSwitch=1`、`start=0`、`limit=30` |
| 真实 ID | `musicListID = a001`；首页 `contentType = 4`（歌单） |
| 响应 | `playListSongInfoList` / `songSimpleInfos` / `contentSimpleInfos` / `listRcmInfos`，最终归一化为歌曲 |
| 鉴权 | 同 §1.2 Digest |

证据：

- `a001` 是首页 `contentType=4` 歌单：`HUAWEI_204_PROTOCOL.md:41-47`；`MUYU_HOME_RECOMMENDATION.md:138`。
- 当前日志实测该请求 200、66,902B、30 首：`LOG_TRIAGE_2026-11-26T20-06.md:120`。
- 因此 `GET` 已被真机日志证实；旧报告里“E5 记录 POST body”的冲突，应以本轮 200 + 30 首的 GET 为准。
  - 冲突本身：`MUYU_HOME_RECOMMENDATION.md:290`。

### 2.3 队列 / 音质 / 分页

- 队列：30 首整张 `a001` 歌单；点任意一首后，下一首在本歌单内续播。
  - 这是由“daily30 返回 30 首 + 卡片进入同一列表”得出的 **inference**；沐语内部是否把“a001 当前页”还是“全部 30 首”作为 queue，**未找到**逐函数证据。
- 音质：按每首歌上游 `fileInfos` 档位走 §7；默认最高，失败降标准。
- 分页/换组：每日30首本身是 30 首固定列表；没有找到“上一组/下一组”在每日30首上的独立证据。
- 刷新：`EditorialDaily` / `refreshHomeDestination`；首页 `刷新主页`。
  - `MUYU_HOME_RECOMMENDATION.md:139-142`、`:198`。
- 缓存：首页 JSON 落盘 **未找到**；只确认内存 catalog 与图片缓存。

### 2.4 失败降级 / 空态

- 真实接口失败时，沐语应显示空态/重试；没有找到用其他板块填充每日30首的证据。
- 当前 Hmusic：
  - `daily30()` 固定 `start=0&limit=30`，并 `.take(30)`。
    - `lib/protocol/huawei_api.dart:2073-2092`。
  - `discover()` 若 `daily` 为空，则用 `data.daily`，仍空则 `fallbackPart(0,5)`。
    - `lib/protocol/huawei_api.dart:1966-1968`。
  - `playCard('daily')` 空时退到 `discover.radio`。
    - `lib/services/app_state.dart:700-710`。
  - 这不是沐语证据支持的“独立日推”语义。

---

## 3. 心动模式

### 3.1 UI / 入口 / 点击

- 首页第 3 张卡，标题 `心动模式`，大红心封面，副标题“歌名 · 歌手”。
  - 证据：`muyu_window.png`；`MUYU_HOME_RECOMMENDATION.md:13`、`:38-44`、`:144-149`。
- 点击：切到心动队列并续播，不是复用“现在就听”。
  - 函数：`main.toggleHeart` / `activateHomeHeartQueue` / `canEnterHeart` / `refillHeart`；`main.App.HeartRecommendations`。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:116`、`:146-148`。

### 3.2 API / 参数

**未找到。**

- 二进制中没有 heart 专属路径常量。
- `privatefm` 的 `rcmMode` 只接受 `1/2/3`，但没有证据说明哪个值等于“心动”。
- 不能把 `privatefm(mode=2)` 当成事实；这是当前 Hmusic 的推断。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:146-149`、`:286`。

### 3.3 真实 ID / 字段

- 没有找到真实 `contentID` / `contentType` / `serviceType` / `chartId`。
- 只有函数名和 `HeartRecommendations`，没有响应字段级证据。
- 结论：**端点、参数、响应字段均为 unknown**。

### 3.4 队列语义

- `activateHomeHeartQueue` 暗示独立队列，与 `listen` 并列，不是复用首页歌曲。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:148`、`:195`。
- 队列长度、分页、续播游标：**未找到**。

### 3.5 音质 / 缓存 / 失败

- 音质同 §7。
- 缓存：**未找到**。
- 失败降级：**未找到**；不能假定回填“现在就听”或热歌。

### 3.6 当前 Hmusic 差异

- `parseDiscover()` 用 `pmf001` 批次的 `id/label` 是否含 `heart` / `心动` 来切心动。
  - 代码：`lib/protocol/huawei_api.dart:2356-2359`、`:2382`。
- `discover()` 若 `data.heart` 为空，用 `fallbackPart(2,5)` 填。
  - 代码：`lib/protocol/huawei_api.dart:1960-1962`。
- `playCard('heart')` 空时请求 `privateRadio(mode:'2')`，仍空退 `discover.radio`。
  - 代码：`lib/services/app_state.dart:712-723`。
- 现有测试 `test/playback_entry_test.dart:169-186`、`:490-513` 正在锁死“全带标签的 pmf001 + 8011 空 + privatefm 400 仍有数据”的兜底行为；这与沐语“心动端点未找到”的证据边界冲突，后续应改成“独立板块空就是空 / 先验证端点”的测试。

---

## 4. 新歌推荐

### 4.1 UI / 入口 / 点击

- 首页第 4 张卡，标题 `新歌推荐`，带 `New` 角标，封面专辑图，副标题“歌名 · 歌手”。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:13`、`:38-44`、`:151-156`；`home-editorial/new`，`_strings_204.tsv` off=14786802 / 14765302。
- 换批：`上一组歌曲` / `下一组歌曲`，按“组”翻。
  - 证据：`_strings_204.tsv` off=14765302；`MUYU_HOME_RECOMMENDATION.md:156`、`:196`。
- 点击：起播“新歌”批次；是否打开详情 **未找到**。

### 4.2 API / 参数

**未找到专属端点。**

候选（均未验证）：

1. `page/detail/all` 的 `contentType=96` 分区，读 `childSimpleInfos`。
   - `HUAWEI_204_PROTOCOL.md:41-54`。
2. `column/detail/bycolumnid` 的某个新歌栏目。
   - `MUYU_HOME_RECOMMENDATION.md:155`。
3. `pmf001` 下带 `new/新歌` 标签的子批次。
   - `MUYU_HOME_RECOMMENDATION.md:153-155`；当前 Hmusic 采用这一推断。

### 4.3 真实 ID / 字段

- 没有固定的 `contentID` / `columnId` / `chartId`。
- 解析兼容精简键 `ID` / `NM` / `pic` 与完整键 `contentID` / `contentName` / `durationSeconds` / `artistNamePairs`。
  - 证据：`MUYU_FULL_FUNCTION_MAP.md:133`；`MUYU_HOME_RECOMMENDATION.md:154`。
- 取歌字段仍为 `listRcmInfos` / `songSimpleInfos` / `contentSimpleInfos`。

### 4.4 队列 / 分页

- 队列 = 当前“组”的新歌列表；点歌后在该组内续播（inference）。
- 组大小：**未找到**。
- “上一组/下一组”是否重新请求服务端、还是本地切批：**未找到**。

### 4.5 音质 / 缓存 / 失败

- 音质同 §7。
- 缓存：**未找到**。
- 空态/降级：没有找到“新歌为空就拿每日/热歌填充”的证据；应显示空态。

### 4.6 当前 Hmusic 差异

- `parseDiscover()` 读 `contentType=96` 的 `childSimpleInfos`，并读 `pmf001` 中 `new/新歌/newsong` 批次。
  - 代码：`lib/protocol/huawei_api.dart:2323-2335`、`:2359-2362`、`:2383`、`:2442-2445`。
- 空时用 `fallbackPart(3,5)` 填。
  - 代码：`lib/protocol/huawei_api.dart:1963-1965`。
- `home_page.dart._changeGroup()` 只改 `_cardGroup`，只换卡片预览歌，不请求新的一组新歌。
  - 代码：`lib/widgets/home_page.dart:277-282`、`:464-470`。
  - 这是“上一组/下一组”的假实现：数据没有换组。

---

## 5. 为你推荐

### 5.1 UI / 入口 / 点击

- 首页 5 卡下方的歌曲列表，右上 `1 / 5` + 左右箭头；每行封面 / 歌名 / 歌手 / 收藏 / 加歌单。
  - 证据：`muyu_window.png`；`MUYU_HOME_RECOMMENDATION.md:13`、`:45`、`:166`。
- 点击某首：播放该首，队列 = 当前“为你推荐”列表。
  - inference：`MUYU_HOME_RECOMMENDATION.md:170`。

### 5.2 API

| 项 | 值 |
|---|---|
| Endpoint | `GET /music-operation-service/v1/service/column/detail/bycolumnid?` |
| Query | `columnId=8011&start=0&limit=30&hasRecommend=1`；栏目键 `recom_exclusive`，兜底栏目号 `8011` |
| 方法 | GET（字面量本身带 `?`） |
| 响应取歌 | `columnInfoExs` / `contentSimpleInfos` / `listRcmInfos` / `songSimpleInfos` |
| 鉴权 | 同 §1.2 Digest |

证据：

- 端点：`_strings_204.tsv` off=15004256；`MUYU_HOME_RECOMMENDATION.md:63`、`:167`。
- `recom_exclusive` → `8011` 相邻字符串：`_strings_204.tsv` off=14795940；`MUYU_HOME_RECOMMENDATION.md:80-82`。
- 错误文案“首页未返回私享好歌列表或栏目编号”“栏目详情未返回私享好歌列表”：`MUYU_HOME_RECOMMENDATION.md:82`、`:171`。

### 5.3 分页 / 缓存

- UI 分页器 `1/5` 是 observed；它是服务端 `start/limit` 分页还是前端切组，**未找到**。
  - `MUYU_HOME_RECOMMENDATION.md:169`、`:288`。
- 缓存：**未找到**；不要假定首页 JSON 落盘。

### 5.4 队列 / 音质 / 失败

- 队列：当前这批“为你推荐”歌曲（inference）；点歌后续播仍在同一批。
- 音质同 §7。
- 失败：
  - 8011 空响应是 observed：2026-11-26 日志 200、61B、0 首，`featuredSongs raw=0 parsed=0 empty=true`。
    - `LOG_TRIAGE_2026-11-26T20-06.md:119`、`:167`。
  - 沐语在栏目号缺失/栏目详情无歌时显示错误文案和空态，不伪造新歌。
    - `MUYU_HOME_RECOMMENDATION.md:171`。

### 5.5 当前 Hmusic 差异

- `featuredSongs()` 固定 `columnId=8011`，请求 `start=0&limit=30&hasRecommend=1`，并记录 raw/parsed/empty。
  - 代码：`lib/protocol/huawei_api.dart:2052-2071`。
- `recommendedColumnId` 永远写成 `featuredColumnId`，没有从响应 `columnInfoExs` 动态取真实栏目号。
  - 代码：`lib/protocol/huawei_api.dart:1972`、`:2467`。
- `discover()` 在 `featured` 空时用 `data.recommended`，仍空则 `fallbackPart(1,5)`。
  - 代码：`lib/protocol/huawei_api.dart:1952-1956`。
  - 这会把“8011 真空”伪装成“有推荐”，与沐语空态语义相反。
- `HomePage` 只读 `discover.recommended`，UI 按 5 首/页本地切页。
  - 代码：`lib/widgets/home_page.dart:35-39`、`:59-70`。
  - 沐语 `1/5` 是否服务端分页未找到；当前实现是纯前端 5 首切页。
- `playSongFromList(context, state, song, songs)` 传入整个推荐列表，队列语义正确。
  - 代码：`lib/widgets/home_page.dart:94-100`；`lib/widgets/common.dart:601-616`。

---

## 6. 搜索

### 6.1 UI / 入口 / 点击

- 首页顶部有搜索框，提交后 `state.doSearch` 并切到搜索页；搜索页顶部也有搜索框。
  - 代码：`lib/widgets/home_page.dart:198-223`；`lib/pages/secondary_pages.dart:52-65`。
- 搜索页三个 tab：歌曲 `N` / 歌手 `N` / 专辑 `N`。
  - 代码：`lib/pages/secondary_pages.dart:94-122`。
- 点歌曲行：`playSongFromList(..., songs)`，队列 = 整个当前歌曲结果列表。
  - 代码：`lib/pages/secondary_pages.dart:124-136`；`lib/widgets/common.dart:601-616`。
- 点歌手：打开歌手页；点专辑：按 `album` 类型打开歌单。
  - 代码：`lib/pages/secondary_pages.dart:138-217`；`lib/services/app_state.dart:487-503`。

### 6.2 API

| 项 | 值 |
|---|---|
| Endpoint | `POST /music-search-service/v10/service/fuzzysearch` |
| Body | `contentType`、`correct:"1"`、`queryWord`、`start:"0"`、`limit:"20/30"`（全部字符串字段） |
| contentType | `1`=歌曲、`2`=专辑、`3`=歌手、`4`=歌单 |
| 响应取歌 | `songSimpleInfos`，兼容 `contentSimpleInfos` / `songs` / `songList` |
| 歌手/专辑 | `artistSimpleInfos` / `artistInfoExs` / `albumSimpleInfos` / `albumInfoExs` |
| 鉴权 | 同 §1.2 Digest |

证据：

- 端点：`HUAWEI_204_PROTOCOL.md:67`；`MUYU_FULL_FUNCTION_MAP.md:105`。
- contentType 语义：`HUAWEI_204_PROTOCOL.md:67`；`TINGLAN_SOURCE_REFERENCE.md:70`。
- 真实账号验证搜索歌曲 30 / 歌手 30 / 专辑 30：`MUYU_204_MODULE_MAP.md:48`。

### 6.3 沐语搜索实现边界

- observed：端点、contentType 语义、能返回歌曲/歌手/专辑。
- inference：搜索结果点歌后以结果列表为队列；这一点由播放层通用队列语义推出，沐语内部队列字段 **未找到**。
- unknown：
  - 沐语是“一次请求返回三类”还是“按 contentType 分别请求三次” **未找到**。
  - 搜索分页/加载更多 **未找到**。
  - 搜索历史/搜索元数据 UI（符号 `native_search_history.go` / `native_search_metadata.go`）的具体交互 **未找到**。

### 6.4 当前 Hmusic 搜索差异

- `searchAll()` 并发发 3 个请求：`contentType=1/2/3`，`start=0`、`limit=30`。
  - 代码：`lib/protocol/huawei_api.dart:365-416`。
- `_searchJson()` body 使用字符串字段，符合源码事实。
  - 代码：`lib/protocol/huawei_api.dart:418-435`。
- 每个类型单独 `catch (_) => null`，某一类失败时只丢该类，不把整体错误抛给 UI。
  - 代码：`lib/protocol/huawei_api.dart:370-393`。
- 没有搜索分页/加载更多；每次只取 `start=0` 的 30 条。
  - 代码：`lib/protocol/huawei_api.dart:365-416`。
- `searchAll()` 没有请求 `contentType=4` 歌单；沐语搜索是否展示歌单 **未找到**，当前只展示歌曲/歌手/专辑。
- 搜索队列正确：`SearchPage._songResults()` 把完整 `state.searchResults` 传给播放。
  - 代码：`lib/pages/secondary_pages.dart:128-135`。

---

## 7. 播放 / 取流

### 7.1 取流 API

| 项 | 值 |
|---|---|
| Endpoint | `POST /music-play-service/v3/service/file/bycontentcode` |
| Body | `contentCode`（歌曲真实 ID / contentID / songCode）、`contentType:"1"`、`qualityType` |
| 方法 | POST JSON |
| 响应主字段 | 顶层 `fileURL` 是可直接播放的 https 签名地址；`fileInfos` 为辅助档位 |
| 其他字段 | `size` / `fileSize`、`playQuality` / `qualityType`、`playFragmentFlag`、`fragmentInfo.hasFragement`、`auditionEnd` / `auditionTime` |
| 鉴权 | 同 §1.2 Digest |

证据：

- 端点：`HUAWEI_204_PROTOCOL.md:72`；`MUYU_FULL_FUNCTION_MAP.md:119`；`REA_DEEP_PLAYER_ANALYSIS.md:140`。
- body 字段：`MUYU_FULL_FUNCTION_MAP.md:134`；`TINGLAN_SOURCE_REFERENCE.md:73`。
- 顶层 `fileURL` 实测：`HUAWEI_204_PROTOCOL.md:88-92`；`TINGLAN_SOURCE_REFERENCE.md:79`。
- `contentType` 固定 `"1"`，不是歌曲码：`LOG_TRIAGE_2026-11-26T20-06.md:103`。

### 7.2 音质档位

华为 `qualityType` / `fileInfos.quality`：

| qualityType | 含义 |
|---|---|
| `1` | MQ / standard MP3 |
| `2` | HQ |
| `3` | SQ / lossless FLAC |
| `5` / `7` | Hi-Res |

证据：`HUAWEI_204_PROTOCOL.md:90`；`MUYU_HOME_RECOMMENDATION.md:777-783`（当前代码注释引用同一实测）。

沐语运行时：

- `quality = "hires"`，即默认请求最高档。
- `confirmedAudio` 里可以看到 `requested: "hires"` 但实际 `quality: "lossless" | "standard" | "hq"`，说明“请求最高 ≠ 实际最高”，客户端必须接受降档。
  - 证据：`C:/沐语/independent-data/native-ui.json` 的 `quality` 与多条 `confirmedAudio`。
- `platformQuality` 是分音源档位：`kugou=viper_clear`、`netease=jymaster`、`qq=RS01`。
  - 证据：`native-ui.json` 的 `platformQuality`。
- 华为 `fileInfos` 档位来自上游，不在客户端写死“标准/无损两档循环”。
  - 证据：`NETEASE_AND_QUALITY_DECOMPILED.md:83-91`（结论同样适用于华为的上游档位模型）。

### 7.3 试听 / preview / fragment

- observed：无 Hi-Res 权限时，`qualityType=7` 仍可 200，但 `fileURL` 是 `_AQ.mp3`，约 465KB / 30 秒，并带 `auditionEnd/auditionTime`；同曲 `1/2/3/5` 是 4.3/10.8/23/51MB 的完整文件。
  - 证据：`HUAWEI_204_PROTOCOL.md:94-98`。
- 判定优先级：
  1. URL 路径含 `_AQ` / `_PV`（`/preview/` 也应视为试听）。
  2. `playFragmentFlag == "1"`。
  3. `fragmentInfo.hasFragement == "1"` 且带 `auditionEnd` / `auditionTime`。
- 注意：`auditionTime` 单独不能判定试听，全曲也可能有；`/preview/` 才是源码事实中的强判定。
  - 证据：`TINGLAN_SOURCE_REFERENCE.md:80`。
- 60 秒试听：**未找到**；实测是约 30 秒 `_AQ`，旧日志也没有 30/60 秒泄漏。
  - `LOG_TRIAGE_2026-11-26T20-06.md:143-145`。

### 7.4 业务码与降级

| 码/条件 | 语义 | 正确动作 |
|---|---|---|
| `142411` / “Only super diamond vip” / “超级钻石” | 当前档位需要超级钻石 VIP | 继续尝试下一档，通常最终 `standard(1)` |
| `142400` / 无版权 / 不可播放 / 没有可用 | 当前歌曲或档位不可用 | 继续下一档；全部失败则报“不可播” |
| `990000` | 鉴权/请求头不合规（额外 `x-*` 头等） | **立即中止降档**，提示重新登录 / 修请求头 |
| `990006` / token expired / 令牌过期 | 登录态失效 | **立即中止降档**，要求重新登录 |
| HTTP 400 privatefm `refInfo` 数组 | 字段类型错误 | `refInfo` 必须是字符串 |
| HTTP 400 recommend/playlist 0B | 具体字段未知 | 不能用假请求体硬修；记录并走真实歌单兜底 |

证据：

- `142411` / `142400` / `990000` / `990006` 处理：`lib/protocol/huawei_gateway.dart:43-67`、`:431-483`。
- 2026-11-26 日志：142411 后继续 5/3/1；990000/990006 都在登录前；OAuth 成功后不再出现。
  - `LOG_TRIAGE_2026-11-26T20-06.md:19`、`:78-85`、`:139`。
- `privatefm` 400 类型错误：`LOG_TRIAGE_2026-11-26T20-06.md:168`。

### 7.5 播放链路与队列

沐语：

- `catalog.Library.Locate` / `LocateBest` / `LocateFromFiles` / `LocateQuality` / `huaweiAudioFiles` 取流。
- `nativeaudio` 负责 Media Foundation / FLAC / MP3 / seek；`media.Proxy.PublishStream / ServeHTTP / Revoke` 把 CDN 签名 URL 包装成本机回环 URL，透传 Range。
- 证据：`MUYU_FULL_FUNCTION_MAP.md:84-85`；`REA_DEEP_PLAYER_ANALYSIS.md:59-65`；`TINGLAN_SOURCE_REFERENCE.md:97-100`。
- 队列：`playback.go` / `native_queue*.go` / `native_play_timers.go`；三态播放模式（列表循环 / 随机 / 单曲）。
  - 证据：`MUYU_FULL_FUNCTION_MAP.md:49`；`REA_DEEP_PLAYER_ANALYSIS.md:94-99`。

当前 Hmusic：

- `AppState.play(song, queue)` 把传入列表整体作为队列；点歌后 `MuyuAudioController.playSong` 真正取流和播放。
  - 代码：`lib/services/app_state.dart:843-887`。
- `playSong` 先取全部可用档位，`playbackCandidates` 从目标档位向下排序；逐档 `LeaseProxy.publish` + `AudioPlayer.play`，失败后 `stop` 再试下一档。
  - 代码：`lib/services/audio_controller.dart:253-352`、`:374-386`。
- 成功后 `onPlayerComplete` 调 `next()`；`next()` 在本地 `queue` 内循环，单曲模式重播当前曲，随机模式取时间戳取模。
  - 代码：`lib/services/audio_controller.dart:46-51`、`:553-566`。
- `playSong` 使用 `mimeTypeFor` 显式给 `UrlSource` 传 `audio/flac` / `audio/mpeg` 等 MIME，避免租约代理无扩展名。
  - 代码：`lib/services/audio_controller.dart:388-400`。
- `LeaseProxy` 透传 `Range` / `Content-Range` / `Content-Length`，并将 `audio/x-flac` 归一为 `audio/flac`。
  - 代码：`lib/services/lease_proxy.dart:52-143`、`:156-174`。

### 7.6 当前 Hmusic 播放差异 / 风险

1. **队列续播不会自动跳过下一首的失败**：
   - `AppState.play` 对首次点歌会尝试最多 5 首（`lib/services/app_state.dart:855-883`）。
   - 但播放完成后的 `MuyuAudioController.next()` 直接 `playSong(queue[nextIndex])`，失败只置 `error`，不会继续 `next()`。
   - 结果：第一首能播、后续某首 FLAC 解码失败时，播放会停住，而不是自动跳下一首。
2. **电台没有服务端续播**：
   - `privateFm()` 只请求一页；`queue` 106 首的 `next/more` 没有进入 `AudioController` 或 `AppState`。
   - 与沐语 `expandHomeRadio` / `nextPlatformHomeRadio` 不一致。
3. **试听判定缺 `/preview/`**：
   - `_isAudition` 只判 `_AQ` / `_PV` 后缀、`playFragmentFlag`、`fragmentInfo + audition`。
     - `lib/protocol/huawei_api.dart:1036-1052`。
   - 没有判 URL path 是否包含 `/preview/`；而源码事实明确 `/preview/` 是强判定。
     - `TINGLAN_SOURCE_REFERENCE.md:80`。
4. **失败后 `lastHasUrl` 被置 false**：
   - 所有档位都取到过 URL 但解码失败时，`catch` 里把 `lastHasUrl=false`。
     - `lib/services/audio_controller.dart:353-367`。
   - 这只影响日志，但会误导“URL 有没有取到”的排障。
5. **`audioFiles` 的档位请求顺序是“每档带一串 code”**：
   - `hiRes -> 7/5/3`、`lossless -> 3/2/5`、`standard -> 1/2/3`，并始终补 standard。
     - `lib/protocol/huawei_api.dart:779-783`。
   - 这是当前实现的选择；沐语 2.0.4 是否有同样的 `7/5/3` 顺序，只对 `7→5→3` 有抓包证据，其余档位的顺序 **未找到**。

---

## 8. 本次日志现象逐条解释

基线：`LOG_TRIAGE_2026-11-26T20-06.md`，日志 192 条，20:03:50–20:05:35。

### 8.1 “收藏能播、其他不能播”

- 收藏条目没有可识别 `fileInfos`，`qualitiesFromUpstream` 保守返回 `{standard}`，取流只请求 `qualityType=1`，拿到完整 MP3。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:16`、`:58-64`、`:132-135`。
- 搜索/歌手/榜单条目带上游 `fileInfos`，`chooseQuality` 默认 `hiRes`，选中 `qualityType=5` 的 FLAC。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:78-85`、`:136-137`。
- URL 已取到，iOS AVPlayer 对 FLAC `setSourceUrl` 失败；旧播放层只试一次，不降档。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:17-18`、`:156-161`。
- 当前代码已加逐档 `play` 失败后降级 + MIME 归一，理论覆盖该根因；但 AVPlayer 拒绝该 FLAC 的精确底层原因 **未找到**。
  - 代码：`lib/services/audio_controller.dart:266-352`；`lib/services/lease_proxy.dart:156-174`。
  - 边界：`LOG_TRIAGE_2026-11-26T20-06.md:161`、`:268`。

### 8.2 “8011 空”

- 2026-11-26 日志：`column/detail/bycolumnid?columnId=8011` 200、61B、0 首。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:119`、`:167`。
- 沐语也可能遇到 8011 空；它的正确行为是显示“首页未返回私享好歌列表或栏目编号”一类空态，而不是拿热歌填充。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:171`。
- 当前 `discover()` 会把 `fallbackPart(1,5)` 填进 `recommended`，所以 UI 可能不再显示 8011 空态，这反而偏离沐语。
  - 代码：`lib/protocol/huawei_api.dart:1952-1956`。

### 8.3 `privatefm` 400

- 日志 L56 服务端明确：`Cannot deserialize value of type java.lang.String from Array value`；旧代码把 `refInfo` 传成 `[]`。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:117`、`:168`。
- 当前代码已改为字符串 `''`。
  - 代码：`lib/protocol/huawei_api.dart:2125-2128`。
- 改成字符串后是否一定 200：**未找到**真机复测证据；如果仍 400，需要真实 `refInfo` 内容，不能继续猜。
  - 边界：`LOG_TRIAGE_2026-11-26T20-06.md:267`。

### 8.4 `recommend/playlist` 400

- 日志 L58-L59：400、0B，具体字段 **未找到**。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:118`、`:169`、`:266`。
- 当前代码请求体为 `contentType:1, start:0, limit:30`，并在空时用同账号真实 `playlists()` 兜底。
  - 代码：`lib/protocol/huawei_api.dart:2146-2165`、`:1897-1905`。
- 这是合理的产品降级，但不是沐语协议事实；`recommend/playlist` 的正确 body 仍需抓包/反编译补证。

### 8.5 `24926` 热歌 200 首

- 日志实测 `chart/detail/bychartid?24926` 200、200 首。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:121`。
- 当前 `chartSongs()` 用 `chartID + chartId + contentType=1 + start/limit` GET，逐页拉到 200 首。
  - 代码：`lib/protocol/huawei_api.dart:2176-2196`、`:2199-2223`。
- 但“热歌速递卡片 = 24926”仍是 **inference**；沐语报告明确写“热歌速递专属端点未找到，推断为热歌榜”。
  - 证据：`MUYU_HOME_RECOMMENDATION.md:160-161`、`:287`。

### 8.6 “独立板块未返回歌曲”

- 旧逻辑 `parseDiscover` 只有在 `pmf001` 的未标签批次 `remaining` 非空时才给 `listen/recommended/heart/new/hot` 分槽；全部批次带标签时 `listen/recommended` 为空。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:171-174`。
- 旧 `_dedupeHomeSections` 用全局 `seen`，会把与 24926 重复的板块整段删空。
  - 证据：`LOG_TRIAGE_2026-11-26T20-06.md:174`。
- 当前代码已把 `_dedupeHomeSections` 改成“全重复至少保留第一首”，并加 `fallbackPool`。
  - 代码：`lib/protocol/huawei_api.dart:1995-2037`、`:1930-1968`。
- 但“用 fallbackPool 填满”并不是沐语证据支持的独立板块行为；它会把“接口确实没返回”变成“别的板块有歌”。正确的产品语义应是：
  - 有真实独立源 → 用真实源；
  - 真实独立源为空 → 显示空态 / 可重试；
  - 不把 24926 / a001 / 8011 互相填充成六个不同标题。

---

## 9. 当前 Hmusic 与沐语的关键差异清单

| 优先级 | 差异 | 证据 / 代码 |
|---|---|---|
| P0 | 首页跨板块 `fallbackPool`：每日/热歌/8011 的歌词被轮流塞进 listen/heart/new | `huawei_api.dart:1930-1968`；沐语独立队列 `MUYU_HOME_RECOMMENDATION.md:195` |
| P0 | 心动模式端点未找到，当前用 `pmf001` 标签 + `privatefm(mode=2)` 推断 | `huawei_api.dart:2356-2362`、`app_state.dart:712-723`；`MUYU_HOME_RECOMMENDATION.md:146-149` |
| P0 | 现在就听只有单页，没有 `next/more` 续播游标；队列在本地循环 | `audio_controller.dart:553-566`；`native-ui.json playback.source` |
| P0 | 播放完成后的 `next()` 不自动跳过下一首的取流/解码失败 | `audio_controller.dart:46-51`、`:553-566`；`app_state.dart:855-883` |
| P1 | “上一组/下一组”只换卡片预览，不重新取组 | `home_page.dart:277-282`、`:464-470`；沐语 `上一组/下一组` `_strings_204.tsv` off=14765302 |
| P1 | 8011 空被 fallback 填满，丢失真实空态 | `huawei_api.dart:1952-1956`；日志 L61 空 |
| P1 | 推荐栏目号硬编码 8011，不从 `columnInfoExs` 动态取 | `huawei_api.dart:1972`、`:2467` |
| P1 | 热歌速递绑定 24926 是推断，不是证据 | `huawei_api.dart:1884-1888`；`MUYU_HOME_RECOMMENDATION.md:160-161` |
| P1 | 搜索只取首批 30 条，没有加载更多；未请求 contentType=4 歌单 | `huawei_api.dart:365-416` |
| P1 | 试听判定缺 `/preview/` 强判据 | `huawei_api.dart:1036-1052`；`TINGLAN_SOURCE_REFERENCE.md:80` |
| P1 | `recommend/playlist` 请求体未被验证，400 0B | `huawei_api.dart:2146-2165`；日志 L58-L59 |
| P2 | 卡片点击打开分页页，不是像“现在就听”那样直接起播 | `home_page.dart:230-245`、`:575-667` |
| P2 | 首页 JSON 无落盘缓存，每次 refresh 重新请求 6 路 | `huawei_api.dart:1866-1888`；`app_state.dart:302-305` |
| P2 | `audioFiles` 失败时把 `lastHasUrl=false`，日志误导 | `audio_controller.dart:353-367` |

---

## 10. 实现子代理后续优先改什么

> 只列改动点，不在本轮改代码。

### 10.1 协议 / 数据层

1. `lib/protocol/huawei_api.dart`
   - `discover()`：删除/收窄全局 `fallbackPool`；每个板块只用自己的真实源。
   - `parseDiscover()`：保留 `contentType=96`、`contentType=12`、`pmf001` 的三层解析，但不要把 `remaining` 轮询分给 heart/new/hot/listen。
   - `privateFm()`：增加 `rcmScenario` 参数；补 `next/more` 分页/续播方法（先验证 `privatefm` 返回的游标字段）。
   - `featuredSongs()`：优先从 `columnInfoExs` 取真实 `columnId`，`8011` 只作兜底；8011 空时保持空。
   - `recommendedPlaylists()`：不要为 400 猜 body；保留真实 `playlists()` 兜底，但标注“非沐语原生推荐歌单”。
   - `audioFiles()`：补 `/preview/` 判定；考虑把 `auditionEnd` 单独作为弱信号记录；保持 142411/142400 继续、990000/990006 中止。
   - `searchAll()`：加 `start/limit` 分页；评估是否请求 contentType=4；把每类错误显式带回 UI，而不是静默 `null`。

2. `lib/services/app_state.dart`
   - `playCard()`：不要再用 `discover.radio` 填充 daily/heart/hot；空就报“接口未返回”。
   - `_loadHuaweiHome()`：`homeSongs` 只作为全局默认入口，不参与卡片。
   - 为 `listen/heart` 增加独立队列状态（例如 `radioCursor` / `heartCursor`），不要让 `AudioController.queue` 直接循环一页。

3. `lib/services/audio_controller.dart`
   - `next()`：失败时自动继续下一首（带最大尝试数，避免无限循环）；或者复用 `AppState.play` 的“最多 5 首”策略。
   - `playSong()`：全档失败时保留 `lastHasUrl` / `lastQualityType`，只把 `lastErrorCode` 置为失败码。
   - 如要支持电台续播，增加“队列尾部回调”而不是在 `next()` 里直接取模。

4. `lib/widgets/home_page.dart`
   - `_changeGroup()`：如果沐语真实是服务端换组，改为请求新组；若未验证，先不要把它标成“换一批”。
   - 卡片点击：区分“打开详情”和“直接起播”；沐语“现在就听”证据支持直接起播。

### 10.2 测试（优先窄测试）

- `test/playback_entry_test.dart:490-513` 当前断言“8011 空 / privatefm 400 / recommend 400 仍有数据”。这条应拆成：
  - 真实独立源存在时，各板块用自己的数据；
  - 独立源为空时，板块保持空，不跨板块填充；
  - `privatefm` body 的 `refInfo` 是字符串；
  - `privatefm` 返回 `next/more` 时，队列能续播。
- 新增 `test/home_section_independence_test.dart`：五个列表互不相同，任一为空不被其他列表填充。
- 新增 `test/playback_fallback_test.dart`：142411 → 5/3 FLAC 失败 → 1 MP3 成功；990000 不降档；`/preview/` URL 被拒绝；`_AQ/_PV` 被拒绝。
- 新增 `test/playback_queue_test.dart`：next/previous 按 ID 重新取流；下一首失败会自动跳到再下一首（设定上限）。
- 保留 `test/live_home_dump_test.dart` 作为真机探针：它已经打印 HOME columns、DISCOVER 计数、8011/privatefm/24926 结果，适合验证“独立板块是否真空”。
  - 代码：`test/live_home_dump_test.dart:22-125`。
- `test/live_huawei_probe_test.dart:56-61` 已断言 Hi-Res 请求不得返回 `_AQ/_PV`；补充 `/preview/`。
- `test/live_playback_scan_test.dart:19-75` 适合逐首扫描首页/搜索/榜单可播性，验证不是“只有收藏能播”。

---

## 11. 未找到 / 禁止编造

1. 心动模式的端点、参数、响应字段、队列长度：**未找到**。
2. 新歌推荐的专属端点、真实栏目 ID、组大小：**未找到**。
3. 热歌速递卡片是否绑定 24926：**inference，未验证**。
4. 为你推荐 `1/5` 是服务端 `start/limit` 分页还是前端切组：**未找到**。
5. 首页 JSON 是否落盘缓存：**未找到**；只确认图片缓存。
6. `privatefm` 的 `next/more` 精确语义、`refInfo` 非空格式、`rcmScenario=21` 的触发条件：**未找到**。
7. 沐语搜索是一次请求返回三类，还是按 contentType 分三次请求：**未找到**。
8. 沐语搜索分页、搜索历史/元数据交互：**未找到**。
9. 沐语“每日30首”卡片点击是直接起播还是打开详情：**未找到**。
10. `recommend/playlist` 400 的具体缺失字段：**未找到**（响应 0B）。
11. AVPlayer 拒绝华为 FLAC 的精确底层原因：**未找到**。
12. 60 秒试听：**未找到**；只实测约 30 秒 `_AQ`。
13. 990006 的精确服务端触发条件：**未找到**；当前按鉴权失效处理。

---

## 12. 证据索引

| 结论 | 证据 |
|---|---|
| 首页 5 卡顺序 / 为你推荐 1/5 | `rea_evidence/muyu_window.png`；`MUYU_HOME_RECOMMENDATION.md:13`、`:45` |
| 现在就听 3 封面拼贴 / 卡片容器 | `_strings_204.tsv` off=14753209、14786802；`MUYU_HOME_RECOMMENDATION.md:91-94` |
| 现在就听 = radio / listen / 106 首 | `C:/沐语/independent-data/native-ui.json` → `playback.source`、`playback.queue`、`playback.index` |
| `privatefm` 端点 / 参数 | `_strings_204.tsv` off=14993173；`MUYU_HOME_RECOMMENDATION.md:128-130`；`MUYU_FULL_FUNCTION_MAP.md:132` |
| `pmf001` 三层结构 | `home_decomp.txt:2`；`MUYU_HOME_RECOMMENDATION.md:73-78` |
| 每日30首 `a001` / GET 200 30 首 | `HUAWEI_204_PROTOCOL.md:41-47`；`LOG_TRIAGE_2026-11-26T20-06.md:120` |
| 心动模式只有函数名 | `MUYU_HOME_RECOMMENDATION.md:146-149`、`:286` |
| 新歌推荐无专属端点 | `MUYU_HOME_RECOMMENDATION.md:153-156`、`:287` |
| 新歌组翻页按钮 | `_strings_204.tsv` off=14765302；`MUYU_HOME_RECOMMENDATION.md:94`、`:156` |
| 为你推荐 8011 / recom_exclusive | `_strings_204.tsv` off=14795940、15004256；`MUYU_HOME_RECOMMENDATION.md:80-82`、`:167` |
| 8011 空 61B | `LOG_TRIAGE_2026-11-26T20-06.md:119`、`:167` |
| 搜索端点 / contentType | `HUAWEI_204_PROTOCOL.md:67`；`TINGLAN_SOURCE_REFERENCE.md:70` |
| 取流端点 / body / fileURL | `HUAWEI_204_PROTOCOL.md:72`、`:88-92`；`MUYU_FULL_FUNCTION_MAP.md:119`、`:134` |
| 音质 1/2/3/5/7 | `HUAWEI_204_PROTOCOL.md:90` |
| 试听 `_AQ` / audition | `HUAWEI_204_PROTOCOL.md:94-98`；`TINGLAN_SOURCE_REFERENCE.md:80` |
| 142411 / 990000 / 990006 | `LOG_TRIAGE_2026-11-26T20-06.md:19`、`:78-85`、`:139`；`huawei_gateway.dart:43-67`、`:431-483` |
| 当前首页 fallback | `lib/protocol/huawei_api.dart:1930-1968` |
| 当前心动推断 | `lib/protocol/huawei_api.dart:2356-2362`；`lib/services/app_state.dart:712-723` |
| 当前新歌组假切换 | `lib/widgets/home_page.dart:277-282` |
| 当前播放逐档降级 | `lib/services/audio_controller.dart:266-352` |
| 当前队列 next | `lib/services/audio_controller.dart:46-51`、`:553-566` |
| 当前搜索 3 路并发 | `lib/protocol/huawei_api.dart:365-416` |
| 当前测试锁死兜底 | `test/playback_entry_test.dart:490-513` |

---

## 13. 边界声明

- 本文没有修改 `lib/`、`test/` 或任何业务代码。
- 本文没有提交、推送或创建分支。
- 用户先前截图目录 `C:/Data/xwechat_files/.../2026-11/9e20f478899dc29eb19741386f9343c8/` 当前存在 6 张 jpg；本轮只确认路径存在，未逐张做进程归属/视觉复核，因此不作为独立事实来源。
- 旧文档 `MUYU_HOME_RECOMMENDATION.md` 的 §8 撤回项（`contentType=998`、`serviceType=...`、`recommend_for_you`）仍应视为不存在；当前 Hmusic 代码已不再依赖它们。
