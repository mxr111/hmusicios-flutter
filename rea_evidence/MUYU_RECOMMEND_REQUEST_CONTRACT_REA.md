# 沐语推荐请求契约深挖（privatefm / recommend/playlist）

日期：2026-11-26\
目标：`C:/沐语/Muyu.exe`（沐语 2.0.4.0，Go 1.27.4，PE32+ x86-64）\
范围：只读取证；不改 `lib/`、`test/`；不提交、不推送、不建分支。\
报告中的凭据类字段只保留字段名，值统一为 `<redacted>`。

---

## 0. 结论先行

1. **`privatefm` 和 `recommend/playlist` 都是 POST + JSON，路径也没有版本歧义。** 当前 `lib/protocol/huawei_api.dart` 的 method / path / `Content-Type` 不是 400 的主因。
2. **`recommend/playlist` 的真实 body 不是 `rcmScenario`、`termType`、`scenario`、`recommendStrategy` 这 4 个字段。** 它们属于 `querydaily`；当前代码把每日推荐契约发给了歌单推荐端点，这是确定的结构性错误。
3. **`recommend/playlist` 的真实 body 是 `contentCodes`（字符串数组）、`limit`（整数 12）、`rcmScenario`（字符串 `"1"`）。** 首页首次请求的 `contentCodes` 是空数组。
4. **`privatefm` 的真实 body 同样不是当前代码的形状。** 反编译显示 `cadence` / `rcmMode` 在心动首屏是 Go 的零接口值（JSON `null`），`rcmScenario` 是 `"21"`，`refInfo` 是一段 74 字节的行为 JSON 字符串，不是空串。
5. **`refInfo` 的真实内容是 `{"download":[],"share":[],"dislike":[],"collect":[],"cancel":[],"play":[]}`。** 这是本次最关键的 `privatefm` 发现；当前代码发送 `refInfo:""`，与沐语构造点不一致。
6. **`privatefm` 在 catalog 层对应的是 `"heart"`（心动模式），不是 `"listen"`（现在就听）。** `"listen"` 实际走 `HomeRadioSeed` 的首页聚合 GET；当前客户端把两者语义接反了。
7. **真实请求头远多于当前客户端。** `applicationSend` 会构造 `x-recommend:1`、`x-appid:200001`、`x-hc:WIFI`、`x-proxy:0`、`x-deviceid`、`x-realdeviceid`、`x-musicuuid`、`x-uid`、`x-bearer`、`Accept-Lang:zh_CN` 等；当前客户端只发通用头。哪些 header 是推荐端点强制项，静态证据不足。
8. **本轮没有捕获到沐语运行时请求。** 起始时 `Muyu.exe` 未运行，未启动、未 hook、未点击 UI；因此本报告的请求字段全部是 `decompiled`，不是 `observed-runtime`。

---

## 1. 证据等级与地址校正

| 等级 | 本报告中的含义 |
| --- | --- |
| `observed-runtime` | 既有日志、既有 live probe、既有端口探测直接产生；不是本轮新抓取 |
| `observed-memory` | 既有 REA 从沐语进程内存取得的 HTTP/结构；本轮未新增 |
| `decompiled` | 对 `Muyu.exe` 当前 2.0.4 的 PE / pclntab / 反汇编 / 字符串常量直接读取 |
| `inference` | 由 Go 语义、调用链或同类结构推断，未在沐语请求中直接看到 |
| `not-found` | 本轮或现有材料未找到；不写成事实 |

### 1.1 地址校正（重要）

`_syms_204.tsv` 里的 pclntab 函数地址需要 **+0x1000** 才是当前 PE 的实际 VA。此前报告中的
`gateway.applicationRequest@0x1404225c0` 与 2.0.4 当前二进制不一致；当前实际入口是
`0x1404273c0`。本报告统一写实际 VA，并在括号里给出 pclntab 原始值，避免继续引用旧地址。

