# 沐语运行时请求体取证报告

日期：2026-11-26
目标：`C:/沐语/Muyu.exe`（沐语 2.0.4.0，Go 1.27.4，PID 52048）
范围：`privatefm`、`recommend/playlist`、`fuzzysearch`、`bycontentcode`、`bycolumnid`、`bymusiclistid`、`bychartid`

> 本文件只记录请求结构、字段名和脱敏样例。所有请求头值、token、Authorization、`security` 前缀值均为 `<redacted>`；正文中不存在 token 字段。

---

## 0. 结论摘要

1. **本轮没有拿到沐语自身的 observed-runtime 请求体。** 沐语进程处于空闲态，未点击窗口、未使用 Computer Use；本地端口不是业务 API；Go 堆在 21:07 已回收，1.6GB 可读私有内存扫描 0 命中。
2. **`privatefm` 的请求字段可以确定到 4 个：`cadence`、`rcmMode`、`rcmScenario`、`refInfo`。** 这是 `gateway.applicationRequest` 的反编译结论，属于 `decompiled`，不是本轮抓包。
3. **`refInfo` 必须是字符串。** 这一条有服务端 400 明文：“Cannot deserialize value of type java.lang.String from Array value”，但来源是 hmusic 客户端日志，不是沐语请求；它证明的是**服务端字段类型契约**。沐语首屏 `refInfo` 是否为 `""`、非空时是什么格式，仍是 `not-found`。
4. **`recommend/playlist` 当前 `{contentType:1,start:0,limit:30}` 没有证据支持。** 二进制里存在一个完整的推荐请求字面量 `{"rcmScenario":"1","termType":"1","scenario":"1","recommendStrategy":"0"}`，它是最值得先试的候选；但它属于哪个 endpoint 仍是 `inference`。
5. **`bycontentcode` 是三个字段：`contentCode`、`contentType`、`qualityType`。** 没有 `copyrightSwitch`、`resourceType`、`songCode` 的字段证据；`copyrightSwitch` 属于 `bymusiclistid`，不应混入取流请求。
6. **`bycolumnid` 的 `columnId` 更像“首页动态栏目优先、8011 兜底”**，不是硬编码 8011。`8011` 只在 hmusic 真机日志里被观测为 200/61B/0 首，沐语是否固定 8011 仍是 `inference`。

---

## 1. 进程、方法与工具

### 1.1 进程与模块

| 项 | 值 | 证据等级 |
| --- | --- | --- |
| 进程 | `Muyu.exe` PID 52048，Responding=True | observed-runtime |
| 版本 | 2.0.4.0（FileVersion），ProductVersion 2.0.4 | observed-runtime |
| 文件 SHA256 | `7D531A894FF91625B0724B3C072D2522156F53EA4ED2CC5D26BB3367ECB9F7C6` | observed-runtime |
| 编译器 | Go 1.27.4；PE32+ x86-64；ImageBase `0x140000000` | observed-runtime |
| 运行时模块基址 | `0x7ff6bb900000`（ASLR 后） | observed-runtime |
| pclntab | 33,337 个函数；magic `0xFFFFFFF1`；函数地址需 `.text` RVA `+0x1000` 修正 | observed-runtime |

### 1.2 本轮使用的方法

| 方法 | 对象 | 结果 |
| --- | --- | --- |
| 只读 PE / pclntab 解析 | `Muyu.exe` | 取得函数名、RVA、字符串表；确认 Go 1.27.4 |
| Capstone 反汇编 + 字符串交叉引用 | `Muyu.exe` | 提取 `cadence/rcmMode/refInfo/rcmScenario` 等字段簇；直连 LEA 未命中外层 endpoint 常量（Go 字符串表经二级指针间接引用） |
| Frida 17.27.6 attach | PID 52048 | 在 `crypto/tls.(*Conn).Write`、`crypto/tls.(*Conn).Read`、`io.ReadAll` 正确地址下钩；运行期间无业务请求，未产出 observed-runtime body |
| Go 堆内存扫描 | PID 52048 | 3,406 个私有可读 range、约 1.63GB；`cadence`、`rcmMode`、`refInfo`、`rcmScenario`、`contentCode`、`qualityType`、`queryWord`、`columnId`、`hasRecommend`、`musicListID`、`privatefm`、`fuzzysearch`、`bycontentcode`、`contentType` 全部 0 命中 |
| 本地端口探测 | `127.0.0.1:18030`、`127.0.0.1:18033`、`10.179.53.188:18033` | 18030 全 404；18033 全 403 `LAN only`。判定 18033 为 DLNA/SSDP 媒体服务，不是业务 API |
| 应用日志 | `independent-data/logs/muyu-20261126.log` | 只记录 `POST/GET [已隐藏]` 和业务码；URL/body 均被客户端主动隐藏 |
| 应用缓存 | `independent-data/cache/muyu-pages/*.json` | 有 app 级 `tracks/next/more/total` 和 `Items/Tracks/Next/More`；不是华为原始响应 |
| 既有 REA 产物 | `rea_evidence/` 下的 Ghidra 反编译、字符串表、live probe | 提供 `decompiled` / `observed-memory` 级证据 |

