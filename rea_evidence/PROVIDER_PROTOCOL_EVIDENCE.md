# 沐语 2.0.4 · 第三方音源协议证据

> 目标：`Muyu-2.0.4-Windows-x64.exe`（82 MB，Go 1.27.x，module `muyu.local/desktop`）。
> 方法：pclntab 全符号表（`_syms_204.tsv`）+ 字符串常量（`_strings_204.tsv` / `_gostrings_204.tsv`）
> + 函数边界。**本轮不包含联网实测**，每条都标注证据强度，避免把公开协议当成二进制事实。

## 1. 音源函数表（pclntab 实测）

### 1.1 酷狗 `internal/providers/kugou`

| 函数 | VA | 职责 |
| --- | --- | --- |
| `Client.Search` | 0x140776860 | 搜索 |
| `searchSignature` | 0x140778ac0 | 搜索签名 |
| `Edition.signGateway` | 0x14076e200 | 网关签名 |
| `Edition.androidSalt` | — | 安卓签名盐 |
| `Client.newDevice` | 0x140765640 | 设备指纹 |
| `Client.HomeSongs` / `HomeCollections` / `HomeRank` | 0x140760d80 / 0x1407619c0 / 0x140762f60 | 首页 |
| `Client.PlaylistTracks` / `UserPlaylists` | 0x14076ec00 / 0x140771720 | 歌单 |
| `Client.Locate` / `LocateExact` / `locateTierWithIDs` | 0x14076a360 / 0x14076a0a0 / 0x14076b220 | 取流 |
| `Client.Lyrics` / `lyricGet` | 0x140767a80 / 0x140767420 | 歌词 |
| `Client.Comments` | 0x140756460 | 评论 |
| `Client.NewEditionQR` / `CheckQR` | 0x140766480 / 0x140766ca0 | 扫码登录 |
| `Client.Membership` / `conceptMembership` | 0x140768580 / 0x140769b40 | 会员 |
| `Client.FavoriteStatus` / `SetFavorite` | 0x14075c720 / 0x14075ca20 | 收藏 |

### 1.2 QQ 音乐 `internal/providers/qq`

| 函数 | VA | 职责 |
| --- | --- | --- |
| `Client.Search` | 0x1407b1b20 | 搜索 |
| `Client.rpc` | 0x1407a5ec0 | musicu.fcg RPC |
| `Client.HomeSongs` | 0x14079d9a0 | 首页歌曲 |
| `Client.DiscoveryCharts` / `DiscoveryChart` | 0x14079b8e0 / 0x14079be00 | 榜单 |
| `Client.PlaylistTracks` / `UserPlaylists` | 0x1407ab4e0 / 0x1407ac9a0 | 歌单 |
| `Client.Locate` / `locateSources` / `AvailableQualities` | 0x1407a6d00 / 0x1407a7080 / 0x1407a6ee0 | 取流/音质 |
| `Client.Lyrics` / `Comments` | 0x1407a4960 / 0x14079a2a0 | 歌词/评论 |
| `Client.NewQR` / `CheckQR` / `NewAppQR` / `exchange` | 0x14079e460 / 0x14079f440 / 0x140797b40 / 0x1407a1780 | 扫码登录 |
| `Client.Profile` / `Membership` | 0x1407965e0 / 0x1407a5520 | 账号/会员 |
| `qq.zzcSign` | 0x1407a1060 | QQ 签名 |
| `qq.qrConnectPacket` / `connectQR` / `qrMQTT.*` | 0x1407adb80 / 0x1407ad640 / 0x1407af0a0 | App 扫码（MQTT） |

> 说明：原版 QQ 登录同时支持 Web 扫码与 **App 扫码（MQTT 长连接）**；Flutter 版先实现 Web 扫码 + 手动 Cookie。

## 2. 端点常量（字符串 .rdata 证据）

### 2.1 酷狗

