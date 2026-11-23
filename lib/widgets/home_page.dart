import 'package:flutter/material.dart';

import '../models.dart';
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

  /// 截图里出现的真实歌名，作为无网络时的占位数据
  static List<Song> demoSongs() => <Song>[
        Song(id: 'demo-1', name: '夜的第七章', artists: const ['周杰伦', '潘儿'],
            qualities: const {AudioQuality.standard, AudioQuality.hiRes}),
        Song(id: 'demo-2', name: '江南', artists: const ['林俊杰'],
            qualities: const {AudioQuality.standard, AudioQuality.lossless}),
        Song(id: 'demo-3', name: '后来的我们', artists: const ['五月天'],
            qualities: const {AudioQuality.standard, AudioQuality.hiRes}),
        Song(id: 'demo-4', name: '晴天', artists: const ['周杰伦']),
        Song(id: 'demo-5', name: '不能说的秘密', artists: const ['周杰伦']),
        Song(id: 'demo-6', name: '想见你想见你想见你', artists: const ['八三夭'],
            qualities: const {AudioQuality.standard, AudioQuality.lossless}),
      ];

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final online = state.homeSongs.isNotEmpty;
    final songs = online ? state.homeSongs : demoSongs();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 108),
      children: [
        _header(),
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
              onPlay: () => _playCard(cards[i].action, songs),
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
            message: '尚未登录华为账号。当前展示的是离线占位界面；'
                '登录并补齐请求签名后即可加载真实曲库。',
          ),
        ...List<Widget>.generate(
          songs.length,
          (i) => SongRow(
            song: songs[i],
            index: i,
            onPlay: () => state.play(songs[i], queue: songs),
            onFavorite: () {
              setState(() {
                songs[i].favorite = !songs[i].favorite;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        const Text('主页', style: MuyuTheme.title),
        const SizedBox(width: 16),
        const SourceSwitcher(),
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

  void _playCard(String action, List<Song> songs) {
    final state = widget.state;
    if (songs.isEmpty) return;
    final start = switch (action) {
      'daily' => 1 % songs.length,
      'heart' => 2 % songs.length,
      'new' => 3 % songs.length,
      'hot' => 4 % songs.length,
      _ => 0,
    };
    state.play(songs[start], queue: songs);
  }
}

/// 顶部音源切换：截图里「华为音乐」蓝色胶囊 + 酷狗 K / QQ音乐 / 网易云 圆标。
/// 按需求只接通华为音乐，其余置灰提示。
class SourceSwitcher extends StatelessWidget {
  const SourceSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: MuyuColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 13, color: MuyuColors.accent),
              SizedBox(width: 5),
              Text('华为音乐',
                  style: TextStyle(
                      fontSize: 11,
                      color: MuyuColors.accent,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ...<_SourceDotData>[
          const _SourceDotData('K', Color(0xFF3B82F6)),
          const _SourceDotData('Q', Color(0xFFFACC15)),
          const _SourceDotData('云', Color(0xFFEF4444)),
        ].map((d) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _SourceDot(data: d),
            )),
      ],
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
      message: '该音源未接入（本项目仅实现华为音乐）',
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
