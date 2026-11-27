import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderAbstractViewport, RenderBox, ScrollCacheExtent;
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
/// - 宽屏左封面 / 右逐字歌词；竖屏用 PageView 在封面页与歌词页间切换
/// - 逐字卡拉OK：当前行先画 accent 42% 底，再 clip 叠加已唱部分（accent 全亮），
///   已唱宽度在字间连续推进，边缘羽化
/// - 点击歌词行 seek
class ImmersivePlayer extends StatefulWidget {
  const ImmersivePlayer({super.key, required this.state});

  final AppState state;

  @override
  State<ImmersivePlayer> createState() => _ImmersivePlayerState();
}

class _ImmersivePlayerState extends State<ImmersivePlayer> {
  late final PageController _pageController = PageController(initialPage: 0);
  final ValueNotifier<int> _stagePage = ValueNotifier<int>(0);

  AppState get state => widget.state;

  @override
  void dispose() {
    _pageController.dispose();
    _stagePage.dispose();
    super.dispose();
  }

  void _showLyricsPage() {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onPageChanged(int page) {
    if (_stagePage.value != page) _stagePage.value = page;
  }

  @override
  Widget build(BuildContext context) {
    final song = state.audio.current;
    final pal = state.palette;
    final size = MediaQuery.of(context).size;
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait ||
        size.width < size.height;
    final topInset = MediaQuery.paddingOf(context).top;

    return ValueListenableBuilder<int>(
      valueListenable: _stagePage,
      builder: (context, page, _) {
        final onLyricsPage = portrait && page == 1;
        final darkStage = pal.dark || onLyricsPage;
        final stagePal = darkStage && !pal.dark ? _darkStagePalette(pal) : pal;

        // 不在这里监听播放器进度：进度高频变化会让整页每秒重建。
        // 歌词与进度条各自用 Ticker / ValueListenableBuilder 局部刷新。
        return Scaffold(
          backgroundColor: stagePal.base,
          body: Stack(
            children: [
              // 1. 封面模糊背景
              Positioned.fill(
                child: _Backdrop(url: song?.cover, dark: darkStage),
              ),
              // 2. 蒙层：歌词页更暗，保证文字可读。
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: darkStage
                        ? Colors.black.withValues(
                            alpha: onLyricsPage ? 0.72 : 0.48,
                          )
                        : Colors.white.withValues(alpha: 0.30),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    if (!state.immersiveFullscreen)
                      _topBar(
                        context,
                        song,
                        stagePal,
                        portrait: portrait,
                        page: page,
                      ),
                    Expanded(
                      child: _stage(
                        context,
                        song,
                        stagePal,
                        size,
                        portrait: portrait,
                      ),
                    ),
                    if (!state.immersiveFullscreen)
                      _BottomControls(state: state, pal: stagePal),
                  ],
                ),
              ),
              // 沉浸模式只留播放器效果；顶部半透明安全区 + 两个轻量退出入口，
              // 位置显式叠加 status bar 高度，绝不覆盖系统时间/日期。
              if (state.immersiveFullscreen)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: topInset + 64,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.black.withValues(alpha: 0.38),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (state.immersiveFullscreen)
                Positioned(
                  top: topInset + 8,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _immersiveButton(
                        icon: Icons.keyboard_arrow_down,
                        tooltip: '退出全屏播放',
                        onPressed: _closePlayer,
                      ),
                      const SizedBox(width: 6),
                      _immersiveButton(
                        icon: Icons.fullscreen_exit,
                        tooltip: '退出全屏沉浸',
                        onPressed: state.toggleImmersiveFullscreen,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _immersiveButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.38),
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// 退出播放器时同时退出沉浸，避免下次从播放条进入仍停在无控件全屏。
  void _closePlayer() {
    if (state.immersiveFullscreen) state.toggleImmersiveFullscreen();
    state.closeFullPlayer();
  }

  /// 经典播放器舞台：竖屏双页，宽屏左封面右歌词。
  Widget _stage(
    BuildContext context,
    Song? song,
    MuyuPalette pal,
    Size size, {
    required bool portrait,
  }) {
    final classic = portrait
        ? PageView(
            key: const ValueKey<String>('immersive-portrait-pages'),
            controller: _pageController,
            onPageChanged: _onPageChanged,
            children: [
              KeyedSubtree(
                key: const ValueKey<String>('immersive-cover-page'),
                child: _PortraitCoverPage(
                  state: state,
                  song: song,
                  pal: pal,
                  onTap: _showLyricsPage,
                ),
              ),
              KeyedSubtree(
                key: const ValueKey<String>('immersive-lyrics-page'),
                child: _LyricSide(state: state, pal: pal),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(width: size.width * 0.06),
              SizedBox(
                width: math.min(size.width * 0.34, 420),
                child: _CoverSide(
                  state: state,
                  song: song,
                  pal: pal,
                  spinning: state.audio.playing,
                ),
              ),
              const SizedBox(width: 48),
              Expanded(
                child: _LyricSide(state: state, pal: pal),
              ),
              SizedBox(width: size.width * 0.05),
            ],
          );
    return KeyedSubtree(
      key: const ValueKey<String>('immersive-stage-classic'),
      child: classic,
    );
  }

  Widget _topBar(
    BuildContext context,
    Song? song,
    MuyuPalette pal, {
    required bool portrait,
    required int page,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: pal.text, size: 30),
            onPressed: _closePlayer,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  song?.name ?? '正在播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: pal.text,
                  ),
                ),
                if (song != null)
                  Text(
                    song.artistText,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                if (portrait)
                  Text(
                    page == 0 ? '封面 · 轻点封面或右滑查看歌词' : '歌词 · 左滑返回封面',
                    key: ValueKey<String>('immersive-page-hint-$page'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: pal.muted.withValues(alpha: 0.9),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              state.immersiveFullscreen
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              color: pal.text,
            ),
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
                child: Text(
                  '歌词样式',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: pal.text,
                  ),
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.format_align_center, color: pal.accent),
                title: Text('歌词居中', style: TextStyle(color: pal.text)),
                trailing: Switch(
                  value: st.align == LyricAlign.center,
                  onChanged: (v) => state.updateLyricStyle(
                    st.copyWith(align: v ? LyricAlign.center : LyricAlign.left),
                  ),
                ),
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.format_bold, color: pal.accent),
                title: Text('歌词粗体', style: TextStyle(color: pal.text)),
                trailing: Switch(
                  value: st.bold,
                  onChanged: (v) =>
                      state.updateLyricStyle(st.copyWith(bold: v)),
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
                      .map(
                        (c) => DropdownMenuItem<int>(
                          value: c,
                          child: Text('$c 列'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      state.updateLyricStyle(st.copyWith(columns: v));
                    }
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
                      .map(
                        (f) =>
                            DropdownMenuItem<String>(value: f, child: Text(f)),
                      )
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
                        onChanged: (v) =>
                            state.updateLyricStyle(st.copyWith(fontScale: v)),
                      ),
                    ),
                    Text(
                      '${(st.fontScale * 100).round()}%',
                      style: TextStyle(color: pal.muted, fontSize: 11),
                    ),
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
              ValueListenableBuilder<int>(
                valueListenable: state.lyricsRevision,
                builder: (context, _, _) => StatefulBuilder(
                  builder: (context, setSheetState) {
                    final offsetMs = state.audio.lyricOffset.inMilliseconds
                        .clamp(-5000, 5000);
                    final seconds = (offsetMs / 1000).toStringAsFixed(2);
                    final signedSeconds = offsetMs > 0 ? '+$seconds' : seconds;
                    final label = offsetMs == 0
                        ? '无偏移 · 拖动滑块或点 +/- 校准 100ms'
                        : '当前偏移 ${offsetMs > 0 ? '+' : ''}$offsetMs ms'
                              '（$signedSeconds 秒）';
                    return Column(
                      children: [
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.sync, color: pal.accent),
                          title: Text(
                            '歌词同步',
                            style: TextStyle(color: pal.text),
                          ),
                          subtitle: Text(
                            label,
                            style: TextStyle(color: pal.muted, fontSize: 11),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Slider(
                            key: const ValueKey<String>('lyric-offset-slider'),
                            value: offsetMs.toDouble(),
                            min: -5000,
                            max: 5000,
                            divisions: 100,
                            label: offsetMs == 0
                                ? '0 ms'
                                : '${offsetMs > 0 ? '+' : ''}$offsetMs ms',
                            onChanged: (value) {
                              state.setLyricOffset(
                                Duration(milliseconds: value.round()),
                              );
                              setSheetState(() {});
                            },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              tooltip: '歌词延后 100ms',
                              onPressed: () {
                                state.setLyricOffset(
                                  state.audio.lyricOffset -
                                      const Duration(milliseconds: 100),
                                );
                                setSheetState(() {});
                              },
                            ),
                            TextButton(
                              onPressed: () {
                                state.resetLyricOffset();
                                setSheetState(() {});
                              },
                              child: const Text('重置'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              tooltip: '歌词提前 100ms',
                              onPressed: () {
                                state.setLyricOffset(
                                  state.audio.lyricOffset +
                                      const Duration(milliseconds: 100),
                                );
                                setSheetState(() {});
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ],
                    );
                  },
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
              child: Text(
                '音质',
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
              ),
            ),
            ...AudioQuality.values.map(
              (q) => ListTile(
                leading: Icon(
                  state.audio.quality == q
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: pal.accent,
                ),
                title: Text(q.label, style: TextStyle(color: pal.text)),
                onTap: () {
                  state.setQuality(q);
                  Navigator.pop(context);
                },
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '音效',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: pal.text,
                  ),
                ),
              ),
            ),
            ...MuyuAudioController.kEffects.map(
              (e) => ListTile(
                dense: true,
                leading: Icon(
                  state.audio.effect == e
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: pal.accent,
                  size: 18,
                ),
                title: Text(e, style: TextStyle(color: pal.text, fontSize: 13)),
                onTap: () => state.setEffect(e),
              ),
            ),
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
              child: Text(
                '定时停止',
                style: TextStyle(fontWeight: FontWeight.w700, color: pal.text),
              ),
            ),
            ...<int>[5, 10, 15, 30, 45, 60].map(
              (m) => ListTile(
                dense: true,
                title: Text(
                  '$m 分钟后停止',
                  style: TextStyle(color: pal.text, fontSize: 13),
                ),
                onTap: () {
                  state.audio.setSleepTimer(m);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              dense: true,
              title: Text(
                '取消定时',
                style: TextStyle(color: pal.text, fontSize: 13),
              ),
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

/// 浅色主题进入暗色歌词页时只替换前景/表面色，强调色仍跟随用户主题。
MuyuPalette _darkStagePalette(MuyuPalette pal) => MuyuPalette(
  name: pal.name,
  label: pal.label,
  base: const Color(0xFF0D0D10),
  surface: const Color(0xFF141418),
  text: Colors.white,
  secondary: Colors.white70,
  muted: Colors.white60,
  accent: pal.accent,
  dark: true,
);

/// 竖屏封面页：唯一进入歌词页的显式入口是点击封面本身。
class _PortraitCoverPage extends StatelessWidget {
  const _PortraitCoverPage({
    required this.state,
    required this.song,
    required this.pal,
    required this.onTap,
  });

  final AppState state;
  final Song? song;
  final MuyuPalette pal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth * 0.82, 420.0);
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: width,
              child: _CoverSide(
                state: state,
                song: song,
                pal: pal,
                spinning: state.audio.playing,
                maxHeight: constraints.maxHeight,
                onTap: onTap,
              ),
            ),
          ),
        );
      },
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
    return Transform.scale(
      scale: 1.12,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Image.network(
          url.toString(),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}

/// 左侧封面（黑胶光盘效果 + 按压形变 + 滑动光效）。
class _CoverSide extends StatefulWidget {
  const _CoverSide({
    required this.state,
    required this.song,
    required this.pal,
    required this.spinning,
    this.maxHeight,
    this.onTap,
  });
  final AppState state;
  final Song? song;
  final MuyuPalette pal;
  final bool spinning;

  /// 窄屏时由父级限制封面高度，避免 Column 溢出。
  final double? maxHeight;

  /// 竖屏点封面进入歌词页；宽屏不传。
  final VoidCallback? onTap;

  @override
  State<_CoverSide> createState() => _CoverSideState();
}

class _CoverSideState extends State<_CoverSide> with TickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 170),
    lowerBound: 0,
    upperBound: 1,
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  bool get _shouldAnimateSheen => widget.state.glassSlide && widget.spinning;

  @override
  void initState() {
    super.initState();
    if (_shouldAnimateSheen) _sheen.repeat();
  }

  @override
  void didUpdateWidget(covariant _CoverSide oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasAnimating = oldWidget.state.glassSlide && oldWidget.spinning;
    if (wasAnimating != _shouldAnimateSheen) _syncSheen();
  }

  void _syncSheen() {
    if (_shouldAnimateSheen) {
      _sheen.repeat();
    } else {
      _sheen.stop();
      _sheen.value = 0;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var side = math.min(MediaQuery.of(context).size.height * 0.5, 420.0);
        if (constraints.maxWidth.isFinite) {
          side = math.min(side, constraints.maxWidth);
        }
        if (constraints.maxHeight.isFinite) {
          // 封面下方还有歌名/歌手/专辑，约需 92px；不管横竖屏都必须
          // 把封面本体压进剩余高度，否则 1200x900 的经典布局也会溢出。
          side = math.min(side, math.max(60.0, constraints.maxHeight - 92));
        }
        if (widget.maxHeight != null) {
          // 文字区约需 90px，封面本体不超过剩余高度。
          side = math.min(side, math.max(60.0, widget.maxHeight! - 92));
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: side,
              height: side,
              child: AspectRatio(
                aspectRatio: 1,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTap,
                  onTapDown: widget.state.glassPress
                      ? (_) => _press.forward()
                      : null,
                  onTapUp: widget.state.glassPress
                      ? (_) => _press.reverse()
                      : null,
                  onTapCancel: widget.state.glassPress
                      ? () => _press.reverse()
                      : null,
                  child: AnimatedBuilder(
                    animation: _press,
                    builder: (context, child) {
                      final t = Curves.easeOutCubic.transform(_press.value);
                      return Transform.scale(
                        scale: 1.0 - 0.018 * t,
                        child: child,
                      );
                    },
                    child: ClipOval(
                      child: CustomPaint(
                        foregroundPainter: _SheenPainter(
                          animation: _sheen,
                          color: widget.state.glowColor,
                          enabled: _shouldAnimateSheen,
                        ),
                        child: VinylCover(
                          url: widget.song?.cover,
                          size: side,
                          spinning: widget.spinning,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              widget.song?.name ?? '未在播放',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: widget.pal.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.song?.artistText ?? '',
              style: TextStyle(
                fontSize: 13,
                color: widget.pal.text.withValues(alpha: 0.62),
              ),
            ),
            if (widget.song?.album != null && widget.song!.album.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.song!.album,
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.pal.text.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SheenPainter extends CustomPainter {
  const _SheenPainter({
    required this.animation,
    required this.color,
    required this.enabled,
  }) : super(repaint: enabled ? animation : null);
  final Animation<double> animation;
  final Color color;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;
    canvas.save();
    final bounds = Offset.zero & size;
    canvas.clipPath(Path()..addOval(bounds));
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.55);
    final span = size.width * 2.6;
    final x = -span / 2 + animation.value * span;
    final band = Rect.fromLTWH(
      x - size.width * 0.22,
      -size.height,
      size.width * 0.44,
      size.height * 2,
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(band);
    canvas.drawRect(band, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SheenPainter old) =>
      old.animation != animation ||
      old.color != color ||
      old.enabled != enabled;
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
  final ValueNotifier<Duration> _displayPosition = ValueNotifier<Duration>(
    Duration.zero,
  );
  Ticker? _ticker;
  String? _songId;

  bool get _shouldTick =>
      widget.state.audio.playing && widget.state.lyrics.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final audio = widget.state.audio;
    _songId = audio.current?.id;
    _displayPosition.value = audio.lyricPosition;
    _ticker = createTicker((_) {
      if (!mounted) return;
      // 只把位置推给 LyricFocusList；换行判断和滚动都在列表内部完成，
      // 这里不 setState，避免整页跟着播放进度重建。
      _displayPosition.value = widget.state.audio.lyricPosition;
    });
    audio.addListener(_onAudioChanged);
    if (_shouldTick) _ticker!.start();
  }

  void _onAudioChanged() {
    final audio = widget.state.audio;
    final songId = audio.current?.id;
    if (songId != _songId) {
      _songId = songId;
      _displayPosition.value = audio.lyricPosition;
      // 切歌时换 key 重建 LyricFocusList，清空旧歌的滚动动画与延迟回调。
      if (mounted) setState(() {});
    } else {
      _displayPosition.value = audio.lyricPosition;
    }
    _syncTicker();
  }

  void _syncTicker() {
    if (_shouldTick) {
      if (_ticker?.isActive == false) _ticker!.start();
    } else if (_ticker?.isActive == true) {
      _ticker!.stop();
      _displayPosition.value = widget.state.audio.lyricPosition;
    }
  }

  @override
  void didUpdateWidget(covariant _LyricSide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.audio != widget.state.audio) {
      oldWidget.state.audio.removeListener(_onAudioChanged);
      widget.state.audio.addListener(_onAudioChanged);
    }
    _onAudioChanged();
    _syncTicker();
  }

  @override
  void dispose() {
    widget.state.audio.removeListener(_onAudioChanged);
    _ticker?.dispose();
    _displayPosition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.state.lyrics;
    return ValueListenableBuilder<int>(
      valueListenable: widget.state.lyricsRevision,
      builder: (context, revision, _) {
        final songId = widget.state.audio.current?.id ?? _songId;
        return LyricFocusList(
          key: ValueKey<String>('lyrics:${songId ?? ''}:$revision'),
          songId: songId,
          lines: lines,
          position: _displayPosition,
          pal: widget.pal,
          onLineTap: (i) {
            if (i >= 0 && i < lines.length) {
              widget.state.audio.seek(lines[i].time);
            }
          },
        );
      },
    );
  }

  static int _activeIndex(List<LyricLine> lines, Duration pos) =>
      _lyricIndexAt(lines, pos);
}

/// 计算给定播放位置对应的歌词行下标（-1 表示尚未到第一句）。
int _lyricIndexAt(List<LyricLine> lines, Duration position) {
  var idx = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].time <= position) idx = i;
  }
  return idx;
}

/// 歌词聚焦列表：当前行始终稳定落在可视区域中线附近。
///
/// 滚动只在以下情况触发：active 行改变、切歌/换歌词、seek 等位置跳变。
/// 逐帧播放位置只用于判断是否换行，不会每帧调用 [ScrollController.animateTo]。
/// 所有滚动都走同一个 controller，新的 [ScrollController.animateTo] 会覆盖旧的
/// 滚动活动，因此快速换行/切歌不会叠加多个动画。
///
/// 目标行尚未被 `ListView.builder` 构建时（例如拖动进度条远距离 seek），
/// 先用已构建行的真实坐标估算并 `jumpTo`，下一帧再精确居中。
class LyricFocusList extends StatefulWidget {
  const LyricFocusList({
    super.key,
    required this.lines,
    required this.position,
    required this.pal,
    required this.onLineTap,
    this.songId,
    this.controller,
  });

  final List<LyricLine> lines;

  /// 已叠加用户校准偏移的歌词位置（[MuyuAudioController.lyricPosition]）。
  final ValueListenable<Duration> position;
  final MuyuPalette pal;
  final ValueChanged<int> onLineTap;

  /// 切歌时变化；变化后清空旧行 key、滚动目标并重新居中。
  final String? songId;

  /// 测试或外部统一管理滚动时注入；不传则由列表自己创建并释放。
  final ScrollController? controller;

  @override
  State<LyricFocusList> createState() => _LyricFocusListState();
}

class _LyricFocusListState extends State<LyricFocusList> {
  static const EdgeInsets _listPadding = EdgeInsets.symmetric(vertical: 120);
  static const Duration _scrollDuration = Duration(milliseconds: 320);

  final ScrollController _fallbackScroll = ScrollController();
  final Map<int, GlobalKey> _rowKeys = <int, GlobalKey>{};

  int _active = -1;
  int _scrollEpoch = 0;
  int _correctionAttempts = 0;
  int? _scheduledEpoch;
  bool _pendingForce = false;
  double _estimatedRowHeight = 64;

  ScrollController get _scroll => widget.controller ?? _fallbackScroll;

  @override
  void initState() {
    super.initState();
    _active = _lyricIndexAt(widget.lines, widget.position.value);
    widget.position.addListener(_onPositionChanged);
    _scheduleCenter(force: true);
  }

  @override
  void didUpdateWidget(covariant LyricFocusList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.position != widget.position) {
      oldWidget.position.removeListener(_onPositionChanged);
      widget.position.addListener(_onPositionChanged);
    }

    final songChanged = oldWidget.songId != widget.songId;
    final linesChanged = !identical(oldWidget.lines, widget.lines);
    if (songChanged || linesChanged) {
      _rowKeys.clear();
      _scrollEpoch++; // 让上一首歌/上一份歌词的延迟回调失效。
      _correctionAttempts = 0;
      _active = _lyricIndexAt(widget.lines, widget.position.value);
      _scheduleCenter(force: true);
      return;
    }

    final active = _lyricIndexAt(widget.lines, widget.position.value);
    if (active != _active) {
      _active = active;
      _correctionAttempts = 0;
      _scheduleCenter();
    }
  }

  @override
  void dispose() {
    widget.position.removeListener(_onPositionChanged);
    _fallbackScroll.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final active = _lyricIndexAt(widget.lines, widget.position.value);
    // 同一句内的高频位置更新不滚动，只刷新当前行的卡拉OK painter。
    if (active == _active) return;
    _correctionAttempts = 0;
    setState(() => _active = active);
    _scheduleCenter();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (lines.isEmpty) {
      return Center(
        child: Text(
          '暂无歌词 · 可在设置中开启第三方歌词匹配，或导入本地 .lrc / .ttml',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: widget.pal.text.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final active = _active;
    return ListView.builder(
      controller: _scroll,
      padding: _listPadding,
      // 远距离 seek 时让目标行有更大机会进入构建范围，随后精确居中。
      scrollCacheExtent: const ScrollCacheExtent.pixels(1600),
      itemCount: lines.length,
      itemBuilder: (context, i) => _LyricRow(
        key: _rowKeys.putIfAbsent(i, GlobalKey.new),
        line: lines[i],
        active: i == active,
        distance: active < 0 ? 999 : (i - active).abs(),
        pal: widget.pal,
        position: i == active ? widget.position : null,
        lineEnd: i + 1 < lines.length ? lines[i + 1].time : null,
        onTap: () => widget.onLineTap(i),
      ),
    );
  }

  /// 合并同一帧内的多次滚动请求；force 表示即使目标 offset 未变也要重新居中。
  void _scheduleCenter({bool force = false}) {
    if (!mounted) return;
    _pendingForce = _pendingForce || force;
    if (_scheduledEpoch == _scrollEpoch) return;
    _scheduledEpoch = _scrollEpoch;
    final epoch = _scrollEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _scrollEpoch) return;
      _scheduledEpoch = null;
      final pendingForce = _pendingForce;
      _pendingForce = false;
      _centerActive(force: pendingForce);
    });
  }

  void _centerActive({required bool force}) {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || _active < 0) return;
    if (_active >= widget.lines.length) return;

    var target = _revealOffsetFor(_active);
    if (target == null) {
      // 目标行尚未构建：用当前已构建行的真实坐标估算，跳过去后再精确居中。
      final estimate = _estimateOffsetFor(_active);
      if (estimate.isFinite) {
        _scroll.jumpTo(estimate < 0 ? 0 : estimate);
      }
      if (_correctionAttempts < 2) {
        _correctionAttempts++;
        _scheduleCenter(force: true);
      }
      return;
    }

    _correctionAttempts = 0;
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    final delta = (clamped - position.pixels).abs();
    if (!force && delta < 1.0) return;
    // 同一个 ScrollController 上再次 animateTo 会取消上一次滚动活动，
    // 因此连续换行/切歌只会保留最后一次动画，不会叠加。
    _scroll.animateTo(
      clamped,
      duration: _scrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  /// 用目标行自身的 RenderBox 求精确滚动位置（alignment 0.5 = 视口居中）。
  double? _revealOffsetFor(int index) {
    final render = _rowKeys[index]?.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport == null) return null;
    final height = render.size.height;
    if (height > 0) {
      _estimatedRowHeight = _estimatedRowHeight * 0.8 + height * 0.2;
    }
    return viewport.getOffsetToReveal(render, 0.5).offset;
  }

  /// 目标行未构建时的估算：锚定到任意已构建行的真实内容坐标，再按平均行高外推。
  double _estimateOffsetFor(int index) {
    final position = _scroll.position;
    final viewport = position.viewportDimension;
    var heightSum = 0.0;
    var heightCount = 0;
    int? anchorIndex;
    double? anchorTop;

    for (final entry in _rowKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached || !render.hasSize) continue;
      final viewportObject = RenderAbstractViewport.maybeOf(render);
      if (viewportObject == null) continue;
      if (entry.key != index) {
        heightSum += render.size.height;
        heightCount++;
      }
      if (anchorIndex == null ||
          (entry.key - index).abs() < (anchorIndex - index).abs()) {
        anchorIndex = entry.key;
        anchorTop = viewportObject.getOffsetToReveal(render, 0.0).offset;
      }
    }

    final average = heightCount > 0
        ? heightSum / heightCount
        : _estimatedRowHeight;
    if (average > 0) _estimatedRowHeight = average;
    if (anchorIndex != null && anchorTop != null) {
      return anchorTop +
          (index - anchorIndex) * average +
          average / 2 -
          viewport / 2;
    }
    return _listPadding.top + index * average + average / 2 - viewport / 2;
  }
}

class _LyricRow extends StatelessWidget {
  const _LyricRow({
    super.key,
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
    final focus = math.max(0.0, 1 - distance / 4.0).clamp(0.0, 1.0);
    final fontSize = 19.0 + 5.0 * focus;
    final baseColor = pal.text.withValues(
      alpha: active ? 1.0 : (0.30 + 0.10 * (1 - focus)),
    );
    final targetOpacity = active ? 1.0 : (0.62 + 0.28 * focus);

    return AnimatedSlide(
      offset: Offset(0, active ? -0.006 : 0),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutQuart,
      child: AnimatedScale(
        scale: active ? 1.014 : 1.0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutQuart,
        child: AnimatedOpacity(
          opacity: targetOpacity,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutQuart,
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: active ? 12 : 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: active
                    ? LinearGradient(
                        colors: [
                          pal.accent.withValues(alpha: 0.10),
                          Colors.transparent,
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
              ),
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
                  ...line.subtitles.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        s,
                        style: TextStyle(
                          fontSize: 13,
                          color: pal.text.withValues(alpha: 0.48),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
      text: TextSpan(
        text: text,
        style: style.copyWith(color: color),
      ),
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
                      onChanged: (v) =>
                          audio.seek(Duration(seconds: v.toInt())),
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
                  icon: Icon(
                    audio.playing ? Icons.pause : Icons.play_arrow,
                    color: pal.surface,
                    size: 28,
                  ),
                  onPressed: audio.toggle,
                ),
              ),
              IconButton(
                icon: Icon(Icons.skip_next, color: pal.text, size: 30),
                onPressed: audio.next,
              ),
              IconButton(
                icon: Icon(
                  audio.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  color: pal.text,
                ),
                tooltip: '音量',
                onPressed: () => _showVolumeSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showVolumeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: pal.surface,
      builder: (sheetContext) => SafeArea(
        child: AnimatedBuilder(
          animation: state.audio,
          builder: (context, _) {
            final volume = state.audio.volume.clamp(0.0, 1.0);
            final muted = volume == 0;
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '音量',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        tooltip: muted ? '取消静音' : '静音',
                        icon: Icon(
                          muted ? Icons.volume_off : Icons.volume_up,
                          color: pal.text,
                        ),
                        onPressed: () => state.setVolume(muted ? 1.0 : 0.0),
                      ),
                      Expanded(
                        child: Slider(
                          key: const ValueKey<String>('volume-slider'),
                          value: volume,
                          min: 0,
                          max: 1,
                          divisions: 100,
                          label: '${(volume * 100).round()}%',
                          onChanged: (value) => state.setVolume(value),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${(volume * 100).round()}%',
                          key: const ValueKey<String>('volume-percent'),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12, color: pal.muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '拖动滑块调整音量，不会误触静音',
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _t(String s) =>
      Text(s, style: TextStyle(fontSize: 11, color: pal.muted));

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
  final ValueNotifier<Duration> _displayPosition = ValueNotifier<Duration>(
    Duration.zero,
  );
  Ticker? _ticker;
  int _active = -1;
  String? _songId;
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  bool get _shouldAnimate =>
      widget.state.audio.playing && widget.state.lyrics.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final audio = widget.state.audio;
    _songId = audio.current?.id;
    _displayPosition.value = audio.lyricPosition;
    _ticker = createTicker((_) {
      if (!mounted) return;
      final next = widget.state.audio.lyricPosition;
      _displayPosition.value = next;
      final active = _LyricSideState._activeIndex(widget.state.lyrics, next);
      // 只在换句时重建整层；句内逐帧颜色由 _KaraokeText 的 painter 完成。
      if (active != _active) {
        _active = active;
        setState(() {});
      }
    });
    audio.addListener(_onAudioChanged);
    _syncAnimations();
  }

  void _onAudioChanged() {
    final audio = widget.state.audio;
    final songId = audio.current?.id;
    if (songId != _songId) {
      _songId = songId;
      _active = -1;
      if (mounted) setState(() {});
    }
    _displayPosition.value = audio.lyricPosition;
    _syncAnimations();
  }

  void _syncAnimations() {
    if (_shouldAnimate) {
      if (_ticker?.isActive == false) _ticker!.start();
      if (!_ambient.isAnimating) _ambient.repeat();
    } else {
      if (_ticker?.isActive == true) _ticker!.stop();
      if (_ambient.isAnimating) _ambient.stop();
      _displayPosition.value = widget.state.audio.lyricPosition;
    }
  }

  @override
  void didUpdateWidget(covariant SonnetLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.audio != widget.state.audio) {
      oldWidget.state.audio.removeListener(_onAudioChanged);
      widget.state.audio.addListener(_onAudioChanged);
    }
    _onAudioChanged();
    _syncAnimations();
  }

  @override
  void dispose() {
    widget.state.audio.removeListener(_onAudioChanged);
    _ambient.dispose();
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
    final glow = st.followCoverColor
        ? widget.state.glowColor
        : widget.pal.accent;
    final glass = widget.state.glass;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: _SonnetGeometryPainter(
              glow: glow,
              animation: _ambient,
              glass: glass,
              animated: widget.state.glassSlide,
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _ambient,
          builder: (context, child) {
            final wave = math.sin(_ambient.value * math.pi * 2);
            final pulse = 1.0 + 0.055 * wave;
            return Opacity(
              opacity: 0.72 + 0.28 * (0.5 + 0.5 * wave),
              child: Transform.scale(scale: pulse, child: child),
            );
          },
          child: Align(
            alignment: Alignment.centerRight,
            child: RepaintBoundary(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [glow.withValues(alpha: 0.16), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (lines.isEmpty || active < 0)
          Center(
            child: Text(
              '暂无歌词',
              style: TextStyle(
                color: widget.pal.text.withValues(alpha: 0.5),
                fontSize: 16,
              ),
            ),
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
                        left: st.align == LyricAlign.center
                            ? w * 0.22
                            : w * 0.10,
                        child: _outlinedTransition(
                          lines[active - 1].text,
                          (h * 0.11 * st.fontScale).clamp(48.0, 150.0),
                        ),
                      ),
                    Positioned(
                      top: h * 0.36,
                      left: st.align == LyricAlign.center ? w * 0.10 : w * 0.06,
                      right: st.align == LyricAlign.center ? w * 0.10 : 0,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.025),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: ValueListenableBuilder<Duration>(
                          key: ValueKey(
                            '${_songId ?? ''}:${current.time.inMilliseconds}:${current.text}',
                          ),
                          valueListenable: _displayPosition,
                          builder: (context, pos, _) => _KaraokeText(
                            line: current,
                            pal: widget.pal,
                            position: pos,
                            lineEnd: active + 1 < lines.length
                                ? lines[active + 1].time
                                : null,
                            fontSize: (h * 0.15 * st.fontScale).clamp(
                              64.0,
                              200.0,
                            ),
                            fontWeight: st.bold
                                ? FontWeight.w900
                                : FontWeight.w600,
                            baseColor: Colors.white.withValues(alpha: 0.45),
                            sungColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (active + 1 < lines.length)
                      Positioned(
                        top: h * 0.60,
                        left: st.align == LyricAlign.center
                            ? w * 0.26
                            : w * 0.18,
                        child: _outlinedTransition(
                          lines[active + 1].text,
                          (h * 0.10 * st.fontScale).clamp(44.0, 130.0),
                        ),
                      ),
                    if (current.subtitles.isNotEmpty)
                      Positioned(
                        top: h * 0.53,
                        left: st.align == LyricAlign.center
                            ? w * 0.12
                            : w * 0.08,
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
        shadows: [Shadow(color: color.withValues(alpha: 0.85), blurRadius: 1)],
      ),
    );
  }

  Widget _outlinedTransition(String text, double size) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 360),
    switchInCurve: Curves.easeOutCubic,
    switchOutCurve: Curves.easeInCubic,
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    child: KeyedSubtree(
      key: ValueKey(text),
      child: _outlined(text, size, Colors.white),
    ),
  );
}

/// 几何线框：十字 / 菱形 / 圆弧 / 虚线对齐框（对应 native_sonnet_geometry.go）。
class _SonnetGeometryPainter extends CustomPainter {
  const _SonnetGeometryPainter({
    required this.glow,
    required this.animation,
    required this.glass,
    required this.animated,
  }) : super(repaint: animated ? animation : null);
  final Color glow;
  final Animation<double> animation;
  final ImmersiveGlass glass;
  final bool animated;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animated ? animation.value * math.pi * 2 : 0.0;
    final wave = math.sin(t);
    final glassAlpha = 0.18 + glass.index * 0.035;
    final line = Paint()
      ..color = Colors.white.withValues(
        alpha: glassAlpha + (animated ? 0.035 * wave : 0),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final dim = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // 十字线（左上 + 中上）
    final wobble = animated ? 5.0 * wave : 0.0;
    _cross(canvas, line, size.width * 0.28 + wobble, size.height * 0.14, 34);
    _cross(canvas, line, size.width * 0.52 - wobble, size.height * 0.09, 26);
    // 菱形（右上）
    final d = size.width * 0.07;
    final cx = size.width * 0.74;
    final cy = size.height * 0.30;
    final softGlow = Paint()
      ..color = glow.withValues(alpha: 0.045 + glass.index * 0.012)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(cx, cy),
      d * (1.05 + (animated ? 0.06 * wave : 0)),
      softGlow,
    );
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(animated ? 0.10 * wave : 0);
    canvas.drawPath(
      Path()
        ..moveTo(0, -d)
        ..lineTo(d, 0)
        ..lineTo(0, d)
        ..lineTo(-d, 0)
        ..close(),
      line,
    );
    canvas.restore();
    // 圆弧（左下）
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.14, size.height * 0.66),
        width: 180,
        height: 180,
      ),
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
    _dashedRect(
      canvas,
      dash,
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.42,
        size.width * 0.5,
        size.height * 0.3,
      ),
      animated ? (t * 3) % 12 : 0,
    );
  }

  void _cross(Canvas c, Paint p, double x, double y, double r) {
    c.drawLine(Offset(x - r, y), Offset(x + r, y), p);
    c.drawLine(Offset(x, y - r), Offset(x, y + r), p);
  }

  void _dashedRect(Canvas c, Paint p, Rect r, double phase) {
    const dash = 6.0;
    for (var x = r.left - phase; x < r.right; x += dash * 2) {
      final start = math.max(x, r.left);
      final end = math.min(x + dash, r.right);
      if (start >= end) continue;
      c.drawLine(Offset(start, r.top), Offset(end, r.top), p);
      c.drawLine(Offset(start, r.bottom), Offset(end, r.bottom), p);
    }
    for (var y = r.top - phase; y < r.bottom; y += dash * 2) {
      final start = math.max(y, r.top);
      final end = math.min(y + dash, r.bottom);
      if (start >= end) continue;
      c.drawLine(Offset(r.left, start), Offset(r.left, end), p);
      c.drawLine(Offset(r.right, start), Offset(r.right, end), p);
    }
  }

  @override
  bool shouldRepaint(covariant _SonnetGeometryPainter old) =>
      old.glow != glow ||
      old.animation != animation ||
      old.glass != glass ||
      old.animated != animated;
}
