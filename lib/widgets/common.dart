import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';

/// 明确分页条：只改本地页码，不发请求。
///
/// 标签文字固定为「第 x / y 页」，窄屏时用 [Wrap] 自动换行，避免按钮溢出。
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final safeCount = math.max(1, pageCount);
    final safePage = page.clamp(1, safeCount);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    Widget pageButton(String label, int target, {bool enabled = true}) {
      return TextButton(
        onPressed: enabled && target != safePage
            ? () => onPageChanged(target.clamp(1, safeCount))
            : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          foregroundColor: scheme.primary,
          disabledForegroundColor: muted.withValues(alpha: 0.45),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );
    }

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 2,
        children: <Widget>[
          pageButton('首页', 1, enabled: safePage > 1),
          pageButton('上一页', safePage - 1, enabled: safePage > 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '第 $safePage / $safeCount 页',
              key: const ValueKey<String>('pagination-page-label'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          pageButton('下一页', safePage + 1, enabled: safePage < safeCount),
          pageButton('末页', safeCount, enabled: safePage < safeCount),
        ],
      ),
    );
  }
}

/// 每页只构建当前页的通用列表；点页码只改本地 state，不触发数据加载。
///
/// - 在 [Expanded] / 有界高度里使用默认 `shrinkWrap = false`，分页条固定在底部。
/// - 嵌在外层 [ListView] 时传 `shrinkWrap: true`，由外层负责滚动。
class PaginatedList<T> extends StatefulWidget {
  const PaginatedList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.pageSize = 20,
    this.shrinkWrap = false,
    this.padding = EdgeInsets.zero,
    this.separatorBuilder,
    this.empty,
    this.resetKey,
    this.showPageBar = true,
    this.physics,
  }) : assert(pageSize > 0, 'pageSize must be positive');

  final List<T> items;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final int pageSize;
  final bool shrinkWrap;
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder? separatorBuilder;
  final Widget? empty;
  final Object? resetKey;
  final bool showPageBar;
  final ScrollPhysics? physics;

  @override
  State<PaginatedList<T>> createState() => _PaginatedListState<T>();
}

class _PaginatedListState<T> extends State<PaginatedList<T>> {
  int _page = 1;

  int get _pageCount => math.max(
    1,
    (widget.items.length + widget.pageSize - 1) ~/ widget.pageSize,
  );

  @override
  void didUpdateWidget(covariant PaginatedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) _page = 1;
    _page = _page.clamp(1, _pageCount);
  }

  void _goToPage(int page) {
    final next = page.clamp(1, _pageCount);
    if (next == _page) return;
    setState(() => _page = next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return widget.empty ?? const SizedBox.shrink();
    }

    final pageCount = _pageCount;
    final page = _page.clamp(1, pageCount);
    final start = (page - 1) * widget.pageSize;
    final end = math.min(start + widget.pageSize, widget.items.length);
    final visible = widget.items.sublist(start, end);
    final list = ListView.separated(
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : widget.physics,
      itemCount: visible.length,
      separatorBuilder:
          widget.separatorBuilder ??
          (BuildContext context, int index) => const SizedBox.shrink(),
      itemBuilder: (context, i) =>
          widget.itemBuilder(context, start + i, visible[i]),
    );

    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.shrinkWrap) list else Expanded(child: list),
        if (widget.showPageBar)
          PaginationBar(
            page: page,
            pageCount: pageCount,
            onPageChanged: _goToPage,
          ),
      ],
    );
  }
}

