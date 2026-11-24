import 'package:flutter/material.dart';

import '../models.dart';
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
          else if (state.searchResults.isEmpty)
            const Text('输入关键词开始搜索华为音乐曲库', style: MuyuTheme.muted)
          else
            Expanded(
              child: ListView.builder(
                itemCount: state.searchResults.length,
                itemBuilder: (context, i) => SongRow(
                  song: state.searchResults[i],
                  index: i,
                  onPlay: () => state.play(state.searchResults[i],
                      queue: state.searchResults),
                  onFavorite: () => state.toggleFavorite(state.searchResults[i]),
                  onArtistTap: () =>
                      state.openArtistFromSong(state.searchResults[i]),
                ),
              ),
            ),
        ],
      ),
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
  const MinePage({super.key, required this.state, required this.onLogin});

  final AppState state;
  final VoidCallback onLogin;

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
                      state.api.displayName ??
                          (state.isLoggedIn ? '华为音乐用户' : '未登录'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      state.isLoggedIn
                          ? '已连接华为音乐'
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
        const SizedBox(height: 20),
        Text('我喜欢的音乐',
            style: MuyuTheme.section),
        const SizedBox(height: 8),
        if (state.isLoggedIn && favs.isEmpty)
          const StatePanel(message: '收藏列表为空，可在播放条点击 ♥ 收藏歌曲。'),
        ...List<Widget>.generate(
          favs.length,
          (i) => SongRow(
            song: favs[i],
            index: i,
            onPlay: () => state.play(favs[i], queue: favs),
          ),
        ),
      ],
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
