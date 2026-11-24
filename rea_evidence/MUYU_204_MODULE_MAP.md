# 沐语 2.0.4 全量模块地图（pclntab）

> 数据源：`rea_evidence/_syms_204.tsv`（33,337 个函数符号，Go 1.27）。
> 复现：`python rea_evidence/tools/summarize_modules.py`。
> 说明：stdlib/other 29,671 个是 Go 运行时/标准库，不是业务代码。

## 1. 业务模块函数分布

| 模块 | 函数数 | 职责 | Flutter 状态 |
| --- | ---: | --- | --- |
| `main` | 2,770 | UI、nativeModel、页面/播放器/歌单/登录/评论/皮肤 | 主要页面已复刻 |
| `providers` | 185 | kugou / qq / netease / subsonic | 酷狗、QQ 已接骨架；网易云已接；Subsonic 未接 |
| `nativeaudio` | 92 | Media Foundation、FLAC/MP3 解码、seek、音量 | 用 audioplayers 替代 |
| `catalog` | 83 | 搜索/歌单/收藏/榜单/歌手/专辑/相似/取流 | 华为核心已接并实测 |
| `update` | 68 | 在线更新/公告/历史 | iOS 未接 |
| `gateway` | 60 | 华为 HTTP/Digest/重试/恢复 | 已按 2.0.4 实测重写 |
| `nativecache` | 53 | 图片缓存 | 用 Image.network 缓存 |
| `dlna` | 49 | DLNA 投播 | 未接（iOS 无对应） |
| `desktop` | 47 | 托盘/自启/快捷键/存储 | iOS 不适用 |
| `nativeeffects` | 39 | 8 音效 + 均衡器 | 菜单有，DSP 未接 |
| `sonnetnative` | 39 | 几何艺术歌词 | 已复刻视觉 |
| `localmedia` | 35 | 本地扫描/标签/封面 | 已接 ID3/FLAC 标签与播放 |
| `schema` | 25 | Song/Playlist/Quality 模型 | 已对齐 |
| `nativelog` | 23 | 日志脱敏 | 未接 |
| `browserlogin` | 22 | WebView2 OAuth | 用 webview_flutter 替代 |
| `media` | 17 | 媒体抽象 | audioplayers 替代 |
| `identity` | 12 | OAuth PKCE / 凭据 | 已按 tinglan 源码实现 |
| `lyrics` | 11 | LRC/HMRC | 已接 |
| `nativeprefs` | 11 | 偏好 | shared_preferences |
| `sonnetgpu` | 11 | GPU 光晕 | 未接（Flutter 自绘） |
| `install` / `runtimecontrol` / `network` / `memberaccess` | 4/4/3/3 | 安装、运行控制、网络、会员 | 部分/未接 |

## 2. 关键功能面（2.0.4 实测）

- 四音源：华为（gateway+catalog）、酷狗、QQ、网易云、Subsonic。
- 登录：华为 OAuth PKCE + 内置浏览器；酷狗/QQ/网易云扫码或 Cookie。
- 首页：`page/detail/all` 29 个 column，contentType 1/2/4/6/7/10/11/12/20/96。
- 播放器：黑胶/经典/沉浸/极简/任务栏 5 形态；三态播放、定时停止、音效、均衡器。
- 歌词：HMRC 逐字、LRC、翻译、桌面歌词、几何艺术字。
- 歌单/收藏：创建/删除/增删歌曲/排序/批量/补全/替换。
- 本地音乐：扫描、标签、封面、本地歌单。
- 下载/缓存/更新/公告/赞赏/DLNA/投播。

## 3. 本轮已用真实账号验证的华为链路

1. 收藏 v5：`000000 Success!`，返回真实歌曲。
2. 首页 GET：18 首歌 / 27 歌单 / 10 榜单 / 40 电台。
3. 搜索：歌曲 30 / 歌手 30 / 专辑 30。
4. 每日30首歌单（a001）：真实歌曲。
5. 自建歌单（v1 GET）：30 首真实歌曲。
6. 榜单（GET）：200 首真实歌曲。
7. 取流：返回 `https://music-common-drcn.dbankcdn.cn/..._MQ.mp3?X-Amz-...`。

详细协议见 `HUAWEI_204_PROTOCOL.md`。

## 4. 尚未完全一致的模块（后续优先级）

| 优先级 | 缺口 |
| --- | --- |
| P0 | 华为每日推荐/私人FM/recommend 的 POST envelope（当前 400，已用首页数据兜底） |
| P0 | 酷狗/QQ 真实账号联网验证；扫码登录与写操作 |
| P1 | 评论展开/点赞、MV、下载、音效 DSP、均衡器 |
| P1 | 歌单批量补全/替换/排序、收藏按日期排序 |
| P2 | 桌面歌词、任务栏播控、DLNA、在线更新（iOS 不适用） |