| 函数 | pclntab（`_syms_204.tsv`） | 实际 VA | 用途 |
| --- | ---: | ---: | --- |
| `gateway.(*Connection).HomeRadioSeed` | `0x140425000` | `0x140426000` | `"listen"` 首页聚合 GET |
| `gateway.(*Connection).RadioSongs` | `0x1404253a0` | `0x1404263a0` | `privatefm` 请求构造 |
| `gateway.(*Connection).RadioMode` | `0x1404258c0` | `0x1404268c0` | 读取 userconfig 的 `privatefm.RcmMode` |
| `gateway.(*Connection).RecommendedLists` | `0x140425a40` | `0x140426a40` | `recommend/playlist` 请求构造 |
| `gateway.(*Connection).Daily` | `0x140425cc0` | `0x140426cc0` | `querydaily` 硬编码 4 字段 body |
| `gateway.(*Connection).EditorialDaily` | `0x140425e40` | `0x140426e40` | `querydaily` 动态 3 字段 body |
| `gateway.(*Connection).applicationRequest` | `0x1404263c0` | `0x1404273c0` | method/path/body 统一入口 |
| `gateway.(*Connection).applicationSend` | `0x140426680` | `0x140427680` | 头、签名、重试、响应解析 |
| `gateway.(*Connection).send` | `0x140427c60` | `0x140428c60` | `net/http.NewRequestWithContext` + 写入 body |
| `catalog.(*Library).RecommendedLists` | `0x140445be0` | `0x140446be0` | 组装 `contentCodes/limit/rcmScenario` |
| `catalog.(*Library).HomeSongsWithRadioMode` | `0x14043e3c0` | `0x14043f3c0` | `heart/listen/hot/recommend` 路由 |
| `catalog.(*Library).NextRadioSongs` | `0x14043e6c0` | `0x14043f6c0` | `privatefm` 续页 |
| `main.(*App).RecommendedPlaylists` | `0x140b982e0` | `0x140b992e0` | 首页推荐歌单调用者 |

---

## 2. `privatefm` 真实契约

### 2.1 method / path / query / content-type

| 项 | 证据 | 等级 |
| --- | --- | --- |
| Method | `gateway.RadioSongs` 在 `0x140426825` 加载 `"POST"`（长度 4），在 `0x14042684e` 调用 `applicationRequest` | `decompiled` |
| Path | `0x140426831` 加载 `/music-recommend-service/v1/service/recommend/privatefm`，长度 `0x37`（55） | `decompiled` |
| Query | 路径本身不含 `?`；`applicationRequest` 直接把该 path 传下去 | `decompiled` |
| Content-Type | `applicationSend` / `send` 写 `application/json` 或 `application/json;charset=UTF-8`；`send` 在 `0x140428df5` 引用 `application/json` | `decompiled` |
| Body 外层 | 直接 `json/v2.Marshal(map[string]any)`，再作为 body 字节交给 `applicationRequest`；未发现 `request` / `body` / `params` 包裹 | `decompiled` |
| 压缩/加密 | 未发现请求体 gzip、protobuf 或业务加密；`Content-Encoding` 字符串出现在通用的响应/头处理区，不能证明请求体压缩 | `not-found`（请求体压缩/加密） |

**结论：当前客户端用 POST + JSON 是对的，不应改成 GET。**

### 2.2 body 构造点

`gateway.RadioSongs` 的实际 VA 为 `0x1404263a0`，关键构造：

- `0x140426407`：`runtime.makemap_small`，body 是 `map[string]any`。
- `0x14042640a`–`0x140426425`：写入 `cadence`，值为 Go 零接口（两个 8 字节均写 0）。
- `0x140426434`：根据布尔参数在 `"16"` 与 `"21"` 之间选择 `rcmScenario`。
- `0x1404264d6`：写入 `rcmScenario`。
- `0x14042652f`–`0x140426568`：写入 `refInfo`，类型是 `string`，数据指针指向 `0x143e48690` 的字符串头。
- `0x1404265a9`：调用 `encoding/json/v2.Marshal`。
- `0x140426825` / `0x140426831` / `0x14042684e`：method `"POST"`、path、`applicationRequest`。

