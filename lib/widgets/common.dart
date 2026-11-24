import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

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
    final dpr = (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1).clamp(1.0, 3.0);
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

/// 黑胶唱片封面：截图里播放条左侧的旋转圆形封面
class VinylCover extends StatelessWidget {
  const VinylCover({super.key, this.url, this.size = 48, this.spinning = false});

  final Uri? url;
  final double size;
  final bool spinning;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFF3A3A40), Color(0xFF101014)],
          stops: [0.35, 1],
        ),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
      ),
      child: Center(
        child: ClipOval(
          child: SizedBox(
            width: size * 0.6,
            height: size * 0.6,
            child: CoverArt(
              url: url,
              size: size * 0.6,
              circle: true,
              seed: 2,
            ),
          ),
        ),
      ),
    );
    if (!spinning) return disc;
    return RotationTransition(
      turns: const AlwaysStoppedAnimation<double>(0.12),
      child: disc,
    );
  }
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
          horizontal: small ? 4 : 6, vertical: small ? 1 : 2),
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

/// 音源徽章：截图里「华为音乐」蓝色小圆标 + 文字
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
          Text(label,
              style: const TextStyle(fontSize: 10, color: MuyuColors.accent)),
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
  });

  final Song song;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onMore;
  final VoidCallback? onArtistTap;
  final int index;

  @override
  Widget build(BuildContext context) {
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
                  Text(song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MuyuColors.ink)),
                  const SizedBox(height: 3),
                  GestureDetector(
                    onTap: onArtistTap,
                    child: Row(
                      children: [
                        Icon(song.source.icon,
                            size: 11, color: song.source.color),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(song.artistText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MuyuTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (song.member)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.diamond, size: 13, color: Color(0xFFE0A020)),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: QualityBadge(
                song.qualities.isEmpty
                    ? AudioQuality.standard
                    : song.qualities.reduce((a, b) => a.index > b.index ? a : b),
                small: true,
              ),
            ),
            TinyIconButton(
              icon: song.favorite ? Icons.favorite : Icons.favorite_border,
              color: song.favorite ? MuyuColors.primary : const Color(0xFF2AA560),
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
          Expanded(
            child: Text(message, style: MuyuTheme.body),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(actionLabel ?? '重试')),
        ],
      ),
    );
  }
}
