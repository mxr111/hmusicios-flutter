# 沐语（实机运行）vs Flutter 复刻：实测差距清单

> 时间：2026-11-24。方法：Win32 激活 Muyu.exe 主窗口（PID 16696）+ Pillow 逐页截图，
> 与 Flutter 工程逐项对照。截图在 `rea-muyu/captures/`。
> 说明：MyGo 自绘窗口忽略合成鼠标消息（SendInput/PostMessage 均被忽略），无法自动翻页；
> 但抓到了主页 + 收藏子页的真实渲染，结合符号/文案证据足以对照。

## 1. 实机截图事实

### 1.1 主页（muyu_window.png + captures/muyu_live_home.png）
- 侧栏：头像「土豆」+ SVIP 徽标 / 主页 / 音乐厅 / 唱片架 / 我的 / 自定义入口+ / 本地音乐。
- 顶部：标题「主页」+ 音源胶囊「华为音乐」+ K(蓝)/Q(黄)/红(网易云) 圆标 + 右侧「千语取歌」按钮 + 搜索框。
- 5 张推荐卡：Music FM(现在就听/后来的我们·五月天) / November 23(每日30首/不能说的秘密) /
  心动模式(白心) / 新歌推荐(封面) / 热歌速递(动漫图)——每张有真实封面/排版，非纯色块。
- 「为你推荐 1/5」+ 左右翻页箭头；歌曲行：封面 / 歌名 / 歌手 / 右侧 ♥收藏 + 🔖歌单。
- 底部单胶囊播放条：黑胶封面 + 歌名/歌手 + 蓝色来源图标 + 金色 Hi-Res 徽标 +
  播控(上一首/播放/下一首) + 进度(1:17/4:45) + 音质徽标 + ♥ + 🔖 + 音效 + ⋯ + 音量 + 队列。

### 1.2 收藏页（我的 → 收藏，captures/muyu_live_home.png 等）
- 顶部：返回箭头 + 「搜索当前歌单」搜索框。
- 收藏卡：网易云紫色音符图标「收藏 518首」/ 华为红色音符图标「收藏 737首」——**按平台聚合**。
- 点进某平台收藏后：列头「歌曲 | 会员 | 音质」；歌曲行：封面 / 歌名 / 蓝色来源音符 + 歌手 /
  黄色钻石会员徽标(会员列) / Hi-Res金色描边或SQ粉色描边徽标(音质列) / ♥收藏。

## 2. 差距清单（实测 → Flutter 原状 → 本轮修复）

| 项 | 沐语实测 | Flutter 原状 | 本轮 |
| --- | --- | --- | --- |
| 收藏页结构 | 平台聚合卡（华为/网易云各一张，带歌曲数） | 单一「我喜欢的音乐」列表 | ✅ 改为平台收藏卡 + 点击进入筛选列表 |
| 歌曲行来源标识 | 歌名下方蓝色/红色来源音符 | 无 | ✅ Song.source + 来源图标 |
| 会员徽标 | 会员列黄色钻石 | 无 | ✅ Song.member + 钻石图标 |
| 音质徽标配色 | Hi-Res 金 / SQ 粉 / HQ 灰 | 全金色 | ✅ QualityBadge 按档配色 |
| 音质徽标显示 | 显示该歌实际最高档 | 仅 Hi-Res 时显示 | ✅ 显示 qualities 最高档 |
| 多平台会话 | 同时显示两家收藏 | 单一音源会话 | 已有 MusicSource 切换（本轮前完成） |
| 歌曲行收藏按钮 | ♥ + 🔖 | ✅ 已有 | 保持 |
| 侧栏/主页卡片/播放条 | 见 §1.1 | 基本一致（卡片副标题为接口数据或空态） | 保持 |

## 3. 未能自动化的部分（诚实说明）
- MyGo 自绘窗口对合成输入（mouse_event / SendInput / PostMessage WM_LBUTTON*）无响应，
  只能截图不能自动导航。播放页/歌词页/设置页/皮肤页此前已由
  `muyu_window2.png` + 符号 + 611 文案充分取证并复刻（`MUYU_LYRICS_SKIN_UI.md`）。
- 若需进一步实机核对这些页面，需人工在沐语里点击，或接入真机输入驱动（如驱动级 SendInput）。

## 4. 本轮代码
- `models.dart`：MusicSourceLabel 枚举 + Song.source/member。
- `common.dart`：SongRow 来源图标/会员钻石/最高档音质徽标；QualityBadge 三档配色。
- `huawei_api.dart` / `netease_api.dart`：parseSong 写入 source/member。
- `app_state.dart`：favoriteFilter + openFavorites/closeFavorites。
- `secondary_pages.dart`：MinePage 平台收藏卡 + 筛选列表（列头「歌曲 会员 音质」）。