第二分支（`0x14042662c` 起）在同样的 `cadence` / `rcmScenario` / `refInfo` 之外，把传入的 `rcmMode` 作为字符串写入，然后再次 `json/v2.Marshal`。

### 2.3 两种真实 body

#### A. 心动首屏（`HomeSongsWithRadioMode("heart")`）

`catalog.HomeSongsWithRadioMode` 在 `0x14043f4c6` 判断到 `"heart"` 后，在 `0x14043f4e2` 调
`gateway.RadioSongs`，并把 `r10d` 设为 1。`RadioSongs` 的 `cmovne` 选择 `"21"`，因此首屏是：

```json
{
  "cadence": null,
  "rcmMode": null,
  "rcmScenario": "21",
  "refInfo": "{\"download\":[],\"share\":[],\"dislike\":[],\"collect\":[],\"cancel\":[],\"play\":[]}"
}
```

证据：

- `cadence` / `rcmMode` 的 `mapassign_faststr` 后写入两个 0；body map 的元素类型是接口（同一函数对 `rcmScenario` 调用了 `runtime.convTstring`）。
- `rcmScenario` 的 `"21"` 分支：`0x140426434` 的 `cmovne`。
- `refInfo` 字符串：VA `0x143e48690` 的 Go string header 指向 `0x140e5a288`，长度 74，内容就是上面那串 JSON。
- `refInfo` 的类型描述符是 `0x144a2a270`，`kind=24`（Go string），不是数组。

> `cadence` / `rcmMode` 序列化为 JSON `null` 是 Go `map[string]any` 的语义推断（`inference`）；字段存在、写零、`refInfo` 为 74 字节字符串是 `decompiled`。

#### B. 心动续页（`NextRadioSongs`）

`catalog.NextRadioSongs` 在 `0x14043f6f9` 把 `r10d` 置 0，然后调用 `RadioSongs`。此时 `rcmMode` 会被校验为 `"1"/"2"/"3"` 之一，`rcmScenario` 为 `"16"`，`refInfo` 仍是同一段行为 JSON：

```json
{
  "cadence": null,
  "rcmMode": "1",
  "rcmScenario": "16",
  "refInfo": "{\"download\":[],\"share\":[],\"dislike\":[],\"collect\":[],\"cancel\":[],\"play\":[]}"
}
```

`rcmMode` 的合法值校验在 `0x1404265be`–`0x1404265ed`：长度必须为 1，字节必须是 `'1'`、`'2'` 或 `'3'`；否则构造“私人电台推荐模式无效”错误并返回。

### 2.4 `refInfo` 是 `privatefm` 400 的最大结构性问题

当前 `lib/protocol/huawei_api.dart:2173-2177` 发送：

```json
{
  "cadence": "",
  "rcmMode": "1",
  "rcmScenario": "16",
  "refInfo": ""
}
```

与沐语构造点相比，至少有三处不一致：

1. `refInfo` 从 74 字节行为 JSON 变成空串。
2. 首屏心动使用 `rcmMode:null` + `rcmScenario:"21"`；当前是 `rcmMode:"1"` + `rcmScenario:"16"`，这是续页/另一分支的形状。
3. `cadence` 在沐语构造里是 Go 零接口值（`null`），当前是 `""`；服务端是否接受空串未找到证据。

此前 hmusic 日志里的 400 body
`Cannot deserialize value of type java.lang.String from Array value`
证明的是 `refInfo` 必须是字符串，但**改成 `""` 仍然不是沐语的真实值**。因此“把数组改成空串”只修了类型，没有修内容。

### 2.5 `privatefm` 的真实语义

`catalog.HomeSongsWithRadioMode` 的分支（`0x14043f400`–`0x14043f540`）：

| type 字符串 | 调用 | 证据 |
| --- | --- | --- |
| `"heart"` | `gateway.RadioSongs` → `privatefm` | `0x14043f4c6`–`0x14043f4e2` |
| `"listen"` | `gateway.HomeRadioSeed` → 首页 `page/detail/all` GET | `0x14043f509`–`0x14043f50c` |
| `"hot"` / `"new"` | `gateway.EditorialDaily` → `querydaily` | `0x14043f45d`–`0x14043f470` |
| `"recommend"` | `gateway.FeaturedSongs` → `column/detail/bycolumnid` | `0x14043f53b`–`0x14043f540` |

