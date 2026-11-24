import 'package:flutter/material.dart';

import '../models.dart';
import '../models_skin.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/immersive_player.dart';
import '../widgets/discover_page.dart';
import '../widgets/oauth_webview_page.dart';

/// 搜索页：顶部搜索框 + 结果列表
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.state});

  final AppState state;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  int _resultTab = 0;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.state.searchKeyword;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('搜索', style: MuyuTheme.title),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            onSubmitted: state.doSearch,
            decoration: InputDecoration(
              hintText: '搜索歌曲、歌手、专辑',
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (state.loading)
            const LinearProgressIndicator(minHeight: 2)
          else if (state.error != null)
            StatePanel(message: state.error!, onRetry: () => state.doSearch(_controller.text))
          else if (state.searchResults.isEmpty &&
              state.searchArtists.isEmpty &&
              state.searchAlbums.isEmpty)
            const Text('输入关键词开始搜索华为音乐曲库', style: MuyuTheme.muted)
          else ...[
            _resultTabs(state),
            const SizedBox(height: 12),
            Expanded(
              child: switch (_resultTab) {
                1 => _artistResults(state),
                2 => _albumResults(state),
                _ => _songResults(state),
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultTabs(AppState state) {
    return Row(
      children: [
        _tabChip('歌曲 ${state.searchResults.length}', 0),
        const SizedBox(width: 8),
        _tabChip('歌手 ${state.searchArtists.length}', 1),
        const SizedBox(width: 8),
        _tabChip('专辑 ${state.searchAlbums.length}', 2),
      ],
    );
  }

  Widget _tabChip(String label, int index) {
    final selected = _resultTab == index;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _resultTab = index),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : MuyuColors.inkMuted,
      ),
      selectedColor: MuyuColors.accent,
      backgroundColor: Colors.white,
      side: BorderSide(color: MuyuColors.divider),
      showCheckmark: false,
    );
  }

  Widget _songResults(AppState state) {
    if (state.searchResults.isEmpty) {
      return const StatePanel(message: '搜索接口未返回歌曲。');
    }
    return ListView.builder(
      itemCount: state.searchResults.length,
      itemBuilder: (context, i) => SongRow(
        song: state.searchResults[i],
        index: i,
        onPlay: () => state.play(state.searchResults[i],
            queue: state.searchResults),
        onFavorite: () => state.toggleFavorite(state.searchResults[i]),
        onArtistTap: () => state.openArtistFromSong(state.searchResults[i]),
      ),
    );
  }

  Widget _artistResults(AppState state) {
    if (state.searchArtists.isEmpty) {
      return const StatePanel(message: '该搜索接口暂未返回歌手结果；可先搜索歌曲，再从歌曲行进入歌手。');
    }
    return ListView.separated(
      itemCount: state.searchArtists.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: MuyuColors.divider),
      itemBuilder: (context, i) {
        final artist = state.searchArtists[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: CoverArt(url: artist.cover, size: 46, circle: true, seed: i),
          title: Text(artist.name, style: MuyuTheme.body),
          subtitle: artist.desc.isEmpty
              ? null
              : Text(artist.desc,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MuyuTheme.muted),
          trailing: const Icon(Icons.chevron_right, size: 18),
          onTap: () => state.openArtist(artist.id, name: artist.name),
        );
      },
    );
  }

  Widget _albumResults(AppState state) {
    if (state.searchAlbums.isEmpty) {
      return const StatePanel(message: '该搜索接口暂未返回专辑结果。');
    }
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width > 900 ? 5 : 3,
        childAspectRatio: 0.82,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemCount: state.searchAlbums.length,
      itemBuilder: (context, i) {
        final album = state.searchAlbums[i];
        return GestureDetector(
          onTap: () => state.openPlaylist(album),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => CoverArt(
                    url: album.cover,
                    size: box.maxWidth,
                    radius: 12,
                    seed: i,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${album.songCount} 首', style: MuyuTheme.muted),
            ],
          ),
        );
      },
    );
  }
}

/// 音乐厅（发现页）：委托给华为音乐发现页实现。
class HallPage extends StatelessWidget {
  const HallPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => DiscoverPage(state: state);
}

