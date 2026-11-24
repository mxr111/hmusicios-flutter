import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../models.dart';
import '../models_skin.dart';
import '../services/app_state.dart';
import '../services/audio_controller.dart';
import '../services/lyric_progress.dart';
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

    // 不在这里监听播放器进度：进度高频变化会让整页每秒重建。
    // 歌词与进度条各自用 Ticker / ValueListenableBuilder 局部刷新。
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
                if (!state.immersiveFullscreen) _topBar(context, song, pal),
                Expanded(
                  child: _stage(context, song, pal, size, wide),
                ),
                if (!state.immersiveFullscreen)
                  _BottomControls(state: state, pal: pal),
                // 沉浸模式下仍保留一个轻量的退出入口
                if (state.immersiveFullscreen)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 12),
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen_exit, color: Colors.white70),
                        onPressed: state.toggleImmersiveFullscreen,
                        tooltip: '退出全屏沉浸',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 舞台：按播放器样式分派（REA 4 种样式）。
  Widget _stage(BuildContext context, Song? song, MuyuPalette pal, Size size, bool wide) {
    // 从播放条进入时先展示「封面 + 歌词」的播放页；点歌词按钮才进入
    // 以歌词为主的 sonnet 视图。两种视图都保留封面。
    if (!state.showLyrics) {
      return wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: size.width * 0.06),
                SizedBox(
                  width: math.min(size.width * 0.34, 420),
                  child: _CoverSide(
                      song: song, pal: pal, spinning: state.audio.playing),
                ),
                const SizedBox(width: 48),
                Expanded(child: _LyricSide(state: state, pal: pal)),
                SizedBox(width: size.width * 0.05),
              ],
            )
          : _NarrowLyrics(state: state, song: song, pal: pal);
    }
    switch (state.playerStyle) {
      case PlayerStyle.modern:
        // 新版：沐语标志性 sonnet 几何艺术字歌词铺满屏幕 + 小尺寸黑胶封面。
        return Stack(
          children: [
            SonnetLyrics(state: state, pal: pal),
            if (song != null)
              Positioned(
                left: 18,
                top: 8,
                child: VinylCover(
                  url: song.cover,
                  size: 86,
                  spinning: state.audio.playing,
                ),
              ),
          ],
        );
      case PlayerStyle.cover:
        // 封面沉浸：大图铺底 + 歌词悬浮。
        return Stack(
          children: [
            if (song?.cover != null)
              Positioned.fill(child: _Backdrop(url: song!.cover, dark: true)),
            _LyricSide(state: state, pal: pal),
          ],
        );
      case PlayerStyle.classic:
        // 经典：左封面右歌词（窄屏上下）。
        return wide
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
            : _NarrowLyrics(state: state, song: song, pal: pal);
      case PlayerStyle.minimal:
        // 简洁：只有居中歌词，无封面。
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _LyricSide(state: state, pal: pal),
          ),
        );
    }
  }

  Widget _topBar(BuildContext context, Song? song, MuyuPalette pal) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: pal.text, size: 30),
            onPressed: state.closeFullPlayer,
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
            icon: Icon(
              state.showLyrics ? Icons.album_outlined : Icons.lyrics_outlined,
              color: pal.text,
            ),
            onPressed: () {
              state.showLyrics = !state.showLyrics;
              state.refresh();
            },
            tooltip: state.showLyrics ? '封面播放页' : '歌词页',
          ),
          IconButton(
            icon: Icon(Icons.style_outlined, color: pal.text),
            onPressed: () => _showPlayerStylePanel(context, pal),
            tooltip: '播放器样式',
          ),
          IconButton(
            icon: Icon(state.immersiveFullscreen
                ? Icons.fullscreen_exit
                : Icons.fullscreen, color: pal.text),
            onPressed: () => state.toggleImmersiveFullscreen(),
            tooltip: '全屏沉浸',
          ),
          IconButton(
            icon: Icon(Icons.text_snippet_outlined, color: pal.text),
            onPressed: () => _showLyricStylePanel(context, pal),
            tooltip: '歌词样式',
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

  void _showPlayerStylePanel(BuildContext context, MuyuPalette pal) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('播放器样式',
                  style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
            ),
            ...PlayerStyle.values.map((s) => ListTile(
                  leading: Icon(
                    state.playerStyle == s ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: pal.accent,
                  ),
                  title: Text(s.label, style: TextStyle(color: pal.text)),
                  subtitle: Text(s.desc,
                      style: TextStyle(color: pal.muted, fontSize: 11)),
                  onTap: () {
                    state.setPlayerStyle(s);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showLyricStylePanel(BuildContext context, MuyuPalette pal) {
    final st = state.lyricStyle;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.surface,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('歌词样式',
                    style: TextStyle(fontWeight: FontWeight.w700, color: pal.text)),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.format_align_center, color: pal.accent),
                title: Text('歌词居中', style: TextStyle(color: pal.text)),
                trailing: Switch(
                  value: st.align == LyricAlign.center,
                  onChanged: (v) => state.updateLyricStyle(
                      st.copyWith(align: v ? LyricAlign.center : LyricAlign.left)),
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.format_bold, color: pal.accent),
                title: Text('歌词粗体', style: TextStyle(color: pal.text)),
                trailing: Switch(
                  value: st.bold,
                  onChanged: (v) => state.updateLyricStyle(st.copyWith(bold: v)),
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.view_column, color: pal.accent),
                title: Text('歌词列数', style: TextStyle(color: pal.text)),
                trailing: DropdownButton<int>(
                  value: st.columns,
                  underline: const SizedBox.shrink(),
                  items: <int>[1, 2, 3]
                      .map((c) => DropdownMenuItem<int>(value: c, child: Text('$c 列')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) state.updateLyricStyle(st.copyWith(columns: v));
                  },
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.text_fields, color: pal.accent),
                title: Text('歌词字体', style: TextStyle(color: pal.text)),
                trailing: DropdownButton<String>(
                  value: st.font,
                  underline: const SizedBox.shrink(),
                  items: kBuiltinFonts
                      .map((f) => DropdownMenuItem<String>(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) state.updateLyricStyle(st.copyWith(font: v));
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.font_download, color: pal.accent, size: 18),
                    const SizedBox(width: 12),
                    Text('字号', style: TextStyle(color: pal.text)),
                    Expanded(
                      child: Slider(
                        value: st.fontScale,
                        min: 0.7,
                        max: 1.8,
                        divisions: 11,
                        onChanged: (v) => state.updateLyricStyle(
                            st.copyWith(fontScale: v)),
                      ),
                    ),
                    Text('${(st.fontScale * 100).round()}%',
                        style: TextStyle(color: pal.muted, fontSize: 11)),
                  ],
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.palette_outlined, color: pal.accent),
                title: Text('颜色随封面主色变化', style: TextStyle(color: pal.text)),
                trailing: Switch(
                  value: st.followCoverColor,
                  onChanged: (v) =>
                      state.updateLyricStyle(st.copyWith(followCoverColor: v)),
                ),
              ),
            ],
          ),
        ),
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
/// 高频刷新只发生在当前行的 CustomPainter，列表本身按「当前行」变化才重建。
class _LyricSide extends StatefulWidget {
  const _LyricSide({required this.state, required this.pal});
  final AppState state;
  final MuyuPalette pal;

