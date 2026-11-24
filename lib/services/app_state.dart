import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;

import '../models.dart';
import '../models_home.dart';
import '../models_skin.dart';
import '../protocol/huawei_api.dart';
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
  AppState({SessionStore? sessionStore})
      : _sessionStore = sessionStore ?? PreferencesSessionStore() {
    audio.addListener(notifyListeners);
    local.addListener(notifyListeners);
    // 授权码换到的账号 token / 音乐 token 变化时立刻持久化。
    api.gateway.onSessionChanged = () => persistSession();
    api.onProfileChanged = () {
      persistSession();
      notifyListeners();
    };
  }

  final SessionStore _sessionStore;
  final HuaweiAPI api = HuaweiAPI();
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

  late final MuyuAudioController audio =
      MuyuAudioController(api, netease: netease, kugou: kugou, qq: qq);

  int tab = 0;
  bool loading = false;
  String? error;
  void Function(String message)? onError;
  bool showLyrics = false;
  bool showPlayer = false;

  /// 12 款主题索引（源码事实 tinglan/theme.go），默认晨光。
  int themeIndex = 0;
  int? _lastLightTheme;
  int? _lastDarkTheme = 6;
  MuyuPalette get palette => kMuyuPalettes[themeIndex.clamp(0, kMuyuPalettes.length - 1)];
  bool get darkMode => palette.dark; // 兼容旧 ThemeMode 逻辑
  int homePage = 1;
  int _homeRefreshSeed = 0;

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
  List<Artist> searchArtists = <Artist>[];
  List<Playlist> searchAlbums = <Playlist>[];
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
  Future<void> loadHome() async {
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
    await _guard(() async {
      var data = await api.discover();
      // 首页聚合接口偶发返回空结构：改用推荐歌单/榜单两个独立服务兜底，
      // 仍是真实接口数据，不填假歌。
      if (data.newSongs.isEmpty &&
          data.playlists.isEmpty &&
          data.charts.isEmpty &&
          data.radio.isEmpty) {
        final lists = await _soft(api.recommendedPlaylists(), <Playlist>[]);
        final charts = await _soft(api.charts(), <Playlist>[]);
        if (lists.isNotEmpty || charts.isNotEmpty) {
          data = DiscoverData(playlists: lists, charts: charts);
        }
      }
      discover = _rotateDiscover(data);
      homeSongs = discover.newSongs;
      playlists = discover.playlists;
      charts = discover.charts;
      discoverLoaded = true;
    });
  }

  /// 首页「刷新」：服务端同一账号的推荐接口目前返回同一批内容，
  /// 这里在真实数据上做确定性的轮换，保证每次刷新首屏会变化。
  Future<void> refreshHome() async {
    _homeRefreshSeed++;
    await loadHome();
  }

  DiscoverData _rotateDiscover(DiscoverData data) {
    if (_homeRefreshSeed == 0) return data;
    return DiscoverData(
      banners: data.banners,
      newSongs: _rotate(data.newSongs),
      playlists: _rotate(data.playlists),
      charts: data.charts,
      radio: _rotate(data.radio),
      albums: _rotate(data.albums),
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
    playlistSongsList = await _soft(
      switch (source) {
        MusicSource.netease => netease.playlistTracks(playlist.id),
        MusicSource.kugou => kugou.playlistTracks(playlist.id),
        MusicSource.qq => qq.playlistTracks(playlist.id),
        MusicSource.huawei => playlist.kind == 'album'
            ? api.albumSongs(playlist.id)
            : playlist.kind == 'chart'
                ? api.chartSongs(playlist.id)
                : api.playlistSongs(playlist),
      },
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
      switch (source) {
        MusicSource.netease => netease.comments(songCode),
        MusicSource.kugou => kugou.comments(songCode),
        MusicSource.qq => qq.comments(songCode),
        MusicSource.huawei => api.comments(songCode),
      },
      <Comment>[],
    );
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
            netease.userPlaylists(''), <Playlist>[]); // uid 由登录后填
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
      switch (action) {
        case 'radio':
          songs = ne
              ? (neteaseHome.radioSongs.isNotEmpty
                  ? neteaseHome.radioSongs
                  : await netease.privateFm())
              : await api.privateRadio(mode: '1');
          break;
        case 'daily':
          songs = ne
              ? (neteaseHome.dailySongs.isNotEmpty
                  ? neteaseHome.dailySongs
                  : await netease.dailySongs())
              : await api.dailySongs();
          break;
        case 'heart':
          songs = ne
              ? (neteaseHome.dailySongs.isNotEmpty
                  ? neteaseHome.dailySongs
                  : await netease.dailySongs())
              : await api.privateRadio(mode: '2');
          break;
        case 'new':
          songs = discover.newSongs.isNotEmpty
              ? discover.newSongs
              : (ne ? await netease.newSongs() : await api.dailySongs());
          break;
        case 'hot':
          if (ne) {
            songs = discover.newSongs.isNotEmpty
                ? discover.newSongs
                : await netease.newSongs();
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
      searchArtists = <Artist>[];
      searchAlbums = <Playlist>[];
      notifyListeners();
      return;
    }
    await _guard(() async {
      if (source == MusicSource.netease) {
        searchResults = await netease.search(searchKeyword);
        searchArtists = <Artist>[];
        searchAlbums = <Playlist>[];
      } else if (source == MusicSource.kugou) {
        searchResults = await kugou.search(searchKeyword);
        searchArtists = <Artist>[];
        searchAlbums = <Playlist>[];
      } else if (source == MusicSource.qq) {
        searchResults = await qq.search(searchKeyword);
        searchArtists = <Artist>[];
        searchAlbums = <Playlist>[];
      } else {
        final result = await api.searchAll(searchKeyword);
        searchResults = result.songs;
        searchArtists = result.artists;
        searchAlbums = result.albums;
      }
      tab = 1;
    });
  }

  Future<void> showLyricsFor(Song song) async {
    showPlayer = true;
    showLyrics = true;
    notifyListeners();
    await _loadLyrics(song);
  }

  /// 点播放条进入全屏播放器（默认封面/唱片区），不切到歌词焦点。
  Future<void> openFullPlayer(Song song) async {
    showPlayer = true;
    showLyrics = false;
    notifyListeners();
    await _loadLyrics(song);
  }

  void closeFullPlayer() {
    showPlayer = false;
    showLyrics = false;
    notifyListeners();
  }

  Future<void> _loadLyrics(Song song) async {
    try {
      if (source == MusicSource.huawei && song.lyricUrl != null) {
        lyrics = await api.lyricsFromUrl(song.lyricUrl!);
        if (lyrics.isEmpty) lyrics = await api.lyrics(song.id);
      } else {
        lyrics = switch (source) {
          MusicSource.netease => await netease.lyrics(song.id),
          MusicSource.kugou => await kugou.lyrics(song.id),
          MusicSource.qq => await qq.lyrics(song.id),
          MusicSource.huawei => await api.lyrics(song.id),
        };
      }
    } catch (e) {
      lyrics = <LyricLine>[];
      AppLog.add('lyrics', '${song.name} [${song.id}]: $e');
    }
    notifyListeners();
  }

  Future<void> play(Song song, {List<Song>? queue}) async {
    final list = (queue == null || queue.isEmpty)
        ? <Song>[song]
        : List<Song>.of(queue);
    var start = list.indexWhere((s) => s.id == song.id);
    if (start < 0) {
      list.insert(0, song);
      start = 0;
    }
    error = null;
    final attempts = list.length < 5 ? list.length : 5;
    String? lastError;
    for (var i = 0; i < attempts; i++) {
      final candidate = list[(start + i) % list.length];
      await audio.playSong(candidate, list: list);
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

  static bool _looksUnplayable(String? message) {
    if (message == null || message.isEmpty) return false;
    return message.contains('142400') ||
        message.contains('没有可用') ||
        message.contains('无版权') ||
        message.contains('版权') ||
        message.contains('not available') ||
        message.contains('不可播放');
  }

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
    persistSession();
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
    persistSession();
  }

  void signInWithToken(String token) {
    api.signInWithToken(token);
    notifyListeners();
    persistSession();
    loadHome();
    loadLibrary();
  }

  /// 启动时恢复登录态；恢复后由调用方决定是否自动加载首页/曲库。
  Future<void> restoreSession() async {
    await local.load();
    final snapshot = await _sessionStore.read();
    if (snapshot == null) return;
    if (snapshot.huaweiToken.isNotEmpty && snapshot.huaweiUserId.isNotEmpty) {
      api.restoreSession(
        musicToken: snapshot.huaweiToken,
        snsUserId: snapshot.huaweiUserId,
        accountToken: snapshot.huaweiAccountToken,
        refreshToken: snapshot.huaweiAccountToken.isNotEmpty
            ? snapshot.huaweiAccountToken
            : null,
        nick: snapshot.huaweiNickname,
      );
      api.avatarUrl =
          snapshot.huaweiAvatar.isEmpty ? null : snapshot.huaweiAvatar;
      api.memberLabel = snapshot.huaweiMemberLabel.isEmpty
          ? null
          : snapshot.huaweiMemberLabel;
      api.isMember = snapshot.huaweiIsMember;
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
      kugou.signInWithCookies(
        Map<String, dynamic>.from(snapshot.kugouCookies),
      );
    }
    if (snapshot.qqCookies.isNotEmpty) {
      qq.signInWithCookies(Map<String, dynamic>.from(snapshot.qqCookies));
    }
    source = MusicSource.values.firstWhere(
      (s) => s.name == snapshot.source,
      orElse: () => MusicSource.huawei,
    );
    audio.source = source;
    themeIndex = snapshot.themeIndex.clamp(0, kMuyuPalettes.length - 1);
    if (palette.dark) {
      _lastDarkTheme = themeIndex;
    } else {
      _lastLightTheme = themeIndex;
    }
    notifyListeners();
  }

  /// 登录成功后落盘；凭证变化（401 自动换会话）也会回调到这里。
  Future<void> persistSession() async {
    await _sessionStore.write(SessionSnapshot(
      source: source.name,
      huaweiToken: api.gateway.session?.token ?? '',
      huaweiUserId: api.gateway.session?.snsUserId ?? '',
      huaweiAccountToken: api.gateway.accountToken ?? '',
      huaweiNickname: api.displayName ?? '',
      huaweiAvatar: api.avatarUrl ?? '',
      huaweiMemberLabel: api.memberLabel ?? '',
      huaweiIsMember: api.isMember,
      neteaseMusicU: netease.gateway.session?.musicU ?? '',
      neteaseCsrf: netease.gateway.session?.csrf ?? '',
      neteaseNickname: netease.gateway.session?.nickname ?? '',
      neteaseUserId: netease.gateway.session?.userId ?? '',
      kugouCookies: kugou.gateway.session?.cookies ?? const <String, String>{},
      qqCookies: qq.gateway.session?.cookies ?? const <String, String>{},
      themeIndex: themeIndex,
    ));
  }

  void signOut() {
    api.signOut();
    netease.signOut();
    kugou.signOut();
    qq.signOut();
    _sessionStore.clear();
    homeSongs = <Song>[];
    favorites = <Song>[];
    playlists = <Playlist>[];
    charts = <Playlist>[];
    chartSongs = <Song>[];
    activeChartId = null;
    discover = const DiscoverData();
    discoverLoaded = false;
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
    audio.removeListener(notifyListeners);
    local.removeListener(notifyListeners);
    local.dispose();
    audio.dispose();
    api.gateway.dispose();
    netease.gateway.dispose();
    kugou.gateway.dispose();
    qq.gateway.dispose();
    super.dispose();
  }
}
