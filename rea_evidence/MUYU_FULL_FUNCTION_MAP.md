# 沐语 Muyu.exe 1.2.0 全量反编译 · 功能地图

> 目标：`C:\沐语\Muyu.exe` = `rea-muyu/win/Muyu.exe`，82,458,112 B，Go 1.27.4，module `muyu.local/desktop`。
> 引擎：REA CLI 6.7.0 + Ghidra 12.1.4 + JDK 21（`~/.workbuddy/mcp.json` 已持久化）。
> 时间：2026-11-24。本文是「反编译整个 exe」的交付文档，函数地址均由 pclntab 实测（`go_sym_addr.py`）。

---

## 1. 反编译规模（全量，非抽样）

| 维度 | 数量 | 证据文件 |
| --- | --- | --- |
| Go 函数（pclntab） | 33,051 | `all-sym-addrs.tsv` |
| 有效功能符号（去重） | 1,348 | `full-symbols.json` |
| 源码路径 | 1,975 | `full-symbols.json` |
| 根目录模块源文件 | 222 | 本文 §3 |
| 中文 UI 文案 | 25,305 | `full-symbols.json` |
| 华为音乐 API 路径 | 26 | `full-symbols.json` / `endpoints.dart` |
| 函数级伪代码（Ghidra） | 已反编译 4 + 批量 30 | `decomp_*.json` |

---

## 2. 功能模块分布（按符号数）

| 模块 | 符号数 | 功能 |
| --- | --- | --- |
| internal/providers | 255 | 4 个第三方音源：酷狗 92 / QQ 89 / 网易 66 / Subsonic 8 |
| (root) | 222 | 主程序 UI/控制/播放/收藏/歌单（222 个 .go 文件，见 §3） |
| internal/nativeaudio | 113 | 解码/seek/音量/Media Foundation/FLAC 帧级 seek |
| internal/catalog | 107 | 曲库：搜索/歌单/收藏/榜单/歌手/专辑/相似/取流 |
| internal/nativeeffects | 82 | 8 种音效 + 均衡器 |
| internal/update | 80 | 在线更新/公告/历史 |
| internal/gateway | 69 | 华为私有网关（HTTP/签名/读恢复） |
| internal/sonnetnative + sonnetgpu | 85 | 沉浸式歌词几何/光晕/GPU 着色 |
| internal/nativecache | 62 | 图片缓存 |
| internal/desktop | 55 | 托盘/自启/协议/快捷键/存储 |
| internal/localmedia | 36 | 本地音乐扫描/探测 |
| internal/browserlogin | 32 | WebView2 OAuth 扫码登录 |
| internal/lyrics | 14 | LRC/HMRC 逐字歌词解析 |

---

## 3. 根目录 222 个模块文件 → 功能归类

| 功能域 | 代表文件 | 能力 |
| --- | --- | --- |
| 首页/发现 | native_home*.go (10), discovery.go, home_recommendations.go, daily_recommendations.go | 首页栏目、编辑精选卡、电台、为你推荐 |
| 播放器形态 | native_vinyl_player.go, native_folia_player.go, native_immersive_player*, native_minimal_player.go, native_sonnet_player.go, native_taskbar_player*.go | 黑胶/经典/沉浸/极简/任务栏 5 种形态 |
| 播放控制 | playback.go, native_queue*.go, native_play_timers.go, native_playback_capabilities.go | 三态模式/队列/定时停止/续播 |
| 音效音质 | native_audio_effects.go, native_equalizer.go, native_quality_menu_lookup.go, native_song_quality.go, native_ultra_audio_badge.go | 8 音效 + 均衡器 + 金色最高档徽标 |
| 歌词 | native_lyric*.go (8), native_desktop_lyrics.go, native_immersive_lyrics.go | 逐字/译文/桌面歌词/样式选择 |
| 歌单收藏 | favorites.go, favorite_order.go, playlists.go, native_playlist*.go (14), native_favorite*.go | 收藏排序/歌单增删/歌曲排序/搜索 |
| 搜索 | native_search_history.go, native_search_metadata.go, provider_search.go | 搜索历史/元数据/全平台搜索 |
| 歌手/专辑/MV | native_artist.go, provider_album.go, LocateMV | 歌手详情/专辑/AV |
| 社区 | community.go, native_comments.go, provider_comments.go | 评论/点赞 |
| 登录/账号 | login.go, browser_session.go, native_login.go, native_provider_login.go, native_account_platforms.go | OAuth/多平台账号 |
| 本地音乐 | native_local*.go, local_playlist_order.go | 本地扫描/歌单 |
| 下载 | native_download.go | 离线下载 |
| 会员 | native_order_status.go, memberaccess | 会员校验 |
| 设置/系统 | native_settings*.go, native_theme_accent.go, native_system_*.go, native_shortcuts*.go | 主题/系统快捷键/输出设备 |
| 更新 | updater.go, native_update*.go | 在线更新/公告 |

