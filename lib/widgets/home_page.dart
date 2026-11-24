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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final songs = state.discover.recommended.isNotEmpty
        ? state.discover.recommended
        : state.homeSongs;
    final pageCount = songs.isEmpty ? 1 : ((songs.length + 4) ~/ 5);
    final page = _recPage.clamp(1, pageCount);
    final visibleSongs = songs.skip((page - 1) * 5).take(5).toList();
    final playlists = state.discover.playlists;
    final cards = _cards(state, songs);

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _header(context, state),
        const SizedBox(height: 16),
        _heroCards(cards),
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
                    onRetry: state.loadHome,
                    actionLabel: '重试',
                  ),
                ),
              if (!state.isLoggedIn)
                const StatePanel(
                  message: '尚未登录华为账号。请到「我的」扫码登录后加载真实曲库。',
                )
              else if (!state.loading && songs.isEmpty)
                StatePanel(
                  message: '首页接口未返回歌曲，请重试。',
                  onRetry: state.loadHome,
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
                trailing: playlists.isEmpty ? '暂无数据' : '共 ${playlists.length} 个',
                onNext: () {
                  state.selectTab(2);
                },
                nextTooltip: '去音乐厅看榜单',
              ),
              const SizedBox(height: 12),
              if (playlists.isEmpty)
                StatePanel(
                  message: '华为接口未返回推荐歌单。',
                  onRetry: state.loadHome,
                  actionLabel: '重试',
                )
              else
                _playlistGrid(playlists),
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
              Text('主页',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: pal.text)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
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
                    fontSize: 13, color: MuyuColors.inkMuted),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: MuyuColors.inkMuted),
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
        Text(title,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: pal.text)),
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

  Widget _playlistGrid(List<Playlist> playlists) {
    final width = MediaQuery.of(context).size.width;
    final columns = width > 1200 ? 6 : (width > 900 ? 5 : 3);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: width > 900 ? 0.78 : 0.62,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, i) {
        final playlist = playlists[i];
        return InkWell(
          onTap: () => widget.state.openPlaylist(playlist),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => CoverArt(
                    url: playlist.cover,
                    size: box.maxWidth,
                    radius: 12,
                    seed: i,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.name.isEmpty ? '未命名歌单' : playlist.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.state.palette.text),
              ),
              if (playlist.songCount > 0)
                Text('${playlist.songCount} 首', style: MuyuTheme.muted),
            ],
          ),
        );
      },
    );
  }

  /// 五张卡分别绑定首页真实栏目：
  /// 现在就听（listen）/ 每日30首 / 心动模式 / 新歌推荐 / 热歌速递。
  List<HomeCardSpec> _cards(AppState state, List<Song> recommendations) {
    final discover = state.discover;
    final listen = discover.listen.isNotEmpty
        ? discover.listen
        : (recommendations.isNotEmpty ? recommendations : state.homeSongs);
    final now = listen.isNotEmpty ? listen.first : null;
    final newSong =
        discover.newSongs.isNotEmpty ? discover.newSongs.first : now;
    final heart = discover.heart.isNotEmpty
        ? discover.heart.first
        : (discover.radio.isNotEmpty ? discover.radio.first : now);
    final hotSong = discover.hot.isNotEmpty ? discover.hot.first : null;
    final daily = _firstWhereOrNull(
        discover.playlists, (Playlist p) => p.id == 'a001');
    final hot = _firstWhereOrNull(
        discover.charts, (Playlist p) => p.name.contains('热歌'));
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
    final listenCovers = <Uri>[];
    for (final song in listen.take(3)) {
      final cover = song.cover;
      if (cover != null && !listenCovers.contains(cover)) {
        listenCovers.add(cover);
      }
    }
    String subtitle(Song? song, String fallback) =>
        song == null ? fallback : '${song.name} · ${song.artistText}';
    return <HomeCardSpec>[
      HomeCardSpec(
        badge: '♫  Music FM',
        title: '现在就听',
        subtitle: subtitle(now, '点击加载真实推荐'),
        gradient: MuyuColors.cardNow,
        icon: Icons.radio,
        action: 'radio',
        cover: now?.cover,
        covers: listenCovers,
      ),
      HomeCardSpec(
        badge: months[date.month - 1],
        title: '每日30首',
        subtitle: daily?.name ?? '点击打开每日推荐',
        gradient: MuyuColors.cardDaily,
        icon: Icons.calendar_month,
        action: 'daily',
        cover: daily?.cover,
        bigText: '${date.day}',
      ),
      HomeCardSpec(
        badge: '♥',
        title: '心动模式',
        subtitle: subtitle(heart, '私人电台推荐'),
        gradient: MuyuColors.cardHeart,
        icon: Icons.favorite,
        action: 'heart',
        cover: heart?.cover,
      ),
      HomeCardSpec(
        badge: '♫  New',
        title: '新歌推荐',
        subtitle: subtitle(newSong, '加载最新歌曲'),
        gradient: MuyuColors.cardNew,
        icon: Icons.new_releases_outlined,
        action: 'new',
        cover: newSong?.cover,
      ),
      HomeCardSpec(
        badge: '热歌速递',
        title: '热歌速递',
        subtitle: hotSong != null
            ? subtitle(hotSong, '热歌速递')
            : (hot?.name ?? '点击打开热歌榜'),
        gradient: MuyuColors.cardHot,
        icon: Icons.whatshot,
        action: 'hot',
        cover: hotSong?.cover ?? hot?.cover,
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
    switch (action) {
      case 'radio':
        final list = state.discover.listen.isNotEmpty
            ? state.discover.listen
            : (state.discover.recommended.isNotEmpty
                ? state.discover.recommended
                : state.homeSongs);
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        } else {
          await state.loadHome();
        }
        return;
      case 'daily':
        final daily = _firstWhereOrNull(
            state.discover.playlists, (Playlist p) => p.id == 'a001');
        if (daily != null) {
          await state.openPlaylist(daily);
        } else {
          await state.loadHome();
        }
        return;
      case 'hot':
        if (state.discover.hot.isNotEmpty) {
          await state.play(state.discover.hot.first,
              queue: state.discover.hot);
          return;
        }
        final chart = _firstWhereOrNull(
            state.discover.charts, (Playlist p) => p.name.contains('热歌'));
        if (chart != null) {
          await state.openPlaylist(chart);
        } else {
          await state.loadHome();
        }
        return;
      case 'heart':
        final list = state.discover.heart.isNotEmpty
            ? state.discover.heart
            : (state.discover.radio.isNotEmpty
                ? state.discover.radio
                : state.homeSongs);
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        } else {
          await state.loadHome();
        }
        return;
      case 'new':
        final list = state.discover.newSongs.isNotEmpty
            ? state.discover.newSongs
            : (state.discover.recommended.isNotEmpty
                ? state.discover.recommended
                : state.homeSongs);
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        } else {
          await state.loadHome();
        }
        return;
      default:
        final list = state.discover.recommended.isNotEmpty
            ? state.discover.recommended
            : state.homeSongs;
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        } else {
          await state.loadHome();
        }
    }
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
            Text(item.label,
                style: TextStyle(
                    fontSize: 11,
                    color: item.color,
                    fontWeight: FontWeight.w700)),
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
                    fontSize: 13, fontWeight: FontWeight.w700, color: fg),
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
                        Text(spec.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: fg)),
                        const SizedBox(height: 3),
                        Text(spec.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: fg.withValues(alpha: 0.75))),
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
        return Text(spec.bigText ?? '30',
            style: TextStyle(
                fontSize: 74,
                fontWeight: FontWeight.w300,
                color: fg.withValues(alpha: 0.92)));
      case 'heart':
        return Icon(Icons.favorite,
            size: 84, color: fg.withValues(alpha: 0.92));
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
        return Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: CoverArt(url: spec.cover, size: 100, radius: 6, seed: 3),
        );
      default:
        return Icon(spec.icon, size: 72, color: fg.withValues(alpha: 0.85));
    }
  }
}
