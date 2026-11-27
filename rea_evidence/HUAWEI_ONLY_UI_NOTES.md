# 华为音乐单音源 UI 收敛说明

## UI 收敛

- `lib/widgets/home_page.dart`
  - 删除 `SourceSwitcher`、`_SourceSpec` 以及首页顶部的多音源横向切换。
  - 标题旁固定显示 `SourceBadge` 的「华为音乐」标识。
  - 保留 5 张首页卡、「为你推荐」、推荐歌单、热歌榜、上一页/下一页和
    空态显式重试；各板块继续只读 `state.discover` 的独立列表。
- `lib/widgets/sidebar.dart`
  - 用户区固定读取华为账号，未登录文案为「登录华为音乐」，登录后副标题
    固定为「华为音乐账号」。
  - 自定义入口、本地音乐、设置不包含其他音源入口。
- `lib/widgets/discover_page.dart`
  - 音乐厅标题固定显示华为音乐徽章，只展示华为推荐歌单与华为榜单，
    保留榜单网格分页和点击进入详情。
- `lib/widgets/common.dart`
  - `SourceBadge` 固定渲染「华为音乐」文案与蓝色标识。
  - `SongRow` 的来源小图标固定为华为音乐图标/颜色；即使底层
    `Song.source` 仍是网易云、酷狗、QQ 或本地，也不会渲染其他来源文案。

## 其他音源 UI 文件

已用 `apply_patch` 删除以下无引用文件：

- `lib/widgets/netease_login_sheet.dart`
- `lib/widgets/kugou_login_sheet.dart`
- `lib/widgets/qq_login_sheet.dart`

`lib/widgets/netease_home_page.dart` 暂未删除：`test/ui_smoke_test.dart`
仍直接构造 `NeteaseHomePage`。该文件已移除对已删除 `SourceSwitcher` 的
引用，保证当前代码可编译；待该测试不再引用后，可用 `apply_patch` 删除。

## 底层协议保留原因

- `lib/protocol/netease_api.dart`、`kugou_api.dart`、`qq_api.dart` 仍被
  `AppState`、音频控制器、会话/播放兼容逻辑引用。
- `MusicSource` / `MusicSourceLabel` 枚举仍供底层协议和歌曲数据模型使用。
- 本次只收敛 UI 展示与入口，不删除底层协议，避免破坏已有会话恢复、播放
  解析和 A/B 并行改动的契约。

## 验证

- 针对修改文件运行 `flutter analyze`：无问题。
- 运行 `test/home_ui_test.dart`、`test/home_group_ui_test.dart`、
  `test/pagination_artist_ui_test.dart`、`test/huawei_only_ui_test.dart`：
  全部通过。