  @override
  State<_LyricSide> createState() => _LyricSideState();
}

class _LyricSideState extends State<_LyricSide> with TickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<Duration> _displayPosition =
      ValueNotifier<Duration>(Duration.zero);
  Ticker? _ticker;
  int _lastActive = -1;

  @override
  void initState() {
    super.initState();
    _displayPosition.value = widget.state.audio.displayPosition;
    _ticker = createTicker((_) {
      if (!mounted) return;
      final next = widget.state.audio.displayPosition;
      _displayPosition.value = next;
      final active = _activeIndex(widget.state.lyrics, next);
      if (active != _lastActive) {
        _lastActive = active;
        _scrollTo(active);
        // 只重建列表的行状态（字号/焦点），逐帧颜色由当前行 painter 完成。
        setState(() {});
      }
    });
    if (widget.state.audio.playing) _ticker!.start();
  }

  @override
  void didUpdateWidget(covariant _LyricSide oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPlaying = oldWidget.state.audio.playing;
    final playing = widget.state.audio.playing;
    if (wasPlaying != playing) {
      if (playing) {
        _ticker!.start();
      } else {
        _ticker!.stop();
        _displayPosition.value = widget.state.audio.position;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _displayPosition.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.state.lyrics;
    final active = _activeIndex(lines, _displayPosition.value);
    if (active >= 0 && active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo(active));
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
        position: i == active ? _displayPosition : null,
        lineEnd: i + 1 < lines.length ? lines[i + 1].time : null,
        onTap: () => widget.state.audio.seek(lines[i].time),
      ),
    );
  }

  void _scrollTo(int active) {
    if (!mounted || active < 0 || !_scroll.hasClients) return;
    _scroll.animateTo(
      (active * 76.0 - 180).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
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
    required this.lineEnd,
    required this.onTap,
  });

  final LyricLine line;
  final bool active;
  final int distance;
  final MuyuPalette pal;
  final ValueListenable<Duration>? position;
  final Duration? lineEnd;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              child: active && line.hasWords && position != null
                  ? ValueListenableBuilder<Duration>(
                      valueListenable: position!,
                      builder: (context, pos, _) => _KaraokeText(
                        line: line,
                        pal: pal,
                        position: pos,
                        lineEnd: lineEnd,
                        fontSize: fontSize,
                      ),
                    )
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

