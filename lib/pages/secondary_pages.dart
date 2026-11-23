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
    final playlists = state.playlists.isNotEmpty
        ? state.playlists
        : <Playlist>[
            const Playlist(id: 'p1', name: '我喜欢的音乐', songCount: 128),
            const Playlist(id: 'p2', name: '深夜循环', songCount: 42),
            const Playlist(id: 'p3', name: '华语经典', songCount: 66),
            const Playlist(id: 'p4', name: '通勤路上', songCount: 30),
          ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
      children: [
        const Text('唱片架', style: MuyuTheme.title),
        const SizedBox(height: 18),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.of(context).size.width > 900 ? 5 : 3,
          childAspectRatio: 0.86,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: List<Widget>.generate(playlists.length, (i) {
            final p = playlists[i];
            return Column(
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
            );
          }),
        ),
      ],
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
    final favs = state.favorites.isNotEmpty
        ? state.favorites
        : _HomePageDemoSongs.get();
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
        const Text('我喜欢的音乐', style: MuyuTheme.section),
        const SizedBox(height: 8),
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
          message: '本工程由 REA 对沐语 v2.0.3 (Muyu.exe) 的静态逆向 + '
              '运行时进程内存取证复刻，仅实现华为音乐数据源。'
              '请求签名算法未能还原，若接口返回 401/403 属已知缺口。',
        ),
        const SizedBox(height: 8),
        const Text(
          'REA 观察：Go 1.27.4 / MyGo 原生界面 / WebView2 PKCE 登录 / '
          'api-drcn.music.dbankcloud.cn 私有网关 / h·sq·hr 三档音质 / '
          '可撤销的本地租约代理 Range 透传。',
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

/// 主页占位歌曲在「我的」页复用（避免重复硬编码）
class _HomePageDemoSongs {
  const _HomePageDemoSongs._();

  static List<Song> get() => <Song>[
        Song(id: 'fav-1', name: '夜的第七章', artists: const ['周杰伦', '潘儿'], favorite: true),
        Song(id: 'fav-2', name: '江南', artists: const ['林俊杰'], favorite: true),
        Song(id: 'fav-3', name: '后来的我们', artists: const ['五月天'], favorite: true),
        Song(id: 'fav-4', name: '晴天', artists: const ['周杰伦'], favorite: true),
      ];
}