`gateway.HomeRadioSeed` 的真实请求（`0x140426053`–`0x140426072`）是：

```text
GET /music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1
```

它从首页的 `columnInfoExs` / `contentSimpleInfos` 中找 `pmf001`。因此：

- **“现在就听”不是 `privatefm`，而是首页聚合里的 `pmf001`。**
- **`privatefm` 是“心动模式”的请求；当前客户端把 `privateFm()` 用在 listen 上，语义是反的。**
- `gateway.RadioMode`（`0x1404268c0`）通过 GET `/music-user-service/v1/service` 下的
  `userconfig/detail/all` 读取 `userConfigsInfo.privatefm.RcmMode`，进一步支持
  `privatefm` 是心动配置，而不是 listen 队列。

---

## 3. `recommend/playlist` 真实契约

### 3.1 method / path / query / content-type

| 项 | 证据 | 等级 |
| --- | --- | --- |
| Method | `gateway.RecommendedLists` 在 `0x140426ab5` 加载 `"POST"`，在 `0x140426ac1` 调 `applicationRequest` | `decompiled` |
| Path | `0x140426aa2` 加载 `/music-recommend-service/v1/service/recommend/playlist`，长度 `0x36`（54） | `decompiled` |
| Query | 路径不含 `?`；没有 `/v2/`、`/v3/`、`/v5/` 分支 | `decompiled` |
| Content-Type | 同 `applicationSend` / `send`：`application/json` | `decompiled` |
| Body 外层 | `catalog.RecommendedLists` 直接 `json/v2.Marshal(map[string]any)`，无外层包裹 | `decompiled` |

### 3.2 `catalog.RecommendedLists` 的真实 body

实际 VA `0x140446be0`：

- `0x140446c2f`：`runtime.makemap_small`。
- `0x140446c5b`–`0x140446c7f`：写入 `contentCodes`，值来自 `runtime.convTslice`，即字符串数组。
- `0x140446cb7`–`0x140446cef`：写入 `limit`。类型描述符 `0x144a2a4b0` 的 `kind=2`（Go int），数据指针 `0x143e42950` 处的 8 字节值是 `0x0c`，即 **12**。
- `0x140446cff`–`0x140446d36`：写入 `rcmScenario`。类型描述符 `0x144a2a270` 的 `kind=24`（Go string），数据指针 `0x143e47140` 的字符串头指向 `0x143e42a18`，长度 1，内容是 `"1"`。
- `0x140446d6a`：`encoding/json/v2.Marshal`。
- `0x140446dc4`：调用 `gateway.RecommendedLists`。

首页首次请求由 `main.(*App).RecommendedPlaylists`（实际 VA `0x140b992e0`）调用；
`main.(*nativeModel).loadHomeKinds.func1` 在 `0x140ce13f5` 调用它时传入的是空 `[]string`
（`rdi` 为数据指针、`esi=0`、`r8d=0`）。因此首页首次 body 是：

```json
{
  "contentCodes": [],
  "limit": 12,
  "rcmScenario": "1"
}
```

证据等级：

- 字段名 `contentCodes` / `limit` / `rcmScenario`：`decompiled`。
- `limit=12`：`decompiled`（类型 + 静态值）。
- 首页 `contentCodes=[]`：`decompiled`（调用点空 slice）。
- JSON 对象键顺序：`inference`；字段集合与类型是 `decompiled`。

### 3.3 当前 `recommend/playlist` 为什么稳定 400

当前 `lib/protocol/huawei_api.dart:2239-2250` 发送：

```json
{
  "rcmScenario": "1",
  "termType": "1",
  "scenario": "1",
  "recommendStrategy": "0"
}
```

这 4 个字段在二进制里的归属是 **`gateway.Daily` / `querydaily`**，不是 `recommend/playlist`：

