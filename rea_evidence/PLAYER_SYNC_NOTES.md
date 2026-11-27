# 歌词时间线与播放器同步契约

## 职责边界

- A（AppState / 持久化）：负责 `setLyricOffset`、`resetLyricOffset` 的会话持久化，
  在切歌和播放设置变化时刷新 `state.lyrics`，并递增 `AppState.lyricsRevision`。
- B（播放器）：负责单调播放时钟、±5 秒夹紧、±100ms 校准、歌词列表重建 key、
  音量滑块与全屏播放器经典布局。
- 全屏播放器不再持久化或切换播放器皮肤；`PlayerStyle` 仅保留 `classic`，
  `AppState.setPlayerStyle` 保持兼容但最终统一为 classic。

## 稳定调用契约

- `MuyuAudioController.lyricRevision` / `settingsRevision`：版本型 `ValueNotifier<int>`。
- `MuyuAudioController.invalidateLyrics()`：切歌或歌词内容变化时递增 lyricRevision。
- `MuyuAudioController.setLyricOffset(Duration)`：先按 `PlaybackClock.clampOffset`
  限制到 ±5 秒，再 notify、递增 lyricRevision/settingsRevision。
- `AppState.setLyricOffset` / `resetLyricOffset`：UI 唯一入口，负责持久化并刷新歌词。
- `AppState.lyricsRevision`：歌词面板与 `LyricFocusList` 的 key 都监听它；
  偏移、切歌、音效/音质/音量等设置变化后都必须产生新的 key。

## 时间线原则

1. 播放器原始位置由 `PlaybackClock` 用单调 Stopwatch 外推；暂停冻结、seek 重锚、
   快速切歌由 generation 丢弃迟到回调。
2. 歌词位置始终是 `audio.lyricPosition`，即单调位置叠加 `lyricOffset`，
   不允许 UI 自己修改播放器 position。
3. `LyricFocusList` 保留 `getOffsetToReveal(..., 0.5)` 当前行居中、`_scrollEpoch`
   竞态保护、当前行局部 `RepaintBoundary` / 卡拉 OK `CustomPaint`。
4. 同步滑块只修改 offset；不重启播放器、不改播放进度、不触发网络取流。
