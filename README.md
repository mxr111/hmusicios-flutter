# 沐语 Flutter 复刻版（MuyuFlutter）

基于 **REA 对沐语 Windows 客户端（v2.0.3 / v2.0.4）的静态逆向 + 运行时进程内存取证**，并用同源项目 **tinglan（Go+Viva 华为音乐客户端）** 做源码级交叉校正，用 Flutter 重写其界面与四音源播放闭环。

> 🟢 **v3（2026-11-24）**：四音源（华为 / 网易云 / 酷狗 / QQ）+ 本地音乐 + 登录态持久化 + 全量分页。
> - 华为收藏 / 自建歌单 / 收藏歌单 / 歌手歌曲不再截断在 50 首，按 50 一页翻到短页（去重、无进展即停）。
> - 启动时恢复华为音乐 token / 网易云 MUSIC_U / 酷狗 Cookie / QQ Cookie，不再每次打开都重新扫码。
> - 搜索页新增「歌曲 / 歌手 / 专辑」三栏；华为响应含 artistSimpleInfos / albumSimpleInfos 时直接展示。
> - 本地音乐：系统文件选择 → 复制进沙箱 → 解析 ID3v2 / FLAC Vorbis → 持久化 → 直接播放。
> - 酷狗 / QQ 协议见 `rea_evidence/PROVIDER_PROTOCOL_EVIDENCE.md`；签名算法来自公开协议，标注「待真机验证」。

> 🔴 **v2 重大修正（2026-11-23）**：REA 反编译拿不到函数伪代码（本机无 Ghidra/IDA/Hopper/Kuna 引擎），但找到了同源项目 tinglan 的源码，纠正了此前两个致命错误：
> 1. **鉴权不是 Bearer**，而是 `Authorization: Digest username=app-music-baseline, nonce=<随机>, created=<UTC>, token=<music token>`；且需三段式：OAuth 授权（域名 `oauth-login.platform.hicloud.com`）→ 换账号 AT → `loginex` 换音乐 token + snsUserID。这解释了此前真机接口不通的根因。
> 2. **取流 qualityType 是 "1"(MP3)/"3"(FLAC)**，不是 h/sq/hr；主音频用顶层 `fileURL`。
>
> 详见工作区 `rea-muyu/TINGLAN_SOURCE_REFERENCE.md` 与 `rea-muyu/REA_DEEP_PLAYER_ANALYSIS.md`。

### v2 新增界面

| 页面 | 文件 | 依据 |
| --- | --- | --- |
| 华为音乐发现页（音乐厅） | `widgets/discover_page.dart` | REA 文案「音乐厅/排行榜/推荐歌单/新歌推荐/热歌速递/心动电台」；Banner 轮播 + 8 金刚区 + 推荐歌单 + 新歌 + 榜单 + 电台 |
| 沉浸播放页（深色黑胶 + 逐字卡拉 OK） | `widgets/immersive_player.dart` | 运行时截图 `muyu_window2.png` + tinglan `stage.go`；封面模糊背景、焦点字号、已唱部分 smootherstep 推进 + 羽化、点击 seek |
| 12 款主题 | `theme.dart` | tinglan `theme.go` 精确色值（晨光/晴海/鼠尾草/暖砂/蔷薇/冰川/午夜蓝/深林/石墨/夜玫瑰/咖啡/曜石） |
| 歌词解析 | `protocol/huawei_api.dart` | tinglan `hmrc.go`/`lyrics.go`；HMRC 逐字 + LRC 行级 + 译文合并 |

本机验证：`flutter analyze` → No issues found!；`flutter test` → **+8 全过**（含 Digest 头、HMRC、qualityType 回归）；`flutter build bundle` → 成功。

## 一、环境（本机已配置完成）

| 项 | 值 |
| --- | --- |
| Flutter | `3.47.5` stable（`C:\Dev\Tools\flutter`） |
| Dart | `3.13.4` |
| VS Code | `C:\Dev\Microsoft VS Code\Vs code.exe` |
| 插件 | `dart-code.dart-code` / `dart-code.flutter` 3.146.0 |
| 配置 | 用户 PATH 已加 `C:\Dev\Tools\flutter\bin`；用户 settings.json 已写 `dart.flutterSdkPath`；工程 `.vscode/settings.json` 也显式指向 SDK |

本机验证结果：

```
flutter pub get   → Changed 39 dependencies
flutter analyze   → No issues found!
flutter test      → +4: All tests passed!
```

用 VS Code 打开本目录即可，Dart/Flutter 插件会自动识别 SDK。

## 二、REA 证据（本工程 `rea_evidence/`）

1. **窗口截图** `muyu_window.png`：对运行中的 Muyu.exe（PID 2584）用 `capture_window.py`（Win32 `EnumWindows` + `GetWindowRect` + Pillow `ImageGrab`）截取。这是界面还原的第一手依据。
2. **运行时内存取证** `read_mem.py`：Python ctypes + `VirtualQueryEx` / `ReadProcessMemory`，扫描 837 MB / 1352 个内存区，抓到 Go 堆里的真实请求 URL：
   ```
   https://api-drcn.music.dbankcloud.cn/music-userbehavior-service/v1/service/favorite/simple/exist?contentID=70684&contentType=1
   ```
   → 证明「域名 + 完整路径 + `?query` 原样拼接」，**`?` 不能被编码**（早期 iOS 版因此 404）。
