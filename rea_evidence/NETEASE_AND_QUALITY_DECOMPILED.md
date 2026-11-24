# 网易云音源 + 上游音质判定：REA 反编译事实

> 目标：Muyu.exe 1.2.0（Go 1.27.4）。引擎：REA 6.7.0 + Ghidra 12.1.4 + JDK21。
> 时间：2026-11-24。所有地址来自 pclntab 实测（`go_sym_addr.py`）。

## 1. 网易云音源模块（internal/providers/netease，66 符号）

### 1.1 源文件（能力面）
account.go / album.go / artists.go / client.go / comments.go / discovery.go /
favorite.go / home.go / login.go / lyrics.go / playback.go / playlist_edit.go /
playlists.go / privilege.go / search.go

### 1.2 Client 方法（对外能力，35 个）
- 登录：`NewQR`（申请二维码 unikey）/ `CheckQR`（轮询扫码状态）
- 账号：`Profile` / `Membership` / `PlaybackQualityMembership`
- 搜索：`Search` / `SearchPreview` / `SearchArtists`
- 首页：`HomeDaily` / `HomeHeart` / `HomeRadar` / `HomeCharts` / `DiscoveryPlaylists` / `homeSongs`
- 歌单：`UserPlaylists` / `PlaylistTracks` / `CreatePlaylist` / `DeletePlaylist` / `ChangePlaylistTrack`
- 收藏：`SetFavorite` / `FavoriteStatus` / `MarkFavorites`
- 内容：`AlbumTracks` / `Comments` / `Lyrics`
- 播放/音质：`Locate` / `locate` / `locateQuality` / `EnrichSongQualities` / `HasPlaybackQuality` / `songQualities` / `songPrivilegesByID` / `qualityMembershipFromCharges`

### 1.3 鉴权与加密
- `encryptCBC`（0x14076e120）+ `weapiForm`（0x14076e3a0）：网易云 weapi 标准双重 AES-CBC。
  - 实测二进制含 IV 字符串 `0102030405060708`（16B）。
  - 第一层密钥为固定串，第二层为随机 16B（weapi 标准），配合 RSA 的 `encSecKey`（exponent/ modulus）。
  - `post`（0x14076e960 附近）/ `postDesktop` / `postWithCookies` / `postTrackCatalog`：统一 POST 封装，带 `csrf_token`、`MUSIC_U` cookie。
- cookie 字段实测：`csrf_token`、`MUSIC_U`。

### 1.4 API 路径（精确，从二进制 .rdata 提取，非猜测）
```
/weapi/login/qrcode/unikey          # 二维码登录 key
/weapi/login/qrcode/client/loginQQ  # 扫码状态轮询（unikey）
music.163.com/login                 # 登录页
/weapi/music-vip-membership/front/vip/info   # 会员/音质权益
/weapi/search/get                   # 搜索
/weapi/song/lyric                   # 歌词（字符串与 https 粘连）
/weapi/song/enhance/player/url/v1   # 取流（含音质 level）
/weapi/song/like/get                # 收藏状态
/weapi/radio/like                   # 心动模式
/weapi/toplist/detail               # 榜单
/weapi/v3/song/detail               # 歌曲详情
/weapi/v6/playlist/detail           # 歌单详情
/weapi/user/playlist                # 用户歌单（字符串粘连 uniform_get_Dissinfo）
/weapi/playlist/create              # 建歌单
/weapi/playlist/remove              # 删歌单
/weapi/playlist/manipulate/tracks   # 歌单增删歌曲
/weapi/v1/album                     # 专辑
/weapi/v1/discovery/recommend/resource  # 推荐歌单
/weapi/v3/discovery/recommend/songs     # 每日推荐
/weapi/v1/resource/comments/R_SO_4_     # 评论
/weapi/playmode/intelligence/list       # 智能播放（私人漫游）
music.163.com/api/nuser/account/get     # 账号资料
```

## 2. 上游音质判定（关键：档位来自上游，不本地写死）

### 2.1 音质档位字符串（实测存在于二进制）
`standard` / `higher` / `exhigh` / `lossless` / `hires` / `jyeffect` / `sky` / `jymaster`
（网易云官方 level 体系：标准/较高/极高/无损/Hi-Res/沉浸环绕/天空声/-JY大师）

### 2.2 音质字段（实测 JSON tag）
- `privilege`（12 处）、`songPrivilege`（19 处）
- `maxbr`（最大码率）、`br`（码率）、`level`（档位）
- `fee`（收费类型）、`chargeInfoList`（付费档位列表，4 处）
- 码率档位：`128000` / `250000` / `320000` / `990000`

### 2.3 音质判定函数（地址）
| 函数 | VA | 作用 |
| --- | --- | --- |
| `netease.songQualities` | — | 从 privilege / songPrivilege 派生该歌档位集合 |
| `netease.songPrivilegesByID` | — | 批量取 privilege |
| `netease.qualityMembershipFromCharges` | — | 从 chargeInfoList 判定付费档位权益 |
| `netease.Client.locateQuality` | 0x140773b80 | 按目标档位定位可用音源 |
| `netease.Client.PlaybackQualityMembership` | 0x140777d20 | 该账号可用的播放档位 |
| `catalog.harmonyQualityBadge` | 0x1404386e0 | 华为音质金色徽标 |
| `catalog.(*Library).SongQuality` | 0x140447080 | 单曲音质 |
| `catalog.(*Library).FillSongQualities` | 0x140447960 | **用上游数据填充歌曲档位** |
| `catalog.ApplyHuaweiAudioFiles` | 0x140447d20 | 应用上游返回的音频文件 |
| `catalog.NeedsSongQuality` | 0x140448040 | 是否需要补查音质 |
| `catalog.huaweiAudioFiles` | 0x14043aaa0 | 华为取流档位（上游 fileURL） |

### 2.4 结论（"音质从上游确定"）
EXE 不是客户端写死"标准/无损两档循环请求"，而是：
1. 上游详情/搜索响应带 `privilege`（含 `maxbr`/`level`/`fee`/`chargeInfoList`）；
2. `FillSongQualities` / `songQualities` 把这些字段映射为每首歌的**实际可用档位集合**；
3. 取流时用 `locateQuality` / `locate` 按目标档位向上游要对应 level；
4. 播放档位以下载到的 `br`/`level` 为准，`PlaybackQualityMembership` 决定哪些档位会员可用。

因此 Flutter 必须改为：档位集合来自上游字段（privilege/chargeInfoList/fileURL 的 br/level），
取流按目标 level 请求，不再本地固定 qualityType 1/3 硬猜。
