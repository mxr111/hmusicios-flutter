import 'package:flutter/material.dart';

import '../models.dart';
import '../models_skin.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 主页：顶部标题/音源/搜索 + 5 张推荐卡 + 「为你推荐」5 首/页 +
/// 底部「推荐歌单」网格。所有内容来自真实华为接口。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _search = TextEditingController();
  int _recPage = 1;
  int _chartPage = 1;
  int _cardGroup = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // 「为你推荐」只认 8011 私享好歌，不再回退 homeSongs。
    final songs = state.discover.recommended;
    final pageCount = songs.isEmpty ? 1 : ((songs.length + 4) ~/ 5);
    final page = _recPage.clamp(1, pageCount);
    final visibleSongs = songs.skip((page - 1) * 5).take(5).toList();
    final playlists = state.discover.playlists;
    final charts = state.discover.charts;
    final chartCount = charts.isEmpty ? 1 : charts.length.clamp(1, 10);
    final chartPage = _chartPage.clamp(1, chartCount);
    final cards = _cards(state);

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _header(context, state),
        const SizedBox(height: 16),
        _heroCards(cards),
        _cardGroupBar(),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionRow(
                title: '为你推荐',
                trailing: songs.isEmpty ? '暂无数据' : '$page/$pageCount',
                onPrevious: page > 1
                    ? () => setState(() => _recPage = page - 1)
                    : null,
                onNext: page < pageCount
                    ? () => setState(() => _recPage = page + 1)
                    : null,
              ),
              if (state.loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: StatePanel(
                    message: state.error!,
                    onRetry: () => state.refreshHome(force: true),
                    actionLabel: '重试',
                  ),
                ),
              if (!state.isLoggedIn)
                const StatePanel(message: '尚未登录华为账号。请到「我的」扫码登录后加载真实曲库。')
              else if (!state.loading && songs.isEmpty)
                StatePanel(
                  message: '为你推荐（8011）未返回歌曲。',
                  onRetry: () => state.refreshHome(force: true),
                  actionLabel: '重试',
                )
              else
                ...visibleSongs.map(
                  (song) => SongRow(
                    song: song,
                    index: songs.indexOf(song),
                    showTags: false,
                    onPlay: () => state.play(song, queue: songs),
                    onFavorite: () => state.toggleFavorite(song),
                    onArtistTap: () => state.openArtistFromSong(song),
                  ),
                ),
              const SizedBox(height: 26),
              _sectionRow(
                title: '推荐歌单',
                trailing: playlists.isEmpty
                    ? '暂无数据'
                    : '共 ${playlists.length} 个',
              ),
              const SizedBox(height: 12),
              if (playlists.isEmpty)
                StatePanel(
                  message: '暂无推荐歌单',
                  onRetry: () => state.refreshHome(force: true),
                  actionLabel: '重试',
                )
              else
                _playlistStrip(playlists),
              const SizedBox(height: 26),
              _sectionRow(
                title: '热歌榜',
                trailing: charts.isEmpty
                    ? '暂无数据'
                    : '$chartPage/${charts.length > 10 ? 10 : charts.length}',
                onPrevious: chartPage > 1
                    ? () => setState(() => _chartPage = chartPage - 1)
                    : null,
                onNext: chartPage < chartCount
                    ? () => setState(() => _chartPage = chartPage + 1)
                    : null,
              ),
              const SizedBox(height: 12),
              if (charts.isEmpty)
                StatePanel(
                  message: '暂无榜单数据',
                  onRetry: () => state.refreshHome(force: true),
                  actionLabel: '重试',
                )
              else
                _hotChartPanel(charts[chartPage - 1]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, AppState state) {
    final pal = state.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '主页',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: pal.text,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(child: SourceSwitcher(state: state)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '换一批',
                onPressed: state.refreshHome,
              ),
              OutlinedButton.icon(
                onPressed: () {
                  state.selectTab(1);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('千语取歌：输入歌曲或歌手名开始搜索')),
                  );
                },
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: const Text('千语取歌', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: TextField(
              controller: _search,
              onSubmitted: (value) => state.doSearch(value),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索音乐',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: MuyuColors.inkMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: MuyuColors.inkMuted,
                ),
                filled: true,
                fillColor: pal.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCards(List<HomeCardSpec> cards) {
    return SizedBox(
      height: MuyuDims.cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) => HomeCard(
          spec: cards[i],
          onPlay: () => _playCard(widget.state, cards[i].action),
        ),
      ),
    );
  }

  Widget _cardGroupBar() {
    final pal = widget.state.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Row(
        children: [
          Text('上一组 / 下一组', style: TextStyle(fontSize: 12, color: pal.muted)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() {
              _cardGroup = _cardGroup == 0 ? 4 : _cardGroup - 1;
            }),
            child: const Text('上一组'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _cardGroup = (_cardGroup + 1) % 5;
            }),
            child: const Text('下一组'),
          ),
        ],
      ),
    );
  }

  Widget _sectionRow({
    required String title,
    required String trailing,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    String? nextTooltip,
  }) {
    final pal = widget.state.palette;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: pal.text,
          ),
        ),
        const Spacer(),
        Text(trailing, style: TextStyle(fontSize: 12, color: pal.muted)),
        if (onPrevious != null)
          TinyIconButton(icon: Icons.chevron_left, onTap: onPrevious),
        if (onNext != null)
          TinyIconButton(
            icon: Icons.chevron_right,
            onTap: onNext,
            tooltip: nextTooltip,
          ),
      ],
    );
  }

  Widget _playlistStrip(List<Playlist> playlists) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final playlist = playlists[i];
          return SizedBox(
            width: 132,
            child: InkWell(
              onTap: () => widget.state.openPlaylist(playlist),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverArt(url: playlist.cover, size: 132, radius: 12, seed: i),
                  const SizedBox(height: 8),
                  Text(
                    playlist.name.isEmpty ? '未命名歌单' : playlist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.state.palette.text,
                    ),
                  ),
                  if (playlist.songCount > 0)
                    Text('${playlist.songCount} 首', style: MuyuTheme.muted),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _hotChartPanel(Playlist chart) {
    final pal = widget.state.palette;
    return InkWell(
      onTap: () => widget.state.openPlaylist(chart),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CoverArt(url: chart.cover, size: 64, radius: 10, seed: 3),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chart.name.isEmpty ? '热歌榜' : chart.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    chart.songCount > 0
                        ? '${chart.songCount} 首 · chartID ${chart.id}'
                        : 'chartID ${chart.id}',
                    style: TextStyle(fontSize: 11, color: pal.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  /// 五张卡分别绑定首页真实栏目：
  /// 现在就听（listen）/ 每日30首 / 心动模式 / 新歌推荐 / 热歌速递。
  List<HomeCardSpec> _cards(AppState state) {
    final discover = state.discover;
    final listen = discover.listen;
    final dailySongs = discover.daily;
    final newSongs = discover.newSongs;
    final heartSongs = discover.heart;
    final hotSongs = discover.hot;
    Song? pick(List<Song> list) =>
        list.isEmpty ? null : list[_cardGroup % list.length];
    final now = pick(listen);
    final dailySong = pick(dailySongs);
    final newSong = pick(newSongs);
    final heartSong = pick(heartSongs);
    final hotSong = pick(hotSongs);
    final dailyPlaylist = _firstWhereOrNull(
      discover.playlists,
      (Playlist playlist) => playlist.id == 'a001',
    );
    final date = DateTime.now();
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final dateLabel = months[date.month - 1];
    final listenCovers = <Uri>[];
    for (final song in listen.take(3)) {
      final cover = song.cover;
      if (cover != null && !listenCovers.contains(cover)) {
        listenCovers.add(cover);
      }
    }
    String subtitle(Song? song, String emptyLabel) =>
        song == null ? emptyLabel : '${song.name} · ${song.artistText}';
    return <HomeCardSpec>[
      HomeCardSpec(
        badge: '♫  Music FM',
        title: '现在就听',
        subtitle: subtitle(now, '暂无现在就听歌曲'),
        gradient: MuyuColors.cardNow,
        icon: Icons.radio,
        action: 'radio',
        cover: now?.cover,
        covers: listenCovers,
      ),
      HomeCardSpec(
        badge: dateLabel,
        title: '每日30首',
        subtitle: subtitle(dailySong, '暂无每日30首歌曲'),
        gradient: MuyuColors.cardDaily,
        icon: Icons.calendar_month,
        action: 'daily',
        cover: dailyPlaylist?.cover ?? dailySong?.cover,
        bigText: '${date.day}',
      ),
      HomeCardSpec(
        badge: '♥',
        title: '心动模式',
        subtitle: subtitle(heartSong, '暂无心动模式歌曲'),
        gradient: MuyuColors.cardHeart,
        icon: Icons.favorite,
        action: 'heart',
        cover: heartSong?.cover,
      ),
      HomeCardSpec(
        badge: '♫  New',
        title: '新歌推荐',
        subtitle: subtitle(newSong, '暂无新歌推荐'),
        gradient: MuyuColors.cardNew,
        icon: Icons.new_releases_outlined,
        action: 'new',
        cover: newSong?.cover,
      ),
      HomeCardSpec(
        badge: '♫  Hot',
        title: '热歌速递',
        subtitle: subtitle(hotSong, '暂无热歌速递歌曲'),
        gradient: MuyuColors.cardHot,
        icon: Icons.whatshot,
        action: 'hot',
        cover: hotSong?.cover,
      ),
    ];
  }

  static T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) test) {
    for (final value in values) {
      if (test(value)) return value;
    }
    return null;
  }

  Future<void> _playCard(AppState state, String action) async {
    List<Song> list;
    switch (action) {
      case 'radio':
        list = state.discover.listen;
        break;
      case 'daily':
        list = state.discover.daily;
        break;
      case 'hot':
        list = state.discover.hot;
        break;
      case 'heart':
        list = state.discover.heart;
        break;
      case 'new':
        list = state.discover.newSongs;
        break;
      default:
        return;
    }
    if (list.isEmpty) {
      // 只重试本板块；绝不借用其他卡片或 homeSongs。
      await state.refreshHome(force: true);
      list = switch (action) {
        'radio' => state.discover.listen,
        'daily' => state.discover.daily,
        'hot' => state.discover.hot,
        'heart' => state.discover.heart,
        _ => state.discover.newSongs,
      };
    }
    if (list.isEmpty) {
      if (action == 'daily') {
        final daily = _firstWhereOrNull(
          state.discover.playlists,
          (Playlist playlist) => playlist.id == 'a001',
        );
        if (daily != null) {
          await state.openPlaylist(daily);
          return;
        }
      }
      state.error = '「$action」独立板块未返回歌曲（不回填其他列表）';
      state.refresh();
      return;
    }
    final index = _cardGroup % list.length;
    await state.play(list[index], queue: list);
  }
}

/// 顶部音源切换：华为 / 网易云 / 酷狗 / QQ 四个真实音源。
class SourceSwitcher extends StatelessWidget {
  const SourceSwitcher({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final sources = <_SourceSpec>[
      const _SourceSpec(
        source: MusicSource.huawei,
        label: '华为音乐',
        icon: Icons.graphic_eq,
        color: MuyuColors.accent,
      ),
      const _SourceSpec(
        source: MusicSource.netease,
        label: '网易云',
        icon: Icons.cloud_queue,
        color: Color(0xFFEF4444),
      ),
      const _SourceSpec(
        source: MusicSource.kugou,
        label: '酷狗',
        icon: Icons.music_note,
        color: Color(0xFF3B82F6),
      ),
      const _SourceSpec(
        source: MusicSource.qq,
        label: 'QQ',
        icon: Icons.music_note,
        color: Color(0xFFFACC15),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in sources) ...[
            if (state.source == item.source)
              _sourcePill(item)
            else
              _sourceDot(item),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _sourcePill(_SourceSpec item) {
    return GestureDetector(
      onTap: () => state.switchSource(item.source),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 13, color: item.color),
            const SizedBox(width: 5),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                color: item.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceDot(_SourceSpec item) {
    return Tooltip(
      message: item.label,
      child: GestureDetector(
        onTap: () => state.switchSource(item.source),
        child: Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: item.color.withValues(alpha: 0.14),
            border: Border.all(color: item.color.withValues(alpha: 0.55)),
          ),
          child: Icon(item.icon, size: 13, color: item.color),
        ),
      ),
    );
  }
}

class _SourceSpec {
  const _SourceSpec({
    required this.source,
    required this.label,
    required this.icon,
    required this.color,
  });

  final MusicSource source;
  final String label;
  final IconData icon;
  final Color color;
}

/// 首页大卡片
class HomeCard extends StatelessWidget {
  const HomeCard({super.key, required this.spec, required this.onPlay});

  final HomeCardSpec spec;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final lightText = spec.action != 'new';
    final fg = lightText ? Colors.white : const Color(0xFF2A2A30);
    return GestureDetector(
      onTap: onPlay,
      child: Container(
        width: MuyuDims.cardWidth,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: spec.gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(MuyuDims.radius),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 16,
              child: Text(
                spec.badge,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
            Center(child: _center(spec, fg)),
            Positioned(
              left: 14,
              right: 12,
              bottom: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          spec.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: fg,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          spec.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: fg.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onPlay,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.play_arrow, size: 22, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _center(HomeCardSpec spec, Color fg) {
    switch (spec.action) {
      case 'daily':
        return SizedBox(
          width: 120,
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (spec.cover != null)
                CoverArt(url: spec.cover, size: 96, radius: 12, seed: 1),
              if (spec.cover != null)
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              Text(
                spec.bigText ?? '30',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w300,
                  color: fg.withValues(alpha: 0.96),
                  shadows: const <Shadow>[
                    Shadow(color: Colors.black38, blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      case 'heart':
        return Icon(
          Icons.favorite,
          size: 84,
          color: fg.withValues(alpha: 0.92),
        );
      case 'radio':
        final covers = spec.covers.isNotEmpty
            ? spec.covers
            : <Uri>[if (spec.cover != null) spec.cover!];
        if (covers.isEmpty) {
          return Icon(spec.icon, size: 72, color: fg.withValues(alpha: 0.85));
        }
        return SizedBox(
          width: 136,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < covers.length; i++)
                Positioned(
                  left: 14.0 + i * 18,
                  top: 20.0 - i * 2,
                  child: Transform.rotate(
                    angle: (i - (covers.length - 1) / 2) * 0.08,
                    child: CoverArt(
                      url: covers[i],
                      size: 78,
                      radius: 8,
                      seed: i,
                    ),
                  ),
                ),
            ],
          ),
        );
      case 'new':
      case 'hot':
        return Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: CoverArt(url: spec.cover, size: 100, radius: 6, seed: 3),
        );
      default:
        return Icon(spec.icon, size: 72, color: fg.withValues(alpha: 0.85));
    }
  }
}