- `gateway.Daily` 实际 VA `0x140426cc0`，在 `0x140426d2c` 拷贝 73 字节字面量
  `{"rcmScenario":"1","termType":"1","scenario":"1","recommendStrategy":"0"}`，
  然后在 `0x140426db0` 加载 `/music-recommend-service/v1/service/recommend/querydaily`。
- `gateway.EditorialDaily` 实际 VA `0x140426e40` 构造的是 `termType`、`scenario`、`rcmScenario`
  三个字段，再发 `querydaily`。

因此当前 `recommendedPlaylists()` 是把“每日推荐”的 body 发给了“推荐歌单”端点。服务端在业务层前直接拒绝并返回 400/0B，这与 live probe 的稳定表现一致。

**`recommend/playlist` 不是错误端点；错误在 body。** 当前 method/path/content-type 都正确，不应换 GET，也不应改域名。

---

## 4. 请求头构造点

### 4.1 当前客户端的通用头

`lib/protocol/huawei_gateway.dart:164-174` 当前只发：

- `User-Agent`
- `Accept: application/json`
- `Accept-Encoding: gzip`
- `Content-Type: application/json;charset=UTF-8`
- `Authorization`（Digest，值 `<redacted>`）

`bycontentcode` 在同一链路下能 200，说明这组通用头 + 签名链路本身有效。

### 4.2 沐语 `applicationSend` 的真实头集合

实际 VA `0x140427680` 的 `applicationSend` 构造了一个 header map，关键 key：

| Header key | 已知值/构造 | 证据 |
| --- | --- | --- |
| `Accept-Lang` | `zh_CN` | `0x140427d30`–`0x140427d68` |
| `x-packagename` | `com.huawei.music` | `0x140427d17` 邻接字符串 |
| `x-bearer` | `<redacted>` | `0x140427d7a`–`0x140427da8` |
| `x-hc` | `WIFI` | `0x140427dc1`–`0x140427dee` |
| `x-appid` | `200001` | `0x140427e07`–`0x140427e34` |
| `x-recommend` | `1` | `0x140427e4d`–`0x140427e7a` |
| `x-proxy` | `0` | `0x140427ed7`–`0x140427f0f` |
| `x-clienttraceid` | 动态值 | `0x140427f21`–`0x140427f68` |
| `x-deviceid` | 动态值 + `;type=6` | `0x140427fad`–`0x140428015` |
| `x-realdeviceid` | 动态值 + `;type=6` | `0x140428039`–`0x1404280a0` |
| `x-musicuuid` | 动态值 | `0x140428092`–`0x1404280db` |
| `x-uid` | 动态值 | `0x1404280ed`–`0x140428134` |
| `x-client-version` | 值未解析 | `0x140427aab` 邻接字符串 |
| `x-subscription` | 动态值 | `0x140427e93` 邻接字符串 |

`applicationSend` 还引用了 `delivery=;mcc=;locale=;upcountry=CN`（`0x140427dee` 邻接），
说明真实设备/地区上下文可能被编码进某些头或查询参数；具体拼装位置未完全还原。

### 4.3 header 是否是 400 的原因

`decompiled` 能证明：沐语真实请求包含大量 `x-*` 头，当前客户端没有。\
`not-found` 的是：`privatefm` / `recommend/playlist` 到底强制要求哪几个头。

因为 `bycontentcode` 在缺这些头时仍 200，**不能**把所有 `x-*` 都列为必填；也不能断言缺头就是 400 主因。当前最可能的主因仍是 body 结构错误。`x-recommend:1` 是推荐服务最值得优先验证的候选，但这是 `inference`，不是结论。

---

## 5. 本地桥接 / Frida 状态

### 5.1 本轮运行时状态

| 项 | 结果 | 等级 |
| --- | --- | --- |
| `Muyu.exe` 进程 | 本轮开始时未运行（`Get-Process` 无结果） | `observed-runtime` |
| Frida hook | 未 attach；未启动进程；未捕获到运行时调用 | `observed-runtime` |
| 请求体运行时抓取 | 未捕获到 | `not-found` |
| 400 响应体 | 本轮未新增；既有日志只有 hmusic 客户端侧 400 | `not-found`（沐语侧） |

