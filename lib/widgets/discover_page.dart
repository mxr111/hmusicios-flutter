import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 音乐厅 = 华为音乐的榜单中心。
///
/// 原版「音乐厅」不是通用发现页，而是华为音乐的榜单集合：
/// 顶部推荐歌单，下面是热歌榜 / 新歌榜 / 人气飙升榜等；点任意榜单
/// 进入该榜单的歌单详情。所有数据来自 `page/detail/all` 的真实
/// `contentType=4/7`，空数据只显示空状态，不造假。
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final pal = state.palette;
    final data = state.discover;
    final wide = MediaQuery.of(context).size.width > 900;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      children: [
        _titleRow(context, pal),
        if (state.loading) const LinearProgressIndicator(minHeight: 2),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: StatePanel(
              message: state.error!,
              onRetry: state.loadHome,
              actionLabel: '重试',
            ),
          ),
        const SizedBox(height: 18),
        _sectionTitle(
          '推荐歌单',
          data.playlists.isEmpty ? '暂无数据' : '共 ${data.playlists.length} 个',
          pal,
        ),
        const SizedBox(height: 12),
        if (data.playlists.isEmpty)
          _empty('华为接口未返回推荐歌单', pal)
          else
          _playlistRow(context, data.playlists, pal),
        const SizedBox(height: 26),
        _sectionTitle(
          '华为音乐榜单',
          data.charts.isEmpty ? '暂无数据' : '点击榜单进入歌单',
          pal,
        ),
        const SizedBox(height: 12),
        if (data.charts.isEmpty)
          _empty('华为接口未返回榜单', pal)
        else
          _chartGrid(context, data.charts, pal, wide),
      ],
    );
  }

  Widget _titleRow(BuildContext context, MuyuPalette pal) {
    return Row(
      children: [
        Text('音乐厅',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: pal.text)),
        const SizedBox(width: 10),
        const SourceBadge(compact: true),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新榜单',
          onPressed: state.refreshHome,
        ),
        IconButton(
          icon: Icon(Icons.search, color: pal.text),
          tooltip: '搜索',
          onPressed: () {
            state.selectTab(1);
          },
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String action, MuyuPalette pal) {
    return Row(
      children: [
        Text(title,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: pal.text)),
        const Spacer(),
        Text(action, style: TextStyle(fontSize: 12, color: pal.muted)),
      ],
    );
  }

  Widget _playlistRow(
    BuildContext context,
    List<Playlist> lists,
    MuyuPalette pal,
  ) {
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: lists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final p = lists[i];
          return SizedBox(
            width: 132,
            child: InkWell(
              onTap: () => _openPlaylist(context, p),
              borderRadius: BorderRadius.circular(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CoverArt(
                      url: p.cover,
                      size: 132,
                      radius: 12,
                      seed: i,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    p.name.isEmpty ? '未命名歌单' : p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: pal.text),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chartGrid(
    BuildContext context,
    List<Playlist> charts,
    MuyuPalette pal,
    bool wide,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: wide ? 4 : 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: wide ? 2.2 : 1.9,
      ),
      itemCount: charts.length,
      itemBuilder: (context, i) {
        final chart = charts[i];
        return InkWell(
          onTap: () => _openChart(context, chart),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: pal.surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CoverArt(url: chart.cover, size: 58, radius: 10, seed: i + 3),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chart.name.isEmpty ? '未命名榜单' : chart.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: pal.text),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chart.songCount > 0 ? '${chart.songCount} 首' : '进入榜单',
                        maxLines: 1,
                        style: TextStyle(fontSize: 11, color: pal.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: pal.muted),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPlaylist(BuildContext context, Playlist playlist) async {
    await state.openPlaylist(playlist);
    if (!context.mounted) return;
    if (state.playlistSongsList.isEmpty) {
      _showMessage(context, '歌单「${playlist.name}」未返回歌曲，请稍后重试');
    }
  }

  /// 榜单必须走 chart 取歌路径，避免把榜单 ID 当普通歌单请求导致“能打开但无歌”。
  Future<void> _openChart(BuildContext context, Playlist chart) async {
    final normalized = Playlist(
      id: chart.id,
      name: chart.name,
      cover: chart.cover,
      songCount: chart.songCount,
      kind: 'chart',
    );
    await state.openPlaylist(normalized);
    if (!context.mounted) return;
    if (state.playlistSongsList.isEmpty) {
      _showMessage(context, '榜单「${chart.name}」未返回歌曲，请稍后重试');
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _empty(String message, MuyuPalette pal) {
    return InkWell(
      onTap: state.refreshHome,
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
            const Text('点击刷新重试',
                style: TextStyle(fontSize: 11, color: MuyuColors.accent)),
          ],
        ),
      ),
    );
  }
}