/// 逐字卡拉OK：连续裁剪已唱宽度，不再按整字 round 跳色。
/// 用 CustomPainter 直接画两遍文字，单帧只重绘当前歌词行。
class _KaraokeText extends StatelessWidget {
  const _KaraokeText({
    required this.line,
    required this.pal,
    required this.position,
    required this.fontSize,
    this.lineEnd,
    this.baseColor,
    this.sungColor,
    this.fontWeight = FontWeight.w600,
  });

  final LyricLine line;
  final MuyuPalette pal;
  final Duration position;
  final Duration? lineEnd;
  final double fontSize;
  final Color? baseColor;
  final Color? sungColor;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final progress = lyricProgress(line, position, lineEnd: lineEnd);
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: 1.25,
    );
    return SizedBox(
      height: fontSize * 1.25,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _KaraokePainter(
            text: line.text,
            style: style,
            progress: progress,
            baseColor: baseColor ?? pal.accent.withValues(alpha: 0.42),
            sungColor: sungColor ?? pal.accent,
          ),
        ),
      ),
    );
  }
}

class _KaraokePainter extends CustomPainter {
  _KaraokePainter({
    required this.text,
    required this.style,
    required this.progress,
    required this.baseColor,
    required this.sungColor,
  });

  final String text;
  final TextStyle style;
  final double progress;
  final Color baseColor;
  final Color sungColor;
  TextPainter? _base;
  TextPainter? _sung;

  @override
  void paint(Canvas canvas, Size size) {
    final base = _base ??= _createPainter(baseColor);
    final sung = _sung ??= _createPainter(sungColor);
    base.layout(maxWidth: size.width);
    sung.layout(maxWidth: size.width);
    base.paint(canvas, Offset.zero);

    final sungWidth = sung.width * progress;
    if (sungWidth <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, sungWidth, size.height));
    sung.paint(canvas, Offset.zero);
    canvas.restore();
  }

  TextPainter _createPainter(Color color) {
    return TextPainter(
      text: TextSpan(text: text, style: style.copyWith(color: color)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    );
  }

  @override
  bool shouldRepaint(covariant _KaraokePainter old) {
    return old.text != text ||
        old.style != style ||
        old.baseColor != baseColor ||
        old.sungColor != sungColor ||
        (old.progress - progress).abs() > 0.0005;
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          ValueListenableBuilder<Duration>(
            valueListenable: audio.positionNotifier,
            builder: (context, value, _) {
              final pos = value.inSeconds
                  .toDouble()
                  .clamp(0.0, total > 0 ? total : 1.0)
                  .toDouble();
              return Row(
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
              );
            },
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

/// 沐语标志性「sonnet 几何艺术字歌词」（REA：native_sonnet_text_geometry.go /
/// native_sonnet_outline.go / native_sonnet_glow.go / sonnetgpu.OriginalStrokes）。
/// 截图事实：超大白色实心字（当前句）+ 白色描边空心字（相邻句）交叠铺满屏幕，
/// 背景深色模糊封面 + 光晕 + 几何线框（十字/菱形/圆弧/虚线对齐框）。
class SonnetLyrics extends StatefulWidget {
  const SonnetLyrics({super.key, required this.state, required this.pal});
  final AppState state;
  final MuyuPalette pal;

  @override
  State<SonnetLyrics> createState() => _SonnetLyricsState();
}

class _SonnetLyricsState extends State<SonnetLyrics>
    with TickerProviderStateMixin {
  final ValueNotifier<Duration> _displayPosition =
      ValueNotifier<Duration>(Duration.zero);
  Ticker? _ticker;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    _displayPosition.value = widget.state.audio.displayPosition;
    _ticker = createTicker((_) {
      if (!mounted) return;
      final next = widget.state.audio.displayPosition;
      _displayPosition.value = next;
      final active = _LyricSideState._activeIndex(widget.state.lyrics, next);
      // 只在换句时重建整层；句内逐帧颜色由 _KaraokeText 的 painter 完成。
      if (active != _active) {
        _active = active;
        setState(() {});
      }
    });
    if (widget.state.audio.playing) _ticker!.start();
  }

  @override
  void didUpdateWidget(covariant SonnetLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasPlaying = oldWidget.state.audio.playing;
    final playing = widget.state.audio.playing;
    if (wasPlaying != playing) {
      if (playing) {
        _ticker!.start();
      } else {
        _ticker!.stop();
        _displayPosition.value = widget.state.audio.position;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _displayPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.state.lyrics;
    final active = _LyricSideState._activeIndex(lines, _displayPosition.value);
    if (active != _active) _active = active;
    final st = widget.state.lyricStyle;
    final glow = st.followCoverColor ? widget.state.glowColor : widget.pal.accent;

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _SonnetGeometryPainter(glow: glow)),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                glow.withValues(alpha: 0.22),
                Colors.transparent,
              ]),
            ),
          ),
        ),
        if (lines.isEmpty || active < 0)
          Center(
            child: Text('暂无歌词',
                style: TextStyle(
                    color: widget.pal.text.withValues(alpha: 0.5), fontSize: 16)),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              final current = lines[active];
              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  alignment: st.align == LyricAlign.center
                      ? Alignment.center
                      : Alignment.centerLeft,
                  children: [
                    if (active - 1 >= 0)
                      Positioned(
                        top: h * 0.20,
                        left: st.align == LyricAlign.center ? w * 0.22 : w * 0.10,
                        child: _outlined(
                          lines[active - 1].text,
                          (h * 0.11 * st.fontScale).clamp(48.0, 150.0),
                          Colors.white,
                        ),
                      ),
                    Positioned(
                      top: h * 0.36,
                      left: st.align == LyricAlign.center ? w * 0.10 : w * 0.06,
                      right: st.align == LyricAlign.center ? w * 0.10 : 0,
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: _displayPosition,
                        builder: (context, pos, _) => _KaraokeText(
                          line: current,
                          pal: widget.pal,
                          position: pos,
                          lineEnd: active + 1 < lines.length
                              ? lines[active + 1].time
                              : null,
                          fontSize:
                              (h * 0.15 * st.fontScale).clamp(64.0, 200.0),
                          fontWeight:
                              st.bold ? FontWeight.w900 : FontWeight.w600,
                          baseColor: Colors.white.withValues(alpha: 0.45),
                          sungColor: Colors.white,
                        ),
                      ),
                    ),
                    if (active + 1 < lines.length)
                      Positioned(
                        top: h * 0.60,
                        left: st.align == LyricAlign.center ? w * 0.26 : w * 0.18,
                        child: _outlined(
                          lines[active + 1].text,
                          (h * 0.10 * st.fontScale).clamp(44.0, 130.0),
                          Colors.white,
                        ),
                      ),
                    if (current.subtitles.isNotEmpty)
                      Positioned(
                        top: h * 0.53,
                        left: st.align == LyricAlign.center ? w * 0.12 : w * 0.08,
                        child: Text(
                          current.subtitles.join(' · '),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _outlined(String text, double size, Color color) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: Colors.transparent,
        height: 1.1,
        shadows: [
          Shadow(color: color.withValues(alpha: 0.85), blurRadius: 1),
        ],
      ),
    );
  }
}

