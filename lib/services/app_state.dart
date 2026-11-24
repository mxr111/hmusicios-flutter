import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../models.dart';
import '../models_skin.dart';
import '../protocol/huawei_api.dart';
import '../protocol/netease_api.dart';
import '../theme.dart';
import 'audio_controller.dart';

/// 全局状态：零第三方状态管理，直接用 ChangeNotifier + AnimatedBuilder。
class AppState extends ChangeNotifier {
  AppState() {
    audio.addListener(notifyListeners);
  }

  final HuaweiAPI api = HuaweiAPI();
  final NeteaseApi netease = NeteaseApi();

  /// 当前音源（沐语支持多平台；本项目接通华为 + 网易云）。
  MusicSource source = MusicSource.huawei;
  bool get isLoggedIn => source == MusicSource.netease
      ? netease.isLoggedIn
      : api.isLoggedIn;

  late final MuyuAudioController audio = MuyuAudioController(api, netease: netease);

  int tab = 0;
  bool loading = false;
  String? error;
  bool showLyrics = false;

  /// 12 款主题索引（源码事实 tinglan/theme.go），默认晨光。
  int themeIndex = 0;
  MuyuPalette get palette => kMuyuPalettes[themeIndex.clamp(0, kMuyuPalettes.length - 1)];
  bool get darkMode => palette.dark; // 兼容旧 ThemeMode 逻辑
  int homePage = 1;

  /// 播放器皮肤（REA：4 种播放器样式 + 歌词样式 + 沉浸光感）。
  PlayerStyle playerStyle = PlayerStyle.modern;
  LyricStyle lyricStyle = const LyricStyle();
  bool immersiveFullscreen = false;
  ImmersiveGlass glass = ImmersiveGlass.normal;
  Color glowColor = kGlowColors.first;
  bool glassPress = true;
  bool glassSlide = true;

  void setPlayerStyle(PlayerStyle style) {
    playerStyle = style;
    notifyListeners();
  }

  void updateLyricStyle(LyricStyle style) {
    lyricStyle = style;
    notifyListeners();
  }

  void toggleImmersiveFullscreen() {
    immersiveFullscreen = !immersiveFullscreen;
    notifyListeners();
  }

  void setGlass(ImmersiveGlass value) {
    glass = value;
    notifyListeners();
  }

  void setGlowColor(Color color) {
    glowColor = color;
    notifyListeners();
  }

  void updateSkin({bool? glassPress, bool? glassSlide}) {
    if (glassPress != null) this.glassPress = glassPress;
    if (glassSlide != null) this.glassSlide = glassSlide;
    notifyListeners();
  }

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

  /// 歌单详情：点击歌单卡片加载其中歌曲。
  Playlist? activePlaylist;
  List<Song> playlistSongsList = <Song>[];

  /// 歌手详情：歌手页的歌曲与专辑入口。
  Artist? activeArtist;
  List<Song> artistSongsList = <Song>[];

  /// 评论：沉浸播放页 / 歌曲菜单进入。
  List<Comment> comments = <Comment>[];
  String? commentsForSong;

  /// 首页数据：只走音源插件真实支持的接口（最近播放 + 歌单发现）。
  Future<void> loadHome() async {
    await _guard(() async {
      if (source == MusicSource.netease) {
        final daily = await _soft(netease.dailySongs(), <Song>[]);
        final lists = await _soft(netease.recommendedPlaylists(), <Playlist>[]);
        discover = DiscoverData(newSongs: daily, playlists: lists);
      } else {
        discover = await api.discover();
      }
      homeSongs = discover.newSongs;
      playlists = discover.playlists;
      charts = discover.charts;
      discoverLoaded = true;
    });
  }

  /// 切换音源：清理当前数据，按新音源重新加载。
  Future<void> switchSource(MusicSource newSource) async {
    if (source == newSource) return;
    source = newSource;
    audio.source = newSource;
    discover = const DiscoverData();
    discoverLoaded = false;
    homeSongs = <Song>[];
    favorites = <Song>[];
    playlists = <Playlist>[];
    charts = <Playlist>[];
    chartSongs = <Song>[];
    searchResults = <Song>[];
    notifyListeners();
    if (isLoggedIn) await loadHome();
  }

  Future<void> loadChart(String chartId) async {
    activeChartId = chartId;
    chartSongs = <Song>[];
    notifyListeners();
    chartSongs = await _soft(api.chartSongs(chartId), <Song>[]);
    notifyListeners();
  }

  /// 打开歌单详情：按 kind 分派到正确的接口（owned/collected/chart）。
  Future<void> openPlaylist(Playlist playlist) async {
    activePlaylist = playlist;
    playlistSongsList = <Song>[];
    showLyrics = false;
    notifyListeners();
    playlistSongsList = await _soft(
      source == MusicSource.netease
          ? netease.playlistTracks(playlist.id)
          : (playlist.kind == 'chart'
              ? api.chartSongs(playlist.id)
              : api.playlistSongs(playlist)),
      <Song>[],
    );
    notifyListeners();
  }

