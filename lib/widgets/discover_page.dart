import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 华为音乐「音乐厅 / 发现页」。
///
/// 界面结构来自 REA 对 Muyu.exe 的文案与符号取证；
/// 所有内容（活动图 / 新歌 / 歌单 / 榜单 / 电台）都来自真实接口。
/// 接口没返回数据就明确显示空状态，绝不拿假歌曲、假歌单名填充。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key, required this.state});

  final AppState state;

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final PageController _banner = PageController(viewportFraction: 0.9);
  int _bannerIndex = 0;

  static const List<_CategorySpec> categories = <_CategorySpec>[
    _CategorySpec('推荐歌单', Icons.recommend, 2),
    _CategorySpec('排行榜', Icons.leaderboard, 2),
    _CategorySpec('新歌', Icons.new_releases, 0),
    _CategorySpec('我的收藏', Icons.favorite, 3),
    _CategorySpec('歌手', Icons.person, 2),
    _CategorySpec('专辑', Icons.album, 2),
    _CategorySpec('播客', Icons.podcasts, 2),
    _CategorySpec('分类', Icons.category, 2),
  ];

  @override
  void dispose() {
    _banner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = widget.state.palette;
    final d = widget.state.discover;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      children: [
        _titleRow(pal),
        if (widget.state.loading)
          const LinearProgressIndicator(minHeight: 2),
        if (d.banners.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _bannerCarousel(d.banners, pal),
        ],
        const SizedBox(height: 16),
        _categories(pal),
        const SizedBox(height: 24),
        _sectionTitle('我的歌单', d.playlists.isEmpty ? '登录后可见' : '共 ${d.playlists.length} 个', pal),
        const SizedBox(height: 12),
        d.playlists.isEmpty
            ? _empty('登录后可见歌单', pal)
            : _playlistGrid(d.playlists, pal),
        const SizedBox(height: 24),
        _sectionTitle('最近播放', d.newSongs.isEmpty ? '暂无数据' : '共 ${d.newSongs.length} 首', pal),
        const SizedBox(height: 8),
        d.newSongs.isEmpty
            ? _empty('暂无最近播放，登录后自动同步', pal)
            : _horizontalSongs(d.newSongs.take(8).toList(), pal),
        const SizedBox(height: 22),
        _sectionTitle('排行榜', d.charts.isEmpty ? '暂无数据' : '点击榜单加载歌曲', pal),
        const SizedBox(height: 12),
        d.charts.isEmpty
            ? _empty('榜单接口未返回数据', pal)
            : _chartGrid(d.charts, pal),
        if (widget.state.activeChartId != null) ...<Widget>[
          const SizedBox(height: 12),
          _sectionTitle('榜单歌曲', widget.state.chartSongs.isEmpty ? '暂无数据' : '共 ${widget.state.chartSongs.length} 首', pal),
          const SizedBox(height: 8),
          widget.state.chartSongs.isEmpty
              ? _empty('榜单详情未返回歌曲', pal)
              : _horizontalSongs(widget.state.chartSongs.take(20).toList(), pal),
        ],
        const SizedBox(height: 24),
        _sectionTitle('我的收藏', widget.state.favorites.isEmpty ? '登录后可见' : '共 ${widget.state.favorites.length} 首', pal),
        const SizedBox(height: 8),
        widget.state.favorites.isEmpty
            ? _empty('登录后可见收藏歌曲', pal)
            : _horizontalSongs(widget.state.favorites.take(10).toList(), pal),
      ],
    );
  }

  Widget _titleRow(MuyuPalette pal) {
    return Row(
      children: [
        Text('音乐厅', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
        const Spacer(),
        const SourceBadge(compact: true),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新发现页',
          onPressed: () => widget.state.loadHome(),
        ),
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

  Widget _bannerCarousel(List banners, MuyuPalette pal) {
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        b.imageUrl == null
                            ? Container(color: pal.surface)
                            : Image.network(
                                b.imageUrl.toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(color: pal.surface),
                              ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[Colors.transparent, Color(0xCC000000)],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              if (b.subtitle.isNotEmpty)
                                Text(b.subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ),
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
          onTap: () {
            widget.state.tab = c.tab;
            widget.state.refresh();
          },
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

  Widget _sectionTitle(String title, String action, MuyuPalette pal) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
        const Spacer(),
        Text(action, style: TextStyle(fontSize: 12, color: pal.muted)),
      ],
    );
  }

  Widget _empty(String message, MuyuPalette pal) {
    return InkWell(
      onTap: () => widget.state.loadHome(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_outlined, size: 22, color: pal.muted),
            const SizedBox(height: 6),
            Text(message, style: TextStyle(fontSize: 12, color: pal.muted)),
            const SizedBox(height: 2),
            const Text('点击刷新重试', style: TextStyle(fontSize: 11, color: MuyuColors.accent)),
          ],
        ),
      ),
    );
  }

  Widget _playlistGrid(List<Playlist> lists, MuyuPalette pal) {
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: lists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final p = lists[i];
          return SizedBox(
            width: 112,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: CoverArt(
                    url: p.cover,
                    size: 112,
                    radius: 12,
                    seed: i + 2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  p.name.isEmpty ? '未命名歌单' : p.name,
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
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.0,
      children: List<Widget>.generate(charts.length.clamp(0, 9), (i) {
        final p = charts[i];
        return InkWell(
          onTap: () => widget.state.loadChart(p.id),
          borderRadius: BorderRadius.circular(12),
          child: Container(
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
                  child: Text(p.name.isEmpty ? '未命名榜单' : p.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _CategorySpec {
  const _CategorySpec(this.label, this.icon, this.tab);
  final String label;
  final IconData icon;
  final int tab;
}
