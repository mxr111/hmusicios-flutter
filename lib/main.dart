import 'package:flutter/material.dart';

import 'pages/secondary_pages.dart';
import 'services/app_state.dart';
import 'theme.dart';
import 'widgets/home_page.dart';
import 'widgets/player_bar.dart';
import 'widgets/sidebar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MuyuApp());
}

class MuyuApp extends StatefulWidget {
  const MuyuApp({super.key});

  @override
  State<MuyuApp> createState() => _MuyuAppState();
}

class _MuyuAppState extends State<MuyuApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    // 未登录时不发请求，直接呈现离线占位界面（与截图一致）
    if (_state.isLoggedIn) _state.loadHome();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) => MaterialApp(
        title: '沐语',
        debugShowCheckedModeBanner: false,
        theme: MuyuTheme.light(),
        darkTheme: MuyuTheme.dark(),
        themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: AppShell(state: _state),
      ),
    );
  }
}

/// 根布局：宽屏（iPad）用左侧栏 + 悬浮播放条；窄屏（iPhone）用底部标签栏。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 760;
    return Scaffold(
      body: Row(
        children: [
          if (wide)
            Sidebar(
              state: state,
              onSettings: () => _openSettings(context),
            ),
          Expanded(child: _content(context)),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : BottomNavigationBar(
              currentIndex: state.tab,
              onTap: state.selectTab,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: MuyuColors.accent,
              unselectedItemColor: MuyuColors.inkMuted,
              items: const <BottomNavigationBarItem>[
                BottomNavigationBarItem(
                    icon: Icon(Icons.home_outlined), label: '主页'),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.music_note_outlined), label: '音乐厅'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.album_outlined), label: '唱片架'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline), label: '我的'),
              ],
            ),
    );
  }

  Widget _content(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _page(context)),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: PlayerBar(state: state),
        ),
        if (state.showLyrics)
          Positioned.fill(child: LyricsPage(state: state)),
        if (state.activePlaylist != null)
          Positioned.fill(child: PlaylistDetailPage(state: state)),
        if (state.activeArtist != null)
          Positioned.fill(child: ArtistDetailPage(state: state)),
      ],
    );
  }

  Widget _page(BuildContext context) {
    switch (state.tab) {
      case 0:
        return HomePage(state: state);
      case 1:
        return SearchPage(state: state);
      case 2:
        return HallPage(state: state);
      case 3:
        return ShelfPage(state: state);
      case 4:
        return MinePage(state: state, onLogin: () => _login(context));
      default:
        return HomePage(state: state);
    }
  }

  void _login(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => LoginSheet(state: state),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          state: state,
          onLogin: () => _login(context),
        ),
      ),
    );
  }
}