### 1.3 为什么本地桥接不可用

- `18030`：`/`、`/index.html`、`/api`、`/api/`、`/health`、`/version` 全部返回 Go 默认 `404 page not found`。没有可发现的业务路由。
- `18033`：`0.0.0.0:18033`，本机和 LAN IP 访问均返回 `403 LAN only`。二进制内同时出现 `239.255.255.250`、`ssdp:all`、`AVTransport`、`device.xml`，判定为 DLNA 接收端，不是首页/搜索 API。
- 因此本轮无法通过“调用沐语自己的本地接口”触发上游华为请求；没有为了制造流量而点击窗口或使用 Computer Use。

---

## 2. 证据等级与边界

| 等级 | 本报告中的含义 |
| --- | --- |
| `observed-runtime` | 沐语进程/日志/缓存/本地端口在本轮或可复核的运行期直接产生 |
| `observed-memory` | 既有 REA 从沐语进程内存抓到的 HTTP 文本/结构；不是本轮重新抓取 |
| `decompiled` | Ghidra 反编译、pclntab 函数、二进制内 UTF-8 字面量/结构标签 |
| `inference` | 只能由字段语义、同类实现或上下文推断，未在沐语请求中直接看到 |
| `not-found` | 本轮未找到；不得写成 observed |

**关键边界：**

- 本轮**没有任何沐语上游请求被捕获**，所以不存在“observed-runtime 的沐语请求体”。
- `hmusic`（本仓库 Flutter 客户端）的 400/400 日志是**客户端日志**，只能证明服务端契约，不能证明沐语内部 body。
- `tinglan` 是第三方同类客户端源码，只能作为 `inference`/交叉验证，不能当作沐语事实。
- 应用缓存里的 `next/more/total` 是**沐语 app 层分页状态**，不保证是华为原始响应字段名。

---

## 3. 逐 endpoint 请求结构

### 3.1 `POST /music-recommend-service/v1/service/recommend/privatefm`

**结论：字段集合为 `cadence / rcmMode / rcmScenario / refInfo`；`refInfo` 必须是字符串；`next` 不在反编译请求体里。**

| 字段 | 类型 | 已知值/规则 | 证据等级 |
| --- | --- | --- | --- |
| `cadence` | string | 沐语构造时写空串 `""` | decompiled（`gateway.applicationRequest`） |
| `rcmMode` | string | 只接受 `"1"` / `"2"` / `"3"`；其他值返回“私人电台推荐模式无效” | decompiled |
| `rcmScenario` | string | 2 字节串，存在 `"16"` / `"21"` 两个分支 | decompiled |
| `refInfo` | string | 必须是字符串；传数组会 400 `Cannot deserialize ... String from Array value` | decompiled + observed-runtime（hmusic 服务端 400 文本） |

**最接近事实的请求样例（字段 decompiled，值 inference）：**

```json
{
  "cadence": "",
  "rcmMode": "1",
  "rcmScenario": "21",
  "refInfo": ""
}
```

> 说明：`rcmMode:"1"` 对应“现在就听”、`"2"` 对应“心动模式”是当前 hmusic 的用法，不是沐语已证实的映射；`rcmScenario` 何时用 16/21 也未找到。

**`next/more` 放哪里：**

- 反编译的 `applicationRequest` 请求体**没有** `next` 字段。
- 沐语运行期的队列状态里有 `playback.source.next=104, more=true`；应用缓存里也有 `tracks/next/more`。这些是 app 层/队列层字段，不能证明是 `privatefm` 请求字段。
- 最合理的结构是：**`refInfo` 作为续页游标放在 body**，`next`/`more` 从响应读取；但这一点是 `inference`，`refInfo` 非空格式仍是 `not-found`。