/// 每页只构建当前页的通用网格；分页条与 [PaginatedList] 共用。
class PaginatedGrid<T> extends StatefulWidget {
  const PaginatedGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.crossAxisCount,
    this.childAspectRatio = 1,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.pageSize = 12,
    this.shrinkWrap = false,
    this.padding = EdgeInsets.zero,
    this.empty,
    this.resetKey,
    this.showPageBar = true,
    this.physics,
  }) : assert(pageSize > 0, 'pageSize must be positive');

  final List<T> items;
  final Widget Function(BuildContext context, int index, T item) itemBuilder;
  final int crossAxisCount;
  final double childAspectRatio;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final int pageSize;
  final bool shrinkWrap;
  final EdgeInsetsGeometry padding;
  final Widget? empty;
  final Object? resetKey;
  final bool showPageBar;
  final ScrollPhysics? physics;

  @override
  State<PaginatedGrid<T>> createState() => _PaginatedGridState<T>();
}

class _PaginatedGridState<T> extends State<PaginatedGrid<T>> {
  int _page = 1;

  int get _pageCount => math.max(
    1,
    (widget.items.length + widget.pageSize - 1) ~/ widget.pageSize,
  );

  @override
  void didUpdateWidget(covariant PaginatedGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetKey != widget.resetKey) _page = 1;
    _page = _page.clamp(1, _pageCount);
  }

  void _goToPage(int page) {
    final next = page.clamp(1, _pageCount);
    if (next == _page) return;
    setState(() => _page = next);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return widget.empty ?? const SizedBox.shrink();
    }

    final pageCount = _pageCount;
    final page = _page.clamp(1, pageCount);
    final start = (page - 1) * widget.pageSize;
    final end = math.min(start + widget.pageSize, widget.items.length);
    final visible = widget.items.sublist(start, end);
    final grid = GridView.builder(
      padding: widget.padding,
      shrinkWrap: widget.shrinkWrap,
      physics: widget.shrinkWrap
          ? const NeverScrollableScrollPhysics()
          : widget.physics,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: math.max(1, widget.crossAxisCount),
        childAspectRatio: widget.childAspectRatio,
        mainAxisSpacing: widget.mainAxisSpacing,
        crossAxisSpacing: widget.crossAxisSpacing,
      ),
      itemCount: visible.length,
      itemBuilder: (context, i) =>
          widget.itemBuilder(context, start + i, visible[i]),
    );

    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.shrinkWrap) grid else Expanded(child: grid),
        if (widget.showPageBar)
          PaginationBar(
            page: page,
            pageCount: pageCount,
            onPageChanged: _goToPage,
          ),
      ],
    );
  }
}

/// 封面：有 URL 走网络图，失败/无 URL 时用渐变占位（保证离线也有完整界面）。
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.url,
    this.size = 44,
    this.radius = 8,
    this.circle = false,
    this.seed = 0,
  });

  final Uri? url;
  final double size;
  final double radius;
  final bool circle;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final palettes = <List<Color>>[
      MuyuColors.cardNow,
      MuyuColors.cardDaily,
      MuyuColors.cardHeart,
      MuyuColors.cardNew,
      MuyuColors.cardHot,
    ];
    final gradient = palettes[seed.abs() % palettes.length];
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: circle
            ? BorderRadius.circular(size / 2)
            : BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.85),
        size: size * 0.4,
      ),
    );

    final borderRadius = circle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(radius);
    final dpr = (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1).clamp(
      1.0,
      3.0,
    );
    final child = url == null
        ? placeholder
        : Image.network(
            url.toString(),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * dpr).round(),
            cacheHeight: (size * dpr).round(),
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          );
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}

/// 黑胶唱片封面：唱片纹路与封面一起旋转，播放时轻微呼吸。
class VinylCover extends StatefulWidget {
  const VinylCover({
    super.key,
    this.url,
    this.size = 48,
    this.spinning = false,
  });

  final Uri? url;
  final double size;
  final bool spinning;

  @override
  State<VinylCover> createState() => _VinylCoverState();
}

