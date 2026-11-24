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

  static final List<HomeCardSpec> cards = <HomeCardSpec>[
    const HomeCardSpec(
      badge: '♫  Music FM',
      title: '现在就听',
      subtitle: '后来的我们 · 五月天',
      gradient: MuyuColors.cardNow,
      icon: Icons.radio,
      action: 'radio',
    ),
    const HomeCardSpec(
      badge: 'November',
      title: '每日30首',
      subtitle: '不能说的秘密 · 周杰伦',
      gradient: MuyuColors.cardDaily,
      icon: Icons.calendar_month,
      action: 'daily',
    ),
    const HomeCardSpec(
      badge: '♥',
      title: '心动模式',
      subtitle: '想见你想见你想见你',
      gradient: MuyuColors.cardHeart,
      icon: Icons.favorite,
      action: 'heart',
    ),
    const HomeCardSpec(
      badge: '♫  New',
      title: '新歌推荐',
      subtitle: '昨天，今天：莫文蔚',
      gradient: MuyuColors.cardNew,
      icon: Icons.new_releases_outlined,
      action: 'new',
    ),
    const HomeCardSpec(
      badge: '热歌速递',
      title: '热歌速递',
      subtitle: 'DeepSeek',
      gradient: MuyuColors.cardHot,
      icon: Icons.whatshot,
      action: 'hot',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // 首页列表只显示真实接口数据，不再用硬编码歌曲冒充（用户明确要求）。
    final songs = state.homeSongs;

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
              onPlay: () => _playCard(cards[i].action),
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
        SourceSwitcher(state: state),
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

  void _playCard(String action) => widget.state.playCard(action);
}

/// 顶部音源切换：截图里「华为音乐」蓝色胶囊 + 酷狗 K / QQ音乐 / 网易云 圆标。
/// 按需求只接通华为音乐，其余置灰提示。
class SourceSwitcher extends StatelessWidget {
  const SourceSwitcher({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Row(
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
        ...<_SourceDotData>[
          const _SourceDotData('K', Color(0xFF3B82F6)),
          const _SourceDotData('Q', Color(0xFFFACC15)),
        ].map((d) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _SourceDot(data: d),
            )),
      ],
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

class _SourceDotData {
  const _SourceDotData(this.label, this.color);
  final String label;
  final Color color;
}

class _SourceDot extends StatelessWidget {
  const _SourceDot({required this.data});
  final _SourceDotData data;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '该音源未接入（本项目实现华为音乐 + 网易云音乐）',
      child: Opacity(
        opacity: 0.45,
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: data.color.withValues(alpha: 0.28),
            shape: BoxShape.circle,
          ),
          child: Text(data.label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: data.color.withValues(alpha: 0.9))),
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
          child: CoverArt(size: 104, radius: 10, seed: 0),
        );
      case 'new':
        return Padding(
          padding: const EdgeInsets.only(bottom: 26),
          child: CoverArt(size: 100, radius: 6, seed: 3),
        );
      default:
        return Icon(spec.icon, size: 72, color: fg.withValues(alpha: 0.85));
    }
  }
}
