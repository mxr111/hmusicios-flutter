import 'package:flutter/material.dart';

import '../models.dart';
import '../models_home.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'home_page.dart' show SourceSwitcher;

/// 网易云独立首页：红白配色 + 轮播 / 金刚入口 / 推荐歌单流 / 独家放送 / 推荐歌曲流。
/// 与华为主页分开，数据全部来自 NeteaseApi.homeFeed() 的真实接口。
class NeteaseHomePage extends StatefulWidget {
  const NeteaseHomePage({
    super.key,
    required this.state,
    this.autoLoad = true,
  });

  final AppState state;

  /// 测试或已有缓存场景可关闭首次自动加载，避免无谓网络请求。
  final bool autoLoad;

  @override
  State<NeteaseHomePage> createState() => _NeteaseHomePageState();
}

class _NeteaseHomePageState extends State<NeteaseHomePage> {
  static const Color neteaseRed = Color(0xFFE60026);

  final TextEditingController _search = TextEditingController();
  final PageController _banner = PageController(viewportFraction: 0.88);
  final ScrollController _scroll = ScrollController();
  int _bannerIndex = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    if (widget.autoLoad && s.neteaseHome.isEmpty && !s.neteaseHomeLoading) {
      s.loadNeteaseHome();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _banner.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final data = s.neteaseHome;
    final songs = AppState.mergeSongs(<List<Song>>[
      data.dailySongs,
      data.newSongs,
      data.radioSongs,
    ]);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
      itemCount: 5 + songs.length,
      itemBuilder: (context, index) {
        switch (index) {
          case 0:
            return _header(s);
          case 1:
            return _searchField();
          case 2:
            return data.banners.isEmpty
                ? const SizedBox.shrink()
                : _banners(data.banners);
          case 3:
            return _entries(s, data);
          case 4:
            return _playlistSection(s, data);
          default:
            return _songRow(s, songs[index - 5], songs, index - 5);
        }
      },
    );
  }

  Widget _header(AppState s) {
    return Row(
      children: [
        const Text('主页', style: MuyuTheme.title),
        const SizedBox(width: 14),
        SourceSwitcher(state: s),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: neteaseRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_queue, size: 14, color: neteaseRed),
              SizedBox(width: 5),
              Text('网易云音乐',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: neteaseRed)),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: '刷新网易云推荐流',
          onPressed: s.loadNeteaseHome,
        ),
      ],
    );
  }

  Widget _searchField() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 12),
      child: SizedBox(
        width: 320,
        child: TextField(
          controller: _search,
          onSubmitted: widget.state.doSearch,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: '搜索网易云音乐',
            hintStyle: const TextStyle(fontSize: 13, color: MuyuColors.inkMuted),
            prefixIcon: const Icon(Icons.search, size: 18, color: neteaseRed),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _banners(List<NeteaseHomeBanner> banners) {
    return RepaintBoundary(
      child: Column(
        children: [
          SizedBox(
            height: 152,
            child: PageView.builder(
              controller: _banner,
              itemCount: banners.length,
              onPageChanged: (i) => setState(() => _bannerIndex = i),
              itemBuilder: (context, i) => _BannerCard(banner: banners[i]),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(banners.length.clamp(0, 12), (i) {
              final active = i == _bannerIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? neteaseRed : MuyuColors.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _entries(AppState s, NeteaseHomeData data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          _Entry(
            icon: Icons.calendar_today_outlined,
            label: '每日推荐',
            color: neteaseRed,
            onTap: () => playSongFromList(
              context,
              s,
              data.dailySongs.first,
              data.dailySongs,
            ),
            enabled: data.dailySongs.isNotEmpty,
          ),
          _Entry(
            icon: Icons.radio,
            label: '私人 FM',
            color: const Color(0xFFF59E0B),
            onTap: () => playSongFromList(
              context,
              s,
              data.radioSongs.first,
              data.radioSongs,
            ),
            enabled: data.radioSongs.isNotEmpty,
          ),
          _Entry(
            icon: Icons.auto_awesome,
            label: '推荐新歌',
            color: const Color(0xFF8B5CF6),
            onTap: () => playSongFromList(
              context,
              s,
              data.newSongs.first,
              data.newSongs,
            ),
            enabled: data.newSongs.isNotEmpty,
          ),
          _Entry(
            icon: Icons.playlist_play,
            label: '推荐歌单',
            color: const Color(0xFF06B6D4),
            onTap: () => _scroll.animateTo(
              280,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOut,
            ),
            enabled: data.playlists.isNotEmpty,
          ),
        ],
      ),
    );
  }

  Widget _playlistSection(AppState s, NeteaseHomeData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('推荐歌单', style: MuyuTheme.section),
            const Spacer(),
            if (s.neteaseHasMorePlaylists)
              TextButton.icon(
                onPressed: s.neteaseHomeLoading ? null : s.loadMoreNeteasePlaylists,
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('换一批', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        if (s.neteaseHomeLoading && data.playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (s.neteaseHomeError != null)
          StatePanel(
            message: s.neteaseHomeError!,
            onRetry: s.loadNeteaseHome,
            actionLabel: '重试',
          ),
        if (data.playlists.isEmpty && !s.neteaseHomeLoading)
          StatePanel(
            message: '推荐歌单接口未返回数据，请检查网络后重试。',
            onRetry: s.loadNeteaseHome,
            actionLabel: '重试',
          ),
        if (data.playlists.isNotEmpty)
          SizedBox(
            height: 154,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _PlaylistCard(
                playlist: data.playlists[i],
                onTap: () => s.openPlaylist(data.playlists[i]),
                seed: i,
              ),
            ),
          ),
        if (data.specials.isNotEmpty) ...<Widget>[
          const SizedBox(height: 22),
          const Text('独家放送', style: MuyuTheme.section),
          const SizedBox(height: 10),
          SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.specials.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _SpecialCard(
                special: data.specials[i],
                seed: i,
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            const Text('推荐流', style: MuyuTheme.section),
            const Spacer(),
            Text(
              s.isLoggedIn ? '个性化推荐' : '公开推荐 · 登录后可个性化',
              style: const TextStyle(fontSize: 11, color: MuyuColors.inkMuted),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _songRow(AppState s, Song song, List<Song> queue, int index) {
    return SongRow(
      song: song,
      index: index,
      onPlay: () => playSongFromList(context, s, song, queue),
      onFavorite: song.id.isEmpty ? null : () => s.toggleFavorite(song),
      onArtistTap: song.id.isEmpty ? null : () => s.openArtistFromSong(song),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});

  final NeteaseHomeBanner banner;

  @override
  Widget build(BuildContext context) {
    final dpr = (MediaQuery.devicePixelRatioOf(context).clamp(1.0, 3.0));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banner.imageUrl != null)
              Image.network(
                banner.imageUrl.toString(),
                fit: BoxFit.cover,
                cacheWidth: (900 * dpr).round(),
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFFFCE8EB)),
                ),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFFCE8EB)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, Color(0xB3000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty)
                    Text(
                      banner.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    required this.enabled,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 12, color: MuyuColors.ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.seed,
  });

  final Playlist playlist;
  final VoidCallback onTap;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 112,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverArt(url: playlist.cover, size: 112, radius: 12, seed: seed + 2),
              const SizedBox(height: 6),
              Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: MuyuColors.ink),
              ),
              if (playlist.songCount > 0)
                Text('${playlist.songCount} 首',
                    style: const TextStyle(fontSize: 10, color: MuyuColors.inkMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpecialCard extends StatelessWidget {
  const _SpecialCard({required this.special, required this.seed});

  final NeteaseHomeSpecial special;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 220,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          child: Row(
            children: [
              CoverArt(url: special.cover, size: 72, radius: 8, seed: seed + 1),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(special.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: MuyuColors.ink)),
                    if (special.subtitle.isNotEmpty)
                      Text(special.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, color: MuyuColors.inkMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
