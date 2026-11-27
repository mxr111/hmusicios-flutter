import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../models.dart';
import '../models_home.dart';
import '../models_skin.dart';
import '../protocol/huawei_api.dart';
import '../protocol/huawei_oauth.dart';
import '../protocol/kugou_api.dart';
import '../protocol/netease_api.dart';
import '../protocol/qq_api.dart';
import '../theme.dart';
import 'audio_controller.dart';
import 'app_log.dart';
import 'local_library.dart';
import 'session_store.dart';

/// 全局状态：零第三方状态管理，直接用 ChangeNotifier + AnimatedBuilder。
class AppState extends ChangeNotifier {
  AppState({
    SessionStore? sessionStore,
    HuaweiAPI? huaweiApi,
    MuyuAudioController? audioController,
  })
    : _sessionStore = sessionStore ?? PreferencesSessionStore(),
      api = huaweiApi ?? HuaweiAPI() {
    audio =
        audioController ??
        MuyuAudioController(
          api,
          netease: netease,
          kugou: kugou,
          qq: qq,
        );
    audio.addListener(_onAudioChanged);
    local.addListener(notifyListeners);
    // 授权码换到的账号 token / 音乐 token 变化时立刻持久化。
    api.gateway.onSessionChanged = () {
      _authChangedAt = DateTime.now();
      persistSession();
    };
    api.onProfileChanged = () {
      persistSession();
      notifyListeners();
    };
  }

  final SessionStore _sessionStore;
  final HuaweiAPI api;
  final NeteaseApi netease = NeteaseApi();
  final KugouApi kugou = KugouApi();
  final QqApi qq = QqApi();
  final LocalLibrary local = LocalLibrary();

  /// 当前音源（沐语支持多平台；本项目接通华为 + 网易云）。
  MusicSource source = MusicSource.huawei;
  bool get isLoggedIn => switch (source) {
    MusicSource.huawei => api.isLoggedIn,
    MusicSource.netease => netease.isLoggedIn,
    MusicSource.kugou => kugou.isLoggedIn,
    MusicSource.qq => qq.isLoggedIn,
  };

  /// 当前音源的账号显示名（侧栏 / 我的页共用）。
  String get accountName => switch (source) {
    MusicSource.huawei =>
      api.displayName ?? (api.isLoggedIn ? '华为音乐用户' : '未登录'),
    MusicSource.netease =>
      (netease.gateway.session?.nickname.isNotEmpty ?? false)
          ? netease.gateway.session!.nickname
          : (netease.isLoggedIn ? '网易云用户' : '未登录'),
    MusicSource.kugou => kugou.isLoggedIn ? kugou.displayName : '未登录',
    MusicSource.qq => qq.isLoggedIn ? qq.displayName : '未登录',
  };

  String get accountAvatar => source == MusicSource.huawei
      ? (api.avatarUrl ?? '')
      : (source == MusicSource.kugou
            ? (kugou.gateway.session?.avatarUrl ?? '')
            : '');

  String get accountMemberLabel => source == MusicSource.huawei
      ? (api.memberLabel ??
            (api.isMember ? '华为音乐会员' : (api.isLoggedIn ? '华为音乐' : '')))
      : '';

  late final MuyuAudioController audio;

  int tab = 0;
  bool loading = false;
  String? error;
  void Function(String message)? onError;
  bool showLyrics = false;
  bool showPlayer = false;
  bool needsRelogin = false;

  final ValueNotifier<int> lyricsRevision = ValueNotifier<int>(0);

  HuaweiCredentials? _savedHuaweiCredentials;
  HuaweiCredentials? get savedHuaweiCredentials => _savedHuaweiCredentials;

  Timer? _sessionKeepAliveTimer;
  Future<void>? _keepAliveInFlight;
  int _lastReloginEpoch = 0;
  int _lyricsLoadGeneration = 0;
  String? _lyricsSongId;
  String? _lastAudioSongId;
  bool _disposed = false;

  /// 12 款主题索引（源码事实 tinglan/theme.go），默认晨光。
  int themeIndex = 0;
  int? _lastLightTheme;
  int? _lastDarkTheme = 6;
  MuyuPalette get palette =>
      kMuyuPalettes[themeIndex.clamp(0, kMuyuPalettes.length - 1)];
  bool get darkMode => palette.dark; // 兼容旧 ThemeMode 逻辑
  int homePage = 1;
  int _homeRefreshSeed = 0;
  Future<void>? _homeInFlight;
  DateTime? _homeRetryBlockedUntil;
  DateTime? _lastForcedRefreshAt;
  DateTime? _authChangedAt;
  int _suppressedHomeRefreshes = 0;

  /// 最小强制刷新间隔：空卡片/短时间重复 force 不再排 N 轮全量请求。
  static const Duration _minHomeRefreshGap = Duration(seconds: 5);
  static const Duration _authRefreshWindow = Duration(minutes: 2);

  /// 测试/日志可见：被防风暴保护抑制的 force 次数。
  int get suppressedHomeRefreshes => _suppressedHomeRefreshes;

  /// 兼容旧调用；项目统一使用经典播放器，样式不再切换。
  PlayerStyle playerStyle = PlayerStyle.classic;
  LyricStyle lyricStyle = const LyricStyle();
  bool immersiveFullscreen = false;
  ImmersiveGlass glass = ImmersiveGlass.normal;
  Color glowColor = kGlowColors.first;
  bool glassPress = true;
  bool glassSlide = true;

