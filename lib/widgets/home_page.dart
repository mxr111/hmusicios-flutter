import 'package:flutter/material.dart';

import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// 主页：顶部标题/华为音乐标识/搜索 + 5 张推荐卡 + 「为你推荐」5 首/页 +
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
  int _cardPage = 1;

  /// 首页卡片的本地预览分页：只按真实列表长度切当前预览歌，不发请求。
  static const int _cardPreviewPageSize = 5;

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
    final cardPageInfo = _cardPageInfo(state);
    final cardPage = _cardPage.clamp(1, cardPageInfo.pageCount);
    final cards = _cards(state, cardPage);
    final hasHomeData =
        cardPageInfo.hasData ||
        songs.isNotEmpty ||
        playlists.isNotEmpty ||
        charts.isNotEmpty;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          _header(context, state),
          const SizedBox(height: 16),
          _heroCards(context, cards),
          _cardPageBar(cardPageInfo, cardPage, hasHomeData),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionRow(
                  title: '为你推荐',
                  trailing: songs.isEmpty ? '暂无数据' : '第 $page / $pageCount 页',
                  onTitleTap: () =>
                      _openSectionPage(context, 'recommended', '为你推荐'),
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
                  const StatePanel(
                    message: '尚未登录华为账号。请到「我的」扫码登录后加载真实曲库。',
                  )
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
                      onPlay: () =>
                          playSongFromList(context, state, song, songs),
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
                  onTitleTap: () => _openCollectionPage(context, charts: false),
                ),
                const SizedBox(height: 12),
                if (playlists.isEmpty)
                  StatePanel(
                    message: '暂无推荐歌单',
                    onRetry: () => state.refreshHome(force: true),
                    actionLabel: '重试',
                  )
                else
                  _playlistStrip(context, playlists),
                const SizedBox(height: 26),
                _sectionRow(
                  title: '热歌榜',
                  trailing: charts.isEmpty
                      ? '暂无数据'
                      : '第 $chartPage / $chartCount 页',
                  onTitleTap: () => _openCollectionPage(context, charts: true),
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
                  _hotChartPanel(context, charts[chartPage - 1]),
              ],
            ),
          ),
        ],
      ),
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
              const SourceBadge(
                key: ValueKey<String>('home-source-badge'),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: '刷新主页',
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

  Widget _heroCards(BuildContext context, List<HomeCardSpec> cards) {
    return SizedBox(
      height: MuyuDims.cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final card = cards[i];
          // REA 证据：沐语「现在就听」点击卡片直接起播独立电台队列，
          // 不先打开详情页；其余四张卡打开各自板块的分页详情。
          final onTap = card.action == 'radio'
              ? () => _playCard(context, card.action)
              : () => _openSectionPage(context, card.action, card.title);
          return HomeCard(
            spec: card,
            onTap: onTap,
            onPlay: () => _playCard(context, card.action),
          );
        },
      ),
    );
  }

  Widget _cardPageBar(_HomeCardPageInfo info, int page, bool hasHomeData) {
    final pal = widget.state.palette;
    if (!hasHomeData) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
        child: StatePanel(
          message: '首页推荐板块暂未返回数据。只有点击「重试」才会重新加载。',
          onRetry: () => widget.state.refreshHome(force: true),
          actionLabel: '重试',
        ),
      );
    }
    // 五张卡本身都没有预览歌时不显示页码；不要伪装出可切换的“页”。
    if (!info.hasData) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Row(
        children: [
          Text(
            '第 $page / ${info.pageCount} 页',
            style: TextStyle(fontSize: 12, color: pal.muted),
          ),
          if (widget.state.loading)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: page > 1 ? () => _changeCardPage(page - 1) : null,
            child: const Text('上一页'),
          ),
          TextButton(
            onPressed: page < info.pageCount
                ? () => _changeCardPage(page + 1)
                : null,
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }

  /// 只切换本地页码；禁止在这里 force 刷新或发网络请求。
  void _changeCardPage(int target) {
    final pageCount = _cardPageInfo(widget.state).pageCount;
    setState(() => _cardPage = target.clamp(1, pageCount));
  }

  /// 页码来自当前首页五张卡各自真实列表长度，而不是固定 `% 5`。
  _HomeCardPageInfo _cardPageInfo(AppState state) {
    final lengths = <int>[
      state.discover.listen.length,
      state.discover.daily.length,
      state.discover.heart.length,
      state.discover.newSongs.length,
      state.discover.hot.length,
    ];
    var maxLength = 0;
    for (final length in lengths) {
      if (length > maxLength) maxLength = length;
    }
    if (maxLength == 0) {
      return const _HomeCardPageInfo(pageCount: 1, hasData: false);
    }
    return _HomeCardPageInfo(
      pageCount: (maxLength + _cardPreviewPageSize - 1) ~/
          _cardPreviewPageSize,
      hasData: true,
    );
  }

  Widget _sectionRow({
    required String title,
    required String trailing,
    VoidCallback? onTitleTap,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
    String? nextTooltip,
  }) {
    final pal = widget.state.palette;
    final titleWidget = Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: pal.text,
      ),
    );
    return Row(
      children: [
        if (onTitleTap == null)
          titleWidget
        else
          Tooltip(
            message: '分页查看全部',
            child: InkWell(
              onTap: onTitleTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleWidget,
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 17, color: pal.muted),
                  ],
                ),
              ),
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

  Widget _playlistStrip(BuildContext context, List<Playlist> playlists) {
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
              onTap: () => _openPlaylist(playlist),
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

  Widget _hotChartPanel(BuildContext context, Playlist chart) {
    final pal = widget.state.palette;
    return InkWell(
      onTap: () => _openChart(chart),
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

  Future<void> _openPlaylist(Playlist playlist) async {
    await widget.state.openPlaylist(playlist);
  }

  /// 首页热歌榜必须按 chart 路径加载；不把榜单当普通收藏歌单请求。
  Future<void> _openChart(Playlist chart) async {
    final normalized = Playlist(
      id: chart.id,
      name: chart.name,
      cover: chart.cover,
      songCount: chart.songCount,
      kind: 'chart',
    );
    await widget.state.openPlaylist(normalized);
  }

  void _openSectionPage(BuildContext context, String action, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            HomeSectionPage(state: widget.state, action: action, title: title),
      ),
    );
  }

  void _openCollectionPage(BuildContext context, {required bool charts}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HomeCollectionPage(state: widget.state, charts: charts),
      ),
    );
  }

  /// 卡片上的播放按钮：直接按独立队列起播，不打开详情页。
  Future<void> _playCard(BuildContext context, String action) async {
    final state = widget.state;
    await state.playCard(action);
    if (!context.mounted) return;
    final message = state.error;
    if (message == null || message.isEmpty || state.onError != null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('播放失败：$message')));
  }

  /// 五张卡分别绑定首页真实栏目：
  /// 现在就听（listen）/ 每日30首 / 心动模式 / 新歌推荐 / 热歌速递。
  List<HomeCardSpec> _cards(AppState state, int page) {
    final discover = state.discover;
    final listen = discover.listen;
    final dailySongs = discover.daily;
    final newSongs = discover.newSongs;
    final heartSongs = discover.heart;
    final hotSongs = discover.hot;
    final offset = (page - 1) * _cardPreviewPageSize;
    Song? pick(List<Song> list) =>
        list.isEmpty ? null : list[offset % list.length];
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
}

