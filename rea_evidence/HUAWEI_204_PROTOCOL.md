# 华为音乐 2.0.4 协议实测（运行时取证）

> 目标进程：`Muyu.exe` v2.0.4（PID 40400，已登录华为账号）。
> 方法：`rea_evidence/tools/dump_http.py` 只读扫描进程内存，抓取真实 HTTP/1.1
> 请求头、URL、POST body 与响应片段；再用 `test/live_huawei_probe_test.dart`
> 以相同 token 验证修复结果。

## 1. 真实请求头（990000 的根因）

抓到的完整 GET：

```http
GET /music-userbehavior-service/v1/service/favorite/simple/exist?contentID=829794&contentType=1 HTTP/1.1
Host: api-drcn.music.dbankcloud.cn
User-Agent: model=HBN-AL00,brand=HUAWEI,rom=0,emui=0,os=12,apilevel=31,manufacturer=HUAWEI,useBrandCust=false,harmonyApiLevel=0,huaweiOsBrand=
Accept: application/json
Authorization: Digest username=app-music-baseline, nonce=<48 位小写 hex>, created=2026-11-24T08:19:15Z, token=<music token>
Content-Type: application/json
Accept-Encoding: gzip
```

结论：

1. **User-Agent 就是设备串**（`model=...`），不是 `com.huawei.music/版本`。
2. **nonce 是 24 个随机字节的 48 位小写 hex**，不是 24 位字母数字。
3. **created 无毫秒**：`2026-11-24T08:19:15Z`。
4. 业务请求**只带 Host / User-Agent / Accept / Authorization /
   Content-Type / Accept-Encoding**。额外 `x-client-version`、`x-deviceid`、
   `x-musicuuid` 等头会让网关返回 **990000**。
5. 旧实现用 24 位字母数字 nonce + 包名 UA + 一堆 x-* 头 → 990000。

## 2. 首页聚合接口

| 项 | 实测 |
| --- | --- |
| 路径 | `/music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1` |
| 方法 | **GET**（POST 返回 **405**） |
| 顶层 | `result` / `pageDisplayType` / `columnInfoExs` / `extendInfo` |
| 列 | `columnInfo` + `contentSimpleInfos` |

`contentType` 语义（实测）：

| contentType | 含义 |
| --- | --- |
| 1 | 歌曲 |
| 2 | 专辑 |
| 4 | 歌单（每日30首 id=`a001` 也在此） |
| 6 | 分类/电台入口 |
| 7 | 榜单（热歌榜 id=`24926`） |
| 10 | MV |
| 11 | Banner / 活动入口 |
| 12 | 功能卡（现在就听 / 私人FM / 歌手 / 歌单） |
| 20 | 有声书 |
| 96 | 分区（`childSimpleInfos`，新歌/新碟） |

真实首页返回（该账号）：歌曲 18、歌单 27、榜单 10、电台 40。

## 3. 业务接口版本 / 方法

| 能力 | 实测接口 | 方法 / 参数 |
| --- | --- | --- |
| 收藏 / 歌单列表 | `/music-userbehavior-service/v5/service/favorite/simple/all` | POST，`{contentTypes:[1] 或 [4,5,7], favoriteQueryInfos:[], limit, start}` |
| 自建歌单歌曲 | `/music-userbehavior-service/v1/service/playlist/detail/all` | GET，`?playListID=&start=&limit=` |
| 收藏歌单歌曲 | `/music-operation-service/v2/service/musiclist/detail/bymusiclistid` | POST，`{musicListID, copyrightSwitch:"1", start, limit:"50"}` |
| 每日30首 | 直接打开首页 `a001` 歌单 | 不再调用 `querydaily`（当前 400） |
| 榜单歌曲 | `/music-operation-service/v1/service/chart/detail/bychartid` | **GET**，`?chartID=&chartId=&contentType=1&start=&limit=` |
| 搜索 | `/music-search-service/v10/service/fuzzysearch` | POST，`contentType=1 歌曲 / 2 专辑 / 3 歌手 / 4 歌单` |
| 歌曲详情 | `/music-metacontent-service/v1/service/song/detail/bysongcode?` | GET（`?` 表示 query） |
| 歌手歌曲 | `/music-metacontent-service/v1/service/song/simple/byartistcode?` | GET，`artistCode&start&limit` |
| 歌手详情 | `/music-metacontent-service/v2/service/artist/detail/byartistcode` | **POST**，`{artistCode, songNum:20, albumNum:20}` |
| 专辑详情 | `/music-metacontent-service/v1/service/album/detail/byalbumcode?` | GET，`albumCode&start&limit` |
| 取流 | `/music-play-service/v3/service/file/bycontentcode` | POST，`{contentCode, contentType:"1", qualityType}` |

## 4. 收藏请求（v5）

运行时抓到的真实 body：

```json
{"contentTypes":[1],"favoriteQueryInfos":[],"limit":50,"start":350}
```

- 没有 `targetSnsUserID`，用户由 token 决定。
- v3 接口在本账号返回 **990000**；v5 返回 `000000 Success!`。
- 用同一 token 实测：v5 收藏返回 3 首（`唯一 / 时光机 / 给未来的自己`）。

## 5. 取流与音质

- 响应顶层 `fileURL` 是可直接播放的 **https** 签名地址
  （`music-common-drcn.dbankcdn.cn/..._MQ.mp3?X-Amz-...`）。
- `fileInfos` 的 `quality` 取值：`1`=MQ、`2`=HQ、`3`=SQ(FLAC)、`5`/`7`=Hi-Res。
- 旧代码只接受 **https**，而部分 CDN 历史响应是 `http://music-pics...`；
  现已同时接受 http/https。
- 取流请求按目标档位尝试：Hi-Res `7→5→3`，无损 `3→2`，标准 `1→2`。

## 6. 仍未解出的部分

| 项 | 现状 |
| --- | --- |
| `querydaily` / `privatefm` / `recommend/playlist` | POST 返回 400；已改用首页真实数据（a001/radio/playlists），不阻塞功能 |
| OAuth refresh_token | 合同实测 400/1101，暂不依赖；登录态靠持久化 music token |
| 歌曲详情 query 具体字段 | 常量确认 GET + `?`，未抓到 live URL；当前用 `songCodes=` |
| 桌面歌词 / 任务栏播控 / 更新器 | iOS 不适用或未接入 |

## 7. 代码落点

- 鉴权头：`lib/protocol/huawei_gateway.dart`（`_nonce` / `headers`）
- 首页 GET：`lib/protocol/huawei_api.dart`（`discover`）
- 首页层级解析：`HuaweiAPI.parseDiscover` + `_findNamedList`
- 收藏 v5 / 歌单 v5：`HuaweiPaths.favorites` / `playlistDetail`
- 榜单 GET：`HuaweiAPI.chartSongs`
- 歌手 v2：`HuaweiPaths.artistDetailV2` / `artistDetail`
- 取流 http + 档位回退：`HuaweiAPI.audioFiles`
