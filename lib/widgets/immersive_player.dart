import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/audio_controller.dart';
import '../theme.dart';
import 'common.dart';

/// 沉浸播放页（源码事实 tinglan/cmd/music/stage.go）：
/// - 封面模糊放大做背景
/// - 两栏（左封面 / 右逐字歌词），窄屏上下
/// - 逐字卡拉OK：当前行先画 accent 42% 底，再 clip 叠加已唱部分（accent 全亮），
///   已唱宽度用 smootherstep 在字间连续推进，边缘羽化
/// - 点击歌词行 seek
class ImmersivePlayer extends StatelessWidget {
  const ImmersivePlayer({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final song = state.audio.current;
    final pal = state.palette;
    final size = MediaQuery.of(context).size;
    final wide = size.width >= 900;

    return AnimatedBuilder(
      animation: state.audio,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: pal.base,
          body: Stack(
            children: [
              // 1. 封面模糊背景
              Positioned.fill(child: _Backdrop(url: song?.cover, dark: pal.dark)),
              // 2. 暗色蒙层（保证文字可读）
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: (pal.dark ? Colors.black : Colors.white)
                        .withValues(alpha: pal.dark ? 0.45 : 0.30),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    _topBar(context, song, pal),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(width: size.width * 0.06),
                                SizedBox(
                                  width: math.min(size.width * 0.34, 420),
                                  child: _CoverSide(song: song, pal: pal, spinning: state.audio.playing),
                                ),
                                const SizedBox(width: 48),
                                Expanded(child: _LyricSide(state: state, pal: pal)),
                                SizedBox(width: size.width * 0.05),
                              ],
                            )
                          : _NarrowLyrics(state: state, song: song, pal: pal),
                    ),
                    _BottomControls(state: state, pal: pal),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topBar(BuildContext context, Song? song, MuyuPalette pal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: pal.text, size: 30),
            onPressed: () {
              state.showLyrics = false;
              state.refresh();
            },
          ),
          Expanded(
            child: Column(
              children: [
                Text(song?.name ?? '正在播放',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: pal.text)),
                if (song != null)
                  Text(song.artistText,
                      maxLines: 1,
                      style: TextStyle(fontSize: 11, color: pal.muted)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz, color: pal.text),
            onPressed: () => _showQualityMenu(context, pal),
            tooltip: '音质与音效',
          ),
        ],
      ),
    );
  }

  void _showQualityMenu(BuildContext context, MuyuPalette pal) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('音质', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            ),
            ...AudioQuality.values.map((q) => ListTile(
                  leading: Icon(
                    state.audio.quality == q ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: pal.accent,
                  ),
                  title: Text(q.label, style: TextStyle(color: pal.text)),
                  onTap: () {
                    state.audio.setQuality(q);
                    Navigator.pop(context);
                  },
                )),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('音效', style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              ),
            ),
            ...MuyuAudioController.kEffects.map((e) => ListTile(
                  dense: true,
                  leading: Icon(
                    state.audio.effect == e ? Icons.check_circle : Icons.circle_outlined,
                    color: pal.accent,
                    size: 18,
                  ),
                  title: Text(e, style: TextStyle(color: pal.text, fontSize: 13)),
                  onTap: () => state.audio.setEffect(e),
                )),
            const Divider(),
            ListTile(
              dense: true,
              leading: Icon(Icons.timer, color: pal.accent, size: 18),
              title: Text(
                state.audio.sleepTimer == null
                    ? '定时停止'
                    : '定时：剩余 ${state.audio.sleepRemaining?.inMinutes ?? 0} 分钟',
                style: TextStyle(color: pal.text, fontSize: 13),
              ),
              onTap: () => _showSleepTimer(context, pal),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showSleepTimer(BuildContext context, MuyuPalette pal) {
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('定时停止',
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            ),
            ...<int>[5, 10, 15, 30, 45, 60].map(
              (m) => ListTile(
                dense: true,
                title: Text('$m 分钟后停止',
                    style: TextStyle(color: pal.text, fontSize: 13)),
                onTap: () {
                  state.audio.setSleepTimer(m);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              dense: true,
              title: Text('取消定时',
                  style: TextStyle(color: pal.text, fontSize: 13)),
              onTap: () {
                state.audio.setSleepTimer(0);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 模糊封面背景。
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url, required this.dark});
  final Uri? url;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: dark
              ? const [Color(0xFF1a1a22), Color(0xFF0d0d10)]
              : const [Color(0xFFdfe6ee), Color(0xFFb8c4d0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
    if (url == null) return fallback;
    return Image.network(
      url.toString(),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}

/// 左侧封面（黑胶光盘效果）。
class _CoverSide extends StatelessWidget {
  const _CoverSide({
    required this.song,
    required this.pal,
    required this.spinning,
    this.maxHeight,
  });
  final Song? song;
  final MuyuPalette pal;
  final bool spinning;

  /// 窄屏时由父级限制封面高度，避免 Column 溢出。
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    var side = math.min(MediaQuery.of(context).size.height * 0.5, 420.0);
    if (maxHeight != null) {
      // 文字区约需 90px，封面本体不超过剩余高度。
      side = math.min(side, math.max(60.0, maxHeight! - 92));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: VinylCover(url: song?.cover, size: side, spinning: spinning),
        ),
        const SizedBox(height: 28),
        Text(song?.name ?? '未在播放',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(height: 8),
        Text(song?.artistText ?? '',
            style: TextStyle(fontSize: 13, color: pal.text.withValues(alpha: 0.62))),
        if (song?.album != null && song!.album.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(song!.album,
                style: TextStyle(fontSize: 11, color: pal.text.withValues(alpha: 0.4))),
          ),
      ],
    );
  }
}

/// 右侧歌词列表（逐字卡拉OK）。
class _LyricSide extends StatefulWidget {
  const _LyricSide({required this.state, required this.pal});
  final AppState state;
  final MuyuPalette pal;

  @override
  State<_LyricSide> createState() => _LyricSideState();
}

class _LyricSideState extends State<_LyricSide> {
  final ScrollController _scroll = ScrollController();
  int _lastActive = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.state.lyrics;
    final pos = widget.state.audio.position;
    final active = _activeIndex(lines, pos);
    // 当前行变化时把焦点行滚到中部。
    if (active >= 0 && active != _lastActive && _scroll.hasClients) {
      _lastActive = active;
      _scroll.animateTo(
        (active * 76.0 - 180).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    }

    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词 · 可在设置中开启第三方歌词匹配，或导入本地 .lrc / .ttml',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: widget.pal.text.withValues(alpha: 0.5)),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 120),
      itemCount: lines.length,
      itemBuilder: (context, i) => _LyricRow(
        line: lines[i],
        active: i == active,
        distance: (i - active).abs(),
        pal: widget.pal,
        position: pos,
        onTap: () => widget.state.audio.seek(lines[i].time),
      ),
    );
  }

  static int _activeIndex(List<LyricLine> lines, Duration pos) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].time <= pos) idx = i;
    }
    return idx;
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    required this.line,
    required this.active,
    required this.distance,
    required this.pal,
    required this.position,
    required this.onTap,
  });

  final LyricLine line;
  final bool active;
  final int distance;
  final MuyuPalette pal;
  final Duration position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 字号：基础 20，距焦点越近越大（源码 focus=1-distance/65）。
    final focus = math.max(0.0, 1 - distance / 4.0);
    final fontSize = 19.0 + 5.0 * focus;
    final baseColor = pal.text.withValues(alpha: active ? 1.0 : (0.30 + 0.10 * (1 - focus.clamp(0, 1))));

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: double.infinity,
              child: active && line.hasWords
                  ? _KaraokeText(line: line, pal: pal, position: position, fontSize: fontSize)
                  : Text(
                      line.text,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        color: baseColor,
                        height: 1.25,
                      ),
                    ),
            ),
            ...line.subtitles.map((s) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(s,
                      style: TextStyle(fontSize: 13, color: pal.text.withValues(alpha: 0.48))),
                )),
          ],
        ),
      ),
    );
  }
}