  void closePlaylist() {
    activePlaylist = null;
    playlistSongsList = <Song>[];
    notifyListeners();
  }

  Future<void> openArtist(String artistCode, {String name = ''}) async {
    activeArtist = Artist(id: artistCode, name: name.isEmpty ? '歌手' : name);
    artistSongsList = <Song>[];
    notifyListeners();
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      _soft<dynamic>(api.artistDetail(artistCode), const Artist(id: '', name: '')),
      _soft<dynamic>(api.artistSongs(artistCode), <Song>[]),
    ]);
    if (results[0] is Artist && (results[0] as Artist).name.isNotEmpty) {
      activeArtist = results[0] as Artist;
    }
    artistSongsList = (results[1] as List).cast<Song>().toList();
    notifyListeners();
  }

  void closeArtist() {
    activeArtist = null;
    artistSongsList = <Song>[];
    notifyListeners();
  }

  /// 从歌曲行点击歌手名进入歌手页；无 artistID 时用歌手名尝试。
  void openArtistFromSong(Song song) {
    final code = song.artistIds.isNotEmpty
        ? song.artistIds.first
        : (song.artists.isNotEmpty ? song.artists.first : '');
    if (code.isEmpty) {
      error = '该歌曲未返回歌手 ID，无法打开歌手页';
      notifyListeners();
      return;
    }
    openArtist(code, name: song.artists.isNotEmpty ? song.artists.first : '');
  }

  Future<void> loadComments(String songCode) async {
    commentsForSong = songCode;
    comments = <Comment>[];
    notifyListeners();
    comments = await _soft(
      source == MusicSource.netease
          ? netease.comments(songCode)
          : api.comments(songCode),
      <Comment>[],
    );
    notifyListeners();
  }

  Future<void> toggleFavorite(Song song) async {
    final next = !song.favorite;
    song.favorite = next;
    notifyListeners();
    try {
      if (source == MusicSource.netease) {
        // 网易云收藏：本地维护状态（radio/like 需额外接口，留待 write 接口）。
      } else {
        await api.toggleFavorite(song.id, next);
      }
      if (next && !favorites.any((s) => s.id == song.id)) {
        favorites = <Song>[...favorites, song];
      } else if (!next) {
        favorites = favorites.where((s) => s.id != song.id).toList();
      }
    } catch (_) {
      song.favorite = !next; // 回滚
    }
    notifyListeners();
  }

  Future<void> createPlaylist(String name) async {
    await _guard(() async {
      await api.createPlaylist(name);
      playlists = await api.playlists();
    });
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _guard(() async {
      await api.deletePlaylist(playlistId);
      playlists = playlists.where((p) => p.id != playlistId).toList();
      if (activePlaylist?.id == playlistId) closePlaylist();
    });
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
      if (source == MusicSource.netease) {
        playlists = await _soft(
            netease.userPlaylists(''), <Playlist>[]); // uid 由登录后填
      } else {
        favorites = await api.favorites();
        try {
          playlists = await api.playlists();
        } catch (_) {
          playlists = <Playlist>[];
        }
      }
    });
  }

  /// 首页 5 张大卡：每张都走真实接口，失败时显示错误状态，不填假歌。
  Future<void> playCard(String action) async {
    await _guard(() async {
      late List<Song> songs;
      final ne = source == MusicSource.netease;
      switch (action) {
        case 'radio':
          songs = ne ? await netease.dailySongs() : await api.privateRadio(mode: '1');
          break;
        case 'daily':
          songs = ne ? await netease.dailySongs() : await api.dailySongs();
          break;
        case 'heart':
          songs = ne ? await netease.dailySongs() : await api.privateRadio(mode: '2');
          break;
        case 'new':
          songs = discover.newSongs.isNotEmpty
              ? discover.newSongs
              : (ne ? await netease.dailySongs() : await api.dailySongs());
          break;
        case 'hot':
          if (ne) {
            songs = discover.newSongs;
          } else {
            songs = await api.similarSongs(
              audio.current?.id ?? (homeSongs.isNotEmpty ? homeSongs.first.id : ''),
            );
            if (songs.isEmpty) songs = discover.newSongs;
          }
          break;
        default:
          songs = homeSongs;
      }
      if (songs.isNotEmpty) {
        await play(songs.first, queue: songs);
      } else {
        error = '「$action」接口未返回歌曲（确认已登录 / 网络可用）';
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
      searchResults = source == MusicSource.netease
          ? await netease.search(searchKeyword)
          : await api.search(searchKeyword);
      tab = 1;
    });
  }

  Future<void> showLyricsFor(Song song) async {
    showLyrics = true;
    notifyListeners();
    try {
      lyrics = source == MusicSource.netease
          ? await netease.lyrics(song.id)
          : await api.lyrics(song.id);
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
    netease.signOut();
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
    netease.gateway.dispose();
    super.dispose();
  }
}