/// 唱片架：歌单网格
class ShelfPage extends StatelessWidget {
  const ShelfPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final playlists = state.playlists;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      children: [
        Row(
          children: [
            const Text('唱片架', style: MuyuTheme.title),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建歌单',
              onPressed: () => _createPlaylist(context),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (!state.isLoggedIn)
          const StatePanel(message: '登录后可见你的歌单（收藏 / 自建 / 榜单）。'),
        if (state.isLoggedIn && playlists.isEmpty)
          StatePanel(
            message: '歌单接口未返回数据，请重试或到「音乐厅」浏览推荐歌单。',
            onRetry: state.loadLibrary,
            actionLabel: '重试',
          ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 5 : 3,
          childAspectRatio: 0.86,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: List<Widget>.generate(playlists.length, (i) {
            final p = playlists[i];
            return GestureDetector(
              onTap: () => state.openPlaylist(p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: p.cover == null
                          ? Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: i.isEven
                                      ? MuyuColors.cardDaily
                                      : MuyuColors.cardHot,
                                ),
                              ),
                              child: const Icon(Icons.album,
                                  size: 40, color: Colors.white),
                            )
                          : Image.network(
                              p.cover.toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: MuyuColors.divider,
                                child: const Icon(Icons.album, size: 40),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text('${p.songCount} 首', style: MuyuTheme.muted),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  void _createPlaylist(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              if (name.isNotEmpty) state.createPlaylist(name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }
}

/// 我的：收藏 / 歌单 / 登录状态
class MinePage extends StatelessWidget {
  const MinePage({
    super.key,
    required this.state,
    required this.onLogin,
    this.onSettings,
    this.onLocalMusic,
  });

  final AppState state;
  final VoidCallback onLogin;
  final VoidCallback? onSettings;
  final VoidCallback? onLocalMusic;

  @override
  Widget build(BuildContext context) {
    final favs = state.favorites;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      children: [
        const Text('我的', style: MuyuTheme.title),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [Color(0xFFF7DFC7), Color(0xFFC28C65)]),
                ),
                child: const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.accountName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.isLoggedIn
                          ? '已连接${state.source.label}'
                          : '登录后可同步收藏与歌单',
                      style: MuyuTheme.muted,
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onLogin,
                child: Text(state.isLoggedIn ? '账号' : '登录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.folder_open_outlined),
          title: const Text('本地音乐', style: MuyuTheme.body),
          subtitle: Text(
            state.local.songs.isEmpty
                ? '导入本机音频，读取内嵌封面与标签'
                : '已导入 ${state.local.songs.length} 首',
            style: MuyuTheme.muted,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onLocalMusic,
        ),
        if (onSettings != null)
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('设置与皮肤', style: MuyuTheme.body),
            trailing: const Icon(Icons.chevron_right),
            onTap: onSettings,
          ),
        const SizedBox(height: 12),
        if (state.favoriteFilter == null) ...[
          Row(
            children: [
              const Text('收藏', style: MuyuTheme.section),
              const Spacer(),
              Text('按平台查看', style: MuyuTheme.muted),
            ],
          ),
          const SizedBox(height: 12),
          _favoritesGrid(context, favs),
        ] else ...[
          _filteredFavorites(context, favs, state.favoriteFilter!),
        ],
      ],
    );
  }

  /// 平台收藏卡（沐语实测：封面拼贴 + 来源图标 + 「收藏」+ 歌曲数）。
  Widget _favoritesGrid(BuildContext context, List<Song> favs) {
    final bySource = <MusicSourceLabel, List<Song>>{};
    for (final s in favs) {
      bySource.putIfAbsent(s.source, () => <Song>[]).add(s);
    }
    // 即使某平台为空也显示卡片（与沐语一致：华为/网易云各一张收藏卡）。
    final sources = <MusicSourceLabel>{
      MusicSourceLabel.huawei,
      MusicSourceLabel.netease,
      ...bySource.keys,
    }.toList();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.of(context).size.width > 700 ? 4 : 2,
      mainAxisSpacing: 14,
      crossAxisSpacing: 14,
      childAspectRatio: 1.05,
      children: sources.map((src) {
        final songs = bySource[src] ?? <Song>[];
        final cover = songs.isNotEmpty ? songs.first.cover : null;
        return GestureDetector(
          onTap: () => state.openFavorites(src),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: cover == null
                      ? Container(
                          color: src.color.withValues(alpha: 0.16),
                          child: Center(
                            child: Icon(src.icon, size: 48, color: src.color),
                          ),
                        )
                      : Image.network(cover.toString(), fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: src.color.withValues(alpha: 0.16),
                            child: Icon(src.icon, size: 48, color: src.color),
                          )),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(src.icon, size: 14, color: src.color),
                  const SizedBox(width: 5),
                  Text('收藏', style: MuyuTheme.body),
                ],
              ),
              Text('${songs.length} 首', style: MuyuTheme.muted),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _filteredFavorites(
      BuildContext context, List<Song> favs, MusicSourceLabel source) {
    return _FavoriteList(
      songs: favs.where((s) => s.source == source).toList(),
      source: source,
      state: state,
    );
  }
}

/// 设置：音质、主题、登录、签名缺口说明
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state, required this.onLogin});

  final AppState state;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('设置', style: MuyuTheme.title),
        const SizedBox(height: 20),
        _card(
          '默认音质',
          DropdownButton<AudioQuality>(
            value: state.audio.quality,
            underline: const SizedBox.shrink(),
            items: AudioQuality.values
                .map((q) => DropdownMenuItem<AudioQuality>(
                    value: q, child: Text(q.label)))
                .toList(),
            onChanged: (q) {
              if (q != null) state.audio.setQuality(q);
            },
          ),
        ),
        _card(
          '深色主题',
          Switch(
            value: state.darkMode,
            onChanged: (_) => state.toggleTheme(),
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.palette_outlined),
          title: const Text('皮肤与外观', style: MuyuTheme.body),
          subtitle: Text('主题 · 歌词样式 · 沉浸光感',
              style: MuyuTheme.muted),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AppearancePage(state: state),
            ),
          ),
        ),
        _card(
          '华为账号',
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.isLoggedIn ? '已登录' : '未登录',
                  style: MuyuTheme.muted),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: onLogin,
                child: Text(state.isLoggedIn ? '切换账号' : '登录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text('关于', style: MuyuTheme.section),
        const SizedBox(height: 8),
        const StatePanel(
          message: '本工程由 REA 对沐语 v1.2.0 (Muyu.exe, Go 1.27.4) 全量反编译复刻，'
              '仅实现华为音乐数据源。登录走内置浏览器 OAuth PKCE + loginex，'
              '业务请求头为 Digest（app-music-baseline + music token）。'
              '接口返回 401/403 时请重新扫码登录。',
        ),
        const SizedBox(height: 8),
        const Text(
          '反编译事实：module muyu.local/desktop / 222 根模块 + 4 音源 / '
          '私有网关 api-drcn.music.dbankcloud.cn / '
          '发现页 columnInfoExs 三层结构 / 取流 qualityType 1(MP3)·3(FLAC) / '
          '逐字 HMRC 歌词 / 三态播放模式 + 8 音效 + 定时停止。',
          style: MuyuTheme.muted,
        ),
      ],
    );
  }

  Widget _card(String label, Widget trailing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(label, style: MuyuTheme.body),
          const Spacer(),
          trailing,
        ],
      ),
    );
  }
}