**400 最可能可修点：**

1. `refInfo` 从数组/对象改成字符串（已有服务端明文）。
2. `cadence`、`rcmMode`、`rcmScenario` 全部是字符串，不要发数字。
3. 不要把 `next` 作为 body 字段发送；如果实现里加了 `next: 106`，先删掉。
4. 若改成字符串后仍 400，说明首屏 `refInfo:""` 可能不是合法值；此时必须抓沐语真实 `refInfo`，不要猜 `{}`、`[]` 或 JSON 字符串。

---

### 3.2 `POST /music-recommend-service/v1/service/recommend/playlist`

**结论：沐语真实 body 未找到。当前 `{contentType:1,start:0,limit:30}` 是 hmusic 的猜测，且稳定 400。**

**二进制内的完整候选字面量（decompiled，endpoint 归属 inference）：**

```json
{"rcmScenario":"1","termType":"1","scenario":"1","recommendStrategy":"0"}
```

| 字段 | 类型 | 说明 | 证据等级 |
| --- | --- | --- | --- |
| `rcmScenario` | string | 推荐场景；与 privatefm 同名字段 | decompiled（字面量） |
| `termType` | string | 终端类型，值为 `"1"` | decompiled（字面量） |
| `scenario` | string | 场景，值为 `"1"` | decompiled（字面量） |
| `recommendStrategy` | string | 推荐策略，值为 `"0"` | decompiled（字面量） |
| `contentType` | string | 若服务端要求，歌单应为 `"4"`，不是 `1` | inference |
| `start` / `limit` | string | 华为侧分页习惯用字符串；沐语实际类型未观测 | inference |
| `countryCode` | string | 同字符串簇出现 `countryCode`，是否必填未找到 | inference |

**响应字段（decompiled）：** `playListInfos`、`playListName`、`contentTypes`、`playListInfo`、`miniMusicListInfoEx`、`picture`、`songNum`。

**400 最可能可修点：**

1. 先原样尝试上面的 4 字段字面量，不附加 `contentType/start/limit`。
2. 如果服务端要求内容类型，`contentType` 用字符串 `"4"`（歌单），不要用数字 `1`（歌曲）。
3. 所有值用字符串，不要混数字。
4. 400 响应是 0B，说明网关在业务层前就拒绝；必须记录请求头字段集合和 body 才能继续定位。当前没有沐语 body，不能断言“缺哪个字段”。

---

### 3.3 `POST /music-search-service/v10/service/fuzzysearch`

**结论：沐语搜索请求未找到；“一次还是四次”“start/limit 类型”“correct 实际值”都没有沐语观测。**

| 字段 | 已知结构 | 证据等级 |
| --- | --- | --- |
| `queryWord` | string，搜索词 | decompiled（字段名）+ inference（类型） |
| `contentType` | string；`1` 歌曲 / `2` 专辑 / `3` 歌手 / `4` 歌单 | decompiled（字段名/接口语义）+ inference |
| `correct` | string，取值 `"1"` | inference（tinglan 源码与 hmusic 代码一致，非沐语观测） |
| `start` | string，默认 `"0"` | inference |
| `limit` | string，默认 `"20"` 或 `"30"` | inference |

**当前 hmusic 的实际 body（代码事实，不是沐语）：**

```json
{
  "contentType": "1",
  "correct": "1",
  "queryWord": "<keyword>",
  "start": "0",
  "limit": "30"
}
```

**一次还是多次：**

- 字段是单数 `contentType`，按类型分请求更符合接口形状。
- 当前 hmusic `searchAll()` 会按 `1/2/3/4` 分别请求，这是 hmusic 的实现选择。
- 沐语是否也只发 `contentType=1`、还是一次发四类，`not-found`；不能把 hmusic 行为写成沐语 observed。

**分页：**

- 若响应含 `next`/`more`/`hasMore`，以响应为准；当前没有沐语原始响应。
- 应用缓存 `e7306cd7...json` 是榜单列表（`Items[].Kind=chart`），不是搜索结果，不能用来证明搜索分页。

