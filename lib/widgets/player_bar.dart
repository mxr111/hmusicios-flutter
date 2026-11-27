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
    name: '未在播放',
    artists: const ['点击播放推荐歌曲'],
    qualities: const {AudioQuality.standard},
  );

  @override
  Widget build(BuildContext context) {
    final audio = state.audio;
    final pal = state.palette;
    final song = audio.current ?? _placeholder;
    final hasTrack = audio.current != null;
    final total = hasTrack && audio.duration.inSeconds > 0
        ? audio.duration.inSeconds.toDouble()
        : 1.0;
    final currentSeconds = hasTrack
        ? audio.position.inSeconds.toDouble().clamp(0.0, total)
        : 0.0;

    return GestureDetector(
      // 原版交互：点播放条空白/封面/歌名进入全屏播放页；
      // 歌词按钮也进入同一页，而不是只切换一个独立歌词层。
      onTap: hasTrack ? () => _openFullPlayer(song) : _startFirst,
      child: Container(
        height: MuyuDims.playerBarHeight,
        decoration: BoxDecoration(
          color: pal.surface,
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
            final compact = constraints.maxWidth < 520;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  VinylCover(
                    url: song.cover,
                    size: 46,
                    spinning: audio.playing,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: compact ? 100 : (wide ? 150 : 110),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: pal.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                song.artistText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: pal.muted,
                                ),
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(width: 6),
                              const SourceBadge(compact: true),
                              const SizedBox(width: 5),
                              QualityBadge(audio.quality, small: true),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (wide) ...[const SizedBox(width: 12), _controls(audio)],
                  const SizedBox(width: 8),
                  if (!compact)
                    Expanded(
                      child: ValueListenableBuilder<Duration>(
                        valueListenable: audio.positionNotifier,
                        builder: (context, value, _) {
                          final seconds = hasTrack
                              ? value.inSeconds.toDouble().clamp(0.0, total)
                              : currentSeconds;
                          return Row(
                            children: [
                              Text(
                                _fmt(seconds),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: pal.muted,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: seconds,
                                  min: 0,
                                  max: total,
                                  activeColor: MuyuColors.primary,
                                  inactiveColor: MuyuColors.divider,
                                  onChanged: (v) =>
                                      audio.seek(Duration(seconds: v.toInt())),
                                ),
                              ),
                              Text(
                                hasTrack && audio.duration.inSeconds > 0
                                    ? _fmt(total)
                                    : '0:00',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: pal.muted,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  if (compact) const Spacer(),
                  if (wide) ..._rightButtons(context, song),
                  if (!wide) ...[
                    TinyIconButton(
                      icon: audio.playing ? Icons.pause : Icons.play_arrow,
                      onTap: _togglePlayback,
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
      ),
    );
  }

  Widget _controls(MuyuAudioController audio) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TinyIconButton(
          icon: audio.playMode.icon,
          color: audio.shuffle ? MuyuColors.accent : MuyuColors.inkMuted,
          onTap: audio.cyclePlayMode,
          size: 16,
          tooltip: '播放模式：${audio.playMode.label}',
        ),
        TinyIconButton(
          icon: Icons.skip_previous,
          onTap: audio.previous,
          size: 20,
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: _togglePlayback,
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

  void _startFirst() {
    if (state.homeSongs.isNotEmpty) {
      state.play(state.homeSongs.first, queue: state.homeSongs);
    } else {
      state.loadHome();
    }
  }

  /// 播放条空白/封面：进入应用级全屏播放器，默认显示封面页。
  void _openFullPlayer(Song song) {
    if (state.immersiveFullscreen) state.toggleImmersiveFullscreen();
    state.openFullPlayer(song);
  }

  /// 歌词按钮 = 歌词放大：打开同一播放器，是否进入歌词页由用户点封面/滑动。
  void _openLyrics(Song song) {
    state.showLyricsFor(song);
    if (!state.immersiveFullscreen) state.toggleImmersiveFullscreen();
  }

  void _togglePlayback() {
    if (state.audio.current == null) {
      _startFirst();
    } else {
      state.audio.toggle();
    }
  }

  List<Widget> _rightButtons(BuildContext context, Song song) {
    final audio = state.audio;
    return [
      const SizedBox(width: 6),
      QualityBadge(audio.quality),
      TinyIconButton(
        icon: song.favorite ? Icons.favorite : Icons.favorite_border,
        color: MuyuColors.primary,
        onTap: () => state.toggleFavorite(song),
        tooltip: song.favorite ? '取消收藏' : '收藏',
      ),
      TinyIconButton(
        icon: Icons.bookmark_border,
        onTap: () => _showAddToPlaylist(context, song),
        tooltip: '添加到歌单',
      ),
      TinyIconButton(
        icon: audio.volume == 0 ? Icons.volume_off : Icons.volume_up,
        onTap: () => _showVolume(context),
        tooltip: '音量',
      ),
      TinyIconButton(
        icon: Icons.more_horiz,
        onTap: () => _showMore(context, song),
        tooltip: '更多',
      ),
      TinyIconButton(
        icon: Icons.lyrics_outlined,
        onTap: () => _openLyrics(song),
        tooltip: '歌词',
      ),
      TinyIconButton(
        icon: Icons.queue_music,
        onTap: () => _showQueue(context),
        tooltip: '播放队列',
      ),
    ];
  }

  void _showVolume(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('音量'),
        content: AnimatedBuilder(
          animation: state.audio,
          builder: (context, _) {
            final audio = state.audio;
            final muted = audio.volume == 0;
            return Row(
              children: [
                IconButton(
                  tooltip: muted ? '取消静音' : '静音',
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  onPressed: () => state.setVolume(muted ? 1.0 : 0.0),
                ),
                Expanded(
                  child: Slider(
                    key: const ValueKey<String>('player-bar-volume-slider'),
                    value: audio.volume.clamp(0.0, 1.0),
                    onChanged: (v) => state.setVolume(v),
                  ),
                ),
                Text('${(audio.volume * 100).round()}%'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylist(BuildContext context, Song song) {
    final playlists = state.playlists;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('添加到歌单', style: MuyuTheme.section),
            ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('暂无歌单，请先在「唱片架」创建', style: MuyuTheme.muted),
              ),
            ...playlists
                .where((p) => p.kind == 'owned')
                .map(
                  (p) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.playlist_add),
                    title: Text(p.name),
                    onTap: () async {
                      await state.api.changeCollectionSong(
                        p.id,
                        song.id,
                        add: true,
                      );
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showMore(BuildContext context, Song song) {
    final audio = state.audio;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.equalizer),
              title: const Text('音效'),
              subtitle: Text(audio.effect),
              onTap: () {
                Navigator.pop(context);
                _showEffects(context, audio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer),
              title: const Text('定时停止'),
              subtitle: Text(
                audio.sleepTimer == null
                    ? '未设置'
                    : '剩余 ${audio.sleepRemaining?.inMinutes ?? 0} 分钟',
              ),
              onTap: () {
                Navigator.pop(context);
                _showSleepTimer(context, audio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.high_quality),
              title: const Text('音质'),
              subtitle: Text(audio.quality.label),
              onTap: () {
                Navigator.pop(context);
                _showQuality(context, audio);
              },
            ),
            ListTile(
              leading: const Icon(Icons.comment_outlined),
              title: const Text('评论'),
              onTap: () {
                Navigator.pop(context);
                state.loadComments(song.id);
                _showComments(context);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showEffects(BuildContext context, MuyuAudioController audio) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('音效', style: MuyuTheme.section),
            ),
            ...MuyuAudioController.kEffects.map(
              (e) => ListTile(
                dense: true,
                title: Text(e),
                trailing: audio.effect == e
                    ? const Icon(Icons.check, color: MuyuColors.accent)
                    : null,
                onTap: () {
                  state.setEffect(e);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimer(BuildContext context, MuyuAudioController audio) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('定时停止', style: MuyuTheme.section),
            ),
            ...<int>[5, 10, 15, 30, 45, 60].map(
              (m) => ListTile(
                dense: true,
                title: Text('$m 分钟后停止'),
                onTap: () {
                  audio.setSleepTimer(m);
                  Navigator.pop(context);
                },
              ),
            ),
            ListTile(
              dense: true,
              title: const Text('取消定时'),
              onTap: () {
                audio.setSleepTimer(0);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQuality(BuildContext context, MuyuAudioController audio) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('音质', style: MuyuTheme.section),
            ),
            ...AudioQuality.values.map(
              (q) => ListTile(
                dense: true,
                title: Text(q.label),
                trailing: audio.quality == q
                    ? const Icon(Icons.check, color: MuyuColors.accent)
                    : null,
                onTap: () {
                  state.setQuality(q);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComments(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: AnimatedBuilder(
            animation: state,
            builder: (context, _) => Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('评论', style: MuyuTheme.section),
                ),
                if (state.comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('暂无评论', style: MuyuTheme.muted),
                  ),
                Expanded(
                  child: ListView.builder(
                    itemCount: state.comments.length,
                    itemBuilder: (context, i) {
                      final c = state.comments[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          c.author,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(c.content),
                        trailing: Text('${c.likes}', style: MuyuTheme.muted),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQueue(BuildContext context) {
    final queue = state.audio.queue;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.7,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('播放队列', style: MuyuTheme.section),
              ),
              if (queue.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('队列为空', style: MuyuTheme.muted),
                )
              else
                Expanded(
                  child: PaginatedSongList(
                    songs: queue,
                    resetKey: queue.length,
                    onPlay: (song) {
                      Navigator.pop(sheetContext);
                      state.play(song, queue: queue);
                    },
                    onFavorite: state.toggleFavorite,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(double seconds) {
    final s = seconds.toInt();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