/// 歌词页：委托给沉浸播放器（深色黑胶 + 逐字卡拉 OK，源码事实 stage.go）。
/// 保留 LyricsPage 名称以兼容 main.dart 的调用。
class LyricsPage extends StatelessWidget {
  const LyricsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => ImmersivePlayer(state: state);
}

/// 登录面板（tinglan 源码事实）：华为音乐走 OAuth 扫码 + PKCE，
/// 不支持账号密码直登。主入口在应用内浏览器完成授权并自动换取音乐会话；
/// 手动填入 music token + snsUserID 仅作为调试后备。
class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key, required this.state});

  final AppState state;

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final TextEditingController _token = TextEditingController();
  final TextEditingController _userId = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    _userId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('登录华为音乐', style: MuyuTheme.section),
          const SizedBox(height: 10),
          const Text(
            '在应用内浏览器打开华为账号授权页完成扫码，'
            '授权后自动用 PKCE 换取音乐会话，无需手动抓包。',
            style: MuyuTheme.muted,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('打开内置浏览器扫码登录'),
            onPressed: () => _openOAuth(context),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 10),
          const Text('已有音乐会话？手动填入（跳过扫码）', style: MuyuTheme.section),
          const SizedBox(height: 8),
          TextField(
            controller: _token,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'music token（loginex 的 token）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _userId,
            decoration: const InputDecoration(
              labelText: 'snsUserID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _apply,
            child: const Text('使用音乐会话'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(color: MuyuColors.primary, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Future<void> _openOAuth(BuildContext context) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OAuthWebViewPage(state: widget.state),
        fullscreenDialog: true,
      ),
    );
    // 授权成功后关闭登录面板；取消则保留面板，方便再次尝试或手动填入。
    if (ok == true && context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _apply() {
    if (_token.text.trim().isEmpty || _userId.text.trim().isEmpty) {
      setState(() => _error = '请同时填入 music token 与 snsUserID');
      return;
    }
    widget.state.api.signInWithSession(_token.text, _userId.text);
    widget.state.persistSession();
    Navigator.pop(context);
    widget.state.refresh();
    widget.state.loadHome();
  }
}


/// 歌单详情：点击唱片架/发现页歌单卡片进入，真实歌曲列表。
class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final playlist = state.activePlaylist!;
    final songs = state.playlistSongsList;
    return PopScope(
      onPopInvokedWithResult: (_, _) => state.closePlaylist(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(playlist.name),
          leading: BackButton(onPressed: () => state.closePlaylist()),
          actions: [
            if (playlist.kind == 'owned')
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除歌单',
                onPressed: () => state.deletePlaylist(playlist.id),
              ),
          ],
        ),
        body: songs.isEmpty
            ? const Center(child: Text('歌单暂无歌曲', style: MuyuTheme.muted))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: songs.length,
                itemBuilder: (context, i) => SongRow(
                  song: songs[i],
                  index: i,
                  onPlay: () => state.play(songs[i], queue: songs),
                  onFavorite: () => state.toggleFavorite(songs[i]),
                ),
              ),
      ),
    );
  }
}

