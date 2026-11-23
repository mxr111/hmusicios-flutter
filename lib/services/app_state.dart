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

  /// 首页 / 发现页数据。每个板块独立容错：某个接口失败只让该板块空，
  /// 不用假数据填充，也不让一次 400 拖垮整页。
  Future<void> loadHome() async {
    await _guard(() async {
      DiscoverData base;
      try {
        base = await api.discover();
      } catch (_) {
        base = const DiscoverData();
      }
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        _soft<dynamic>(api.dailySongs(), <Song>[]),
        _soft<dynamic>(api.privateRadio(), <Song>[]),
        base.playlists.isNotEmpty
            ? Future<dynamic>.value(base.playlists)
            : _soft<dynamic>(api.recommendedPlaylists(), <Playlist>[]),
      ]);
      final daily = (results[0] as List).cast<Song>().toList();
      final radio = (results[1] as List).cast<Song>().toList();
      final lists = (results[2] as List).cast<Playlist>().toList();

      discover = DiscoverData(
        banners: base.banners,
        newSongs: base.newSongs.isNotEmpty ? base.newSongs : daily,
        playlists: lists,
        charts: base.charts,
        radio: radio,
      );
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