/// 逐字卡拉OK：底层已唱部分透明，未唱部分用 accent 42%，
/// 上层 clip 出已唱宽度用 accent 全亮（源码 stage.go 两次绘制 + 羽化）。
class _KaraokeText extends StatelessWidget {
  const _KaraokeText({
    required this.line,
    required this.pal,
    required this.position,
    required this.fontSize,
  });

  final LyricLine line;
  final MuyuPalette pal;
  final Duration position;
  final double fontSize;

  /// smootherstep（源码 sungWidth 用 smootherstep 保持扫过不 jerk）。
  static double _smoother(double t) {
    t = t.clamp(0.0, 1.0);
    return t * t * t * (t * (t * 6 - 15) + 10);
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    // 计算已唱到的字索引与进度。
    var sungChars = 0;
    var sungFraction = 0.0;
    for (var i = 0; i < line.words.length; i++) {
      final w = line.words[i];
      final next = i + 1 < line.words.length
          ? line.words[i + 1].time
          : line.time + const Duration(seconds: 3);
      if (position >= next) {
        sungChars += w.text.length;
      } else if (position >= w.time) {
        sungChars += w.text.length;
        final span = next.inMilliseconds - w.time.inMilliseconds;
        sungFraction = span > 0
            ? _smoother((position.inMilliseconds - w.time.inMilliseconds) / span)
            : 1.0;
        // 当前字只显示 smootherstep 比例的字符数。
        sungChars -= w.text.length;
        sungChars += (w.text.length * sungFraction).round();
        break;
      } else {
        break;
      }
    }
    final shown = line.text;
    final cut = sungChars.clamp(0, shown.length);
    final sung = shown.substring(0, cut);
    final rest = shown.substring(cut);

    return RichText(
      text: TextSpan(
        style: style.copyWith(color: pal.accent.withValues(alpha: 0.42)),
        children: [
          TextSpan(text: sung, style: style.copyWith(color: pal.accent)),
          TextSpan(text: rest),
        ],
      ),
    );
  }
}