**建议：** 保持每类一次请求；`queryWord`、`contentType`、`correct`、`start`、`limit` 全部用字符串；每种类型单独记录状态码/业务码/响应字节数，禁止静默 `catch`。

---

### 3.4 `POST /music-play-service/v3/service/file/bycontentcode`

**结论：三字段 `contentCode / contentType / qualityType`；没有 `copyrightSwitch/resourceType/songCode` 的字段证据。**

| 字段 | 类型 | 已知值/规则 | 证据等级 |
| --- | --- | --- | --- |
| `contentCode` | string | 歌曲真实 content ID，例如 `1092974`；空 ID 不应发请求 | decompiled + observed-memory（既有 REA 抓包） |
| `contentType` | string | `"1"`（歌曲） | decompiled + observed-memory |
| `qualityType` | string | `"1"`=standard/MQ，`"3"`=lossless/SQ；沐语静态还有 HQ/SQ/高解析档位 | decompiled + observed-memory（档位语义来自实测） |

**请求样例：**

```json
{
  "contentCode": "1092974",
  "contentType": "1",
  "qualityType": "1"
}
```

**明确不要加：**

- `copyrightSwitch`：属于 `bymusiclistid` 歌单详情，不是取流字段。
- `resourceType`、`songCode`：在沐语取流结构里 `not-found`，没有证据。
- 任何 `token` 字段：鉴权在请求头，body 不带 token。

**响应：** 顶层 `fileURL` 是可直接播放的签名地址；`fileInfos` 是辅助档位；试听信号 `auditionEnd/auditionTime`、URL 含 `_AQ/_PV` 或 `/preview/`。

---

### 3.5 `GET /music-operation-service/v1/service/column/detail/bycolumnid`

**结论：GET + query；`columnId` 优先动态、`8011` 兜底更符合沐语结构，但“固定 8011”未被证伪。**

| 参数 | 类型 | 已知值/规则 | 证据等级 |
| --- | --- | --- | --- |
| `columnId` / `columnID` | string | 沐语字符串簇同时出现 `recom_exclusive`、`8011`、`columnID`、`columnId` | decompiled |
| `start` | string/int | 当前 hmusic 用 `0`；沐语类型未观测 | inference |
| `limit` | string/int | 当前 hmusic 用 `30`；沐语类型未观测 | inference |
| `hasRecommend` | string/int | 当前 hmusic 用 `1`；沐语结构里有 `hasRecommend` | decompiled（字段名）+ inference（值） |

**查询样例（hmusic 代码/探针，不是沐语 observed）：**

```text
?columnId=8011&start=0&limit=30&hasRecommend=1
```

**动态还是固定：**

- 沐语反编译侧存在 `FeaturedSongs`，并从首页 `columnInfoExs` 读取栏目；`8011`/`recom_exclusive` 作为兜底常量出现。
- 因此 `inference`：应从首页动态取真实栏目 ID，`8011` 仅兜底；不能断言沐语每次都固定 8011。
- hmusic 日志里 `columnId=8011` 返回 200/61B/0 首，这是 hmusic 账号/接口结果，不是沐语。

**建议：** query 键优先 `columnId`，同时保留 `columnID` 兼容；`hasRecommend=1`；`start/limit` 先按字符串发送并在失败时尝试数字，必须记录响应体。

---

### 3.6 `GET /music-operation-service/v3/service/musiclist/detail/bymusiclistid`

**结论：沐语静态是 v3 + `?`，更像 GET；v2 POST 的真实 body 属于旧路径/同类实现。**

| 参数/字段 | 类型 | 已知值/规则 | 证据等级 |
| --- | --- | --- | --- |
| `musicListID` | string | 例如 `a001` | decompiled |
| `copyrightSwitch` | string | `"1"`（v2 POST body 实测）；v3 query 里常见 `copyrightSwitch=1` | observed-memory（v2）/ inference（v3） |
| `start` | int/string | v2 body 为数字；v3 query 字符串 | observed-memory（v2）/ inference（v3） |
| `limit` | string | v2 body 为 `"50"`；v3 query 当前用 `30` | observed-memory（v2）/ inference（v3） |

**v3 GET 样例（当前 hmusic，沐语未观测）：**

```text
?musicListID=a001&copyrightSwitch=1&start=0&limit=30
```

**v2 POST 既有 observed-memory 样例：**

```json
{
  "musicListID": "a001",
  "copyrightSwitch": "1",
  "start": 0,
  "limit": "50"
}
```

