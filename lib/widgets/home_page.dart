import 'package:flutter/material.dart';

import '../models.dart';
import '../models_skin.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 主页：截图里的「标题 + 音源切换 + 搜索框 + 四张推荐大卡片 +
/// 为你推荐(1/5) + 歌曲列表」。无凭据时也保留完整离线占位界面。
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // 首页列表只显示真实接口数据，不再用硬编码歌曲冒充（用户明确要求）。
    final songs = state.homeSongs;
    final cards = _cards(state);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 108),
      children: [
        _header(state),
        const SizedBox(height: 14),
        _searchField(),
        const SizedBox(height: 20),
        SizedBox(
          height: MuyuDims.cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) => HomeCard(
              spec: cards[i],
              onPlay: () => _playCard(state, cards[i].action),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _sectionHeader(),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        if (state.error != null)
          StatePanel(
            message: state.error!,
            onRetry: state.loadHome,
            actionLabel: '重试',
          ),
        if (!state.isLoggedIn)
          const StatePanel(
            message: '尚未登录华为账号。请在「我的」中用华为账号扫码登录后加载真实曲库。',
          ),
        if (state.isLoggedIn && !state.loading && songs.isEmpty)
          StatePanel(
            message: '首页接口未返回歌曲，请点击重试或到「音乐厅」查看其他板块。',
            onRetry: state.loadHome,
            actionLabel: '重试',
          ),
        ...List<Widget>.generate(
          songs.length,
          (i) => SongRow(
            song: songs[i],
            index: i,
            onPlay: () => state.play(songs[i], queue: songs),
            onFavorite: () => state.toggleFavorite(songs[i]),
            onArtistTap: () => state.openArtistFromSong(songs[i]),
          ),
        ),
      ],
    );
  }

  Widget _header(AppState state) {
    return Row(
      children: [
        const Text('主页', style: MuyuTheme.title),
        const SizedBox(width: 16),
        Flexible(child: SourceSwitcher(state: state)),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.auto_awesome, size: 14),
          label: const Text('千语取歌', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ],
    );
  }

  /// 顶部卡片只展示接口真实返回的第一首歌/歌单/榜单，不再写死歌名。
  List<HomeCardSpec> _cards(AppState state) {
    final discover = state.discover;
    final now = state.homeSongs.isNotEmpty ? state.homeSongs.first : null;
    final newSong =
        discover.newSongs.isNotEmpty ? discover.newSongs.first : now;
    final heart = discover.radio.isNotEmpty ? discover.radio.first : now;
    final daily = _firstWhereOrNull(
        discover.playlists, (Playlist p) => p.id == 'a001');
    final hot = _firstWhereOrNull(
        discover.charts, (Playlist p) => p.name.contains('热歌'));
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
      ),
      HomeCardSpec(
        badge: 'November',
        title: '每日30首',
        subtitle: daily?.name ?? '点击打开每日推荐',
        gradient: MuyuColors.cardDaily,
        icon: Icons.calendar_month,
        action: 'daily',
        cover: daily?.cover,
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
        subtitle: hot?.name ?? '点击打开热歌榜',
        gradient: MuyuColors.cardHot,
        icon: Icons.whatshot,
        action: 'hot',
        cover: hot?.cover,
      ),
    ];
  }

  static T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T) test) {
    for (final value in values) {
      if (test(value)) return value;
    }
    return null;
  }

  Widget _searchField() {
    return SizedBox(
      width: 260,
      child: TextField(
        controller: _search,
        onSubmitted: (v) => widget.state.doSearch(v),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: '搜索音乐',
          hintStyle: const TextStyle(fontSize: 13, color: MuyuColors.inkMuted),
          prefixIcon: const Icon(Icons.search, size: 18, color: MuyuColors.inkMuted),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader() {
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Text('为你推荐', style: MuyuTheme.section),
          const Spacer(),
          Text('${state.homePage}/5', style: MuyuTheme.muted),
          TinyIconButton(
            icon: Icons.chevron_left,
            onTap: () {
              if (state.homePage > 1) {
                setState(() => state.homePage--);
              }
            },
          ),
          TinyIconButton(
            icon: Icons.chevron_right,
            onTap: () {
              if (state.homePage < 5) {
                setState(() => state.homePage++);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _playCard(AppState state, String action) async {
    switch (action) {
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
        final chart = _firstWhereOrNull(
            state.discover.charts, (Playlist p) => p.name.contains('热歌'));
        if (chart != null) {
          await state.openPlaylist(chart);
        } else {
          await state.loadHome();
        }
        return;
      case 'heart':
        final list = state.discover.radio.isNotEmpty
            ? state.discover.radio
            : state.homeSongs;
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        } else {
          await state.loadHome();
        }
        return;
      case 'new':
        final list = state.discover.newSongs.isNotEmpty
            ? state.discover.newSongs
            : state.homeSongs;
        if (list.isNotEmpty) {
          await state.play(list.first, queue: list);
        } else {
          await state.loadHome();
        }
        return;
      default:
        if (state.homeSongs.isNotEmpty) {
          await state.play(state.homeSongs.first, queue: state.homeSongs);
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
        _sourceChip(
          label: '华为音乐',
          icon: Icons.graphic_eq,
          color: MuyuColors.accent,
          selected: state.source == MusicSource.huawei,
          onTap: () => state.switchSource(MusicSource.huawei),
        ),
        const SizedBox(width: 8),
        _sourceChip(
          label: '网易云',
          icon: Icons.cloud_queue,
          color: const Color(0xFFEF4444),
          selected: state.source == MusicSource.netease,
          onTap: () => state.switchSource(MusicSource.netease),
        ),
        const SizedBox(width: 8),
        _sourceChip(
          label: '酷狗',
          icon: Icons.music_note,
          color: const Color(0xFF3B82F6),
          selected: state.source == MusicSource.kugou,
          onTap: () => state.switchSource(MusicSource.kugou),
        ),
        const SizedBox(width: 8),
        _sourceChip(
          label: 'QQ',
          icon: Icons.music_note,
          color: const Color(0xFFFACC15),
          selected: state.source == MusicSource.qq,
          onTap: () => state.switchSource(MusicSource.qq),
        ),
        ],
      ),
    );
  }

  Widget _sourceChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: selected
              ? Border.all(color: color.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
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
    return Container(
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
                    child: Icon(Icons.play_arrow,
                        size: 22, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _center(HomeCardSpec spec, Color fg) {
    switch (spec.action) {
      case 'daily':
        return Text('23',
            style: TextStyle(
                fontSize: 74,
                fontWeight: FontWeight.w300,
                color: fg.withValues(alpha: 0.92)));
      case 'heart':
        return Icon(Icons.favorite, size: 84, color: fg.withValues(alpha: 0.92));
      case 'radio':
        return Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: CoverArt(url: spec.cover, size: 104, radius: 10, seed: 0),
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