/// 几何线框：十字 / 菱形 / 圆弧 / 虚线对齐框（对应 native_sonnet_geometry.go）。
class _SonnetGeometryPainter extends CustomPainter {
  const _SonnetGeometryPainter({required this.glow});
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final dim = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 十字线（左上 + 中上）
    _cross(canvas, line, size.width * 0.28, size.height * 0.14, 34);
    _cross(canvas, line, size.width * 0.52, size.height * 0.09, 26);
    // 菱形（右上）
    final d = size.width * 0.07;
    final cx = size.width * 0.74;
    final cy = size.height * 0.30;
    canvas.drawPath(
      Path()
        ..moveTo(cx, cy - d)
        ..lineTo(cx + d, cy)
        ..lineTo(cx, cy + d)
        ..lineTo(cx - d, cy)
        ..close(),
      line,
    );
    // 圆弧（左下）
    canvas.drawArc(
      Rect.fromCenter(
          center: Offset(size.width * 0.14, size.height * 0.66),
          width: 180,
          height: 180),
      0,
      math.pi * 1.4,
      false,
      dim,
    );
    // 虚线对齐框（中部）
    final dash = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    _dashedRect(canvas, dash, Rect.fromLTWH(
      size.width * 0.18, size.height * 0.42, size.width * 0.5, size.height * 0.3));
  }

  void _cross(Canvas c, Paint p, double x, double y, double r) {
    c.drawLine(Offset(x - r, y), Offset(x + r, y), p);
    c.drawLine(Offset(x, y - r), Offset(x, y + r), p);
  }

  void _dashedRect(Canvas c, Paint p, Rect r) {
    const dash = 6.0;
    for (var x = r.left; x < r.right; x += dash * 2) {
      c.drawLine(Offset(x, r.top), Offset(math.min(x + dash, r.right), r.top), p);
      c.drawLine(Offset(x, r.bottom), Offset(math.min(x + dash, r.right), r.bottom), p);
    }
    for (var y = r.top; y < r.bottom; y += dash * 2) {
      c.drawLine(Offset(r.left, y), Offset(r.left, math.min(y + dash, r.bottom)), p);
      c.drawLine(Offset(r.right, y), Offset(r.right, math.min(y + dash, r.bottom)), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SonnetGeometryPainter old) => old.glow != glow;
}