  void setPlayerStyle(PlayerStyle style) {
    playerStyle = PlayerStyle.classic;
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void updateLyricStyle(LyricStyle style) {
    lyricStyle = style;
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void toggleImmersiveFullscreen() {
    immersiveFullscreen = !immersiveFullscreen;
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void setGlass(ImmersiveGlass value) {
    glass = value;
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void setGlowColor(Color color) {
    glowColor = color;
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void updateSkin({bool? glassPress, bool? glassSlide}) {
    if (glassPress != null) this.glassPress = glassPress;
    if (glassSlide != null) this.glassSlide = glassSlide;
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void bumpLyricsRevision() {
    if (_disposed) return;
    lyricsRevision.value++;
  }

  Future<void> setVolume(double v) async {
    await audio.setVolume(v);
    await persistSession();
    bumpLyricsRevision();
    notifyListeners();
  }

  void setEffect(String value) {
    audio.setEffect(value);
    bumpLyricsRevision();
    notifyListeners();
    unawaited(persistSession());
  }

  Future<void> setQuality(AudioQuality q) async {
    await audio.setQuality(q);
    await persistSession();
    bumpLyricsRevision();
    notifyListeners();
  }

  Future<void> setLyricOffset(Duration offset) async {
    await audio.adjustLyricOffset(offset - audio.lyricOffset);
    await persistSession();
    bumpLyricsRevision();
    notifyListeners();
  }

  Future<void> resetLyricOffset() async {
    await audio.resetLyricOffset();
    await persistSession();
    bumpLyricsRevision();
    notifyListeners();
  }

  Future<void> saveHuaweiCredentials(String account, String password) async {
    final credentials = HuaweiCredentials(
      account: account.trim(),
      password: password,
    );
    if (credentials.account.isEmpty || credentials.password.isEmpty) {
      throw ArgumentError('华为账号和密码不能为空');
    }
    await _sessionStore.writeCredentials(credentials);
    _savedHuaweiCredentials = credentials;
    notifyListeners();
  }

  Future<void> clearHuaweiCredentials() async {
    await _sessionStore.clearCredentials();
    _savedHuaweiCredentials = null;
    notifyListeners();
  }

  void clearReloginRequest() {
    if (!needsRelogin) return;
    needsRelogin = false;
    notifyListeners();
  }

  void startSessionKeepAlive() {
    if (_disposed) return;
    _sessionKeepAliveTimer ??= Timer.periodic(
      const Duration(hours: 1),
      (_) => unawaited(_keepHuaweiSession()),
    );
  }

  Future<void> _keepHuaweiSession() {
    final running = _keepAliveInFlight;
    if (running != null) return running;
    final future = _keepHuaweiSessionNow();
    _keepAliveInFlight = future.whenComplete(() {
      _keepAliveInFlight = null;
    });
    return _keepAliveInFlight!;
  }

  Future<void> _keepHuaweiSessionNow() async {
    if (_disposed) return;
    final hasRefreshToken =
        (api.gateway.refreshToken?.trim().isNotEmpty ?? false);
    final hasAccountToken =
        (api.gateway.accountToken?.trim().isNotEmpty ?? false);
    if (!hasRefreshToken && !hasAccountToken) return;

    final refreshed = await _refreshHuaweiSession();
    if (refreshed) {
      needsRelogin = false;
      await persistSession();
      await loadLibrary();
      notifyListeners();
      return;
    }

    final saved = _savedHuaweiCredentials ?? await _sessionStore.readCredentials();
    if (saved != null) {
      _savedHuaweiCredentials = saved;
      _lastReloginEpoch = DateTime.now().millisecondsSinceEpoch;
      needsRelogin = true;
      error = '华为会话已过期，请完成一次 OAuth 验证以刷新登录会话';
      unawaited(persistSession());
    } else {
      needsRelogin = false;
      error = '华为会话已过期，请重新登录华为账号';
    }
    notifyListeners();
  }

  Future<bool> _refreshHuaweiSession() async {
    final refreshToken = api.gateway.refreshToken?.trim() ?? '';
    if (refreshToken.isNotEmpty) {
      try {
        final pair = await refreshAccessToken(refreshToken);
        api.gateway.accountToken = pair.accessToken;
        api.gateway.refreshToken = pair.refreshToken;
        await api.gateway.exchangeMusicToken(pair.accessToken);
        await api.refreshProfile();
        AppLog.add('state', 'OAuth refresh token 静默续期成功');
        return true;
      } catch (_) {
        AppLog.add('state', 'OAuth refresh token 静默续期失败');
      }
    }

    final accountToken = api.gateway.accountToken?.trim() ?? '';
    if (accountToken.isNotEmpty) {
      try {
        await api.gateway.exchangeMusicToken(accountToken);
        await api.refreshProfile();
        AppLog.add('state', '账号 access token 静默续期成功');
        return true;
      } catch (_) {
        AppLog.add('state', '账号 access token 静默续期失败');
      }
    }
    return false;
  }

  List<Song> homeSongs = <Song>[];
  List<Song> searchResults = <Song>[];
  List<Artist> searchArtists = <Artist>[];
  List<Playlist> searchAlbums = <Playlist>[];
  List<Playlist> searchPlaylists = <Playlist>[];
  bool hasMoreSearch = false;
  bool loadingMoreSearch = false;
  int searchStart = 0;
  List<Song> favorites = <Song>[];
  List<Playlist> playlists = <Playlist>[];
  List<Playlist> charts = <Playlist>[];
  List<LyricLine> lyrics = <LyricLine>[];

  /// 发现页：全部来自真实接口，空列表即接口未返回，UI 显示空状态。
  DiscoverData discover = const DiscoverData();
  bool discoverLoaded = false;
  List<Song> chartSongs = <Song>[];

  /// 网易云独立首页（与华为发现页分开，不共用假数据或缓存）。
  NeteaseHomeData neteaseHome = const NeteaseHomeData();
  bool neteaseHomeLoading = false;
  String? neteaseHomeError;
  int neteasePlaylistOffset = 0;
  bool neteaseHasMorePlaylists = true;
  String? activeChartId;
  String searchKeyword = '';

  /// 华为「心动模式」的 privatefm 续播游标。只属于心动队列，
  /// 不参与现在就听/每日/新歌/热歌的数据兜底。
  String radioNext = '';
  bool radioMore = false;
  String radioRefInfo = '';
  String radioScenario = '16';
  String radioMode = '1';

  /// 歌单详情：点击歌单卡片加载其中歌曲。
  Playlist? activePlaylist;
  List<Song> playlistSongsList = <Song>[];

  /// 收藏页平台筛选（沐语实测：我的 → 收藏 → 按平台卡片进入）。
  MusicSourceLabel? favoriteFilter;
  void openFavorites(MusicSourceLabel source) {
    favoriteFilter = source;
    notifyListeners();
  }

  void closeFavorites() {
    favoriteFilter = null;
    notifyListeners();
  }

  /// 歌手详情：歌手页的歌曲与专辑入口。
  Artist? activeArtist;
  List<Song> artistSongsList = <Song>[];

  /// 评论：沉浸播放页 / 歌曲菜单进入。
  List<Comment> comments = <Comment>[];
  String? commentsForSong;

  /// 首页数据：华为发现页与网易云独立首页严格分开，只走真实接口。
  Future<void> loadHome({bool force = false}) async {
    if (source == MusicSource.netease) {
      await loadNeteaseHome();
      return;
    }
    if (source == MusicSource.kugou) {
      await loadKugouHome();
      return;
    }
    if (source == MusicSource.qq) {
      await loadQqHome();
      return;
    }

    final now = DateTime.now();
    var authFresh = false;
    if (force) {
      // 登录成功后的第一次刷新必须真正生效；普通空卡片/短时间重复
      // force 则合并到正在进行的加载或直接抑制。
      final changedAt = _authChangedAt;
      authFresh =
          changedAt != null &&
          now.difference(changedAt) < _authRefreshWindow;
      if (authFresh) _authChangedAt = null;

      if (!authFresh) {
        final lastForced = _lastForcedRefreshAt;
        if (lastForced != null &&
            now.difference(lastForced) < _minHomeRefreshGap) {
          AppLog.add('home', 'force 刷新最小间隔内被抑制');
          _suppressedHomeRefreshes++;
          final running = _homeInFlight;
          if (running != null) await running;
          return;
        }
      }
    }

    final running = _homeInFlight;
    if (running != null) {
      if (!force || !authFresh) {
        if (force) _suppressedHomeRefreshes++;
        return running;
      }
      // 登录后的强制刷新允许在旧请求结束后再补一次，但只补一次。
      await running;
    }

    if (force) {
      _lastForcedRefreshAt = now;
      _homeRetryBlockedUntil = null;
      api.clearAuthCooldown();
    }
    if (!force &&
        _homeRetryBlockedUntil != null &&
        now.isBefore(_homeRetryBlockedUntil!)) {
      return;
    }
    final future = _loadHuaweiHome();
    _homeInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_homeInFlight, future)) {
        _homeInFlight = null;
      }
    }
  }

  Future<void> _loadHuaweiHome() async {
    await _guard(() async {
      final data = await api.discover();
      discover = _rotateDiscover(data);
      // homeSongs 只做全局默认播放入口，不再作为各卡片的公共 fallback。
      // 但如果 8011 为空，用同一份 discover 里真实可用的板块兜底，
      // 避免默认播放入口也变成空列表。
      homeSongs = discover.recommended.isNotEmpty
          ? discover.recommended
          : (discover.radio.isNotEmpty
                ? discover.radio
                : (discover.daily.isNotEmpty
                      ? discover.daily
                      : discover.hot));
      playlists = discover.playlists;
      charts = discover.charts;
      discoverLoaded =
          discover.listen.isNotEmpty ||
          discover.daily.isNotEmpty ||
          discover.heart.isNotEmpty ||
          discover.newSongs.isNotEmpty ||
          discover.hot.isNotEmpty ||
          discover.recommended.isNotEmpty;
    });
  }

  /// 首页刷新：显式用户刷新/登录回调仍可强制，但由 [loadHome] 做
  /// 最小间隔、鉴权冷却与并发合并，避免空卡片点击放大成请求风暴。
  Future<void> refreshHome({bool force = true}) async {
    _homeRefreshSeed++;
    await loadHome(force: force);
  }

  DiscoverData _rotateDiscover(DiscoverData data) {
    if (_homeRefreshSeed == 0) return data;
    // 只在本列表内轮换；绝不在卡片之间复制数据。
    return DiscoverData(
      banners: data.banners,
      newSongs: _rotate(data.newSongs),
      playlists: _rotate(data.playlists),
      charts: _rotate(data.charts),
      radio: _rotate(data.radio),
      albums: _rotate(data.albums),
      recommended: _rotate(data.recommended),
      listen: _rotate(data.listen),
      heart: _rotate(data.heart),
      hot: _rotate(data.hot),
      recommendedColumnId: data.recommendedColumnId,
      features: data.features,
      daily: _rotate(data.daily),
    );
  }

  List<T> _rotate<T>(List<T> values) {
    if (values.length <= 1) return values;
    final offset = _homeRefreshSeed % values.length;
    return <T>[...values.skip(offset), ...values.take(offset)];
  }

  /// 网易云首页推荐流：轮播 / 歌单 / 日推 / 新歌 / 私人FM / 独家放送。
  Future<void> loadNeteaseHome() async {
    if (neteaseHomeLoading) return;
    neteaseHomeLoading = true;
    error = null;
    neteaseHomeError = null;
    notifyListeners();
    try {
      final data = await netease.homeFeed();
      neteaseHome = data;
      neteasePlaylistOffset = data.playlists.length;
      neteaseHasMorePlaylists = data.playlists.isNotEmpty;
      homeSongs = mergeSongs(<List<Song>>[
        data.dailySongs,
        data.newSongs,
        data.radioSongs,
      ]);
      playlists = data.playlists;
      discover = DiscoverData(
        newSongs: homeSongs,
        playlists: data.playlists,
        radio: data.radioSongs,
      );
      discoverLoaded = data.isEmpty == false;
    } catch (e) {
      neteaseHomeError = e.toString();
      error = neteaseHomeError;
    } finally {
      neteaseHomeLoading = false;
      notifyListeners();
    }
  }

  /// 酷狗首页：每日推荐 + TOP500 + 用户歌单，全部走真实接口。
  Future<void> loadKugouHome() async {
    if (!kugou.isLoggedIn) return;
    await _guard(() async {
      final daily = await _soft(kugou.homeSongs(), <Song>[]);
      final rank = await _soft(kugou.homeRank(), <Song>[]);
      final lists = await _soft(kugou.userPlaylists(), <Playlist>[]);
      homeSongs = mergeSongs(<List<Song>>[daily, rank]);
      playlists = lists;
      charts = const <Playlist>[
        Playlist(id: '8888', name: '酷狗 TOP500', kind: 'chart'),
      ];
      discover = DiscoverData(
        newSongs: homeSongs,
        playlists: lists,
        charts: charts,
        radio: daily,
      );
      discoverLoaded = true;
    });
  }

  /// QQ 首页：推荐歌曲 + 歌单广场 + 我的歌单。
  Future<void> loadQqHome() async {
    await _guard(() async {
      final songs = await _soft(qq.homeSongs(), <Song>[]);
      final square = await _soft(qq.homePlaylists(), <Playlist>[]);
      final mine = await _soft(qq.userPlaylists(), <Playlist>[]);
      homeSongs = songs;
      playlists = <Playlist>[...mine, ...square];
      charts = const <Playlist>[];
      discover = DiscoverData(newSongs: songs, playlists: playlists);
      discoverLoaded = true;
    });
  }

  /// 推荐歌单「换一批」：按 offset 拉下一页，去重后追加。
  Future<void> loadMoreNeteasePlaylists() async {
    if (source != MusicSource.netease ||
        neteaseHomeLoading ||
        !neteaseHasMorePlaylists) {
      return;
    }
    neteaseHomeLoading = true;
    neteaseHomeError = null;
    notifyListeners();
    try {
      final more = await netease.homePlaylists(
        offset: neteasePlaylistOffset,
        limit: 12,
      );
      if (more.isEmpty) {
        neteaseHasMorePlaylists = false;
      } else {
        final existing = neteaseHome.playlists.map((p) => p.id).toSet();
        final added = more.where((p) => existing.add(p.id)).toList();
        neteaseHome = neteaseHome.copyWith(
          playlists: <Playlist>[...neteaseHome.playlists, ...added],
        );
        playlists = neteaseHome.playlists;
        neteasePlaylistOffset += more.length;
      }
    } catch (e) {
      neteaseHomeError = e.toString();
    } finally {
      neteaseHomeLoading = false;
      notifyListeners();
    }
  }

  /// 多个推荐源合并为一条流，按歌曲 ID 去重并保留首个来源顺序。
  static List<Song> mergeSongs(Iterable<List<Song>> groups) {
    final seen = <String>{};
    final out = <Song>[];
    for (final group in groups) {
      for (final song in group) {
        if (song.id.isNotEmpty && seen.add(song.id)) out.add(song);
      }
    }
    return out;
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
    searchArtists = <Artist>[];
    searchAlbums = <Playlist>[];
    searchPlaylists = <Playlist>[];
    hasMoreSearch = false;
    loadingMoreSearch = false;
    searchStart = 0;
    radioNext = '';
    radioMore = false;
    radioRefInfo = '';
    radioScenario = '16';
    radioMode = '1';
    audio.onQueueExhausted = null;
    neteaseHome = const NeteaseHomeData();
    neteaseHomeError = null;
    neteasePlaylistOffset = 0;
    neteaseHasMorePlaylists = true;
    notifyListeners();
    // 网易云公开推荐无需登录；华为必须登录后才请求业务接口。
    if (newSource == MusicSource.kugou) {
      await loadKugouHome();
    } else if (newSource == MusicSource.qq) {
      await loadQqHome();
    } else if (newSource == MusicSource.netease || isLoggedIn) {
      await loadHome();
    }
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
    playlistSongsList = await _soft(switch (source) {
      MusicSource.netease => netease.playlistTracks(playlist.id),
      MusicSource.kugou => kugou.playlistTracks(playlist.id),
      MusicSource.qq => qq.playlistTracks(playlist.id),
      MusicSource.huawei =>
        playlist.kind == 'album'
            ? api.albumSongs(playlist.id)
            : playlist.kind == 'chart'
            ? api.chartSongs(playlist.id)
            : api.playlistSongs(playlist),
    }, <Song>[]);
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
    // 网易云/酷狗暂无独立「歌手详情」接口：用歌手名搜索其歌曲，
    // 结果仍是真实接口数据，不伪造歌手页。
    if (source == MusicSource.netease ||
        source == MusicSource.kugou ||
        source == MusicSource.qq) {
      artistSongsList = await _soft(
        source == MusicSource.netease
            ? netease.search(activeArtist!.name)
            : source == MusicSource.kugou
            ? kugou.search(activeArtist!.name)
            : qq.search(activeArtist!.name),
        <Song>[],
      );
      notifyListeners();
      return;
    }
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      _soft<dynamic>(
        api.artistDetail(artistCode),
        const Artist(id: '', name: ''),
      ),
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
    comments = await _soft(switch (source) {
      MusicSource.netease => netease.comments(songCode),
      MusicSource.kugou => kugou.comments(songCode),
      MusicSource.qq => qq.comments(songCode),
      MusicSource.huawei => api.comments(songCode),
    }, <Comment>[]);
    notifyListeners();
  }

  Future<void> toggleFavorite(Song song) async {
    final next = !song.favorite;
    song.favorite = next;
    notifyListeners();
    try {
      if (source == MusicSource.huawei) {
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
          netease.userPlaylists(''),
          <Playlist>[],
        ); // uid 由登录后填
      } else if (source == MusicSource.kugou) {
        playlists = await _soft(kugou.userPlaylists(), <Playlist>[]);
      } else if (source == MusicSource.qq) {
        playlists = await _soft(qq.userPlaylists(), <Playlist>[]);
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
    // 切到任何卡片先摘掉上一轮心动续播；只有 heart 成功起播后再挂回。
    audio.onQueueExhausted = null;
    await _guard(() async {
      late List<Song> songs;
      final ne = source == MusicSource.netease;
      if (source == MusicSource.kugou) {
        switch (action) {
          case 'hot':
            songs = await kugou.homeRank();
            break;
          case 'daily':
          case 'radio':
          case 'heart':
          case 'new':
            songs = homeSongs.isNotEmpty ? homeSongs : await kugou.homeSongs();
            break;
          default:
            songs = homeSongs;
        }
        if (songs.isNotEmpty) {
          await play(songs.first, queue: songs);
        } else {
          error = '「$action」接口未返回歌曲（确认已登录 / 网络可用）';
        }
        return;
      }
      if (source == MusicSource.qq) {
        switch (action) {
          case 'hot':
          case 'new':
          case 'daily':
          case 'radio':
          case 'heart':
            songs = homeSongs.isNotEmpty ? homeSongs : await qq.homeSongs();
            break;
          default:
            songs = homeSongs;
        }
        if (songs.isNotEmpty) {
          await play(songs.first, queue: songs);
        } else {
          error = '「$action」接口未返回歌曲（确认已登录 / 网络可用）';
        }
        return;
      }
      if (!ne) {
        await _playHuaweiCard(action);
        return;
      }
      switch (action) {
        case 'radio':
          songs = neteaseHome.radioSongs.isNotEmpty
              ? neteaseHome.radioSongs
              : await netease.privateFm();
          break;
        case 'daily':
        case 'heart':
          songs = neteaseHome.dailySongs.isNotEmpty
              ? neteaseHome.dailySongs
              : await netease.dailySongs();
          break;
        case 'new':
        case 'hot':
          songs = discover.newSongs.isNotEmpty
              ? discover.newSongs
              : await netease.newSongs();
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

  /// 华为五个首页卡片各用各的板块：不从其他卡片借歌，接口空就保持空态。
  ///
  /// 语义（最新 REA）：
  /// - `listen` /「现在就听」来自首页聚合 `pmf001` 顶层直接歌曲，不走 privatefm；
  /// - `heart` /「心动模式」首屏走 `heartFmFirstPage()`，续页才用 privatefm；
  /// - `daily` / `new` / `hot` 各自只读本板块或本板块的专用接口。
  Future<void> _playHuaweiCard(String action) async {
    // 普通卡片默认不继承任何电台续播；只有心动模式成功起播后重新挂回调。
    audio.onQueueExhausted = null;
    var songs = const <Song>[];
    switch (action) {
      case 'radio':
        // 「现在就听」= 首页 pmf001 顶层直接歌曲，不再请求 privatefm。
        songs = discover.listen;
        break;
      case 'daily':
        songs = discover.daily.isNotEmpty
            ? discover.daily
            : await _soft(api.daily30(), <Song>[]);
        if (songs.isNotEmpty) {
          discover = discover.copyWith(daily: songs);
        }
        break;
      case 'heart':
        // 心动首屏优先走独立接口；失败/空只回退同源 heart 缓存，
        // 不拿 listen/radio/daily/hot 填充，也不再用 privateRadio(mode:'2') 猜。
        try {
          final page = await api.heartFmFirstPage();
          if (page.songs.isNotEmpty) {
            songs = page.songs;
            discover = discover.copyWith(heart: songs);
            radioNext = page.next;
            radioMore = page.more;
            radioRefInfo = page.refInfo;
            radioScenario = '16';
            radioMode = '1';
          } else {
            AppLog.add('state', 'heartFmFirstPage 返回空，回退本板块缓存');
            songs = discover.heart;
          }
        } catch (e) {
          AppLog.add('state', 'heartFmFirstPage 失败，回退本板块缓存：$e');
          songs = discover.heart;
        }
        break;
      case 'new':
        songs = discover.newSongs;
        break;
      case 'hot':
        songs = discover.hot.isNotEmpty
            ? discover.hot
            : await _soft(api.chartSongs(HuaweiAPI.hotChartId), <Song>[]);
        if (songs.isNotEmpty) {
          discover = discover.copyWith(hot: songs);
        }
        break;
      default:
        error = '「$action」独立板块未返回歌曲';
        return;
    }
    if (songs.isEmpty) {
      error = switch (action) {
        'radio' => '「现在就听」独立板块未返回歌曲',
        'heart' => '「心动模式」独立板块未返回歌曲',
        _ => '「$action」独立板块未返回歌曲',
      };
      return;
    }
    await play(songs.first, queue: songs);
    if (audio.error != null) return;
    if (action == 'heart') {
      audio.playEntry = 'heart';
      audio.onQueueExhausted = extendRadioQueue;
    } else {
      // 现在就听/每日/新歌/热歌都保持独立队列，播完不续任何电台。
      audio.onQueueExhausted = null;
    }
  }

  /// 心动模式播放到队列尾部时用 privatefm 请求下一页（续页形状固定为
  /// `mode=1` + `rcmScenario=16`），只把新歌追加到 `discover.heart`；
  /// 不会写入「现在就听」的 `discover.listen`。
  Future<List<Song>> extendRadioQueue() async {
    if (!radioMore || (radioNext.isEmpty && radioRefInfo.isEmpty)) {
      return const <Song>[];
    }
    final requestedNext = radioNext;
    try {
      final page = await api.privateFmPage(
        mode: radioMode,
        rcmScenario: '16',
        refInfo: radioRefInfo,
        next: requestedNext,
      );
      radioNext = page.next;
      radioMore = page.more;
      radioRefInfo = page.refInfo;
      radioScenario = '16';
      radioMode = '1';
      final seen = discover.heart
          .map((song) => song.id)
          .where((id) => id.isNotEmpty)
          .toSet();
      final added = <Song>[];
      for (final song in page.songs) {
        if (song.id.isEmpty || seen.add(song.id)) added.add(song);
      }
      if (added.isNotEmpty) {
        discover = discover.copyWith(
          heart: <Song>[...discover.heart, ...added],
        );
      }
      notifyListeners();
      return added;
    } catch (e) {
      error = '电台续播失败：${_readableError(e)}';
      AppLog.add('state', '$error');
      notifyListeners();
      return const <Song>[];
    }
  }

  Future<void> doSearch(String keyword) async {
    searchKeyword = keyword.trim();
    if (searchKeyword.isEmpty) {
      searchResults = <Song>[];
      searchArtists = <Artist>[];
      searchAlbums = <Playlist>[];
      searchPlaylists = <Playlist>[];
      hasMoreSearch = false;
      loadingMoreSearch = false;
      searchStart = 0;
      notifyListeners();
      return;
    }
    await _guard(() async {
      searchResults = <Song>[];
      searchArtists = <Artist>[];
      searchAlbums = <Playlist>[];
      searchPlaylists = <Playlist>[];
      hasMoreSearch = false;
      searchStart = 0;
      if (source == MusicSource.netease) {
        searchResults = await netease.search(searchKeyword);
      } else if (source == MusicSource.kugou) {
        searchResults = await kugou.search(searchKeyword);
      } else if (source == MusicSource.qq) {
        searchResults = await qq.search(searchKeyword);
      } else {
        final result = await api.searchAll(
          searchKeyword,
          start: 0,
          limit: 30,
          includePlaylists: true,
        );
        searchResults = result.songs;
        searchArtists = result.artists;
        searchAlbums = result.albums;
        searchPlaylists = result.playlists;
        hasMoreSearch = _searchPageHasMore(result);
        searchStart = 30;
      }
      tab = 1;
    });
  }

  /// 搜索页“加载更多”按钮：不做无限滚动，失败时保留已有结果。
  Future<void> loadMoreSearch() async {
    if (source != MusicSource.huawei ||
        loadingMoreSearch ||
        !hasMoreSearch ||
        searchKeyword.trim().isEmpty) {
      return;
    }
    final keyword = searchKeyword;
    final start = searchStart;
    loadingMoreSearch = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.searchAll(
        keyword,
        start: start,
        limit: 30,
        includePlaylists: true,
      );
      if (keyword != searchKeyword) return;
      _appendSearchPage(result);
      hasMoreSearch = _searchPageHasMore(result);
      searchStart = start + 30;
    } catch (e) {
      error = _readableError(e);
      AppLog.add('state', '搜索加载更多失败：$error');
    } finally {
      loadingMoreSearch = false;
      notifyListeners();
    }
  }

  static bool _searchPageHasMore(HuaweiSearchResult result) =>
      result.songs.length >= 30 ||
      result.artists.length >= 30 ||
      result.albums.length >= 30 ||
      result.playlists.length >= 30;

  void _appendSearchPage(HuaweiSearchResult result) {
    final songIds = searchResults
        .map((song) => song.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final song in result.songs) {
      if (song.id.isEmpty || songIds.add(song.id)) searchResults.add(song);
    }
    final artistIds = searchArtists
        .map((artist) => artist.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final artist in result.artists) {
      if (artist.id.isEmpty || artistIds.add(artist.id)) {
        searchArtists.add(artist);
      }
    }
    final albumIds = searchAlbums
        .map((album) => album.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final album in result.albums) {
      if (album.id.isEmpty || albumIds.add(album.id)) searchAlbums.add(album);
    }
    final playlistIds = searchPlaylists
        .map((playlist) => playlist.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final playlist in result.playlists) {
      if (playlist.id.isEmpty || playlistIds.add(playlist.id)) {
        searchPlaylists.add(playlist);
      }
    }
  }

  static String _readableError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  Future<void> showLyricsFor(Song song) async {
    showPlayer = true;
    showLyrics = false;
    notifyListeners();
    await refreshLyricsForCurrentSong(force: true);
  }

  /// 点播放条进入全屏播放器（默认封面/唱片区），不切到歌词焦点。
  Future<void> openFullPlayer(Song song) async {
    showPlayer = true;
    showLyrics = false;
    notifyListeners();
    await refreshLyricsForCurrentSong(force: true);
  }

  void closeFullPlayer() {
    showPlayer = false;
    showLyrics = false;
    notifyListeners();
  }

  void _onAudioChanged() {
    final current = audio.current;
    if (current?.id != _lastAudioSongId) {
      _lastAudioSongId = current?.id;
      _lyricsLoadGeneration++;
      _lyricsSongId = null;
      lyrics = <LyricLine>[];
      bumpLyricsRevision();
    }
    // 取流成功后才加载歌词：失败时不能为了歌词再发一次 playUrl。
    // 正常播放会复用 audioFiles 已缓存进 HuaweiAPI 的歌词地址。
    if (current != null &&
        current.id != _lyricsSongId &&
        audio.lastErrorCode == '000000' &&
        audio.error == null) {
      _lyricsSongId = current.id;
      final generation = ++_lyricsLoadGeneration;
      unawaited(_loadLyrics(current, generation: generation));
    }
    notifyListeners();
  }

  Future<void> refreshLyricsForCurrentSong({bool force = false}) async {
    final current = audio.current;
    if (current == null) {
      _lyricsLoadGeneration++;
      _lyricsSongId = null;
      lyrics = <LyricLine>[];
      bumpLyricsRevision();
      notifyListeners();
      return;
    }
    if (!force && current.id == _lyricsSongId && lyrics.isNotEmpty) {
      bumpLyricsRevision();
      notifyListeners();
      return;
    }
    _lyricsLoadGeneration++;
    _lyricsSongId = current.id;
    lyrics = <LyricLine>[];
    bumpLyricsRevision();
    notifyListeners();
    await _loadLyrics(current, generation: _lyricsLoadGeneration);
  }

  Future<void> _loadLyrics(Song song, {int? generation}) async {
    final requestGeneration = generation ?? ++_lyricsLoadGeneration;
    List<LyricLine> loaded = <LyricLine>[];
    try {
      if (source == MusicSource.huawei && song.lyricUrl != null) {
        loaded = await api.lyricsFromUrl(song.lyricUrl!);
        if (loaded.isEmpty) {
          loaded = await api.lyrics(song.id, allowPlaybackRequest: false);
        }
      } else {
        loaded = switch (source) {
          MusicSource.netease => await netease.lyrics(song.id),
          MusicSource.kugou => await kugou.lyrics(song.id),
          MusicSource.qq => await qq.lyrics(song.id),
          MusicSource.huawei => await api.lyrics(
            song.id,
            allowPlaybackRequest: false,
          ),
        };
      }
    } catch (e) {
      AppLog.add('lyrics', '${song.name} [${song.id}]: $e');
    }
    if (_disposed ||
        requestGeneration != _lyricsLoadGeneration ||
        _lyricsSongId != song.id) {
      return;
    }
    lyrics = loaded;
    bumpLyricsRevision();
    notifyListeners();
  }

  Future<void> play(Song song, {List<Song>? queue}) async {
    // 普通列表不继承上一张心动队列的服务端续播；只有心动模式成功起播后
    // 才重新挂上回调。
    audio.onQueueExhausted = null;
    final list = (queue == null || queue.isEmpty)
        ? <Song>[song]
        : List<Song>.of(queue);
    var start = list.indexWhere((s) => s.id == song.id);
    if (start < 0) {
      list.insert(0, song);
      start = 0;
    }
    final entry = _playEntryName(song, queue);
    audio.playEntry = entry;
    error = null;
    final attempts = list.length < 5 ? list.length : 5;
    String? lastError;
    for (var i = 0; i < attempts; i++) {
      final candidate = list[(start + i) % list.length];
      final hasPreset =
          candidate.localPath != null && candidate.localPath!.isNotEmpty;
      AppLog.add(
        'play',
        'entry=$entry song=${candidate.id} source=${candidate.source.name} '
        'presetUrl=$hasPreset queue=${list.length}',
      );
      await audio.playSong(candidate, list: list);
      AppLog.add(
        'play',
        'entry=$entry song=${candidate.id} '
        'qualityType=${audio.lastQualityType ?? '-'} '
        'hasUrl=${audio.lastHasUrl} code=${audio.lastErrorCode ?? '-'} '
        'error=${audio.error == null ? '-' : (audio.error!.length > 180 ? '${audio.error!.substring(0, 180)}…' : audio.error!)}',
      );
      if (audio.error == null) {
        error = null;
        notifyListeners();
        return;
      }
      lastError = audio.error;
      // 只有“这首不可播/无版权”才继续试下一首；网络错误直接报错，
      // 避免连续 5 次超时让界面像卡死。
      if (!_looksUnplayable(lastError)) break;
    }
    error = lastError ?? '无法播放该歌曲';
    onError?.call(error!);
    notifyListeners();
  }

  /// 从队列对象/内容推断点歌入口，仅用于日志与排障，不参与播放逻辑。
  String _playEntryName(Song song, List<Song>? queue) {
    bool same(List<Song> source) {
      if (queue == null) return false;
      if (identical(queue, source)) return true;
      if (queue.length != source.length || source.isEmpty) return false;
      for (var i = 0; i < queue.length; i++) {
        if (queue[i].id != source[i].id) return false;
      }
      return true;
    }

    if (queue != null) {
      if (same(favorites)) return 'favorites';
      if (same(searchResults)) return 'search';
      if (same(playlistSongsList)) {
        return activePlaylist?.kind == 'chart' ? 'chart' : 'playlist';
      }
      if (same(chartSongs)) return 'chart';
      if (same(artistSongsList)) return 'artist';
      if (same(discover.recommended)) return 'home/recommended';
      if (same(discover.daily)) return 'home/daily';
      if (same(discover.hot)) return 'home/hot';
      if (same(discover.newSongs)) return 'home/new';
      if (same(discover.heart)) return 'home/heart';
      if (same(discover.listen)) return 'home/listen';
      if (same(discover.radio)) return 'home/radio';
      if (same(homeSongs)) return 'home';
    }
    if (song.localPath != null && song.localPath!.isNotEmpty) return 'local';
    return 'queue';
  }

  static bool _looksUnplayable(String? message) {
    if (message == null || message.isEmpty) return false;
    final lower = message.toLowerCase();
    return message.contains('142400') ||
        message.contains('142411') ||
        lower.contains('super diamond vip') ||
        message.contains('超级钻石') ||
        message.contains('VIP 专享') ||
        lower.contains('vip only') ||
        message.contains('没有可用') ||
        message.contains('无版权') ||
        message.contains('版权') ||
        lower.contains('not available') ||
        message.contains('不可播放') ||
        message.contains('无法播放') ||
        message.contains('无法解码');
  }

  /// 测试/诊断用：与 [play] 的自动跳歌判定保持同一套规则。
  @visibleForTesting
  static bool looksUnplayable(String? message) =>
      _looksUnplayable(message);

  /// 供 UI 在修改局部状态后请求重建（避免外部直接调用受保护的 notifyListeners）
  void refresh() => notifyListeners();

  void selectTab(int i) {
    tab = i;
    showLyrics = false;
    showPlayer = false;
    notifyListeners();
    if (i == 0 && !discoverLoaded) loadHome();
    if (i == 3 && favorites.isEmpty && playlists.isEmpty) loadLibrary();
  }

  /// 循环切换 12 款主题。
  void toggleTheme() {
    setTheme((themeIndex + 1) % kMuyuPalettes.length);
  }

  void setTheme(int index) {
    themeIndex = index.clamp(0, kMuyuPalettes.length - 1);
    if (palette.dark) {
      _lastDarkTheme = themeIndex;
    } else {
      _lastLightTheme = themeIndex;
    }
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  /// 设置页的深色/浅色开关：在最近一次浅色与深色主题之间切换，
  /// 不再顺次循环 12 套主题。
  void toggleDarkMode() {
    if (palette.dark) {
      themeIndex = _lastLightTheme ?? 0;
    } else {
      _lastLightTheme = themeIndex;
      themeIndex = _lastDarkTheme ?? 6;
    }
    if (palette.dark) {
      _lastDarkTheme = themeIndex;
    } else {
      _lastLightTheme = themeIndex;
    }
    notifyListeners();
    bumpLyricsRevision();
    unawaited(persistSession());
  }

  void signInWithToken(String token) {
    api.signInWithToken(token);
    notifyListeners();
    persistSession();
    refreshHome(force: true);
    loadLibrary();
  }

  /// 启动时恢复登录态；恢复后由调用方决定是否自动加载首页/曲库。
  Future<void> restoreSession() async {
    await local.load();
    _savedHuaweiCredentials = await _sessionStore.readCredentials();
    final snapshot = await _sessionStore.read();
    if (snapshot == null) return;
    _lastReloginEpoch = snapshot.lastReloginEpoch;
    var hasMusicSession =
        snapshot.huaweiToken.isNotEmpty && snapshot.huaweiUserId.isNotEmpty;
    if (hasMusicSession) {
      api.restoreSession(
        musicToken: snapshot.huaweiToken,
        snsUserId: snapshot.huaweiUserId,
        accountToken: snapshot.huaweiAccountToken,
        refreshToken: snapshot.huaweiRefreshToken.isNotEmpty
            ? snapshot.huaweiRefreshToken
            : null,
        expireTime: snapshot.huaweiExpireTime,
        nick: snapshot.huaweiNickname,
      );
      api.avatarUrl = snapshot.huaweiAvatar.isEmpty
          ? null
          : snapshot.huaweiAvatar;
      api.memberLabel = snapshot.huaweiMemberLabel.isEmpty
          ? null
          : snapshot.huaweiMemberLabel;
      api.isMember = snapshot.huaweiIsMember;
    } else {
      api.gateway.accountToken = snapshot.huaweiAccountToken.isEmpty
          ? null
          : snapshot.huaweiAccountToken;
      api.gateway.refreshToken = snapshot.huaweiRefreshToken.isEmpty
          ? null
          : snapshot.huaweiRefreshToken;
    }

    final sessionExpired = hasMusicSession && !api.isLoggedIn;
    final canRenew =
        (api.gateway.refreshToken?.isNotEmpty ?? false) ||
        (api.gateway.accountToken?.isNotEmpty ?? false);
    if (sessionExpired || (!hasMusicSession && canRenew)) {
      final renewed = await _refreshHuaweiSession();
      hasMusicSession = renewed;
      if (!renewed) {
        api.gateway.session = null;
        error = '登录已过期，请重新完成华为 OAuth 验证';
        needsRelogin = _savedHuaweiCredentials != null;
        AppLog.add('state', '音乐会话恢复失败，需要重新授权');
      }
    } else if (hasMusicSession) {
      // 后台补全真实昵称/头像/会员；失败不影响启动。
      api.refreshProfile();
    }
    if (snapshot.neteaseMusicU.isNotEmpty) {
      netease.signInWithCookies(
        snapshot.neteaseMusicU,
        csrf: snapshot.neteaseCsrf,
        nickname: snapshot.neteaseNickname,
        userId: snapshot.neteaseUserId,
      );
    }
    if (snapshot.kugouCookies.isNotEmpty) {
      kugou.signInWithCookies(Map<String, dynamic>.from(snapshot.kugouCookies));
    }
    if (snapshot.qqCookies.isNotEmpty) {
      qq.signInWithCookies(Map<String, dynamic>.from(snapshot.qqCookies));
    }
    // 当前产品只保留华为入口；旧快照里的其它音源不再恢复为当前音源。
    source = MusicSource.huawei;
    audio.source = source;
    await _applyPersistedSettings(snapshot);
    notifyListeners();
  }

  Future<void> _applyPersistedSettings(SessionSnapshot snapshot) async {
    themeIndex = snapshot.themeIndex.clamp(0, kMuyuPalettes.length - 1);
    if (palette.dark) {
      _lastDarkTheme = themeIndex;
    } else {
      _lastLightTheme = themeIndex;
    }
    lyricStyle = LyricStyle(
      align: LyricAlign
          .values[snapshot.lyricStyleAlign.clamp(0, LyricAlign.values.length - 1)],
      bold: snapshot.lyricStyleBold,
      columns: snapshot.lyricStyleColumns.clamp(1, 3),
      fontScale: snapshot.lyricStyleFontScale.clamp(0.5, 2.0),
      font: snapshot.lyricStyleFont,
      followCoverColor: snapshot.lyricStyleFollowCoverColor,
    );
    glass = ImmersiveGlass
        .values[snapshot.glassIndex.clamp(0, ImmersiveGlass.values.length - 1)];
    glowColor = Color(snapshot.glowColorArgb);
    glassPress = snapshot.glassPress;
    glassSlide = snapshot.glassSlide;
    audio.quality = AudioQuality.values.firstWhere(
      (quality) => quality.name == snapshot.qualityName,
      orElse: () =>
          AudioQuality.values[snapshot.qualityIndex.clamp(
            0,
            AudioQuality.values.length - 1,
          )],
    );
    if (MuyuAudioController.kEffects.contains(snapshot.effect)) {
      audio.effect = snapshot.effect;
    }
    final maxOffsetMs = MuyuAudioController.maxLyricOffset.inMilliseconds;
    final offsetMs = snapshot.lyricOffsetMs.clamp(-maxOffsetMs, maxOffsetMs);
    await audio.adjustLyricOffset(
      Duration(milliseconds: offsetMs) - audio.lyricOffset,
    );
    try {
      await audio.setVolume(snapshot.volume.clamp(0.0, 1.0).toDouble());
    } catch (_) {
      // 启动早期音频插件可能尚未就绪；状态值已恢复，播放时仍会应用。
      audio.volume = snapshot.volume.clamp(0.0, 1.0).toDouble();
    }
    bumpLyricsRevision();
  }

  /// 登录成功后落盘；凭证变化（401 自动换会话）也会回调到这里。
  Future<void> persistSession() async {
    await _sessionStore.write(
      SessionSnapshot(
        source: source.name,
        huaweiToken: api.gateway.session?.token ?? '',
        huaweiUserId: api.gateway.session?.snsUserId ?? '',
        huaweiAccountToken: api.gateway.accountToken ?? '',
        huaweiRefreshToken: api.gateway.refreshToken ?? '',
        huaweiExpireTime: api.gateway.session?.expireTime ?? '',
        huaweiNickname: api.displayName ?? '',
        huaweiAvatar: api.avatarUrl ?? '',
        huaweiMemberLabel: api.memberLabel ?? '',
        huaweiIsMember: api.isMember,
        neteaseMusicU: netease.gateway.session?.musicU ?? '',
        neteaseCsrf: netease.gateway.session?.csrf ?? '',
        neteaseNickname: netease.gateway.session?.nickname ?? '',
        neteaseUserId: netease.gateway.session?.userId ?? '',
        kugouCookies:
            kugou.gateway.session?.cookies ?? const <String, String>{},
        qqCookies: qq.gateway.session?.cookies ?? const <String, String>{},
        themeIndex: themeIndex,
        autoLoginEnabled: _savedHuaweiCredentials != null,
        lastReloginEpoch: _lastReloginEpoch,
        volume: audio.volume,
        effect: audio.effect,
        qualityIndex: audio.quality.index,
        qualityName: audio.quality.name,
        lyricOffsetMs: audio.lyricOffset.inMilliseconds,
        lyricStyleAlign: lyricStyle.align.index,
        lyricStyleBold: lyricStyle.bold,
        lyricStyleColumns: lyricStyle.columns,
        lyricStyleFontScale: lyricStyle.fontScale,
        lyricStyleFont: lyricStyle.font,
        lyricStyleFollowCoverColor: lyricStyle.followCoverColor,
        glassIndex: glass.index,
        glowColorArgb: glowColor.toARGB32(),
        glassPress: glassPress,
        glassSlide: glassSlide,
      ),
    );
  }

  void signOut() {
    api.signOut();
    netease.signOut();
    kugou.signOut();
    qq.signOut();
    _authChangedAt = null;
    _lastForcedRefreshAt = null;
    _homeRetryBlockedUntil = null;
    _savedHuaweiCredentials = null;
    needsRelogin = false;
    _lastReloginEpoch = 0;
    unawaited(_sessionStore.clear());
    homeSongs = <Song>[];
    favorites = <Song>[];
    playlists = <Playlist>[];
    charts = <Playlist>[];
    chartSongs = <Song>[];
    activeChartId = null;
    discover = const DiscoverData();
    discoverLoaded = false;
    searchResults = <Song>[];
    searchArtists = <Artist>[];
    searchAlbums = <Playlist>[];
    searchPlaylists = <Playlist>[];
    hasMoreSearch = false;
    loadingMoreSearch = false;
    searchStart = 0;
    radioNext = '';
    radioMore = false;
    radioRefInfo = '';
    radioScenario = '16';
    radioMode = '1';
    audio.onQueueExhausted = null;
    neteaseHome = const NeteaseHomeData();
    neteaseHomeError = null;
    neteasePlaylistOffset = 0;
    neteaseHasMorePlaylists = true;
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
      if (error!.contains('990000') || error!.contains('重新登录')) {
        // 日志里 990000 会在 5 秒内连打 20 次首页请求；鉴权失败时
        // 冷却 30 秒，等待用户重新登录，不再自动风暴重试。
        _homeRetryBlockedUntil = DateTime.now().add(
          const Duration(seconds: 30),
        );
      }
      AppLog.add('state', error!);
      onError?.call(error!);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 本地音乐导入：返回成功导入数量，错误写入 [error]。
  Future<int> importLocalMusic() async {
    final added = await local.importFromPicker();
    if (local.error != null) error = local.error;
    notifyListeners();
    return added;
  }

  Future<void> removeLocalMusic(Song song) => local.remove(song);

  @override
  void dispose() {
    _disposed = true;
    _sessionKeepAliveTimer?.cancel();
    _sessionKeepAliveTimer = null;
    audio.removeListener(_onAudioChanged);
    local.removeListener(notifyListeners);
    local.dispose();
    audio.dispose();
    lyricsRevision.dispose();
    api.gateway.dispose();
    netease.gateway.dispose();
    kugou.gateway.dispose();
    qq.gateway.dispose();
    super.dispose();
  }
}