/// 歌手详情：歌手名 + 热门歌曲（真实接口）。
class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final artist = state.activeArtist!;
    final songs = state.artistSongsList;
    return PopScope(
      onPopInvokedWithResult: (_, _) => state.closeArtist(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(artist.name),
          leading: BackButton(onPressed: () => state.closeArtist()),
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            if (artist.desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(artist.desc, style: MuyuTheme.muted),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('热门歌曲', style: MuyuTheme.section),
            ),
            if (songs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(18),
                child: Text('未返回歌曲', style: MuyuTheme.muted),
              ),
            ...List<Widget>.generate(
              songs.length,
              (i) => SongRow(
                song: songs[i],
                index: i,
                onPlay: () => state.play(songs[i], queue: songs),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 皮肤 / 外观页（沐语 native_settings.go + theme_accent + lyric_style_picker）。
/// REA 事实：12 款主题（色板预览）、主题色、歌词字体（鸿蒙黑体）、
/// 沉浸光感（超薄/标准/厚/超厚=原毛玻璃）、光感颜色（从颜色列表选 / 随封面）、
/// 按压形变、滑动光效。
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('皮肤与外观')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('主题', style: MuyuTheme.section),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
            ),
            itemCount: kMuyuPalettes.length,
            itemBuilder: (context, i) {
              final p = kMuyuPalettes[i];
              final selected = state.themeIndex == i;
              return GestureDetector(
                onTap: () => state.setTheme(i),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? MuyuColors.accent : MuyuColors.divider,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: p.base,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: p.surface,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text('Aa',
                                          style: TextStyle(
                                              color: p.text, fontSize: 18)),
                                    )),
                              ),
                              Container(width: 8, color: p.accent),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(p.label,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                            if (selected) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check_circle,
                                  size: 13, color: MuyuColors.accent),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('歌词样式', style: MuyuTheme.section),
          const SizedBox(height: 8),
          _switchRow('歌词居中', Icons.format_align_center,
              state.lyricStyle.align == LyricAlign.center, (v) {
            state.updateLyricStyle(state.lyricStyle.copyWith(
                align: v ? LyricAlign.center : LyricAlign.left));
          }),
          _switchRow('歌词粗体', Icons.format_bold, state.lyricStyle.bold, (v) {
            state.updateLyricStyle(state.lyricStyle.copyWith(bold: v));
          }),
          _switchRow('颜色随封面主色变化', Icons.palette_outlined,
              state.lyricStyle.followCoverColor, (v) {
            state.updateLyricStyle(
                state.lyricStyle.copyWith(followCoverColor: v));
          }),
          _dropdownRow<String>('歌词字体', Icons.text_fields, state.lyricStyle.font,
              kBuiltinFonts, (v) {
            state.updateLyricStyle(state.lyricStyle.copyWith(font: v));
          }),
          const SizedBox(height: 24),
          const Text('沉浸光感', style: MuyuTheme.section),
          const SizedBox(height: 8),
          _dropdownRow<ImmersiveGlass>(
            '光感档位', Icons.blur_on, state.glass, ImmersiveGlass.values,
            (v) => state.setGlass(v),
            labelOf: (g) => kGlassLabels[g.index],
          ),
          _switchRow('按压形变', Icons.touch_app, state.glassPress,
              (v) => state.updateSkin(glassPress: v)),
          _switchRow('滑动光效', Icons.animation, state.glassSlide,
              (v) => state.updateSkin(glassSlide: v)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('光感颜色', style: MuyuTheme.body),
          ),
          Wrap(
            spacing: 12,
            children: kGlowColors.map((c) {
              final selected = state.glowColor == c;
              return GestureDetector(
                onTap: () => state.setGlowColor(c),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? MuyuColors.accent : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _switchRow(
      String label, IconData icon, bool value, ValueChanged<bool> onChanged) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: MuyuColors.accent),
      title: Text(label, style: MuyuTheme.body),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  Widget _dropdownRow<T>(String label, IconData icon, T value, List<T> items,
      ValueChanged<T> onChanged, {String Function(T)? labelOf}) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: MuyuColors.accent),
      title: Text(label, style: MuyuTheme.body),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items: items
            .map((v) => DropdownMenuItem<T>(
                value: v,
                child: Text(labelOf == null ? v.toString() : labelOf(v))))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// 平台收藏歌曲列表（沐语实测：返回箭头 + 搜索当前歌单 + 「歌曲 会员 音质」列头）。
class _FavoriteList extends StatefulWidget {
  const _FavoriteList({
    required this.songs,
    required this.source,
    required this.state,
  });
  final List<Song> songs;
  final MusicSourceLabel source;
  final AppState state;

  @override
  State<_FavoriteList> createState() => _FavoriteListState();
}

class _FavoriteListState extends State<_FavoriteList> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final songs = query.isEmpty
        ? widget.songs
        : widget.songs
            .where((s) =>
                s.name.contains(query) || s.artistText.contains(query))
            .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: widget.state.closeFavorites,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '搜索当前歌单',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              const Expanded(child: Text('歌曲', style: MuyuTheme.muted)),
              SizedBox(width: 60, child: Text('会员', style: MuyuTheme.muted)),
              SizedBox(width: 60, child: Text('音质', style: MuyuTheme.muted)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (songs.isEmpty)
          StatePanel(message: query.isEmpty ? '该平台暂无收藏歌曲' : '没有匹配的歌曲')
        else
          ...List<Widget>.generate(
            songs.length,
            (i) => SongRow(
              song: songs[i],
              index: i,
              onPlay: () => widget.state.play(songs[i], queue: songs),
            ),
          ),
      ],
    );
  }
}

/// 本地音乐：导入系统里的音频文件，读取内嵌标签后加入本机曲库。
/// 对应原版 internal/localmedia + native_local*.go；不扫描全盘，只处理用户主动选择的文件。
class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({super.key, required this.state});

  final AppState state;

  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends State<LocalMusicPage> {
  Future<void> _import() async {
    final added = await widget.state.importLocalMusic();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added > 0 ? '已导入 $added 首本地歌曲' : '未导入文件')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final songs = state.local.songs;
    return Scaffold(
      backgroundColor: MuyuColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('本地音乐', style: MuyuTheme.title),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: const Text('导入'),
            onPressed: state.local.loading ? null : _import,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              songs.isEmpty ? '还没有本地歌曲' : '共 ${songs.length} 首 · 全部保存在应用沙箱',
              style: MuyuTheme.muted,
            ),
            const SizedBox(height: 14),
            if (state.local.loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (songs.isEmpty)
              StatePanel(
                message: '支持 MP3 / FLAC / M4A / WAV 等格式；导入后读取 ID3v2 与 FLAC 内嵌标题、歌手、专辑。',
                onRetry: _import,
                actionLabel: '选择文件',
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: songs.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: MuyuColors.divider),
                  itemBuilder: (context, i) {
                    final song = songs[i];
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      leading: CoverArt(url: song.cover, size: 44, seed: i),
                      title: Text(song.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        song.album.isEmpty
                            ? song.artistText
                            : '${song.artistText} · ${song.album}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MuyuTheme.muted,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QualityBadge(
                            song.qualities.contains(AudioQuality.lossless)
                                ? AudioQuality.lossless
                                : AudioQuality.standard,
                            small: true,
                          ),
                          IconButton(
                            tooltip: '播放',
                            icon: const Icon(Icons.play_circle_outline, size: 22),
                            onPressed: () =>
                                state.play(song, queue: songs),
                          ),
                          IconButton(
                            tooltip: '从本地库移除',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => state.removeLocalMusic(song),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