### 5.2 本地端口

既有运行时探测（`MUYU_RUNTIME_REQUEST_BODIES.md` §1.3）：

- `127.0.0.1:18030`：`/`、`/index.html`、`/api`、`/health` 等均返回 Go 默认 404。
- `127.0.0.1:18033`：返回 `403 LAN only`；二进制字符串同时出现 `AVTransport`、`device.xml`、`ssdp:all`、`239.255.255.250`，判定为 DLNA 媒体服务，不是首页/推荐业务 API。

本轮没有发现可用于“刷新首页/推荐/播放”的本地 endpoint 名称：

- 本地 endpoint 名：`not-found`
- 本地参数名：`not-found`
- 能证明 18030/18033 可触发上游推荐请求的证据：`not-found`

因此**不能**通过调用本地桥接来复现 `privatefm` / `recommend/playlist`。

---

## 6. 对 `lib/protocol/huawei_api.dart` 的修正建议（只建议，不改代码）

### 6.1 `privateFmPage()`

```dart
// 建议形状，不是已改代码
body = {
  'cadence': null,          // 沐语首屏是 Go 零接口值；是否接受 "" 未找到
  'rcmMode': null,          // 心动首屏；续页才是 "1"/"2"/"3"
  'rcmScenario': '21',      // 心动首屏；续页是 "16"
  'refInfo': '{"download":[],"share":[],"dislike":[],"collect":[],"cancel":[],"play":[]}',
};
```

具体建议：

1. **`refInfo` 改成字符串化的行为 JSON**，不要发 `""`，更不要发数组/对象。
2. **首屏心动使用 `rcmMode:null` + `rcmScenario:"21"`**；续页再切到 `rcmMode:"1"/"2"/"3"` + `rcmScenario:"16"`。
3. `cadence` 按沐语构造发 `null`；如果 Dart/服务端不接受 null，再单独验证 `""`，不要把它当已证事实。
4. 当前 `privateFm()` 被用于“现在就听”是语义错误；建议把 listen 改为首页 `pmf001`（现有 `HomeRadioSeed` 等价路径），把 `privateFmPage()` 只用于心动。
5. 不要因为 400 就改 GET；method 已是正确的 POST。

### 6.2 `recommendedPlaylists()`

```dart
// 建议形状，不是已改代码
body = {
  'contentCodes': const <String>[],  // 首页首次为空；后续可传种子歌曲 contentCode
  'limit': 12,                       // int，不是字符串
  'rcmScenario': '1',
};
```

具体建议：

1. **删除 `termType` / `scenario` / `recommendStrategy`**；它们属于 `querydaily`。
2. **`limit` 用数字 12**，不要用 `"30"`，也不要把 `start` 塞进去。
3. **`contentCodes` 用字符串数组**，首页首次用 `[]`；不要用 `contentType:1` 代替。
4. method/path/content-type 保持不变：POST + `/music-recommend-service/v1/service/recommend/playlist` + JSON。
5. 400 时至少记录响应体和请求 body 的字段名；当前 0B 响应说明网关在业务层前拒绝，不能只记录状态码。

### 6.3 不要做的事

- 不要把 `privatefm` 改成 GET。
- 不要把 `recommend/playlist` 改成 GET。
- 不要改域名或加 `/v2/`、`/v3/`、`/v5/`；当前 binary 的这两个路径就是 v1。
- 不要用 `querydaily` 的 4 字段 body 继续试 `recommend/playlist`。
- 不要把 `refInfo` 发成 `[]` 或 `{}`；它必须是字符串。
- 不要在没有证据时同时叠加 `x-*` 头；先修 body，再单独验证 header。

---

## 7. 400 的最可能结构性原因

### 7.1 `privatefm`

**最可能：`refInfo` 内容错误 + 首屏分支错误。**

当前请求同时满足：

- `refInfo:""`，而沐语是 74 字节行为 JSON 字符串；
- `rcmMode:"1"` + `rcmScenario:"16"`，而沐语心动首屏是 `null` + `"21"`；
- `cadence:""`，而沐语构造是零接口值。

