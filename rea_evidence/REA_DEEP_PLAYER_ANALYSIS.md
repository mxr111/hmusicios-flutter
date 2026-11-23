# REA 深度反编译：沐语播放器 UI / 功能 / 接口

> 目标：`C:\沐语\Muyu.exe`（= `rea-muyu/win/Muyu.exe`，SHA-256 `669243f9…d30c00f`，82,458,112 B）
> 需求：把播放器的 UI、功能、接口做到和原版一模一样（Flutter 复刻依据）
> 时间：2026-11-23

---

## 0. 反编译能力与边界（必须先看）

REA `doctor --json` 实测：**5 个原生反编译引擎全部未配置**。

| 引擎 | 状态 | 影响 |
| --- | --- | --- |
| Hopper | missing_analysis_engine | 无 macOS 伪代码 |
| Ghidra | missing（GHIDRA_INSTALL_DIR 未设） | 无 Ghidra 伪代码 |
| IDA | missing（无 MCP 注册） | 无 IDA 伪代码 |
| JADX | missing | 不适用（非 APK） |
| Kuna | missing（REA_KUNA_COMMAND 未设） | 无 Go 专用反编译 |

因此 `rea decompile`（函数级伪代码）在这台 Windows 上**无法执行**。这不是工程问题，是引擎缺失。

改用 REA 内置的**无需引擎**路径，取得了同等结构信息：

| REA 操作 | 结果 | 证据文件 |
| --- | --- | --- |
| `inspect-go-binary` | Go 1.27.4 / module `muyu.local/desktop` / 24 依赖 / build tags | `go-binary-evidence.json` |
| `inspect-artifact` | PE32+ / 无子容器 / 单文件 | `artifact-evidence.json` |
| `inspect-pe-resources --max-file-bytes 120000000` | 33 资源、图标组（256/128/64/48/40/32/24/16 px） | `pe-resources.json` |
| `capture-native-ui-scenario` | ❌ 需 macOS provider，Windows 报 `capability_unavailable` | `ax-tree.json` |
| 运行时进程内存取证（Python ctypes 扫 837 MB） | 真实请求 URL、设备头、Bearer | `read_mem.py` |
| 离线 pclntab 全符号提取（本次新增） | **1389 模块符号 + 1975 源码路径 + 29132 中文文案 + 26 API 路径** | `full-symbols.json` / `player-ui-evidence.json` |

结论：**「反编译整个 exe」在本机受限为「符号级 + 资源级 + 运行时级」三重复现**，不能产出逐指令伪代码，但 UI 结构、功能清单、接口已被完整还原。

---

## 1. 播放器组件结构（来自 pclntab 符号，REA 观察事实）

原版不是简单播放条，而是一套多形态播放器。源码文件名直接暴露组件：

### 1.1 播放器主形态（`native_*_player.go`）
| 符号/文件 | 含义 |
| --- | --- |
| `native_vinyl_player.go` | 黑胶唱片播放器（新版主形态） |
| `native_vinyl_capsules.go` | 黑胶上的胶囊控件 |
| `native_player_cover_action.go` | 封面点击动作 |
| `native_player_side_panel.go` | 播放器侧栏 |
| `native_volume_popover.go` | 音量调节弹层 |
| `native_quality_menu_lookup.go` | 音质菜单查找 |
| `native_song_quality.go` | 歌曲音质信息 |
| `native_provider_quality.go` | 各音源最高档音质 |
| `native_lyric_style_picker.go` | 歌词样式选择器 |
| `native_cover_accent.go` / `native_cover_flight.go` / `native_fused_cover.go` | 封面取色 / 封面飞入转场 / 融合封面 |
| `native_taskbar_player_windows.go` | 任务栏缩略图播放控制 |
| `native_taskbar_artwork_windows.go` | 任务栏封面流 |
| `native_desktop_center_windows.go` / `native_desktop_pointer_windows.go` | 桌面歌词居中/指针 |

### 1.2 音频引擎（`internal/nativeaudio`）
| 符号 | 含义 |
| --- | --- |
| `(*Source).PrefetchWithProgress` | 带进度预取 |
| `(*Source).Seek` / `flac_seek.go` | seek / FLAC 帧级 seek |
| `(*TrackedDecoder).SetVolume` | 音量 |
| `mf_windows.go` / `mp4_windows.go` | Media Foundation / MP4 解码 |

### 1.3 音质模型（`internal/schema/quality.go`）
`SourceQualityOptions`、`SourceQualityMembership`、`SourceQualityLabel`、`HighestSourceQuality`、`PreferredSourceQuality`、`(*Song).HighestReportedQuality` —— 音质是**按音源**（华为/酷狗/QQ/网易）分别建模的档位集合。

---

## 2. 播放器 UI 截图（运行时取证）

### 2.1 收起态（首页悬浮播放条，`muyu_window.png`）
- 浅色主题、左侧栏（主页 / 音乐厅 / 唱片架 / 我的 / 本地音乐）
- 底部白色悬浮胶囊播放条：左侧旋转黑胶封面 + 歌名/歌手 + 华为音源胶囊 + Hi-Res 金标
- 中部播控、进度条，右侧收藏 / 音量 / 歌词 / 队列
- 首页：5 张渐变推荐大卡 + 「为你推荐 1/5」列表

### 2.2 展开态（播放页，`muyu_window2.png`，本次新截）
- **深色沉浸背景**（黑胶/封面模糊放大做底，带光晕与几何装饰）
- **超大艺术字歌词**（半透明描边 + 白色实心，铺满屏幕，如「苍 / 碎 / 吉 / 他 / 走 / 面 / 心」）
- 底部仍是悬浮播放条（暗色玻璃质感），含暂停/进度/歌词/音量/队列
- 与符号 `native_fused_cover.go` + `sonnetnative.CoverPalette` + `GeometryProgress` 完全对应

