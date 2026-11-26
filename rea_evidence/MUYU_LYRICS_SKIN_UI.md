# 沐语播放歌词页 + 皮肤页：REA 反编译事实与复刻对照

> 目标：Muyu.exe 1.2.0。引擎：REA 6.7.0 + Ghidra 12.1.4 + JDK21。
> 时间：2026-11-24。证据：`player-ui-evidence.json`（611 播放器文案）、`muyu_window2.png`（展开态截图）、符号表。

## 1. 播放歌词页（展开态）截图事实

`muyu_window2.png` 显示的是沐语标志性 **sonnet 几何艺术字歌词**：
- 背景：深灰/黑色，封面模糊放大 + 右侧椭圆光晕 + 几何装饰。
- 歌词：超大白色**实心**字（当前句）+ 白色**描边空心**字（相邻句）交叠，铺满屏幕。
- 几何线框：十字、菱形、圆弧、虚线对齐框、对齐标记点，细白线半透明。
- 底部：收起态悬浮胶囊播放条（深色玻璃）。

## 2. 源码符号（能力面）

### 2.1 sonnet 几何歌词引擎（internal/sonnetnative + sonnetgpu）
`TextGeometryFrame`(0x140b5f2e0) / `GeometryGroup.Replay`(0x140b5b960) /
`GeometryProgress`(0x140b5da40) / `FrameDecor.Draw`(0x140b59400) /
`CoverPalette`(0x140b5eb80) / `segmentFocus` / `focusDistance` /
`sonnetgpu.OriginalFill`(0x140b627e0) / `OriginalStrokes`(0x140b63a40) /
`Reveal`(0x140b65160) / `prepareNativeSonnetGlyphGlow` / `prepareNativeSonnetGuide`

### 2.2 播放器样式（4 种，文案实测）
「新版播放器 / 经典播放器 / 封面沉浸 / 简洁播放器」
- 文案：「新增封面沉浸样式，可从歌词页底部栏打开缩略图面板切换样式。横屏采用左右布局，竖屏采用上方封面、下方歌词的布局」
- 「新版播放器黑胶唱片随播放旋转」「新版播放器支持交换左右布局」「新版播放器歌词在右」
- 「播放器样式面板改为纵向排列」「关闭播放器样式」

### 2.3 歌词样式面板（文案实测）
`lyricStylePicker`(0x140bd1420) / `lyricStylePanel`(0x140bd15e0) /
`lyricStylePreviewPalette`(0x140bd19a0) / `lyricStyleThumbnail`(0x140bd1c40) /
`setLyricStyle`(0x140c1f9a0) / `applyLyricStyle`(0x140c1fb00)
选项（文案）：「歌词字体」（鸿蒙黑体等内置字体）、「歌词居中」、「歌词粗体」、
「单列/双列/三列」（桌面歌词）、字号、「颜色随封面主色变化」（light settings）、
「歌词显示 / 显示歌词 / 显示背景」

### 2.4 沉浸光感（皮肤，文案实测）
`immersiveLightSettings`(0x140bc67a0)
- 「原毛玻璃设置迁移为沉浸光感的超厚档」
- 「独立设置按压形变、滑动光效、光感颜色和超薄」
- 「光感颜色直接从颜色列表选择」「颜色随封面主色变化」
- 「沉浸与全屏独立控制」「新增歌词页全屏模式」「开启后顶部和底部控件分别退场」

## 3. 主题/皮肤系统（color palette）

主题色板来自同源 tinglan 源码 `native/cmd/music/theme.go paletteFor()`，12 款精确色值
（base/surface/text/secondary/muted/accent/dark）：晨光/晴海/鼠尾草/暖砂/蔷薇/冰川/
午夜蓝/深林/石墨/夜玫瑰/咖啡/曜石。已完整落在 `theme.dart kMuyuPalettes`。

沐语额外（tinglan 无）：主题色（「青色主题色」）、光感颜色列表、按压形变、滑动光效、
跟随系统深浅、鸿蒙黑体全局字体。

## 4. Flutter 复刻实现（本轮）

| 项 | 实现 |
| --- | --- |
| 4 播放器样式 | `models_skin.dart PlayerStyle` + `immersive_player._stage()` 分派 |
| sonnet 几何艺术字 | `SonnetLyrics` + `_SonnetGeometryPainter`：实心/描边大字 + 十字/菱形/圆弧/虚线框 + 光晕 |
| 歌词样式面板 | 沉浸页顶部按钮 → 居中/粗体/列数/字体/字号/随封面色 |
| 全屏沉浸 | `immersiveFullscreen` 切换，顶/底控件退场 |
| 皮肤页 | `AppearancePage`：12 主题色板预览卡 + 歌词样式 + 沉浸光感档位/颜色/按压/滑动 |
| 逐字卡拉OK | 保留原 `_KaraokeText`（tinglan stage.go 源码一致） |

## 5. 歌词同步与微动效回归记录

- 歌词同步控件在「歌词样式」面板中，提供每次 **±100ms** 校准与重置；累计偏移限制为 **±5 秒**。正偏移表示歌词提前，负偏移表示歌词延后。
- 黑胶封面播放时使用 18 秒一圈的连续旋转，并叠加轻微呼吸缩放。
- 沉浸光感设置保留按压形变、滑动光效与光感颜色等用户可调项；字号与跟随封面色也可在歌词样式中调整。

## 6. 证据索引
- `player-ui-evidence.json`：611 播放器 + 527 曲库中文文案
- `muyu_window2.png`：展开态（几何艺术字）截图
- `all-sym-addrs.tsv`：sonnet/ui 函数地址
- `decomp_ui_*.json`：Ghidra 函数级伪代码（生成中）