| 端点 | 证据 |
| --- | --- |
| `https://complexsearch.kugou.com/v2/search/song` | 字符串直出 |
| `https://gateway.kugou.com/v5/url` | 字符串直出（取流） |
| `https://gateway.kugou.com/v2/get_res_privilege/lite` | 字符串直出（音质/版权） |
| `https://gateway.kugou.com/v7/get_all_list` | 字符串直出（用户歌单） |
| `https://gateway.kugou.com/v5/add_list` / `v2/delete_list` | 字符串直出（歌单增删） |
| `https://gateway.kugou.com/pubsongs/v2/get_other_list_file_nofilt` | 字符串直出（歌单歌曲） |
| `https://gateway.kugou.com/mcomment/v1/cmtlist` | 字符串直出（评论） |
| `https://gateway.kugou.com/v3/get_my_info` | 字符串直出（账号） |
| `https://login-user.kugou.com` | 字符串直出（登录） |
| `https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=` | 字符串直出（扫码页） |
| `https://pc.service.kugou.com/yueku/v9/album/single/` | 字符串直出（专辑） |
| `https://pc.service.kugou.com/yueku/v9/singer/home/` | 字符串直出（歌手） |
| `https://krcs.kugou.com` | 字符串直出（歌词） |
| `https://kugouvip.kugou.com/v1/get_union_vip` | 字符串直出（会员） |

参数/字段常量：`hash`、`album_audio_id`、`hash_flac`、`mixsongid`、`audio_info`、`author_name`、
`album_name`、`time_length`、`img`、`privilege`、`qualities`、`token`、`userid`、`mid`、`dfid`、
`clienttime`、`appid`、`clientver`、`signature`、`encode_album_audio_id`。

### 2.2 QQ 音乐

| 端点 | 证据 |
| --- | --- |
| `https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp` | 字符串直出（搜索） |
| `https://u.y.qq.com/cgi-bin/musicu.fcg` | 字符串直出（RPC） |
| `https://u.y.qq.com/cgi-bin/musics.fcg?sign=` | 字符串直出（带签名 RPC） |
| `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg` | 字符串直出（歌词） |
| `https://c.y.qq.com/v8/fcg-bin/fcg_v8_album_info_cp.fcg` | 字符串直出（专辑） |
| `https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg` | 字符串直出（评论） |
| `https://ssl.ptlogin2.qq.com/ptqrshow` / `ptqrlogin` / `check_sig` | 字符串直出（Web 扫码） |
| `https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com` | 字符串直出 |
| `https://isure.stream.qqmusic.qq.com/` | 字符串直出（音频 CDN） |
| `https://y.gtimg.cn/music/photo_new/T002R800x800M000` | 字符串直出（封面前缀） |

参数/字段常量：`songmid`、`song_type`、`vkey`、`sip`、`purl`、`filename`、`uin`、`qqmusic_u`、
`qqmusic_key`、`ptqrtoken`、`ptqrlogin`、`pt_3rd_aid`、`pt_uistyle`、`has_onekey`、`GetDiss`、
`CgiGetDiss`、`GetSession`、`UrlGetVkey`、`music.vkey.GetVkey`、`music.login.LoginServer`。

## 3. 证据强度与缺口

| 项目 | 强度 | 说明 |
| --- | --- | --- |
| URL / 路径 | 强（二进制字符串） | 可直接实现 |
| 函数→职责 | 强（pclntab + 命名） | 方法名即能力面 |
| 响应字段 | 中（字符串 + 现有文档） | 需真机响应校验 |
| 请求体字段组合 | 弱 | 需反编译 `Search` / `rpc` / `Locate` |
| 酷狗 `signature` 算法 | 弱 | `searchSignature` / `signGateway` 未反编译；先按公开 MD5(排序参数+salt) 实现并标「待验证」 |
| QQ `zzcSign` | 弱 | 同上 |
| QQ App 扫码 MQTT | 弱 | 先不做，保留 Web 扫码/Cookie |
| 酷狗概念版/标准版切换 | 中（`Edition.appID` / `clientVersion` / `profileAuthorization`） | 后续补 |

## 4. 对 Flutter 复刻的落地顺序

1. **可验证优先**：QQ 搜索 / 歌单 / 歌词 / 取流（musicu.fcg）→ 酷狗搜索 / 取流。
2. 登录先做「手动 Cookie」，再做 Web 扫码；不做 MQTT App 扫码。
3. 任何未实测端点必须在 UI 显示真实错误，不填假歌。
4. 音质档位继续沿用「上游决定」：QQ `filename` 后缀 / 酷狗 `privilege` 决定可用档位。

## 5. 复现命令

```powershell
# 符号表（地址 大小 名称）
python rea_evidence\tools\dump_symbols.py Muyu-2.0.4-Windows-x64.exe > rea_evidence\_syms_204.tsv
# 字符串（offset 长度 文本），大文件已 gitignore
python rea_evidence\tools\extract_go_strings.py Muyu-2.0.4-Windows-x64.exe > rea_evidence\_gostrings_204.tsv
```
