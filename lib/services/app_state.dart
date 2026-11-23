import 'package:flutter/foundation.dart';

import '../models.dart';
import '../protocol/huawei_api.dart';
import '../theme.dart';
import 'audio_controller.dart';

/// 全局状态：零第三方状态管理，直接用 ChangeNotifier + AnimatedBuilder。
class AppState extends ChangeNotifier {
  AppState() {
    audio.addListener(notifyListeners);
  }

  final HuaweiAPI api = HuaweiAPI();
  late final MuyuAudioController audio = MuyuAudioController(api);

  int tab = 0;
  bool loading = false;
  String? error;
  bool showLyrics = false;

  /// 12 款主题索引（源码事实 tinglan/theme.go），默认晨光。
  int themeIndex = 0;
  MuyuPalette get palette => kMuyuPalettes[themeIndex.clamp(0, kMuyuPalettes.length - 1)];
  bool get darkMode => palette.dark; // 兼容旧 ThemeMode 逻辑
  int homePage = 1;

  List<Song> homeSongs = <Song>[];
  List<Song> searchResults = <Song>[];
  List<Song> favorites = <Song>[];
  List<Playlist> playlists = <Playlist>[];
  List<Playlist> charts = <Playlist>[];
  List<LyricLine> lyrics = <LyricLine>[];

  /// 发现页：全部来自真实接口，空列表即接口未返回，UI 显示空状态。
  DiscoverData discover = const DiscoverData();
  bool discoverLoaded = false;
  List<Song> chartSongs = <Song>[];
  String? activeChartId;
  String searchKeyword = '';

  bool get isLoggedIn => api.isLoggedIn;

  /// 首页数据：只走音源插件真实支持的接口（最近播放 + 歌单发现）。
  Future<void> loadHome() async {
    await _guard(() async {
      discover = await api.discover();
      homeSongs = discover.newSongs;
      playlists = discover.playlists;
      charts = discover.charts;
      discoverLoaded = true;
    });
  }

  Future<void> loadChart(String chartId) async {
    activeChartId = chartId;
    chartSongs = <Song>[];
    notifyListeners();
    chartSongs = await _soft(api.chartSongs(chartId), <Song>[]);
    notifyListeners();
  }

  Future<T> _soft<T>(Future<T> work, T fallback) async {
    try {
      return await work;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> loadLibrary() async {
    await _guard(() async {
      favorites = await api.favorites();
      try {
        playlists = await api.playlists();
      } catch (_) {
        playlists = <Playlist>[];
      }
    });
  }

  Future<void> doSearch(String keyword) async {
    searchKeyword = keyword.trim();
    if (searchKeyword.isEmpty) {
      searchResults = <Song>[];
      notifyListeners();
      return;
    }
    await _guard(() async {
      searchResults = await api.search(searchKeyword);
      tab = 1;
    });
  }

  Future<void> showLyricsFor(Song song) async {
    showLyrics = true;
    notifyListeners();
    try {
      lyrics = await api.lyrics(song.id);
    } catch (_) {
      lyrics = <LyricLine>[];
    }
    notifyListeners();
  }

  Future<void> play(Song song, {List<Song>? queue}) async {
    await audio.playSong(song, list: queue);
    if (audio.error != null) error = audio.error;
    notifyListeners();
  }

  /// 供 UI 在修改局部状态后请求重建（避免外部直接调用受保护的 notifyListeners）
  void refresh() => notifyListeners();

  void selectTab(int i) {
    tab = i;
    showLyrics = false;
    notifyListeners();
    if (i == 0 && !discoverLoaded) loadHome();
    if (i == 3 && favorites.isEmpty && playlists.isEmpty) loadLibrary();
  }

  /// 循环切换 12 款主题。
  void toggleTheme() {
    themeIndex = (themeIndex + 1) % kMuyuPalettes.length;
    notifyListeners();
  }

  void setTheme(int index) {
    themeIndex = index.clamp(0, kMuyuPalettes.length - 1);
    notifyListeners();
  }

  void signInWithToken(String token) {
    api.signInWithToken(token);
    notifyListeners();
    loadHome();
    loadLibrary();
  }

  void signOut() {
    api.signOut();
    homeSongs = <Song>[];
    favorites = <Song>[];
    playlists = <Playlist>[];
    charts = <Playlist>[];
    chartSongs = <Song>[];
    activeChartId = null;
    discover = const DiscoverData();
    discoverLoaded = false;
    notifyListeners();
  }

  Future<void> _guard(Future<void> Function() work) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await work();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    audio.removeListener(notifyListeners);
    audio.dispose();
    api.gateway.dispose();
    super.dispose();
  }
}
