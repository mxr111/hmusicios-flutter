import 'package:flutter/material.dart';

import '../models.dart';
import '../models_skin.dart';
import '../protocol/huawei_api.dart';
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
    final cards = _cards(state);

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
                const StatePanel(message: '尚未登录华为账号。请到「我的」扫码登录后加载真实曲库。')
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
                trailing: playlists.isEmpty
                    ? '暂无数据'
                    : '共 ${playlists.length} 个',
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
                  color: widget.state.palette.text,
                ),
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
  List<HomeCardSpec> _cards(AppState state) {
    final discover = state.discover;
    final listen = discover.listen;
    final dailySongs = discover.daily;
    final newSongs = discover.newSongs;
    final heartSongs = discover.heart;
    final hotSongs = discover.hot;
    final now = _firstOrNull(listen);
    final dailySong = _firstOrNull(dailySongs);
    final newSong = _firstOrNull(newSongs);
    final heartSong = _firstOrNull(heartSongs);
    final hotSong = _firstOrNull(hotSongs);
    final listenFeature = _featureFor(
      discover.features,
      serviceTypes: const <String>['privatefm'],
      ids: const <String>['pfm001'],
    );
    final dailyFeature = _featureFor(
      discover.features,
      serviceTypes: const <String>['dailyrecommend'],
      ids: const <String>['a001'],
    );
    final heartFeature = _featureFor(
      discover.features,
      serviceTypes: const <String>['heartbeatfm'],
      ids: const <String>['pfm002'],
    );
    final newFeature = _featureFor(
      discover.features,
      serviceTypes: const <String>['newsongrecommend'],
      ids: const <String>['a003'],
    );
    final hotFeature = _featureFor(
      discover.features,
      serviceTypes: const <String>['millionfavoriterecommend'],
      ids: const <String>['a006'],
    );
    final dailyPlaylist = _firstWhereOrNull(
      discover.playlists,
      (Playlist playlist) => playlist.id == 'a001',
    );
    final hotChart = _firstWhereOrNull(
      discover.charts,
      (Playlist playlist) => playlist.name.contains('热歌'),
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
    String cardTitle(DiscoverFeature? feature, String fallback) =>
        feature?.title.trim().isNotEmpty == true
        ? feature!.title.trim()
        : fallback;
    return <HomeCardSpec>[
      HomeCardSpec(
        badge: '♫  Music FM',
        title: cardTitle(listenFeature, '现在就听'),
        subtitle: subtitle(now, '暂无现在就听歌曲'),
        gradient: MuyuColors.cardNow,
        icon: Icons.radio,
        action: 'radio',
        cover: listenFeature?.cover ?? now?.cover,
        covers: listenCovers,
      ),
      HomeCardSpec(
        badge: dateLabel,
        title: cardTitle(dailyFeature, '每日30首'),
        subtitle: subtitle(dailySong, '暂无每日30首歌曲'),
        gradient: MuyuColors.cardDaily,
        icon: Icons.calendar_month,
        action: 'daily',
        cover: dailyFeature?.cover ?? dailyPlaylist?.cover ?? dailySong?.cover,
        bigText: '${date.day}',
      ),
      HomeCardSpec(
        badge: '♥',
        title: cardTitle(heartFeature, '心动模式'),
        subtitle: subtitle(heartSong, '暂无心动模式歌曲'),
        gradient: MuyuColors.cardHeart,
        icon: Icons.favorite,
        action: 'heart',
        cover: heartFeature?.cover ?? heartSong?.cover,
      ),
      HomeCardSpec(
        badge: '♫  New',
        title: cardTitle(newFeature, '新歌推荐'),
        subtitle: subtitle(newSong, '暂无新歌推荐'),
        gradient: MuyuColors.cardNew,
        icon: Icons.new_releases_outlined,
        action: 'new',
        cover: newFeature?.cover ?? newSong?.cover,
      ),
      HomeCardSpec(
        badge: cardTitle(hotFeature, '热歌速递'),
        title: cardTitle(hotFeature, '热歌速递'),
        subtitle:
            subtitle(hotSong, hotChart?.name ?? '暂无热歌速递歌曲'),
        gradient: MuyuColors.cardHot,
        icon: Icons.whatshot,
        action: 'hot',
        cover: hotFeature?.cover ?? hotSong?.cover,
      ),
    ];
  }

  static Song? _firstOrNull(List<Song> songs) =>
      songs.isEmpty ? null : songs.first;

  static DiscoverFeature? _featureFor(
    List<DiscoverFeature> features, {
    required List<String> serviceTypes,
    required List<String> ids,
  }) {
    for (final feature in features) {
      final serviceType = feature.serviceType.toLowerCase();
      if (serviceTypes.contains(serviceType) ||
          ids.contains(feature.id.toLowerCase())) {
        return feature;
      }
    }
    return null;
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
        var list = state.discover.listen;
        if (list.isEmpty) {
          await state.loadHome();
          list = state.discover.listen;
        }
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        }
        return;
      case 'daily':
        var list = state.discover.daily;
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
          return;
        }
        final daily = _firstWhereOrNull(
          state.discover.playlists,
          (Playlist playlist) => playlist.id == 'a001',
        );
        if (daily != null) {
          await state.openPlaylist(daily);
          return;
        }
        await state.loadHome();
        list = state.discover.daily;
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
          return;
        }
        final refreshedDaily = _firstWhereOrNull(
          state.discover.playlists,
          (Playlist playlist) => playlist.id == 'a001',
        );
        if (refreshedDaily != null) {
          await state.openPlaylist(refreshedDaily);
        }
        return;
      case 'hot':
        var list = state.discover.hot;
        if (list.isEmpty) {
          await state.loadHome();
        }
        list = state.discover.hot;
        if (list.isNotEmpty) await state.play(list.first, queue: list);
        return;
      case 'heart':
        var list = state.discover.heart;
        if (list.isEmpty) {
          await state.loadHome();
          list = state.discover.heart;
        }
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        }
        return;
      case 'new':
        var list = state.discover.newSongs;
        if (list.isEmpty) {
          await state.loadHome();
          list = state.discover.newSongs;
        }
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        }
        return;
      default:
        return;
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