如果此前 11 个变体都保留了空 `refInfo`，那么它们会共同失败；具体变体清单未在证据中找到，因此“11 个都因 refInfo 失败”是 `inference`，不是逐条 observed。

### 7.2 `recommend/playlist`

**最可能：发送了 `querydaily` 的 body。**

当前 4 个字段在二进制里明确属于 `gateway.Daily` / `querydaily`。`recommend/playlist` 需要
`contentCodes` / `limit` / `rcmScenario`；当前 body 三个都没有。这不是 header 或签名问题，而是请求契约错配。

### 7.3 共同点

- 两个端点都是 POST + JSON，当前 method/content-type 不是问题。
- 两个端点都没有 query 版本分支，当前 path 不是问题。
- 当前 body 都不是沐语 2.0.4 的 body。
- 真实请求头更多，但 `bycontentcode` 200 证明通用签名链路可用；header 是第二顺位嫌疑。

---

## 8. 仍为 `not-found` 的项

| 项 | 状态 |
| --- | --- |
| 沐语本轮 `privatefm` 实际网络请求 | `not-found`（进程未运行，未 hook） |
| 沐语本轮 `recommend/playlist` 实际网络请求 | `not-found` |
| `privatefm` 非空用户行为时 `refInfo` 是否变化 | `not-found`；本轮只拿到全空数组的静态字符串 |
| `rcmMode:null` 是否被服务端接受 | `not-found`；只能确认沐语这样构造 |
| `cadence:null` 是否被服务端接受 | `not-found` |
| `recommend/playlist` 非空 `contentCodes` 的选取规则 | `not-found`；首页首次只证明空数组 |
| `x-recommend` / `x-appid` / `x-hc` 等头的强制子集 | `not-found` |
| `18030` / `18033` 的业务 endpoint 名 | `not-found` |
| 沐语 400 响应体（服务端侧） | `not-found`；既有只有 hmusic 客户端日志 |

---

## 9. 下一步需要什么证据才能真正修到 200

按优先级：

1. **先按第 6 节改 body 做一次真机验证。** `privatefm` 用 `refInfo` 行为 JSON + 心动首屏 `null/"21"`；`recommend/playlist` 用 `contentCodes/limit/rcmScenario`。这是静态证据最强、成本最低的一步。
2. 如果仍 400，记录 **400 响应体全文（脱敏）** 和请求 body 的字段名/类型。当前 `recommend/playlist` 是 0B，必须靠请求侧对照；`privatefm` 的 499B body 是定位字段错误的关键。
3. 做一次**非 UI 触发的运行时 hook**：attach 后 hook `gateway.applicationSend` 或 `net/http.NewRequestWithContext`，记录 method、path、body 长度/字段名、header key 集合；不要 hook TLS Write，不要打印凭据值。
4. 如果 hook 仍无请求，说明当前进程没有自然触发首页/心动/推荐刷新；需要一次由用户授权的真实操作，或在启动阶段 hook 并等待应用自身的启动刷新。本轮不等待用户操作，因此不继续。
5. 用 A/B 方式验证 header：先只加 `x-recommend:1`，再一次加 `x-appid`/`x-hc`/`x-client-version`/`x-musicuuid` 等；每次只改一个变量，记录状态码和响应体。不要一次性叠加全部头，否则无法归因。
6. 如果 body 正确但仍 400，再检查 `refInfo` 是否应随用户行为变化（下载/分享/不喜欢/收藏/取消/播放数组），以及 `contentCodes` 是否必须非空；这两项目前都是 `not-found`。

---

## 10. 安全自查

- 报告未写入任何令牌值、`Authorization` 值、`security` 前缀值或完整签名 URL。
- 只保留 header 字段名和 `<redacted>`。
- 未读取、未输出 `C:/沐语/independent-data/account.bin` 内容。
- 未修改 `lib/`、`test/` 或任何业务代码；未提交、未推送、未建分支。

自查计数：

```text
security_value=0
authorization_value=0
long_credential=0
token_assign=0
```