class _HomeCardPageInfo {
  const _HomeCardPageInfo({required this.pageCount, required this.hasData});

  final int pageCount;
  final bool hasData;
}

List<Song> _homeSectionSongs(AppState state, String action) {
  return switch (action) {
    'radio' => state.discover.listen,
    'daily' => state.discover.daily,
    'heart' => state.discover.heart,
    'new' => state.discover.newSongs,
    'hot' => state.discover.hot,
    'recommended' => state.discover.recommended,
    _ => const <Song>[],
  };
}

/// 首页 5 张卡 / 「为你推荐」的分页详情页。
///
/// 卡片点击只负责打开这一页，不再根据空数据直接弹提示；空板块显示空态
/// 与显式重试按钮，重试才允许触发 [AppState.refreshHome]。
class HomeSectionPage extends StatelessWidget {
  const HomeSectionPage({
    super.key,
    required this.state,
    required this.action,
    required this.title,
  });

  final AppState state;
  final String action;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final songs = _homeSectionSongs(state, action);
        return Scaffold(
          backgroundColor: state.palette.base,
          appBar: AppBar(
            title: Text(title, style: TextStyle(color: state.palette.text)),
            backgroundColor: Colors.transparent,
            foregroundColor: state.palette.text,
            elevation: 0,
          ),
          body: songs.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    if (state.loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    StatePanel(
                      message: '「$title」独立板块暂未返回歌曲。其他推荐板块的数据不会被回填到这里。',
                      onRetry: () => state.refreshHome(force: true),
                      actionLabel: '重试',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '可以返回首页切换其他推荐板块；只有点击「重试」才会重新加载。',
                      style: TextStyle(
                        fontSize: 12,
                        color: state.palette.muted,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          Text(
                            '${songs.length} 首 · 分页浏览',
                            style: TextStyle(
                              fontSize: 12,
                              color: state.palette.muted,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => playSongFromList(
                              context,
                              state,
                              songs.first,
                              songs,
                            ),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: const Text('播放全部'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PaginatedSongList(
                        songs: songs,
                        resetKey: '$action:${songs.length}',
                        onPlay: (song) =>
                            playSongFromList(context, state, song, songs),
                        onFavorite: state.toggleFavorite,
                        onArtistTap: (song) => _openArtist(context, song),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// 歌手详情是 AppShell 内的覆盖层；当前页是路由，先退出再打开，
  /// 避免用户点了歌手却只更新了被路由遮住的下层页面。
  void _openArtist(BuildContext context, Song song) {
    Navigator.of(context).pop();
    state.openArtistFromSong(song);
  }
}

/// 「推荐歌单 / 热歌榜」的分页集合页：从首页标题进入，点条目打开详情。
class HomeCollectionPage extends StatelessWidget {
  const HomeCollectionPage({
    super.key,
    required this.state,
    required this.charts,
  });

  final AppState state;
  final bool charts;

  @override
  Widget build(BuildContext context) {
    final title = charts ? '热歌榜' : '推荐歌单';
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final items = charts ? state.discover.charts : state.discover.playlists;
        return Scaffold(
          backgroundColor: state.palette.base,
          appBar: AppBar(
            title: Text(title, style: TextStyle(color: state.palette.text)),
            backgroundColor: Colors.transparent,
            foregroundColor: state.palette.text,
            elevation: 0,
          ),
          body: items.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    if (state.loading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    StatePanel(
                      message: '「$title」暂未返回数据。只有点击「重试」才会重新加载。',
                      onRetry: () => state.refreshHome(force: true),
                      actionLabel: '重试',
                    ),
                  ],
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Row(
                        children: [
                          Text(
                            charts
                                ? '共 ${items.length} 个榜单'
                                : '共 ${items.length} 个歌单',
                            style: TextStyle(
                              fontSize: 12,
                              color: state.palette.muted,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '分页浏览',
                            style: TextStyle(
                              fontSize: 12,
                              color: state.palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PaginatedList<Playlist>(
                        items: items,
                        resetKey: charts ? 'charts' : 'playlists',
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: Theme.of(context).dividerColor,
                        ),
                        itemBuilder: (context, index, playlist) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            leading: CoverArt(
                              url: playlist.cover,
                              size: 46,
                              seed: index,
                            ),
                            title: Text(
                              playlist.name.isEmpty ? title : playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: MuyuTheme.body,
                            ),
                            subtitle: Text(
                              playlist.songCount > 0
                                  ? '${playlist.songCount} 首'
                                  : (charts ? '点击打开榜单' : '点击打开歌单'),
                              style: MuyuTheme.muted,
                            ),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _openPlaylist(context, playlist),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    final target = charts
        ? Playlist(
            id: playlist.id,
            name: playlist.name,
            cover: playlist.cover,
            songCount: playlist.songCount,
            kind: 'chart',
          )
        : playlist;
    Navigator.of(context).pop();
    state.openPlaylist(target);
  }
}

/// 首页大卡片
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.spec,
    required this.onTap,
    required this.onPlay,
  });

  final HomeCardSpec spec;
  final VoidCallback onTap;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final lightText = spec.action != 'new';
    final fg = lightText ? Colors.white : const Color(0xFF2A2A30);
    return GestureDetector(
      onTap: onTap,
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