/// 窄屏播放页：封面在上、歌词在下。
class _NarrowLyrics extends StatelessWidget {
  const _NarrowLyrics({required this.state, required this.song, required this.pal});
  final AppState state;
  final Song? song;
  final MuyuPalette pal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 320,
              child: _CoverSide(
                song: song,
                pal: pal,
                spinning: state.audio.playing,
                maxHeight: 180,
              ),
            ),
          ),
        ),
        Expanded(child: _LyricSide(state: state, pal: pal)),
      ],
    );
  }
}

/// 底部播放控制（源码 stage.go paintTransport，锚点在收起/展开两态不变）。
class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.state, required this.pal});
  final AppState state;
  final MuyuPalette pal;

  @override
  Widget build(BuildContext context) {
    final audio = state.audio;
    final total = audio.duration.inSeconds.toDouble();
    final pos = audio.position.inSeconds.toDouble().clamp(0.0, total > 0 ? total : 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              _t(_fmt(pos)),
              Expanded(
                child: Slider(
                  value: pos,
                  max: total > 0 ? total : 1.0,
                  activeColor: pal.accent,
                  inactiveColor: pal.text.withValues(alpha: 0.25),
                  onChanged: (v) => audio.seek(Duration(seconds: v.toInt())),
                ),
              ),
              _t(_fmt(total)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: Icon(audio.playMode.icon, color: pal.accent),
                onPressed: audio.cyclePlayMode,
                tooltip: audio.playMode.label,
              ),
              IconButton(
                icon: Icon(Icons.skip_previous, color: pal.text, size: 30),
                onPressed: audio.previous,
              ),
              CircleAvatar(
                radius: 26,
                backgroundColor: pal.accent,
                child: IconButton(
                  icon: Icon(audio.playing ? Icons.pause : Icons.play_arrow,
                      color: pal.surface, size: 28),
                  onPressed: audio.toggle,
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_next, color: pal.text, size: 30),
                onPressed: audio.next,
              ),
              IconButton(
                icon: Icon(audio.volume == 0 ? Icons.volume_off : Icons.volume_up,
                    color: pal.text),
                onPressed: () => audio.setVolume(audio.volume == 0 ? 1.0 : 0.0),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _t(String s) => Text(s, style: TextStyle(fontSize: 11, color: pal.muted));

  static String _fmt(double seconds) {
    final s = seconds.toInt();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