**建议：** 沐语端点常量带 `?`，优先 v3 GET；若 400/405，再按 v2 POST 字符串 body 兜底。不要同时把 `musicListID` 写成 `musicListId` 或 `playListID`。

---

### 3.7 `GET /music-operation-service/v1/service/chart/detail/bychartid`

**结论：GET + query；`chartID` 与 `chartId` 同时保留最稳；`contentType=1`。**

| 参数 | 类型 | 已知值/规则 | 证据等级 |
| --- | --- | --- | --- |
| `chartID` / `chartId` | string | 热歌榜 `24926` | decompiled（`chartID`）+ observed-runtime（hmusic 200/200 首） |
| `contentType` | string | `1`（歌曲） | decompiled/inference |
| `start` | string/int | 分页起点；hmusic 实测可拉到 200 首 | observed-runtime（hmusic） |
| `limit` | string/int | 单页大小；hmusic 用 50/100 等 | inference |

**查询样例：**

```text
?chartID=24926&chartId=24926&contentType=1&start=0&limit=100
```

**响应/分页：** 沐语应用缓存里榜单类页面有 `next`/`more`；`e7306cd7...json` 是榜单 Items（`Kind=chart`），`Next/More` 字段存在。原始 `bychartid` 响应字段名仍是 `not-found`。

---

## 4. 响应里的 `next / more / start / limit / hasMore`

### 4.1 沐语 app 缓存（observed-runtime 产物）

| 缓存文件 | 顶层字段 | 游标值 | 说明 |
| --- | --- | --- | --- |
| `229ffec2...json` | `tracks/next/more/saved` | `next=0, more=false` | 30 首，完整列表 |
| `3747ee07...json` | `tracks/next/more/saved` | `next=0, more=false` | 30 首 |
| `82b47a3a...json` | `tracks/next/more/saved` | `next=0, more=false` | 200 首 |
| `d04204f7...json` | `tracks/next/more/total/saved` | `next=50, more=true, total=519` | 收藏分页，`next` 等于已消费条数 |
| `a9e639b8...json` | `tracks/next/more/saved` | `next=38, more=false` | 38 首 |
| `e7306cd7...json` | `Items/Tracks/Next/More` | `Next/More` | 榜单 Items（`Kind=chart`） |

**语义（inference）：** `next` 是下一条起点/已消费数量，`more` 是是否还有下一页，`total` 是总数，`saved` 是缓存时间。它们是 app 层字段，不保证等于华为原始响应键名。

### 4.2 华为字段线索

- 二进制字符串里同时存在 `hasNextPage`、`hasRecommend`、`totalCount`、`start`、`limit`、`next`、`more`。
- `privatefm` 反编译请求体没有 `next`，因此 `next/more` 更可能是响应字段；续页应把响应里的游标写入 `refInfo`。
- `recommend/playlist` 的 `playListInfos` 是否带 `next`/`hasMore`：`not-found`。
- `fuzzysearch` 的 `songSimpleInfos` 是否带 `next`/`more`：`not-found`。

---

## 5. 对 `lib/protocol/huawei_api.dart` 的具体修正建议（只建议，不改代码）

### 5.1 `privateFm()`

1. body 固定为四个字符串字段：`cadence`、`rcmMode`、`rcmScenario`、`refInfo`。
2. `refInfo` 参数类型改 `String`，首屏默认 `''`；禁止数组/Map。
3. 删除 body 里的 `next`（若存在）；把响应里的 `next`/`more` 解析成 page 对象，下一页把游标写回 `refInfo`。
4. `rcmMode` 只允许 `'1'/'2'/'3'`；非法值本地直接报错，不发请求。
5. 400 时记录响应体（脱敏），不要只记录状态码；当前 499B 的字段错误文本是唯一能定位 `refInfo` 格式的证据。

### 5.2 `recommendedPlaylists()`

1. 先原样尝试 `{"rcmScenario":"1","termType":"1","scenario":"1","recommendStrategy":"0"}`。
2. 不要先发 `{contentType:1,start:0,limit:30}`；`1` 是歌曲类型，不是歌单类型。
3. 若需要 `contentType`，用字符串 `"4"`；`start/limit` 也用字符串。
4. 400 时记录请求体、响应体、`Content-Type`；0B 响应说明必须靠请求侧对比，不能靠错误文本猜。
5. 保留真实账号歌单兜底，但 UI 要标注“非推荐接口数据”。