---

## 4. gateway.Connection 网络能力（29 方法）

`ApplicationRead` / `FeaturedSongs` / `HomeRadioSeed` / `RadioSongs` / `RadioMode` /
`RecommendedLists` / `Daily` / `EditorialDaily` / `MusicApplicationLogin` /
`MusicHomePage` / `applicationRequest` / `applicationSend` / `applicationQuery` /
`MusicRead` / `Music` / `Form` / `PaginationMore` / `SetDeviceID` / `deviceContext` /
`send` / `EnableReadRecovery` / `recoveryEnabled` / `boundedRead` / `ReadLoginCompleted` /
`ReadReadyAfterLogin` / `NeedsReadLogin` / `ResetReadFailures` / `ResetAccountReads` /
`CurrentReadFailure`

## 5. catalog.Library 曲库能力（48 方法）

`Search` / `SearchArtists` / `SearchArtistAlbums` / `SearchArtistSongs` /
`Artist` / `ArtistSongs` / `AlbumSongs` / `SongArtists` / `FindSongArtist` /
`Browse` / `Daily` / `RecommendedLists` / `HomeSongs` / `HomeSongsWithRadioMode` /
`HomeCharts` / `NextRadioSongs` / `Similar` / `Recent` /
`Favorites` / `FavoritePage` / `OrderedFavorites` /
`Collections` / `CollectionSongs` / `CollectionContains` / `CollectionContainsMany` /
`CreateCollection` / `DeleteCollection` / `ChangeCollectionSong(s)` / `CollectionCover` /
`Locate` / `LocateBest` / `LocateFromFiles` / `LocateMV` / `LocateQuality` / `locateHuaweiAudio` /
`SongQuality` / `SongAudioFiles` / `SongCover` / `FillSongQualities` / `huaweiAudioFiles` /
`Entitlements` / `CheckAccount` / `publicSongInfo`

---

## 6. 华为音乐 API 路径（26 条，全部实测）

主域 `https://api-drcn.music.dbankcloud.cn`，域名后直接拼完整路径，`?query` 原样保留。

