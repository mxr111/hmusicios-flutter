import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../services/audio_controller.dart';
import '../theme.dart';
import 'common.dart';

/// 底部悬浮播放条：截图里的白色胶囊，左侧黑胶封面 + 歌名/歌手 +
/// 音源徽章 + 音质标签，中间播控，右侧进度 / 收藏 / 音量 / 歌词 / 队列。
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key, required this.state});

  final AppState state;

  static final Song _placeholder = Song(
    id: 'placeholder',
    name: '后来的我们',
    artists: const ['五月天'],
    durationMs: 285000,
    qualities: const {AudioQuality.standard, AudioQuality.hiRes},
  );

  @override
  Widget build(BuildContext context) {
    final audio = state.audio;
    final song = audio.current ?? _placeholder;
    final hasTrack = audio.current != null;
    final total = hasTrack && audio.duration.inSeconds > 0
        ? audio.duration.inSeconds.toDouble()
        : 285.0;
    final currentSeconds = hasTrack
        ? audio.position.inSeconds.toDouble().clamp(0.0, total)
        : 79.0;

    return Container(
      height: MuyuDims.playerBarHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 820;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                VinylCover(url: song.cover, size: 46, spinning: audio.playing),
                const SizedBox(width: 10),
                SizedBox(
                  width: wide ? 150 : 110,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: MuyuColors.ink)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(song.artistText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MuyuTheme.muted),
                          const SizedBox(width: 6),
                          const SourceBadge(compact: true),
                          const SizedBox(width: 5),
                          QualityBadge(audio.quality, small: true),
                        ],
                      ),
                    ],
                  ),
                ),
                if (wide) ...[
                  const SizedBox(width: 12),
                  _controls(audio),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Text(_fmt(currentSeconds), style: MuyuTheme.muted),
                      Expanded(
                        child: Slider(
                          value: currentSeconds,
                          min: 0,
                          max: total,
                          activeColor: MuyuColors.primary,
                          inactiveColor: MuyuColors.divider,
                          onChanged: (v) =>
                              audio.seek(Duration(seconds: v.toInt())),
                        ),
                      ),
                      Text(_fmt(total), style: MuyuTheme.muted),
                    ],
                  ),
                ),
                if (wide) ..._rightButtons(context, song),
                if (!wide) ...[
                  TinyIconButton(
                    icon: audio.playing ? Icons.pause : Icons.play_arrow,
                    onTap: audio.toggle,
                    size: 24,
                    color: MuyuColors.ink,
                  ),
                  TinyIconButton(
                    icon: Icons.skip_next,
                    onTap: audio.next,
                    size: 20,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _controls(MuyuAudioController audio) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TinyIconButton(
          icon: audio.shuffle ? Icons.shuffle : Icons.repeat,
          color: audio.shuffle ? MuyuColors.accent : MuyuColors.inkMuted,
          onTap: () {},
          size: 16,
          tooltip: '播放模式',
        ),
        TinyIconButton(icon: Icons.skip_previous, onTap: audio.previous, size: 20),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: audio.toggle,
          child: Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF141418),
              shape: BoxShape.circle,
            ),
            child: Icon(
              audio.playing ? Icons.pause : Icons.play_arrow,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 4),
        TinyIconButton(icon: Icons.skip_next, onTap: audio.next, size: 20),
      ],
    );
  }

  List<Widget> _rightButtons(BuildContext context, Song song) {
    final audio = state.audio;
    return [
      const SizedBox(width: 6),
      QualityBadge(audio.quality),
      TinyIconButton(
        icon: song.favorite ? Icons.favorite : Icons.favorite_border,
        color: MuyuColors.primary,
        onTap: () {},
        tooltip: '收藏',
      ),
      TinyIconButton(icon: Icons.bookmark_border, onTap: () {}, tooltip: '歌单'),
      TinyIconButton(
        icon: audio.volume == 0 ? Icons.volume_off : Icons.volume_up,
        onTap: () => audio.setVolume(audio.volume == 0 ? 1.0 : 0.0),
        tooltip: '音量',
      ),
      TinyIconButton(icon: Icons.more_horiz, onTap: () {}, tooltip: '更多'),
      TinyIconButton(
        icon: Icons.lyrics_outlined,
        onTap: () => state.showLyricsFor(song),
        tooltip: '歌词',
      ),
      TinyIconButton(
        icon: Icons.queue_music,
        onTap: () => _showQueue(context),
        tooltip: '播放队列',
      ),
    ];
  }

  void _showQueue(BuildContext context) {
    final queue = state.audio.queue;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('播放队列', style: MuyuTheme.section),
            ),
            if (queue.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('队列为空', style: MuyuTheme.muted),
              ),
            ...queue.map((s) => ListTile(
                  dense: true,
                  leading: CoverArt(url: s.cover, size: 36, seed: 1),
                  title: Text(s.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(s.artistText, style: MuyuTheme.muted),
                  onTap: () {
                    Navigator.pop(context);
                    state.play(s, queue: queue);
                  },
                )),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  static String _fmt(double seconds) {
    final s = seconds.toInt();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