### 5.3 `searchAll()`

1. `start`/`limit` 用字符串；`correct` 用 `"1"`；`queryWord` 原样。
2. 按 `contentType=1/2/3/4` 分别请求，每类单独记录状态码、业务码、字节数、解析条数。
3. 不要 `catch (_) => null` 静默吞错；至少把 `contentType + code + msg` 写入 `AppLog`。
4. 分页以响应 `next/more/hasMore` 为准；没有这些字段时用 `start += limit`，但不要把它标成服务端游标。
5. 如果服务端返回 400 且提示未知字段，优先检查 `correct` 是否应为 `iscorrection` 或 `queryType`；这只是排查顺序，不是结论。

### 5.4 `audioFiles()`

1. body 只保留 `contentCode`、`contentType:"1"`、`qualityType`（字符串）。
2. 不要加 `copyrightSwitch`、`resourceType`、`songCode`、`token`。
3. `qualityType` 先按 Muyu 的 `"1"/"3"` 走；高解析档位 `"5"/"7"` 只在明确需要时尝试，并保留 142411/142400 降档。
4. 顶层 `fileURL` 优先；`fileInfos` 只作辅助；拒绝 `_AQ/_PV`、`/preview/`、`audition` 试听。

### 5.5 `featuredSongs()`

1. 先从首页 `columnInfoExs` 取真实栏目 ID；`8011` 只作兜底。
2. query 用 `columnId=<id>&start=0&limit=30&hasRecommend=1`；同时保留 `columnID` 兼容探针。
3. 8011 返回 200/空时保持空态，不要用热歌填充。

### 5.6 `daily30()`

1. 优先 v3 GET：`?musicListID=a001&copyrightSwitch=1&start=0&limit=30`。
2. 若 400/405，再尝试 v2 POST：`{"musicListID":"a001","copyrightSwitch":"1","start":0,"limit":"50"}`。
3. 不要把 `musicListID` 写成 `playListID`；后者是自建歌单接口。

### 5.7 `chartSongs()`

1. GET query 同时保留 `chartID` 和 `chartId`，`contentType=1`，`start`、`limit` 分页。
2. 分页到 `more=false` 或 `next` 不前进为止；加最大页数保护。
3. 记录每页字节数/条数，避免“200 但 0 首”被当成成功。

---

## 6. 仍未找到（明确 `not-found`）

| 项 | 状态 |
| --- | --- |
| 沐语本轮 `privatefm` 真实 body | not-found（进程空闲、未触发、堆已回收） |
| 沐语 `refInfo` 非空格式、首屏是否 `""` | not-found |
| `rcmMode` 1/2/3 与“现在就听/心动”的精确映射 | not-found |
| `rcmScenario` 何时 16、何时 21 | not-found |
| 沐语 `recommend/playlist` 真实 body | not-found |
| 字面量 `rcmScenario/termType/scenario/recommendStrategy` 是否属于 `recommend/playlist` | inference，未证实 |
| 沐语搜索是一次还是四次、是否发 `contentType=4` | not-found |
| 沐语搜索 `start/limit` 实际类型、`correct` 实际值 | not-found |
| 沐语 `bycontentcode` 实际 `qualityType` 序列 | not-found（仅知字段/类型/语义） |
| 沐语 `bycontentcode` 是否还有隐藏字段 | not-found（现有证据只支持三字段） |
| 沐语 `bycolumnid` 是动态栏目还是固定 8011 | inference（动态优先、8011 兜底） |
| 沐语 `bymusiclistid` 实际是 v3 GET 还是 v2 POST | inference（v3 常量带 `?`，优先 GET） |
| 七个 endpoint 的华为原始响应体/游标键名 | not-found（只有 app 缓存） |

---

## 7. 保密自查

- 未打印、摘录、写入任何 `security` 前缀值、`Authorization`、`accessToken`、`refreshToken`、`musicToken` 值；本报告不含 token 值。
- 请求头只保留字段名，值统一 `<redacted>`。
- 正文样例不含 token 字段；如未来加入，必须写成 `"***REDACTED***"`。
- 未读取或输出 `independent-data/account.bin` 内容。
- 未修改 `lib/`、`test/` 或任何业务代码；未提交、未推送、未建分支。
