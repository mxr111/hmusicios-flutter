# 沐语 Flutter 复刻版（MuyuFlutter）

基于 **REA 对 `C:\沐语\Muyu.exe`（沐语 v2.0.3 Windows 客户端）的静态逆向 + 运行时进程内存取证**，用 Flutter 重写其界面与「华为音乐」播放闭环。按需求**只接华为音乐一家数据源**。

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
| App 图标（沐语红环 + 白色「沐」字，REA 配色） | `assets/app_icon.png` + 全套 iOS 尺寸 |

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

**Windows 不能编译 iOS IPA**（Apple 工具链限制）。已配 `.github/workflows/build-flutter-ipa.yml`：push 到 `main` 后由 `macos-15` runner 执行 `flutter analyze` → `flutter test` → `flutter build ipa --release --no-codesign`，产出 `MuyuFlutter-unsigned-ipa` 产物，自签后装到 iPad。

## 七、已知缺口

- 🔴 **请求签名算法未还原**：静态逆向与运行时内存都没看到 timestamp/nonce/signature。若接口返回 **401/403**，即为该缺口；需自有账号抓包补齐。设置页支持手动填入 `access_token` 调试。
- 账号密码登录字段为 REA 路径 + 推断，可能不通；华为 OAuth PKCE 在原生版已实现，Flutter 版保留端点常量。
- 其它音源（酷狗 / QQ / 网易云）图标保留但置灰，本项目不接入。
- 未登录时展示的是截图同款离线占位数据，不是真实曲库。
- IPA 未签名，需 AltStore / Sideloadly / 自有证书自签。
