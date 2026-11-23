import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 华为音乐「发现页 / 音乐厅」。
/// 结构事实来源：REA 对 Muyu.exe 的中文文案提取——
/// 「音乐厅」「排行榜」「推荐歌单」「歌单分类」「新歌推荐」「热歌速递」
/// 「心动电台」「发现刚刚抵达的新鲜旋律」「展示各平台的榜单和推荐歌单」。
/// 数据优先用已登录接口（首页 / 榜单 / 相似推荐），无数据时保留完整占位界面。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.state});

  final AppState state;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final PageController _banner = PageController(viewportFraction: 0.9);
  int _bannerIndex = 0;

  static const List<_BannerSpec> banners = <_BannerSpec>[
    _BannerSpec('发现刚刚抵达的新鲜旋律', '新歌推荐', '每日上新 · 听见好音乐',
        <Color>[Color(0xFF6C5CE7), Color(0xFFA29BFE)]),
    _BannerSpec('热歌速递', '本周热歌榜', '大家都在听', <Color>[Color(0xFFE8416A), Color(0xFFFF8A65)]),
    _BannerSpec('心动电台', '私人漫游', '懂你的音乐品味', <Color>[Color(0xFF0984E3), Color(0xFF74B9FF)]),
  ];

  static const List<_CategorySpec> categories = <_CategorySpec>[
    _CategorySpec('推荐歌单', Icons.recommend),
    _CategorySpec('排行榜', Icons.leaderboard),
    _CategorySpec('新歌', Icons.new_releases),
    _CategorySpec('心动电台', Icons.favorite),
    _CategorySpec('歌手', Icons.person),
    _CategorySpec('专辑', Icons.album),
    _CategorySpec('播客', Icons.podcasts),
    _CategorySpec('分类', Icons.category),
  ];

  @override
  void dispose() {
    _banner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.state.palette;
    final charts = widget.state.charts;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      children: [
        _titleRow(pal),
        const SizedBox(height: 16),
        _bannerCarousel(pal),
        const SizedBox(height: 22),
        _categories(pal),
        const SizedBox(height: 24),
        _sectionTitle('推荐歌单', '查看更多', pal),
        const SizedBox(height: 12),
        _playlistGrid(pal),
        const SizedBox(height: 24),
        _sectionTitle('新歌速递', '全部', pal),
        const SizedBox(height: 8),
        _horizontalSongs(_newSongs(), pal),
        const SizedBox(height: 22),
        _sectionTitle('排行榜', charts.length > 4 ? '更多榜单' : '全部', pal),
        const SizedBox(height: 12),
        _chartGrid(charts, pal),
        const SizedBox(height: 24),
        _radioCards(pal),
      ],
    );
  }

  Widget _titleRow(MuyuPalette pal) {
    return Row(
      children: [
        Text('音乐厅', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
        const Spacer(),
        const SourceBadge(compact: true),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.search, color: pal.text),
          onPressed: () {
            widget.state.tab = 1; // 切到搜索页
            widget.state.refresh();
          },
        ),
      ],
    );
  }

  Widget _bannerCarousel(MuyuPalette pal) {
    return SizedBox(
      height: 150,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _banner,
              itemCount: banners.length,
              onPageChanged: (i) => setState(() => _bannerIndex = i),
              itemBuilder: (context, i) {
                final b = banners[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: b.gradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(b.subtitle,
                            style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Text(b.title,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                        const SizedBox(height: 6),
                        Text(b.tagline,
                            style: const TextStyle(fontSize: 12, color: Colors.white70)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(banners.length, (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _bannerIndex ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _bannerIndex ? pal.accent : pal.muted.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                )),
          ),
        ],
      ),
    );
  }

  Widget _categories(MuyuPalette pal) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.1,
      children: categories.map((c) {
        return InkWell(
          onTap: () => _onCategory(c.label),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(c.icon, size: 26, color: pal.accent),
                const SizedBox(height: 8),
                Text(c.label, style: TextStyle(fontSize: 12, color: pal.text)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _onCategory(String label) {
    switch (label) {
      case '排行榜':
      case '推荐歌单':
      case '分类':
        widget.state.tab = 2; // 唱片架（歌单/榜单聚合）
        break;
      case '歌手':
      case '专辑':
        widget.state.tab = 2;
        break;
      default:
        widget.state.tab = 0; // 首页推荐
    }
    widget.state.refresh();
  }

  Widget _sectionTitle(String title, String action, MuyuPalette pal) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
        const Spacer(),
        Text(action, style: TextStyle(fontSize: 12, color: pal.muted)),
      ],
    );
  }

  Widget _playlistGrid(MuyuPalette pal) {
    final lists = widget.state.playlists;
    final items = lists.take(6).toList();
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.isEmpty ? 6 : items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = items.isNotEmpty ? items[i] : null;
          return SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CoverArt(
                    url: p?.cover,
                    size: 112,
                    radius: 12,
                    seed: i + 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p?.name ?? _demoPlaylistNames[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: pal.text),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const List<String> _demoPlaylistNames = <String>[
    '华语流行精选', '深夜治愈系', '国风雅集', '运动燃脂', '经典老歌', '轻音乐放松',
  ];

  List<Song> _newSongs() {
    final all = widget.state.homeSongs;
    return all.isEmpty ? _DiscoverDemo.songs : all.take(8).toList();
  }

  Widget _horizontalSongs(List<Song> songs, MuyuPalette pal) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: songs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = songs[i];
          return SizedBox(
            width: 220,
            child: InkWell(
              onTap: () => widget.state.audio.playSong(s, list: songs),
              child: Row(
                children: [
                  CoverArt(url: s.cover, size: 60, radius: 8, seed: i),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.text)),
                        const SizedBox(height: 4),
                        Text(s.artistText, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: pal.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chartGrid(List<Playlist> charts, MuyuPalette pal) {
    final names = charts.isEmpty
        ? const <String>['飙升榜', '新歌榜', '热歌榜', '原创榜', '华语榜', '欧美榜']
        : charts.map((p) => p.name).toList();
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: List<Widget>.generate(names.length.clamp(0, 6), (i) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                MuyuColors.cardHeart[0].withValues(alpha: 0.9),
                MuyuColors.cardDaily[1],
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text('${i + 1}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white70)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(names[i], maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _radioCards(MuyuPalette pal) {
    return Row(
      children: [
        Expanded(child: _radioCard('心动电台', '根据你的喜好推荐', Icons.favorite, MuyuColors.cardHeart, pal)),
        const SizedBox(width: 12),
        Expanded(child: _radioCard('私人漫游', ' endless mix', Icons.explore, MuyuColors.cardDaily, pal)),
      ],
    );
  }

  Widget _radioCard(String title, String sub, IconData icon, List<Color> grad, MuyuPalette pal) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: grad, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
              Text(sub, style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BannerSpec {
  const _BannerSpec(this.title, this.subtitle, this.tagline, this.gradient);
  final String title;
  final String subtitle;
  final String tagline;
  final List<Color> gradient;
}

class _CategorySpec {
  const _CategorySpec(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _DiscoverDemo {
  static final List<Song> songs = <Song>[
    Song(id: 'd-1', name: '发现新旋律', artists: const ['华为音乐'],
        qualities: const {AudioQuality.standard, AudioQuality.hiRes}),
    Song(id: 'd-2', name: '热歌速递', artists: const ['华语流行']),
    Song(id: 'd-3', name: '心动时刻', artists: const ['治愈系']),
  ];
}