3. **静态提取**：`vinyl-player` / `lyrics-stage` / `style-panel-floating-player` / `home-card-press` / `song-quality` / `volume-popup` 等组件名；488 个主题/封面色；中文文案「主题为浅色」「主页支持切换华为音乐」「为你推荐」「心动模式」等。
4. 完整协议事实见上一版工程的 `CHECK_REPORT.md` / `PROTOCOL_NOTES.md`。

## 三、界面还原清单（对照截图）

| 截图元素 | Flutter 实现 |
| --- | --- |
| 左侧栏：头像/昵称/等级、主页（蓝色竖条选中）、音乐厅、唱片架、我的、自定义入口+、本地音乐 | `widgets/sidebar.dart` |
| 顶部「主页」+ 华为音乐胶囊 + K/Q/云 音源圆标 + 千语取歌 | `widgets/home_page.dart` |
| 圆角搜索框「搜索音乐」 | 同上 |
| 四张渐变卡片：Music FM / November 23 每日30首 / 心动模式 / New 新歌推荐（+热歌速递） | `HomeCard` |
| 「为你推荐 1/5」+ 左右翻页 + 歌曲行（封面、歌名、歌手、红心、书签、Hi-Res） | `SongRow` |
| 底部白色悬浮胶囊播放条：黑胶封面、歌名/歌手、音源徽章、Hi-Res、循环/上一首/播放/下一首、进度 1:19–4:45、收藏/音量/更多/歌词/队列 | `widgets/player_bar.dart` |
| 全屏歌词页（REA 组件 `lyrics-stage`） | `pages/secondary_pages.dart` |
| 浅色主题（REA 确认「主题为浅色」）+ 深色切换 | `theme.dart` / 设置页 |
| App 图标：用户提供的渐变音符图，按 RGB 阈值 + 边界泛洪抠掉黑边，同色系渐变补齐为不透明 | `scripts/process_icon.py` → `assets/app_icon.png` → `scripts/gen_ios_icons.py` 全套尺寸 |

iPad 宽屏用侧栏，iPhone 窄屏自动切底部标签栏。无网络/未登录时也保留完整离线占位界面。

## 四、功能链路

```
华为账号登录 / 手动 access_token
  → HuaweiGateway（设备串伪装 HBN-AL00、client_id 101444301、完整请求头）
  → HuaweiAPI（首页 / 搜索 / 榜单 / 收藏 / 歌单 / 歌词 / 相似推荐）
  → /music-play-service/v3/service/file/bycontentcode 取 h/sq/hr 签名 URL
  → LeaseProxy（dart:io HttpServer，127.0.0.1 一次性 token，Range/206/410 流式透传）
  → audioplayers → AVPlayer(iOS) / ExoPlayer(Android)
```

关键修复沿用运行时取证结论：`makeUrl()` 把 path 与 query 分开，带 query 的接口先 GET、遇 404/405 自动 POST 重试；单元测试锁死了「不得出现 `%3F`」这条回归线。

## 五、目录

```
lib/
  main.dart                       入口 / 根布局 / iPad·iPhone 自适应
  theme.dart  models.dart         REA 配色、音质/歌曲/歌单模型
  protocol/endpoints.dart         REA 观察到的全部服务路径
  protocol/huawei_gateway.dart    URL 构造、请求头、GET/POST 自适应、错误分类
  protocol/huawei_api.dart        曲库接口 + 容错解析 + LRC
  services/lease_proxy.dart       可撤销租约代理
  services/audio_controller.dart  播放器 / 队列 / 音质
  services/app_state.dart         全局状态
  widgets/                        侧栏、主页、卡片、歌曲行、播放条
  pages/                          搜索 / 音乐厅 / 唱片架 / 我的 / 设置 / 歌词 / 登录
scripts/gen_ios_icons.py           由源图生成全套 iOS 图标尺寸
.github/workflows/                 macOS 云端编译未签名 IPA
```

## 六、运行与编译

```bash
cd MuyuFlutter
flutter pub get
flutter analyze
flutter test
flutter run -d windows          # Windows 桌面（需 Visual Studio 工具链）
flutter build apk --release     # Android（需 Android SDK）
flutter build ipa --no-codesign # 仅 macOS + Xcode
```

**Windows 不能编译 iOS IPA**（Apple 工具链限制）。已配 `.github/workflows/build-flutter-ipa.yml`：push 到 `main` 后由 macOS runner（`macos-14`，避开 `macos-15` 池排队）执行 `flutter analyze` → `flutter test` → `flutter build ipa --release --no-codesign`（Flutter 3.47 只产出 `Runner.xcarchive` 并跳过 IPA）→ 从 xcarchive 里的 `.app` 打包未签名 IPA，上传 `MuyuFlutter-unsigned-ipa` 产物，自签后装到 iPad。

## 七、已知缺口

- 🔴 **华为业务请求的额外签名仍未还原**：若接口返回 401/403，需自有账号抓包补齐；设置页支持手动填入 `access_token` 调试。
- 酷狗 `signature` / QQ `zzcSign` 已按二进制字符串与公开协议实现，并写了离线单测，但**未用真实账号联网验证**；失败时 UI 会显示真实错误。
- 酷狗 / QQ 目前只做「Cookie 手动登录」+ 搜索 / 歌单 / 歌词 / 取流 / 评论；扫码登录、收藏与歌单增删尚未接入。
- 本地音乐已解析 ID3v2 / FLAC 标签，但内嵌封面（APIC / FLAC PICTURE）暂未显示，使用渐变占位。
- 网易云 / 酷狗 / QQ 的歌手页用「歌手名搜索」兜底，不是原版独立歌手详情接口。
- IPA 未签名，需 AltStore / Sideloadly / 自有证书自签。
