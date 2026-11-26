import 'package:flutter/material.dart';

import 'models_skin.dart';
import 'pages/secondary_pages.dart';
import 'services/app_state.dart';
import 'widgets/netease_login_sheet.dart';
import 'theme.dart';
import 'widgets/home_page.dart';
import 'widgets/kugou_login_sheet.dart';
import 'widgets/netease_home_page.dart';
import 'widgets/player_bar.dart';
import 'widgets/qq_login_sheet.dart';
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
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    _state.onError = (message) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
      });
    };
    _bootstrap();
  }

  /// 先恢复上次登录态，再加载首页/曲库；恢复失败也保持离线界面可用。
  Future<void> _bootstrap() async {
    try {
      await _state.restoreSession();
    } catch (_) {
      // 本地会话损坏时按未登录启动，不阻塞界面。
    }
    if (!mounted || !_state.isLoggedIn) return;
    await _state.loadHome();
    await _state.loadLibrary();
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
        title: 'Hmusic',
        scaffoldMessengerKey: _messengerKey,
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
    // 播放器是应用级全屏层：进入后不再保留侧栏、底部标签栏/播放条和
    // 任何页面头部，退出时只恢复状态标记，不重建/打断当前播放。
    if (state.showPlayer || state.showLyrics) {
      return LyricsPage(state: state);
    }
    final wide = MediaQuery.of(context).size.width >= 760;
    return Scaffold(
      // 根布局必须避开系统状态栏；否则宽屏侧栏账号头和主页标题会压住
      // iOS/Android 左上角的日期时间。底部交给 BottomNavigationBar。
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (wide)
              Sidebar(
                state: state,
                onSettings: () => _openSettings(context),
                onLocalMusic: () => _openLocalMusic(context),
                onAccount: () => _login(context),
              ),
            Expanded(child: _content(context)),
          ],
        ),
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
                  icon: Icon(Icons.home_outlined),
                  label: '主页',
                ),
                BottomNavigationBarItem(icon: Icon(Icons.search), label: '搜索'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.music_note_outlined),
                  label: '音乐厅',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.album_outlined),
                  label: '唱片架',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  label: '我的',
                ),
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
        return state.source == MusicSource.netease
            ? NeteaseHomePage(state: state)
            : HomePage(state: state);
      case 1:
        return SearchPage(state: state);
      case 2:
        return HallPage(state: state);
      case 3:
        return ShelfPage(state: state);
      case 4:
        return MinePage(
          state: state,
          onLogin: () => _login(context),
          onSettings: () => _openSettings(context),
          onLocalMusic: () => _openLocalMusic(context),
        );
      default:
        return state.source == MusicSource.netease
            ? NeteaseHomePage(state: state)
            : HomePage(state: state);
    }
  }

  void _login(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => switch (state.source) {
        MusicSource.netease => NeteaseLoginSheet(state: state),
        MusicSource.kugou => KugouLoginSheet(state: state),
        MusicSource.qq => QqLoginSheet(state: state),
        MusicSource.huawei => LoginSheet(state: state),
      },
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SettingsPage(state: state, onLogin: () => _login(context)),
      ),
    );
  }

  void _openLocalMusic(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LocalMusicPage(state: state)),
    );
  }
}