class _VinylCoverState extends State<VinylCover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController.unbounded(
    vsync: this,
    duration: const Duration(seconds: 18),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _startSpin();
  }

  @override
  void didUpdateWidget(covariant VinylCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spinning != widget.spinning) {
      if (widget.spinning) {
        _startSpin();
      } else {
        _turns.stop();
      }
    }
  }

  void _startSpin() {
    // 从暂停时的角度继续，周期结束时只多转一整圈，因此不会跳回封面初始角度。
    final start = _turns.value;
    _turns.repeat(min: start, max: start + 1);
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disc = RepaintBoundary(
      child: ClipOval(
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0xFF3A3A40), Color(0xFF101014)],
                    stops: [0.35, 1],
                  ),
                ),
                child: Center(
                  child: ClipOval(
                    child: SizedBox(
                      width: widget.size * 0.6,
                      height: widget.size * 0.6,
                      child: CoverArt(
                        url: widget.url,
                        size: widget.size * 0.6,
                        circle: true,
                        seed: 2,
                      ),
                    ),
                  ),
                ),
              ),
              CustomPaint(painter: _VinylGroovesPainter()),
            ],
          ),
        ),
      ),
    );
    if (!widget.spinning) {
      return RotationTransition(turns: _turns, child: disc);
    }
    return RotationTransition(
      turns: _turns,
      child: AnimatedBuilder(
        animation: _turns,
        builder: (context, child) {
          final pulse = 1.0 + 0.006 * math.sin(_turns.value * math.pi * 2);
          return Transform.scale(scale: pulse, child: child);
        },
        child: disc,
      ),
    );
  }
}

class _VinylGroovesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.55, radius * 0.006);

    // 细密但低对比的压纹，让旋转在大封面上可感知，小尺寸下也不抢封面。
    for (var i = 0; i < 7; i++) {
      final t = i / 7;
      groove.color = Colors.white.withValues(alpha: 0.035 + 0.012 * (i % 2));
      canvas.drawCircle(center, radius * (0.33 + t * 0.16), groove);
    }

    final glint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = math.max(0.7, radius * 0.012)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.46),
      -math.pi * 0.82,
      math.pi * 0.18,
      false,
      glint,
    );
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) => false;
}

class QualityBadge extends StatelessWidget {
  const QualityBadge(this.quality, {super.key, this.small = false});

  final AudioQuality quality;
  final bool small;

  @override
  Widget build(BuildContext context) {
    // 沐语实测徽标：Hi-Res 金色描边 / SQ 粉色描边 / HQ 灰色描边。
    final label = switch (quality) {
      AudioQuality.standard => 'HQ',
      AudioQuality.lossless => 'SQ',
      AudioQuality.hiRes => 'Hi-Res',
    };
    final color = switch (quality) {
      AudioQuality.standard => const Color(0xFF8A9099),
      AudioQuality.lossless => const Color(0xFFE8406A),
      AudioQuality.hiRes => MuyuColors.hiRes,
    };
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 4 : 6,
        vertical: small ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 9 : 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 华为音乐徽章：截图里的蓝色小圆标 + 固定文案。
///
/// [label] 仅为兼容旧调用保留；UI 已收敛为华为音乐单音源，不再渲染其他平台。
class SourceBadge extends StatelessWidget {
  const SourceBadge({super.key, this.label = '华为音乐', this.compact = false});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 14 : 16,
          height: compact ? 14 : 16,
          decoration: const BoxDecoration(
            color: MuyuColors.accent,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.graphic_eq, size: 10, color: Colors.white),
        ),
        if (!compact) ...[
          const SizedBox(width: 4),
          const Text(
            '华为音乐',
            style: TextStyle(fontSize: 10, color: MuyuColors.accent),
          ),
        ],
      ],
    );
  }
}