| 服务 | 路径 |
| --- | --- |
| 首页 | `/music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1` |
| 栏目详情 | `/music-operation-service/v1/service/column/detail/...` |
| 榜单 | `/music-operation-service/v1/service/chart/detail/bychartid` |
| 分类 | `/music-operation-service/v1/service/category/simple/bycontenttype` |
| 歌单详情 | `/music-operation-service/v3/service/musiclist/detail/bymusiclistid` |
| 每日推荐 | `/music-recommend-service/v1/service/recommend/querydaily` |
| 推荐歌单 | `/music-recommend-service/v1/service/recommend/playlist` |
| 私人电台 | `/music-recommend-service/v1/service/recommend/privatefm` |
| 相似推荐 | `/music-recommend-service/v2/service/recommend/querysimilar` |
| 搜索 | `/music-search-service/v10/service/fuzzysearch` |
| 歌曲详情 | `/music-metacontent-service/v1/service/song/detail/bysongcode` |
| 歌手详情 | `/music-metacontent-service/v1/service/artist/detail/byartistcode` |
| 歌手歌曲 | `/music-metacontent-service/v1/service/song/simple/byartistcode` |
| 专辑详情 | `/music-metacontent-service/v1/service/album/detail/byalbumcode` |
| MV | `/music-metacontent-service/v1/service/mvfile/bymvid` |
| 用户信息 | `/music-odpapp-service/v5/service/userinfo` + `/loginex` |
| 会员 | `/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6` |
| 收藏判断 | `/music-userbehavior-service/v1/service/favorite/simple/exist?contentID=&contentType=` |
| 收藏列表 | `/music-userbehavior-service/v3/service/favorite/simple/all` |
| 收藏增删 | `/music-userbehavior-service/v1/service/favorite/create` / `delete` |
| 歌单增删 | `/music-userbehavior-service/v1/service/playlist/create` / `delete` |
| 歌单详情 | `/music-userbehavior-service/v1/service/playlist/detail/all` |
| 最近播放 | `/music-userbehavior-service/v1/service/recentlyplayed/query?contentType=1` |
| 取流 | `/music-play-service/v3/service/file/bycontentcode` |
| 评论 | `/music-sns-service/v1/service/comment/query` + `/querycount` |
| 用户配置 | `/music-user-service/v1/service/userconfig/detail/all` |

鉴权：OAuth PKCE → loginex → music token + snsUserID；业务头 `Authorization: Digest username=app-music-baseline, nonce=<24B>, created=<UTC>, token=<music token>`。

---

## 7. 函数级反编译关键结论（Ghidra 实测）

| 函数 | VA | 结论 |
| --- | --- | --- |
| `MusicHomePage` | 0x1404224e0 | 首页读 `columnInfoExs → contentSimpleInfos → childSimpleInfos → listRcmInfos` 三层结构 |
| `applicationRequest` | 0x1404225c0 | privatefm body = cadence/rcmMode/rcmScenario/refInfo；rcmMode ∈ {1,2,3} |
| `HomeSongs` | 0x14043a2e0 | 兼容精简键 ID/NM/pic 与完整键 contentID/contentName/durationSeconds/artistNamePairs |
| `RecommendedLists` | 0x140441b40 | 取流 bycontentcode body = contentType/contentCode/qualityType；响应顶层 fileURL |

详见 `MUYU_DISCOVERY_DECOMPILED.md`。

---

## 8. Flutter 复刻范围界定

用户约束：**只做华为音乐音源 + 运行于 iOS/iPadOS**。因此：
- ✅ 复现：首页/音乐厅/唱片架/我的/本地音乐 5 页、搜索、歌单/收藏增删、榜单、电台、歌手/专辑详情、评论、取流三档音质、逐字歌词、沉浸播放页、三态播放模式、定时停止、音效菜单、12 主题、OAuth 内置浏览器登录。
- ❌ 不做：酷狗/QQ/网易/Subsonic 音源（无凭据且用户明确排除）、Windows 任务栏/托盘/自启/全局快捷键/桌面歌词（iOS 无对应 API）、在线更新器（iOS 沙箱禁止）、Media Foundation 解码（用 audioplayers 替代）。
- 桌面歌词在 iOS 用「沉浸播放页大字歌词」等价实现。

---

## 9. 证据索引

- `all-sym-addrs.tsv`：33,051 函数地址（pclntab 实测）
- `go_sym_addr.py`：Go 符号→VA 解析器（本项目反编译必备前置）
- `full-symbols.json` / `player-ui-evidence.json`：符号 + 文案
- `decomp_*.json`：Ghidra 函数级伪代码
- `MUYU_DISCOVERY_DECOMPILED.md` / `REA_DEEP_PLAYER_ANALYSIS.md`：专题报告
- `muyu_window.png` / `muyu_window2.png`：收起态 / 沉浸态截图