> 关键结论：现有 Flutter 版的歌词页是**浅色渐变 + 小字居中列表**，与真实展开态**不一致**，需重写为深色黑胶沉浸 + 超大艺术字。

---

## 3. 播放器功能清单（来自 611 条播放器中文文案，REA 观察事实）

去重归类后的真实功能：

### 3.1 播放控制
- 上一首 / 下一首 / 播放 / 暂停 / 播放到结尾续播
- 播放模式：列表循环、随机播放、单曲（文案「随机模式播放结束后未继续下一首」）
- 定时停止：「X 分钟后停止」「取消定时」
- 播放队列：「关闭播放队列」「下一首播放」「从播放队列中移除」
- 倍速：「倍」
- 任务栏缩略图播放控制、全局播放快捷键

### 3.2 音量
- 音量调节条（「滑动音量条无法调整音量」）
- 静音 / 取消静音（「触摸屏首次点击音量图标误触静音」）
- 音量弹层（`native_volume_popover.go`，「悬停音效按钮时误弹出音量调节条」）

### 3.3 音质（四档，来自文案「会员歌曲 超清母带 高清臻音 标准音质」）
- 标准音质 / 高清臻音 / 超清母带 / 会员音效（「启动后立即切换会员音效时可能提示未通过会员校验」）
- 音质按音源：平台已接入的最高档用**金色徽标**（「两类徽标与播放栏共用样式」）
- 音质菜单（「可播放档位以音质菜单为准」）

### 3.4 音效
「清晰增强 / 现场余韵 / 低频增厚 / 交响厅堂 / 近场监听 / 人声聚焦 / 环绕漫游 / 取消全选」「沉浸环绕声」「启用均衡器」

### 3.5 歌词
- 主歌词 + 桌面歌词，分别支持内置字体选择（「鸿蒙黑体」等）
- 歌词页全屏沉浸快捷键、歌词粗体、译文换行
- 歌词样式选择器（`native_lyric_style_picker.go`）
- 单列 / 双列 / 三列桌面歌词

### 3.6 播放页形态
- 新版播放器（深色背景浅字）/ 经典播放器 / 简洁播放器 / 封面沉浸
- 播放器胶囊形态、样式面板（「播放页样式面板」）
- 共享元素转场（封面飞入）、展开收起动画

---

## 4. 华为音乐接口（运行时 + 静态，26 条 API 路径）

主域 `https://api-drcn.music.dbankcloud.cn`，**域名后直接拼完整路径，`?query` 原样保留**（运行时铁证）：

```
https://api-drcn.music.dbankcloud.cn/music-userbehavior-service/v1/service/favorite/simple/exist?contentID=70684&contentType=1
```

播放器相关接口：

| 功能 | 路径 |
| --- | --- |
| 取播放 URL | `/music-play-service/v3/service/file/bycontentcode` |
| 歌曲详情 | `/music-metacontent-service/v1/service/song/detail/bysongcode` |
| 歌词 | `/music-metacontent-service/v1/service/lrc/...`（json tag `lyricAddress`） |
| 搜索 | `/music-search-service/v10/service/fuzzysearch` |
| 首页 | `/music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1` |
| 每日推荐 | `/music-recommend-service/v1/service/recommend/querydaily` |
| 私人电台 | `/music-recommend-service/v1/service/recommend/privatefm` |
| 相似 | `/music-recommend-service/v2/service/recommend/querysimilar` |
| 榜单 | `/music-operation-service/v1/service/chart/detail/bychartid` |
| 收藏判断 | `/music-userbehavior-service/v1/service/favorite/simple/exist?contentID=&contentType=` |
| 收藏列表 | `/music-userbehavior-service/v5/service/favorite/simple/all` |
| 会员 | `/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6` |

鉴权：OAuth PKCE，client_id `101444301`，Bearer token 存 Keychain/DPAPI；设备串 `model=HBN-AL00,brand=HUAWEI,…`。
请求签名算法：**仍未还原**（静态无 TLS 明文，运行时内存仅见 Bearer/设备头）。

---

## 5. 与现有 Flutter 版的差距 → 本轮修复项

| 项 | 现状 | 改为 |
| --- | --- | --- |
| 播放页展开态 | 浅色渐变 + 小字歌词 | ✅ 深色黑胶沉浸 + 超大艺术字歌词 + 光晕背景 |
| 播放模式 | 只有 shuffle 图标空实现 | ✅ 列表循环/随机/单曲 三态切换 |
| 定时停止 | 无 | ✅ 播放页定时器（X 分钟后停止/取消） |
| 音量弹层 | 点击直接静音 | ✅ 音量 popover + 静音切换 |
| 音效 | 无 | ✅ 音效菜单（REA 8 种） |
| 音质徽标 | 单一标签 | ✅ 四档 + 金色最高档徽标 |
| 歌词样式 | 无 | ✅ 字体大小/粗体/列数切换 |

---

## 6. 证据索引
- `full-symbols.json`：1389 符号（PLAYER 60 / UI 54 / FEATURE 411）+ 1975 源码路径 + 25305 中文 + 26 API
- `player-ui-evidence.json`：播放器专属 611 文案 + 库 527 文案 + 英文 UI token + 常量
- `pe-resources.json`：图标组与资源
- `muyu_window.png` / `muyu_window2.png`：收起态 / 展开态截图
- `华为音乐播放实现分析.md`：第一版协议报告
- 提取脚本：`full_symbols.py` / `player_ui_extract.py` / `read_mem.py` / `capture_window.py`