class TinyIconButton extends StatelessWidget {
  const TinyIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.size = 18,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = IconButton(
      icon: Icon(icon, size: size, color: color ?? MuyuColors.inkMuted),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// 统一播放入口：空 ID / 播放失败必须在 UI 给出可读提示，不能静默。
/// 全局 [AppState.onError] 存在时（正式 App 由 main 统一弹 SnackBar）不重复提示。
Future<void> playSongFromList(
  BuildContext context,
  AppState state,
  Song song,
  List<Song> queue,
) async {
  if (song.id.trim().isEmpty) {
    _showPlaybackMessage(context, '无法播放「${song.name}」：歌曲 ID 为空');
    return;
  }
  await state.play(song, queue: queue);
  if (!context.mounted) return;
  final message = state.error;
  if (message == null || message.isEmpty || state.onError != null) return;
  _showPlaybackMessage(context, '播放失败：$message');
}

void _showPlaybackMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 歌曲行：截图「为你推荐」下的封面 + 歌名 + 歌手 + 收藏 + 书签
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.song,
    required this.onPlay,
    this.onFavorite,
    this.onMore,
    this.onArtistTap,
    this.index = 0,
    this.showTags = true,
  });

  final Song song;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onMore;
  final VoidCallback? onArtistTap;
  final int index;
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onSurface;
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Row(
          children: [
            CoverArt(url: song.cover, size: 42, seed: index),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: onArtistTap,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.graphic_eq,
                          size: 11,
                          color: MuyuColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            song.artistText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showTags && song.member)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.diamond, size: 13, color: Color(0xFFE0A020)),
              ),
            if (showTags)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: QualityBadge(
                  song.qualities.isEmpty
                      ? AudioQuality.standard
                      : song.qualities.reduce(
                          (a, b) => a.index > b.index ? a : b,
                        ),
                  small: true,
                ),
              ),
            TinyIconButton(
              icon: song.favorite ? Icons.favorite : Icons.favorite_border,
              color: song.favorite
                  ? MuyuColors.primary
                  : const Color(0xFF2AA560),
              onTap: onFavorite ?? () {},
              tooltip: '收藏',
            ),
            TinyIconButton(
              icon: Icons.bookmark_border,
              onTap: onMore ?? () {},
              tooltip: '添加到歌单',
            ),
          ],
        ),
      ),
    );
  }
}

/// 歌曲列表分页封装：只渲染当前页，但 [onPlay] 由调用方传入完整歌曲队列。
class PaginatedSongList extends StatelessWidget {
  const PaginatedSongList({
    super.key,
    required this.songs,
    required this.onPlay,
    this.onFavorite,
    this.onMore,
    this.onArtistTap,
    this.pageSize = 20,
    this.shrinkWrap = false,
    this.padding = EdgeInsets.zero,
    this.separatorBuilder,
    this.empty,
    this.resetKey,
    this.showPageBar = true,
    this.showTags = true,
  });

  final List<Song> songs;
  final ValueChanged<Song> onPlay;
  final ValueChanged<Song>? onFavorite;
  final ValueChanged<Song>? onMore;
  final ValueChanged<Song>? onArtistTap;
  final int pageSize;
  final bool shrinkWrap;
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder? separatorBuilder;
  final Widget? empty;
  final Object? resetKey;
  final bool showPageBar;
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    return PaginatedList<Song>(
      items: songs,
      pageSize: pageSize,
      shrinkWrap: shrinkWrap,
      padding: padding,
      separatorBuilder: separatorBuilder,
      empty: empty,
      resetKey: resetKey,
      showPageBar: showPageBar,
      itemBuilder: (context, index, song) => SongRow(
        song: song,
        index: index,
        showTags: showTags,
        onPlay: () => onPlay(song),
        onFavorite: onFavorite == null ? null : () => onFavorite!(song),
        onMore: onMore == null ? null : () => onMore!(song),
        onArtistTap: onArtistTap == null ? null : () => onArtistTap!(song),
      ),
    );
  }
}

/// 无凭据 / 请求失败时的重试卡片（对应 REA 里的 discovery-empty / discovery-retry）
class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.message,
    this.onRetry,
    this.actionLabel,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MuyuColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MuyuColors.divider),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: MuyuColors.inkMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: MuyuTheme.body)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(actionLabel ?? '重试')),
        ],
      ),
    );
  }
}
