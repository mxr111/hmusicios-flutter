import 'dart:convert';

import '../models.dart';
import '../services/app_log.dart';
import 'endpoints.dart';
import 'huawei_gateway.dart';

/// 发现页真实数据（字段名来自 REA 对 Muyu.exe 的符号 + 运行时堆取证：
/// dailyRecInfos / chartInfos / chartID / picture / songNum / columnExtendInfo）。
/// 任何板块为 empty 都表示接口没有返回该数据，UI 必须显示空状态而不是假内容。
class DiscoverData {
  const DiscoverData({
    this.banners = const <DiscoverBanner>[],
    this.newSongs = const <Song>[],
    this.playlists = const <Playlist>[],
    this.charts = const <Playlist>[],
    this.radio = const <Song>[],
    this.albums = const <Playlist>[],
    this.recommended = const <Song>[],
    this.listen = const <Song>[],
    this.heart = const <Song>[],
    this.hot = const <Song>[],
    this.recommendedColumnId,
    this.features = const <DiscoverFeature>[],
    this.daily = const <Song>[],
  });

  final List<DiscoverBanner> banners;
  final List<Song> newSongs;
  final List<Playlist> playlists;
  final List<Playlist> charts;
  final List<Song> radio;
  final List<Playlist> albums;

  /// 首页「为你推荐」：来自私享好歌栏目（recom_exclusive / 8011）。
  final List<Song> recommended;

  /// 「现在就听」独立曲库；heart = 心动模式；hot = 热歌速递。
  final List<Song> listen;
  final List<Song> heart;
  final List<Song> hot;
  final String? recommendedColumnId;
  final List<DiscoverFeature> features;
  final List<Song> daily;

  DiscoverData copyWith({
    List<DiscoverBanner>? banners,
    List<Song>? newSongs,
    List<Playlist>? playlists,
    List<Playlist>? charts,
    List<Song>? radio,
    List<Playlist>? albums,
    List<Song>? recommended,
    List<Song>? listen,
    List<Song>? heart,
    List<Song>? hot,
    String? recommendedColumnId,
    List<DiscoverFeature>? features,
    List<Song>? daily,
  }) {
    return DiscoverData(
      banners: banners ?? this.banners,
      newSongs: newSongs ?? this.newSongs,
      playlists: playlists ?? this.playlists,
      charts: charts ?? this.charts,
      radio: radio ?? this.radio,
      albums: albums ?? this.albums,
      recommended: recommended ?? this.recommended,
      listen: listen ?? this.listen,
      heart: heart ?? this.heart,
      hot: hot ?? this.hot,
      recommendedColumnId: recommendedColumnId ?? this.recommendedColumnId,
      features: features ?? this.features,
      daily: daily ?? this.daily,
    );
  }
}

/// 首页真实功能卡。`id` 必须是响应里的真实 contentID（例如 `pmf001` / `a001`），
/// 不再使用二进制里不存在的 serviceType。
class DiscoverFeature {
  const DiscoverFeature({required this.id, required this.title, this.cover});

  final String id;
  final String title;
  final Uri? cover;
}

class DiscoverBanner {
  const DiscoverBanner({
    required this.title,
    this.subtitle = '',
    this.imageUrl,
  });
  final String title;
  final String subtitle;
  final Uri? imageUrl;
}

/// 私人电台单页结果。游标字段只在响应真实给出时才有值，无法解析时保持空
/// 游标 / `more=false`，避免客户端伪造续播状态。
class HuaweiPrivateFmPage {
  const HuaweiPrivateFmPage({
    this.songs = const <Song>[],
    this.next = '',
    this.more = false,
    this.refInfo = '',
    this.rcmScenario = '16',
    this.mode = '1',
  });
  final List<Song> songs;
  final String next;
  final bool more;
  final String refInfo;
  final String rcmScenario;
  final String mode;
}

class _HomeBatch {
  _HomeBatch(this.id, this.label, {this.topLevel = false});
  final String id;
  final String label;
  final bool topLevel;
  final List<Song> songs = <Song>[];
}

/// 一次华为搜索返回的三类结果。
class HuaweiSearchResult {
  const HuaweiSearchResult({
    this.songs = const <Song>[],
    this.artists = const <Artist>[],
    this.albums = const <Playlist>[],
    this.playlists = const <Playlist>[],
  });
  final List<Song> songs;
  final List<Artist> artists;

  /// 专辑复用 Playlist 卡片模型，kind 固定为 'album'。
  final List<Playlist> albums;

  /// 搜索结果中的歌单（contentType=4），kind 固定为 'playlist'。
  final List<Playlist> playlists;
}

/// 取流响应里与音质无关的歌词地址，缓存后供歌词加载复用。
class _PlaybackLyrics {
  const _PlaybackLyrics({this.wordUrl, this.plainUrl});

  final Uri? wordUrl;
  final Uri? plainUrl;

  bool get isEmpty => wordUrl == null && plainUrl == null;

  _PlaybackLyrics merge(_PlaybackLyrics other) => _PlaybackLyrics(
    wordUrl: wordUrl ?? other.wordUrl,
    plainUrl: plainUrl ?? other.plainUrl,
  );
}

/// 与沐语 Go 版 internal/catalog 对等：首页 / 搜索 / 榜单 / 收藏 / 歌单 /
/// 歌词 / 相似推荐 / 取流。解析全部走容错取值，不依赖严格 DTO。
class HuaweiAPI {
  HuaweiAPI({HuaweiGateway? gateway}) : gateway = gateway ?? HuaweiGateway();

  final HuaweiGateway gateway;
  static const int _maxPlaybackLyrics = 64;
  final Map<String, _PlaybackLyrics> _playbackLyrics =
      <String, _PlaybackLyrics>{};
  String? displayName;
  String? avatarUrl;
  String? memberLabel;
  bool isMember = false;
  void Function()? onProfileChanged;

  /// 真实首页常量（REA 证据：recom_exclusive / 8011、每日30首 a001、热歌榜 24926）。
  static const String featuredColumnPath =
      '/music-operation-service/v1/service/column/detail/bycolumnid';
  static const String dailyPlaylistPath =
      '/music-operation-service/v3/service/musiclist/detail/bymusiclistid';
  static const String featuredColumnId = '8011';
  static const String dailyPlaylistId = 'a001';
  static const String hotChartId = '24926';

  static const Duration _authCooldown = Duration(seconds: 30);
  DateTime? _authRetryBlockedUntil;
  Future<void>? _sessionRefresh;

  /// 990000 会话刷新失败后的 30 秒冷却状态（测试 / 日志导出可见）。
  bool get isAuthCoolingDown {
    final until = _authRetryBlockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void clearAuthCooldown() {
    _authRetryBlockedUntil = null;
  }

  /// 源码事实：必须有音乐会话（token + snsUserID）才能发业务请求。
  bool get isLoggedIn {
    final session = gateway.session;
    return session != null && !session.isExpired;
  }

  /// 手动填入音乐 token + snsUserID（调试用，跳过 OAuth 流程）。
  void signInWithSession(String musicToken, String snsUserId, {String? nick}) {
    gateway.session = MusicSession(
      token: musicToken.trim(),
      snsUserId: snsUserId.trim(),
    );
    displayName = (nick != null && nick.trim().isNotEmpty) ? nick.trim() : null;
    gateway.onSessionChanged?.call();
    onProfileChanged?.call();
    refreshProfile();
  }

  /// 从本地持久化数据恢复会话，不需要用户重新扫码。
  void restoreSession({
    required String musicToken,
    required String snsUserId,
    String? accountToken,
    String? refreshToken,
    String? expireTime,
    String? nick,
  }) {
    if (musicToken.trim().isEmpty || snsUserId.trim().isEmpty) return;
    gateway.session = MusicSession(
      token: musicToken.trim(),
      snsUserId: snsUserId.trim(),
      expireTime: expireTime?.trim() ?? '',
    );
    if (accountToken != null && accountToken.isNotEmpty) {
      gateway.accountToken = accountToken;
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      gateway.refreshToken = refreshToken;
    }
    displayName = nick?.isNotEmpty == true ? nick : null;
  }

  /// 兼容旧名：只给 token 时 snsUserID 留空（收藏等接口会失败），
  /// 仅用于快速验证取流。完整功能请用 signInWithSession / signInWithCode。
  void signInWithToken(String token, {String? nick}) {
    signInWithSession(token.trim(), '', nick: nick);
  }

  /// 三段式登录第 2、3 步：授权码 -> 账号 AT -> 音乐会话。
  /// 第 1 步（打开授权页 + PKCE）由 UI 层的 OAuth 流程完成后把 code/verifier 传入。
  Future<void> signInWithCode(String code, String verifier) async {
    final accessToken = await gateway.exchangeOAuthCode(code, verifier);
    await gateway.exchangeMusicToken(accessToken);
    await refreshProfile();
  }

  /// 兼容旧接口名：账号密码登录不是源码支持的方式（tinglan 用扫码 OAuth）。
  /// 这里明确拒绝，避免误导。
  Future<void> signInWithAccount(String account, String password) async {
    throw const HuaweiException('华为音乐不支持账号密码直登，请使用扫码登录（OAuth PKCE）');
  }

  void signOut() {
    gateway.session = null;
    gateway.accountToken = null;
    gateway.refreshToken = null;
    displayName = null;
    avatarUrl = null;
    memberLabel = null;
    isMember = false;
    onProfileChanged?.call();
  }

  /// 真实账号资料：昵称/头像优先取 OAuth userinfo，再用音乐侧
  /// userinfo 兜底（老会话没有 profile scope 时也能显示真实昵称/头像）；
  /// 会员名称来自订阅接口。
  Future<void> refreshProfile() async {
    final at = gateway.accountToken;
    if (at != null && at.isNotEmpty) {
      try {
        final info = await gateway.accountUserInfo(at);
        _applyProfile(info);
      } catch (_) {
        // scope 不含 profile 或账号 AT 过期时继续用音乐侧资料兜底。
      }
    }
    if (_needsProfile()) {
      try {
        final info = await gateway.musicUserInfo();
        if (info != null) _applyProfile(info);
      } catch (_) {
        // 资料接口不可用时保留已有昵称/头像，不影响播放。
      }
    }
    try {
      final json = await gateway.get(HuaweiPaths.subscription);
      final domains = json['domainSubInfos'];
      if (domains is List) {
        for (final domain in domains) {
          if (domain is! Map) continue;
          if ('${domain['domainType']}' != '1') continue;
          final had = domain['hadVIPs'];
          final isVip = had is Map && '${had['vipFlag']}' == '1';
          if (!isVip) continue;
          final subs = domain['subInfos'];
          if (subs is List) {
            for (final sub in subs) {
              if (sub is! Map) continue;
              final product = sub['productInfo'];
              if (product is Map) {
                final name = HuaweiGateway.firstString(
                  Map<String, dynamic>.from(product),
                  const ['productName', 'baseProductName'],
                );
                if (name != null && name.isNotEmpty) {
                  memberLabel = name;
                  isMember = true;
                  break;
                }
              }
            }
          }
          isMember = true;
        }
      }
    } catch (_) {}
    if (displayName == null ||
        displayName!.isEmpty ||
        displayName == '华为音乐账号') {
      final uid = gateway.session?.snsUserId ?? '';
      if (uid.isNotEmpty) {
        final tail = uid.length > 4 ? uid.substring(uid.length - 4) : uid;
        displayName = '华为音乐用户 $tail';
      }
    }
    onProfileChanged?.call();
  }

  bool _needsProfile() =>
      gateway.session != null &&
      ((displayName == null ||
              displayName!.isEmpty ||
              displayName == '华为音乐账号') ||
          (avatarUrl == null || avatarUrl!.isEmpty));

  void _applyProfile(Map<String, dynamic> info) {
    final name = HuaweiGateway.findDeepString(info, const <String>[
      'nickname',
      'nickName',
      'displayName',
      'display_name',
      'screenName',
      'userName',
      'name',
    ]);
    if (name != null && name.isNotEmpty) displayName = name;
    final avatar = HuaweiGateway.findDeepUrl(info, const <String>[
      'headPictureURL',
      'headImgURL',
      'avatarUrl',
      'portraitUrl',
      'userPic',
      'picture',
      'avatar',
      'icon',
    ]);
    if (avatar != null) avatarUrl = avatar.toString();
  }

  /// 首页歌曲：沐语真实链路 = page/detail/all 的 columnInfoExs 三层结构。
  /// REA 反编译 MusicHomePage(0x1404224e0) 确认：
  ///   columnInfoExs → contentSimpleInfos → childSimpleInfos → listRcmInfos
  /// 逐板块容错；首页请求失败时只在调用方显示空状态，不拿假数据填充。
  Future<List<Song>> homeSongs() async {
    return discover().then((d) => d.newSongs);
  }

  /// GET /recentlyplayed/query?contentType=1（音源插件 collections.go History）。
  Future<List<Song>> history() async {
    final json = await gateway.get(HuaweiPaths.recent);
    return deepList(json, const [
      'contentSimpleInfos',
      'songSimpleInfos',
      'songs',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  Future<List<Song>> search(
    String keyword, {
    int start = 0,
    int limit = 20,
  }) async {
    final json = await _searchJson(keyword, start: start, limit: limit);
    return deepList(json, const [
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'songList',
      'result',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  /// 搜索一次请求，同时解析歌曲 / 专辑 / 歌手 / 歌单。
  /// 华为 fuzzysearch 按 contentType 分开返回；单类失败只留该类的空结果，
  /// 全部类型都失败时抛出可读错误，不能把“请求失败”伪装成“没有结果”。
  Future<HuaweiSearchResult> searchAll(
    String keyword, {
    int start = 0,
    int limit = 30,
    bool includePlaylists = true,
  }) async {
    final jsons = <String, Map<String, dynamic>>{};
    final failures = <String, String>{};

    Future<void> searchType(String type) async {
      try {
        jsons[type] = await _searchJson(
          keyword,
          start: start,
          limit: limit,
          contentType: type,
        );
      } catch (e) {
        final code = _errorCode(e);
        failures[type] = code;
        AppLog.add(
          'search',
          'contentType=$type start=$start limit=$limit count=0 error=$code',
        );
      }
    }

    // 运行时实测：contentType 1=歌曲、2=专辑、3=歌手、4=歌单。
    final types = <String>['1', '2', '3', if (includePlaylists) '4'];
    await Future.wait<void>(types.map(searchType));
    if (jsons.isEmpty) {
      final details = types
          .map((type) => '$type=${failures[type] ?? 'unknown'}')
          .join(', ');
      throw HuaweiException('华为搜索失败（${types.join('/')}）：$details');
    }

    final songJson = jsons['1'] ?? const <String, dynamic>{};
    final albumJson = jsons['2'] ?? const <String, dynamic>{};
    final artistJson = jsons['3'] ?? const <String, dynamic>{};
    final playlistJson = jsons['4'] ?? const <String, dynamic>{};
    final songs = deepList(songJson, const [
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'songList',
      'result',
      'list',
      'data',
    ]).map(parseSong).where((s) => s.name != '未知歌曲').toList();
    final artists = deepList(artistJson, const [
      'artistSimpleInfos',
      'artistInfoExs',
      'artistInfos',
      'result',
    ]).map(parseArtist).where((a) => a.name.isNotEmpty).toList();
    final albums = deepList(albumJson, const [
      'albumSimpleInfos',
      'albumInfoExs',
      'albumInfos',
      'result',
    ]).map(parseAlbum).where((a) => a.name.isNotEmpty).toList();
    final playlists =
        deepList(playlistJson, const [
              'playListInfos',
              'playlistInfos',
              'mixPlaylistInfos',
              'contentSimpleInfos',
              'result',
            ])
            .map(parsePlaylist)
            .where((p) => p.id.isNotEmpty && p.name.isNotEmpty)
            .map(
              (p) => Playlist(
                id: p.id,
                name: p.name,
                cover: p.cover,
                songCount: p.songCount,
                kind: 'playlist',
              ),
            )
            .toList();
    return HuaweiSearchResult(
      songs: songs,
      artists: artists,
      albums: albums,
      playlists: playlists,
    );
  }

  Future<Map<String, dynamic>> _searchJson(
    String keyword, {
    required int start,
    required int limit,
    String contentType = '1',
  }) {
    // 源码事实（API_CONTRACT §4）：全部为字符串字段。
    return gateway.request(
      HuaweiPaths.search,
      body: <String, dynamic>{
        'contentType': contentType,
        'correct': '1',
        'queryWord': keyword,
        'start': '$start',
        'limit': '$limit',
      },
    );
  }

  /// 榜单 = 收藏列表里 contentType=7 的条目（音源插件真实支持）。
  Future<List<Playlist>> charts() async {
    final all = await playlists();
    return all.where((p) => p.kind == 'chart').take(8).toList();
  }

  /// 收藏歌曲。默认翻页到短页为止（原版收藏可达数百首，不能只取前 50）。
  Future<List<Song>> favorites({
    int start = 0,
    int limit = 50,
    bool fetchAll = true,
  }) async {
    if (!fetchAll) return _favoritesPage(start, limit);
    return _collectSongPages(_favoritesPage);
  }

  Future<List<Song>> _favoritesPage(int start, int limit) async {
    // 运行时取证（2.0.4）：v5 服务的真实 body 只含
    // contentTypes / favoriteQueryInfos / limit / start，用户由 token 决定。
    final json = await gateway.request(
      HuaweiPaths.favorites,
      body: <String, dynamic>{
        'contentTypes': <int>[1],
        'favoriteQueryInfos': <dynamic>[],
        'limit': limit,
        'start': start,
      },
    );
    return deepList(json, const [
      'favoriteInfos',
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  /// 歌单发现：favorite/simple/all + contentTypes=[4,5,7]（音源插件 collections.go）。
  /// 4=收藏歌单 / 5=自建歌单 / 7=榜单。limit 先试 999，400 时退 50。
  Future<List<Playlist>> playlists() async {
    Future<List<Playlist>> page(int start, int limit) async {
      final json = await gateway.request(
        HuaweiPaths.playlistDetail,
        body: <String, dynamic>{
          'contentTypes': <int>[4, 5, 7],
          'favoriteQueryInfos': <dynamic>[],
          'limit': limit,
          'start': start,
        },
      );
      return _parsePlaylists(json);
    }

    // v5 favorite/simple/all 同时承载收藏与歌单；999 是实测可用上限。
    final all = <Playlist>[];
    final seen = <String>{};
    try {
      final first = await page(0, 999);
      return first;
    } catch (_) {
      var start = 0;
      while (true) {
        final chunk = await page(start, 50);
        var added = 0;
        for (final p in chunk) {
          if (p.id.isNotEmpty && seen.add(p.id)) {
            all.add(p);
            added++;
          }
        }
        if (chunk.length < 50 || added == 0 || all.length > 2000) break;
        start += chunk.length;
      }
      return all;
    }
  }

  static List<Playlist> _parsePlaylists(Map<String, dynamic> json) {
    return deepList(json, const ['favoriteInfos'])
        .map((d) {
          final kindCode =
              HuaweiGateway.firstInt(d, const ['contentType']) ?? 0;
          return Playlist(
            id:
                HuaweiGateway.firstString(d, const [
                  'contentID',
                  'playListID',
                  'id',
                ]) ??
                '',
            name:
                HuaweiGateway.firstString(d, const [
                  'contentName',
                  'playListName',
                  'name',
                ]) ??
                '',
            cover: coverOf(d),
            songCount:
                HuaweiGateway.firstInt(d, const [
                  'totalCount',
                  'songNum',
                  'number',
                ]) ??
                0,
            kind:
                const <int, String>{
                  4: 'collected',
                  5: 'owned',
                  7: 'chart',
                }[kindCode] ??
                '',
          );
        })
        .where((p) => p.id.isNotEmpty && p.kind.isNotEmpty)
        .toList();
  }

  /// 歌单歌曲：自建歌单用 GET detail/all，收藏歌单用 POST bymusiclistid。
  Future<List<Song>> playlistSongs(
    Playlist playlist, {
    int start = 0,
    int limit = 50,
    bool fetchAll = true,
  }) async {
    if (!fetchAll) return _playlistSongsPage(playlist, start, limit);
    return _collectSongPages(
      (offset, size) => _playlistSongsPage(playlist, offset, size),
    );
  }

  Future<List<Song>> _playlistSongsPage(
    Playlist playlist,
    int start,
    int limit,
  ) async {
    final Map<String, dynamic> json;
    if (playlist.kind == 'owned') {
      json = await gateway.get(
        '${HuaweiPaths.ownedPlaylistSongs}?playListID=${Uri.encodeComponent(playlist.id)}'
        '&start=$start&limit=$limit',
      );
    } else if (playlist.kind == 'collected') {
      json = await gateway.request(
        HuaweiPaths.playlistSongs,
        body: <String, dynamic>{
          'musicListID': playlist.id,
          'copyrightSwitch': '1',
          'start': start,
          'limit': '$limit',
        },
      );
    } else {
      return <Song>[];
    }
    return deepList(json, const [
      'playListSongInfoList',
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  Future<List<Song>> similarSongs(String songCode) async {
    final json = await gateway.request(
      HuaweiPaths.similar,
      body: <String, dynamic>{'contentCode': songCode, 'contentType': 1},
    );
    return deepList(json, const [
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  Future<Song> songDetail(String songCode) async {
    // 运行时字符串常量：/song/detail/bysongcode? → GET + query。
    final json = await gateway.get(
      '${HuaweiPaths.songDetail}?songCodes=${Uri.encodeComponent(songCode)}',
    );
    final first = deepList(json, const [
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'list',
      'data',
    ]);
    return first.isEmpty
        ? Song(id: songCode, name: '未知歌曲')
        : parseSong(first.first);
  }

  /// 歌词（源码事实 tinglan/catalog.go Lyrics）：歌词地址随播放响应返回，
  /// 不从曲库详情取。默认只复用 `audioFiles` 取流响应里缓存的歌词地址；
  /// 仅显式传 `allowPlaybackRequest: true` 时才以 `qualityType='1'` 补发
  /// playUrl 兜底（live probe 使用）。优先逐字 HMRC（wordByWordLyric），再行级 LRC
  /// （lineByLineLyric / lyricAddress），并把译文合并进对应行。
  Future<List<LyricLine>> lyrics(
    String songCode, {
    bool allowPlaybackRequest = false,
  }) async {
    final code = songCode.trim();
    var sources = _playbackLyrics[code];
    if (sources == null && allowPlaybackRequest) {
      // 仅在调用方显式 opt-in 时补发；播放链路只复用取流响应缓存。
      final json = await gateway.request(
        HuaweiPaths.playUrl,
        body: <String, dynamic>{
          'contentCode': code,
          'contentType': '1',
          'qualityType': '1',
        },
      );
      sources = _lyricSourcesFrom(json);
    }
    if (sources == null || sources.isEmpty) return <LyricLine>[];
    return _fetchLyrics(sources);
  }

  _PlaybackLyrics _lyricSourcesFrom(dynamic json) {
    Uri? wordUrl; // 逐字 HMRC
    Uri? plainUrl; // 行级 LRC
    // 递归收集 lyricAddress / lineByLineLyric / wordByWordLyric / lyrics。
    _collectLyricFields(json, (key, value) {
      if (value is! String || value.isEmpty) return;
      if (key == 'wordByWordLyric') {
        wordUrl ??= HuaweiGateway.normalizeUrl(value);
      } else if (key == 'lineByLineLyric') {
        final u = HuaweiGateway.normalizeUrl(value);
        if (u != null) plainUrl ??= u;
      } else if (key == 'lyricAddress' || key == 'lyricAddres') {
        final u = HuaweiGateway.normalizeUrl(value);
        if (u != null) plainUrl ??= u;
      }
    });
    return _PlaybackLyrics(wordUrl: wordUrl, plainUrl: plainUrl);
  }

  Future<List<LyricLine>> _fetchLyrics(_PlaybackLyrics sources) async {
    List<LyricLine> lines = <LyricLine>[];
    String? plainText; // 内嵌 LRC 文本
    final wu = sources.wordUrl;
    if (wu != null) {
      try {
        lines = parseHmrc(await gateway.fetchText(wu));
      } catch (_) {}
    }
    final pu = sources.plainUrl;
    if (pu != null) {
      try {
        plainText = await gateway.fetchText(pu);
      } catch (_) {}
    }
    if (plainText != null && plainText.isNotEmpty) {
      final plain = parseLrc(plainText);
      if (lines.isEmpty) {
        lines = plain;
      } else {
        lines = mergeTranslations(lines, plain);
      }
    }
    return lines;
  }

  void _rememberPlaybackLyrics(String code, Map<String, dynamic> json) {
    final next = _lyricSourcesFrom(json);
    if (next.isEmpty) return;
    final previous = _playbackLyrics.remove(code);
    _playbackLyrics[code] = previous == null ? next : previous.merge(next);
    while (_playbackLyrics.length > _maxPlaybackLyrics) {
      _playbackLyrics.remove(_playbackLyrics.keys.first);
    }
  }

  /// 直接抓取搜索结果里携带的歌词 URL（HMRC 或 LRC）。
  Future<List<LyricLine>> lyricsFromUrl(Uri url) async {
    try {
      final text = await gateway.fetchText(url);
      final lines = RegExp(r'<\d+,\d+>').hasMatch(text)
          ? parseHmrc(text)
          : parseLrc(text);
      AppLog.add(
        'lyrics',
        '${url.host}${url.path} -> ${lines.length} lines ${text.length}B',
      );
      return lines;
    } catch (e) {
      AppLog.add('lyrics', 'fetch ${url.host}${url.path} failed: $e');
      return <LyricLine>[];
    }
  }

  /// 递归遍历 JSON，把指定 key 的字符串值回调出来（歌词字段可能嵌套多层、
  /// 还可能是「JSON 字符串套 JSON」）。
  void _collectLyricFields(
    dynamic root,
    void Function(String key, dynamic value) onField,
  ) {
    if (root is Map<String, dynamic>) {
      for (final entry in root.entries) {
        if (const [
          'wordByWordLyric',
          'lineByLineLyric',
          'lyricAddress',
          'lyricAddres',
          'lyrics',
          'contentExInfo',
        ].contains(entry.key)) {
          onField(entry.key, entry.value);
        }
        // contentExInfo 等可能是 JSON 字符串，二次解析。
        if (entry.value is String && entry.value.trim().startsWith('{')) {
          final decoded = jsonDecodeTry(entry.value);
          if (decoded != null) _collectLyricFields(decoded, onField);
        } else {
          _collectLyricFields(entry.value, onField);
        }
      }
    } else if (root is List) {
      for (final v in root) {
        _collectLyricFields(v, onField);
      }
    }
  }

  static dynamic jsonDecodeTry(String s) {
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  /// 取流：档位由上游决定（与 EXE locateQuality / FillSongQualities 一致）。
  /// - upstreamQualities：上游字段（privilege/size_*/level/br）派生的可用档位集合；
  ///   缺省时按标准档请求一次，绝不本地写死「标准+无损两档循环」。
  /// - 实际档位以下游响应的 playQuality/qualityType/level/br + codec 为准。
  Future<List<HuaweiAudioFile>> audioFiles(
    String songCode, {
    Set<AudioQuality>? upstreamQualities,
  }) async {
    final code = songCode.trim();
    if (code.isEmpty) {
      throw const HuaweiException('歌曲缺少 contentCode（列表解析异常），无法取流');
    }
    final out = <HuaweiAudioFile>[];
    // 只请求上游声明可用的档位；按从高到低，避免无谓请求。
    final wanted =
        (upstreamQualities != null
              ? upstreamQualities.toList()
              : <AudioQuality>[AudioQuality.standard])
          ..sort(
            (a, b) => b.index.compareTo(a.index),
          ); // hiRes > lossless > standard
    // 最高档不可播（无版权/会员不足/CDN 拒绝）时，最后再取标准档，
    // 保证“默认最高、失败降级”，而不是一开始就选标准。
    if (!wanted.contains(AudioQuality.standard)) {
      wanted.add(AudioQuality.standard);
    }

    // 运行时取证：华为 fileInfos 的 quality 取值为 1/2/3/5/7。
    // 1=MQ、2=HQ、3=SQ(FLAC)、5/7=Hi-Res。按目标档位依次回退。
    const typeCodes = <AudioQuality, List<String>>{
      AudioQuality.hiRes: <String>['7', '5', '3'],
      AudioQuality.lossless: <String>['3', '2', '5'],
      AudioQuality.standard: <String>['1', '2', '3'],
    };

    String? lastCode;
    String? lastMessage;
    String lastTier = 'standard/1';
    var sawPreview = false;

    for (final q in wanted) {
      for (final typeCode in typeCodes[q] ?? const <String>['1']) {
        lastTier = '${q.name}/$typeCode';
        Map<String, dynamic>? result;
        String? failedCode;
        String? failedMessage;
        try {
          result = await gateway.request(
            HuaweiPaths.playUrl,
            body: <String, dynamic>{
              'contentCode': code,
              'contentType': '1',
              'qualityType': typeCode,
            },
          );
        } on HuaweiBusinessException catch (e) {
          // 401/990000/990006 等鉴权失败交回上层重新登录；142411/142400
          // 只代表当前档位或当前歌曲受限，继续尝试下一档（尤其是 standard）。
          if (e.isAuthFailure) {
            throw _authPlaybackError(e.code, e.detail, path: e.path);
          }
          failedCode = e.code;
          failedMessage = e.detail;
        } on HuaweiException catch (e) {
          if (e.statusCode == 401 ||
              _isAuthFailure(e) ||
              !_looksLikeTierFailure(e)) {
            rethrow;
          }
          failedCode = _errorCode(e);
          failedMessage = e.toString();
        }
        final json = result;
        if (json != null) {
          final businessCode = _playbackBusinessCode(json);
          if (businessCode != null) {
            final businessMessage = _playbackBusinessMessage(json);
            if (HuaweiBusinessException.isAuthBusinessError(
              businessCode,
              businessMessage,
            )) {
              throw _authPlaybackError(
                businessCode,
                businessMessage,
                path: HuaweiPaths.playUrl,
              );
            }
            failedCode = businessCode;
            failedMessage = businessMessage;
          }
        }
        if (failedCode != null || json == null) {
          lastCode = failedCode ?? lastCode;
          lastMessage = failedMessage ?? lastMessage;
          AppLog.add(
            'play',
            'bycontentcode song=$code qualityType=$typeCode '
                'code=${failedCode ?? 'no-response'} hasUrl=false preview=false '
                'msg=${(failedMessage ?? '').replaceAll(RegExp(r'\s+'), ' ')}',
          );
          continue;
        }
        final candidate = HuaweiGateway.firstUrl(json, const [
          'fileURL',
          'fileUrl',
          'playURL',
          'url',
        ]);
        final preview = candidate != null && _isAudition(json, candidate);
        if (preview) sawPreview = true;
        AppLog.add(
          'play',
          'bycontentcode song=$code qualityType=$typeCode '
              'code=000000 hasUrl=${candidate != null} preview=$preview '
              '${_fragmentFlag(json)} '
              'url=${candidate == null ? '' : _audioUrlSuffix(candidate)}',
        );
        if (candidate == null || !_safeAudioUrl(candidate) || preview) {
          lastMessage = candidate == null
              ? '响应没有 fileURL'
              : (preview ? '仅返回试听片段' : 'URL 域名不在白名单');
          continue;
        }
        _rememberPlaybackLyrics(code, json);

        // 以实际请求到的 qualityType 为准：5/7=Hi-Res，3=SQ，1/2=标准。
        final actual = switch (typeCode) {
          '7' || '5' => AudioQuality.hiRes,
          '3' => AudioQuality.lossless,
          _ => AudioQuality.standard,
        };
        if (!out.any((f) => f.quality == actual)) {
          out.add(
            HuaweiAudioFile(
              quality: actual,
              url: candidate,
              sizeBytes:
                  HuaweiGateway.firstInt(json, const ['size', 'fileSize']) ?? 0,
              qualityType: typeCode,
            ),
          );
        }
        // 当前档位已拿到完整可播文件；继续下一个更低的“音质档”，
        // 但不再重复请求同档位的其它 typeCode。
        break;
      }
    }
    if (out.isEmpty) {
      final lower = (lastMessage ?? '').toLowerCase();
      final vipOnly =
          lastCode == '142411' ||
          lower.contains('super diamond vip') ||
          lower.contains('超级钻石');
      final reason = vipOnly
          ? '超级钻石 VIP 专享，当前账号无播放权限'
          : (sawPreview ? '只有试听片段，没有完整音质' : '没有可用的完整音质档位');
      throw HuaweiException(
        '华为取流失败（歌曲 $code，码 ${lastCode ?? 'unknown'}，'
        '最终档位 $lastTier）：$reason',
      );
    }
    final chosen = out.first;
    AppLog.add(
      'play',
      'bycontentcode song=$code choose=${chosen.quality.name} '
          'qualityType=${chosen.qualityType} size=${chosen.sizeBytes} '
          'preview=${chosen.preview}',
    );
    return out;
  }

  static bool _looksLikeTierFailure(Object e) {
    final text = e.toString().toLowerCase();
    return text.contains('142411') ||
        text.contains('142400') ||
        text.contains('super diamond') ||
        text.contains('超级钻石') ||
        text.contains('vip 专享') ||
        text.contains('没有可用') ||
        text.contains('无版权') ||
        text.contains('不可播放') ||
        text.contains('华为服务返回');
  }

  /// 鉴权失败必须变成用户可执行的最终错误，不能被“档位不可用”文案吞掉。
  static HuaweiBusinessException _authPlaybackError(
    String code,
    String detail, {
    String? path,
  }) {
    const hint = '华为鉴权失败，请重新登录华为账号';
    final text = detail.trim();
    final hasHint =
        text.contains('重新登录') ||
        text.contains('重新扫码') ||
        text.contains('登录已失效') ||
        text.contains('登录已过期') ||
        text.contains('会话已过期');
    return HuaweiBusinessException(
      code,
      text.isEmpty ? hint : (hasHint ? text : '$hint：$text'),
      path: path,
    );
  }

  static String? _playbackBusinessCode(Map<String, dynamic> json) {
    final result = json['result'];
    final resultMap = result is Map
        ? Map<String, dynamic>.from(result)
        : const <String, dynamic>{};
    final code =
        HuaweiGateway.firstString(resultMap, const ['resultCode']) ??
        HuaweiGateway.firstString(json, const ['resultCode', 'code']);
    if (code != null && code != HuaweiPaths.successCode) return code;
    final message = _playbackBusinessMessage(json).toLowerCase();
    if (message.contains('142411') ||
        message.contains('only super diamond vip') ||
        message.contains('super diamond vip') ||
        message.contains('超级钻石')) {
      return '142411';
    }
    if (message.contains('142400') ||
        message.contains('没有可用') ||
        message.contains('无版权')) {
      return '142400';
    }
    return null;
  }

  static String _playbackBusinessMessage(Map<String, dynamic> json) {
    final parts = <String>[];
    void collect(Map<String, dynamic> map) {
      for (final key in const [
        'resultMessage',
        'message',
        'msg',
        'errorMessage',
      ]) {
        final value = map[key];
        if (value is String && value.isNotEmpty) parts.add(value);
      }
    }

    final result = json['result'];
    if (result is Map) collect(Map<String, dynamic>.from(result));
    collect(json);
    return parts.join(' ');
  }

  static String _fragmentFlag(Map<String, dynamic> json) {
    final flag = json['playFragmentFlag'];
    final fragment = json['fragmentInfo'];
    final has = fragment is Map ? '${fragment['hasFragement']}' : '';
    return 'fragmentFlag=${flag ?? '-'} hasFragment=${has.isEmpty ? '-' : has} '
        'auditionEnd=${json['auditionEnd'] ?? '-'} '
        'auditionTime=${json['auditionTime'] ?? '-'}';
  }

  static String _audioUrlSuffix(Uri url) {
    final name = url.path.split('/').last;
    final lower = name.toLowerCase();
    final tags = <String>[
      if (lower.endsWith('_aq.mp3') || lower.endsWith('_aq.flac')) 'AQ',
      if (lower.endsWith('_pv.mp3') || lower.endsWith('_pv.flac')) 'PV',
    ];
    return tags.isEmpty ? name : '$name[${tags.join(',')}]';
  }

  bool _safeAudioUrl(Uri u) {
    // 华为 CDN 实际返回 http://music-pics-drcn.dbankcdn.cn/...
    // 只接受 https 会把所有可播放地址过滤掉。
    if (u.scheme != 'https' && u.scheme != 'http') return false;
    final host = u.host.toLowerCase();
    return const [
      '.dbankcdn.cn',
      '.tingmall.com',
      '.kuke.com',
    ].any((s) => host.endsWith(s) && host.length > s.length);
  }

  /// 试听片段识别：Hi-Res 无权限时网关仍返回 200 + fileURL，但只有
  /// 30/60 秒。`/preview/` 与 URL 的 `_AQ`/`_PV` 后缀是强判定；
  /// `auditionEnd`/`auditionTime` 只作为日志里的弱信号辅助排障。
  /// 这类地址绝不能当成完整歌曲交给播放器。
  static bool _isAudition(Map<String, dynamic> json, Uri url) {
    final path = url.path.toLowerCase();
    if (path.contains('/preview/') ||
        path.endsWith('_aq.mp3') ||
        path.endsWith('_pv.mp3') ||
        path.endsWith('_aq.flac') ||
        path.endsWith('_pv.flac')) {
      return true;
    }
    final flag = json['playFragmentFlag'];
    if (flag == '1' || flag == 1) return true;
    final fragment = json['fragmentInfo'];
    if (fragment is Map &&
        '${fragment['hasFragement']}' == '1' &&
        (json.containsKey('auditionEnd') || json.containsKey('auditionTime'))) {
      return true;
    }
    return false;
  }

  /// 收藏增删（源码事实 API_CONTRACT §3.4）：create/delete 两个独立接口，
  /// 按目标状态调用，不盲切布尔；contentType/contentID 均为字符串。
  Future<void> toggleFavorite(String songCode, bool favorite) async {
    await gateway.request(
      favorite ? HuaweiPaths.favoriteCreate : HuaweiPaths.favoriteDelete,
      body: <String, dynamic>{'contentType': '1', 'contentID': songCode},
    );
  }

  Future<String> membership() async {
    final json = await gateway.get(HuaweiPaths.subscription);
    final text =
        HuaweiGateway.firstString(json, const [
          'iVipFlag',
          'HugeVip',
          'vipFlag',
        ]) ??
        '';
    if (text.isNotEmpty) return text;
    return memberLabel ?? '';
  }

  /// 收藏状态判断：favorite/simple/exist?contentID=&contentType=。
  /// REA 运行时内存取证抓到的真实请求（见 REA_DEEP_PLAYER_ANALYSIS §4）。
  Future<bool> isFavorite(String songCode) async {
    try {
      final json = await gateway.get(
        '${HuaweiPaths.favoriteExist}?contentID=${Uri.encodeComponent(songCode)}'
        '&contentType=1',
      );
      for (final key in const ['isFavorite', 'favorite', 'exist', 'existed']) {
        final v = json[key];
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) return v == '1' || v.toLowerCase() == 'true';
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 评论列表（catalog/provider_comments.go + API /comment/query）。
  Future<List<Comment>> comments(
    String songCode, {
    int start = 0,
    int limit = 20,
  }) async {
    final json = await gateway.request(
      HuaweiPaths.comments,
      body: <String, dynamic>{
        'contentID': songCode,
        'contentType': 1,
        'start': start,
        'limit': limit,
      },
    );
    return deepList(json, const [
          'commentInfos',
          'comments',
          'commentList',
          'list',
          'data',
        ])
        .map((d) {
          return Comment(
            id: HuaweiGateway.firstString(d, const ['commentID', 'id']) ?? '',
            author:
                HuaweiGateway.firstString(d, const [
                  'nickName',
                  'userName',
                  'nick',
                  'author',
                ]) ??
                '匿名用户',
            content:
                HuaweiGateway.firstString(d, const [
                  'commentContent',
                  'content',
                  'text',
                ]) ??
                '',
            avatar: HuaweiGateway.firstUrl(d, const [
              'avatarUrl',
              'headUrl',
              'userImage',
              'avatar',
            ]),
            time:
                HuaweiGateway.firstString(d, const [
                  'createTime',
                  'time',
                  'publishTime',
                ]) ??
                '',
            likes:
                HuaweiGateway.firstInt(d, const [
                  'likeCount',
                  'praiseCount',
                  'likes',
                ]) ??
                0,
          );
        })
        .where((c) => c.content.isNotEmpty)
        .toList();
  }

  /// 歌手详情（catalog.Library.Artist + API /artist/detail/byartistcode）。
  Future<Artist> artistDetail(String artistCode) async {
    // 运行时实测：v1 GET 返回 400/405；v2 POST 正常。
    final json = await gateway.request(
      HuaweiPaths.artistDetailV2,
      body: <String, dynamic>{
        'artistCode': artistCode,
        'songNum': 20,
        'albumNum': 20,
      },
    );
    // 详情可能在顶层，也可能在 artistInfo / data 里；取第一个含名称的 Map。
    Map<String, dynamic> d = json;
    for (final key in const [
      'artistInfoEx',
      'artistInfo',
      'artistDetail',
      'data',
      'result',
    ]) {
      final nested = json[key];
      if (nested is Map<String, dynamic>) {
        d = nested;
        if (nested['artistInfo'] is Map<String, dynamic>) {
          d = nested['artistInfo'] as Map<String, dynamic>;
        }
        break;
      }
    }
    return Artist(
      id: artistCode,
      name:
          HuaweiGateway.firstString(d, const ['artistName', 'name', 'artNM']) ??
          '未知歌手',
      cover: coverOf(d, const <String>['artistPicUrl']),
      desc:
          HuaweiGateway.firstString(d, const [
            'artistDesc',
            'description',
            'intro',
          ]) ??
          '',
    );
  }

  /// 歌手热门歌曲（API /song/simple/byartistcode）。
  Future<List<Song>> artistSongs(
    String artistCode, {
    int start = 0,
    int limit = 30,
    bool fetchAll = true,
  }) async {
    Future<List<Song>> page(int offset, int size) async {
      final json = await gateway.get(
        '${HuaweiPaths.artistSongs}?artistCode=${Uri.encodeComponent(artistCode)}'
        '&start=$offset&limit=$size',
      );
      return deepList(json, const [
        'songSimpleInfos',
        'contentSimpleInfos',
        'songs',
        'list',
        'data',
      ]).map(parseSong).toList();
    }

    if (!fetchAll) return page(start, limit);
    return _collectSongPages(page);
  }

  /// 专辑歌曲（API_CONTRACT：GET /album/detail/byalbumcode?albumCode=&start=&limit=）。
  Future<List<Song>> albumSongs(
    String albumCode, {
    int start = 0,
    int limit = 50,
    bool fetchAll = true,
  }) async {
    Future<List<Song>> page(int offset, int size) async {
      final json = await gateway.get(
        '${HuaweiPaths.albumDetail}?albumCode=${Uri.encodeComponent(albumCode)}'
        '&start=$offset&limit=$size',
      );
      return deepList(json, const [
        'songSimpleInfos',
        'contentSimpleInfos',
        'songs',
        'trackInfos',
        'list',
        'data',
      ]).map(parseSong).toList();
    }

    if (!fetchAll) return page(start, limit);
    return _collectSongPages(page);
  }

  /// 创建歌单（API /playlist/create）。
  Future<void> createPlaylist(String name) async {
    await gateway.request(
      HuaweiPaths.playlistCreate,
      body: <String, dynamic>{'playListName': name, 'contentType': 5},
    );
  }

  /// 删除歌单（API /playlist/delete）。
  Future<void> deletePlaylist(String playlistId) async {
    await gateway.request(
      HuaweiPaths.playlistDelete,
      body: <String, dynamic>{'playListID': playlistId, 'contentType': 5},
    );
  }

  /// 向歌单增删歌曲（catalog.ChangeCollectionSong）。
  Future<void> changeCollectionSong(
    String playlistId,
    String songCode, {
    required bool add,
  }) async {
    await gateway.request(
      HuaweiPaths.playlistChangeSong,
      body: <String, dynamic>{
        'playListID': playlistId,
        'contentID': songCode,
        'contentType': 1,
        'operation': add ? 1 : 0,
      },
    );
  }

  // MARK: - 容错解析

  /// 从上游字段派生该歌曲的可用档位（与 EXE songQualities / FillSongQualities 一致）。
  /// 档位完全由上游决定：华为 size_* / 网易 privilege.level·br·maxbr·chargeInfoList。
  /// 只有上游完全没给档位信息时才退回 standard（保守默认）。
  static Set<AudioQuality> qualitiesFromUpstream(Map<String, dynamic> d) {
    final out = <AudioQuality>{};

    AudioQuality fromTier(String raw) {
      switch (raw.toLowerCase()) {
        case '7':
        case '5':
        case 'hr':
        case 'hires':
        case 'hi-res':
        case 'jymaster':
        case 'sky':
          return AudioQuality.hiRes;
        case '3':
        case 'sq':
        case 'flac':
        case 'lossless':
        case 'exhigh':
        case 'higher':
        case '2':
        case 'hq':
        case 'high':
          // 客户端没有独立 HQ 枚举；请求无损档时会按 3→2 回退，
          // 实际返回 2 码率仍是完整 HQ，不会只拿标准 MP3。
          return AudioQuality.lossless;
        default:
          return AudioQuality.standard;
      }
    }

    // 2) 网易云：privilege / songPrivilege 对象里的 level、br、maxbr。
    void applyPrivilege(Map<String, dynamic> p) {
      final level = HuaweiGateway.firstString(p, const [
        'level',
        'quality',
        'flacLevel',
      ]);
      if (level != null && level.isNotEmpty) {
        out.add(fromTier(level));
      }
      final br = HuaweiGateway.firstInt(p, const ['br', 'maxbr', 'maxBr']);
      if (br != null && br > 0) out.add(AudioQuality.fromBitrate(br));
      final dl = p['downloadMaxBr'] ?? p['flacMaxBr'];
      if (dl is num && dl > 0) out.add(AudioQuality.fromBitrate(dl.toInt()));
    }

    // 1/2/3/5/7 是华为 fileInfos 的 qualityType；HQ 归到 lossless，
    // 让取流时优先请求 SQ，失败后回退 HQ(2)，最后才是标准(1)。
    void scanHuawei(Map<String, dynamic> map, [int depth = 0]) {
      for (final q in AudioQuality.values) {
        final v = map[q.sizeKey];
        if (v != null && v != 0 && v != '0') out.add(q);
      }

      final hiRes = map['hiResAvailable'];
      if (hiRes == true) out.add(AudioQuality.hiRes);

      final highest = HuaweiGateway.firstString(map, const [
        'highestQuality',
        'highestReportedQuality',
        'maxQuality',
      ]);
      if (highest != null) out.add(fromTier(highest));

      final audio = map['huaweiAudioFiles'];
      if (audio is Map) {
        final files = Map<String, dynamic>.from(audio);
        final types =
            HuaweiGateway.firstInt(files, const [
              'types',
              'type',
              'qualityTypes',
            ]) ??
            0;
        if (types & 0x60 != 0 || types >= 32) out.add(AudioQuality.hiRes);
        if (types & 0x0E != 0) out.add(AudioQuality.lossless);
        if (types & 0x02 != 0) out.add(AudioQuality.standard);
      }

      for (final key in const ['fileInfos', 'completeFileInfos', 'files']) {
        final list = map[key];
        if (list is! List) continue;
        for (final item in list) {
          if (item is! Map) continue;
          final file = Map<String, dynamic>.from(item);
          final tier = HuaweiGateway.firstString(file, const [
            'qualityType',
            'quality',
            'playQuality',
            'level',
          ]);
          if (tier != null) out.add(fromTier(tier));
          final bitRate = HuaweiGateway.firstInt(file, const [
            'bitRate',
            'br',
            'maxbr',
          ]);
          if (bitRate != null && bitRate > 0) {
            out.add(AudioQuality.fromBitrate(bitRate));
          }
        }
      }

      final contentExInfo = map['contentExInfo'];
      if (depth == 0 &&
          contentExInfo is String &&
          contentExInfo.startsWith('{')) {
        try {
          final decoded = jsonDecode(contentExInfo);
          if (decoded is Map) {
            scanHuawei(Map<String, dynamic>.from(decoded), depth + 1);
          }
        } catch (_) {
          // contentExInfo 不是合法 JSON 时忽略。
        }
      }
    }

    scanHuawei(d);

    for (final key in const ['privilege', 'songPrivilege']) {
      final v = d[key];
      if (v is Map<String, dynamic>) applyPrivilege(v);
    }
    // 顶层 level/br/maxbr（部分详情直接平铺）。
    applyPrivilege(d);

    // 3) chargeInfoList：付费档位列表，每项含 level/br。
    final charges = d['chargeInfoList'];
    if (charges is List) {
      for (final c in charges) {
        if (c is Map<String, dynamic>) applyPrivilege(c);
      }
    }

    // 4) 通用档位字符串（quality/playQuality/minPrivilege/最低权益）。
    final tier = HuaweiGateway.firstString(d, const [
      'quality',
      'playQuality',
      'minPrivilege',
      'maxQuality',
    ]);
    if (tier != null) out.add(fromTier(tier));

    // 只有上游完全没有档位信息时才保守退回标准档；不能把标准档
    // 硬塞进每首歌，否则默认播放在客户端被降成 MP3。
    if (out.isEmpty) out.add(AudioQuality.standard);
    return out;
  }

  /// 华为封面在 `picture:{bigImgURL,middleImgURL,smallImgURL}` 子对象里；
  /// 直接对顶层取 `picture` 会拿到 Map 而丢封面（播放条/歌词页空白）。
  static Uri? coverOf(
    Map<String, dynamic> d, [
    List<String> extraKeys = const <String>[],
  ]) {
    final picture = d['picture'];
    if (picture is Map) {
      final nested = HuaweiGateway.firstUrl(
        Map<String, dynamic>.from(picture),
        const <String>[
          'bigImgURL',
          'middleImgURL',
          'smallImgURL',
          'pic',
          'url',
          'coverUrl',
        ],
      );
      if (nested != null) return nested;
    }
    return HuaweiGateway.firstUrl(d, <String>[
      ...extraKeys,
      'middleImgURL',
      'bigImgURL',
      'smallImgURL',
      'mImg',
      'bImg',
      'sImg',
      'pic',
      'picture',
      'coverUrl',
      'cover',
    ]);
  }

  /// 歌词地址可能在顶层 lyricAddres，也可能藏在 lyrics / contentExInfo
  /// 的 JSON 字符串里；搜索/榜单结果通常只带后者。
  static Uri? lyricUrlOf(Map<String, dynamic> d) {
    final direct = HuaweiGateway.firstUrl(d, const [
      'lyricAddress',
      'lyricAddres',
      'lrcUrl',
    ]);
    if (direct != null) return direct;
    Uri? find(dynamic root) {
      if (root is Map) {
        final url = HuaweiGateway.firstUrl(
          Map<String, dynamic>.from(root),
          const [
            'wordByWordLyric',
            'lineByLineLyric',
            'lyricAddress',
            'lyricAddres',
          ],
        );
        if (url != null) return url;
        for (final value in root.values) {
          final found = find(value);
          if (found != null) return found;
        }
      } else if (root is List) {
        for (final value in root) {
          final found = find(value);
          if (found != null) return found;
        }
      } else if (root is String && root.trim().startsWith('{')) {
        final decoded = jsonDecodeTry(root);
        if (decoded != null) return find(decoded);
      }
      return null;
    }

    for (final key in const ['lyrics', 'contentExInfo']) {
      final found = find(d[key]);
      if (found != null) return found;
    }
    return null;
  }

  static Song parseSong(
    Map<String, dynamic> d, {
    MusicSourceLabel source = MusicSourceLabel.huawei,
  }) {
    final artists = <String>[];
    final artistIds = <String>[];
    // REA HomeSongs：artistNamePairs / arts 里同时含 artistID 与 artistName。
    final pairs = d['artistNamePairs'] ?? d['arts'];
    if (pairs is List && pairs.isNotEmpty) {
      for (final p in pairs) {
        if (p is Map<String, dynamic>) {
          final n = HuaweiGateway.firstString(p, const [
            'artistName',
            'name',
            'artNM',
          ]);
          final id = HuaweiGateway.firstString(p, const [
            'artistID',
            'artistCode',
            'id',
          ]);
          if (n != null) artists.add(n);
          if (id != null) artistIds.add(id);
        }
      }
    }
    if (artists.isEmpty) {
      final single = HuaweiGateway.firstString(d, const [
        'singerName',
        'artistName',
        'artNM',
        'artist',
        'singer',
      ]);
      if (single != null) {
        artists.addAll(
          single
              .split(RegExp(r'[/,、&]'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty),
        );
      }
    }
    if (artistIds.isEmpty) {
      final singleId = HuaweiGateway.firstString(d, const [
        'artistID',
        'artistCode',
        'singerId',
      ]);
      if (singleId != null) artistIds.add(singleId);
    }
    final qualities = qualitiesFromUpstream(d);

    return Song(
      // 沐语 normalizeHomeSongs 兼容两套字段：精简 ID/NM/pic 与完整 contentID/contentName/middleImgURL。
      id:
          HuaweiGateway.firstString(d, const [
            'songCode',
            'contentId',
            'contentID',
            'contentCode',
            'ID',
            'id',
            'songId',
          ]) ??
          // 缺真实 ID 时不再生成时间戳假 ID：假 ID 会让 UI 显示可点，
          // 但 bycontentcode 必然失败。空 ID 由播放层给出可读错误，
          // 首页列表则由 _dedupeSongs 过滤掉。
          '',
      name:
          HuaweiGateway.firstString(d, const [
            'songName',
            'name',
            'songname',
            'contentName',
            'NM',
            'title',
          ]) ??
          '未知歌曲',
      album:
          HuaweiGateway.firstString(d, const [
            'albumName',
            'albNM',
            'album',
            'albumname',
          ]) ??
          '',
      artists: artists,
      artistIds: artistIds,
      cover: coverOf(d),
      // durationSeconds 以秒计（REA 实测字段），其余为毫秒。
      durationMs: HuaweiGateway.firstInt(d, const ['durationSeconds']) != null
          ? HuaweiGateway.firstInt(d, const ['durationSeconds'])! * 1000
          : HuaweiGateway.firstInt(d, const [
                  'songDuration',
                  'durationMs',
                  'duration',
                  'dur',
                  'playDuration',
                ]) ??
                0,
      qualities: qualities,
      lyricUrl: lyricUrlOf(d),
      favorite: d['favorite'] == true || d['isFavorite'] == true,
      source: source,
      member:
          d['isVip'] == true ||
          d['vip'] == true ||
          (HuaweiGateway.firstInt(d, const ['fee']) ?? 0) > 0,
    );
  }

  static List<LyricLine> parseLrc(String text) {
    final lines = <LyricLine>[];
    final re = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');
    for (final raw in const LineSplitter().convert(text)) {
      for (final m in re.allMatches(raw)) {
        final min = int.tryParse(m.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(m.group(2) ?? '0') ?? 0;
        final frac = m.group(3) ?? '0';
        final ms = int.tryParse(frac.padRight(3, '0').substring(0, 3)) ?? 0;
        final content = (m.group(4) ?? '').trim();
        if (content.isEmpty) continue;
        lines.add(
          LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms),
            content,
          ),
        );
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 解析逐字 HMRC（源码事实 tinglan/hmrc.go）：
  ///   [行开始ms,行时长ms]<字偏移ms,字时长ms>字<...>字 ^罗马音/译文
  /// 字偏移相对行首，行开始相对音频起点；全部毫秒。
  static List<LyricLine> parseHmrc(String text) {
    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(
      text.replaceAll('\r\n', '\n'),
    )) {
      final line = raw.trim();
      if (line.isEmpty ||
          line.startsWith('[ti:') ||
          line.startsWith('[ar:') ||
          line.startsWith('[al:') ||
          line.startsWith('[by:') ||
          line.startsWith('[offset:') ||
          !line.startsWith('[')) {
        continue;
      }
      final close = line.indexOf(']');
      if (close < 0) continue;
      final head = _pairMs(line.substring(1, close));
      if (head == null) continue;
      final lineStartMs = head.$1;
      var rest = line.substring(close + 1);

      String romanization = '';
      String translation = '';
      final caret = rest.indexOf('^');
      if (caret >= 0) {
        final tail = _stripWordMarkers(rest.substring(caret + 1).trim());
        rest = rest.substring(0, caret);
        // 源码规则：拉丁行 + 汉字尾 = 译文；汉字行 + 拉丁尾 = 罗马音。
        if (_hasHan(tail) && !_hasHan(_stripWordMarkers(rest))) {
          translation = tail;
        } else {
          romanization = tail;
        }
      }

      final words = <LyricWord>[];
      final buffer = StringBuffer();
      while (true) {
        final open = rest.indexOf('<');
        if (open < 0) break;
        final end = rest.indexOf('>', open);
        if (end < 0) break;
        final pair = _pairMs(rest.substring(open + 1, end));
        if (pair == null) break;
        rest = rest.substring(end + 1);
        final next = rest.indexOf('<');
        final chunk = next < 0 ? rest : rest.substring(0, next);
        rest = next < 0 ? '' : rest.substring(next);
        if (chunk.isEmpty) continue;
        words.add(
          LyricWord(Duration(milliseconds: lineStartMs + pair.$1), chunk),
        );
        buffer.write(chunk);
      }
      final body = buffer.toString().trim();
      if (body.isEmpty) continue;
      lines.add(
        LyricLine(
          Duration(milliseconds: lineStartMs),
          body,
          words: words,
          translation: translation,
          romanization: romanization,
        ),
      );
    }
    return lines;
  }

  static (int, int)? _pairMs(String raw) {
    final parts = raw.split(',');
    if (parts.length != 2) return null;
    final a = double.tryParse(parts[0].trim());
    final b = double.tryParse(parts[1].trim());
    if (a == null || b == null) return null;
    return (a.round(), b.round());
  }

  static String _stripWordMarkers(String s) {
    final out = StringBuffer();
    var i = 0;
    while (i < s.length) {
      if (s[i] == '<') {
        final end = s.indexOf('>', i);
        if (end >= 0 && s.substring(i, end).contains(',')) {
          i = end + 1;
          continue;
        }
      }
      out.write(s[i]);
      i++;
    }
    return out.toString().trim();
  }

  static bool _hasHan(String s) => s.contains(RegExp(r'[\u4e00-\u9fff]'));

  /// 把行级 LRC 的译文合并到逐字 HMRC 对应行（源码 lyrics.MergeSubtitles）。
  static List<LyricLine> mergeTranslations(
    List<LyricLine> words,
    List<LyricLine> plain,
  ) {
    for (final w in words) {
      for (final p in plain) {
        // 时间接近（±600ms）或去标点后文本相同的行视为同一句。
        final near =
            (p.time.inMilliseconds - w.time.inMilliseconds).abs() < 600;
        if (near && p.text.trim().isNotEmpty) {
          if (w.translation.isEmpty) {
            words[words.indexOf(w)] = LyricLine(
              w.time,
              w.text,
              words: w.words,
              translation: p.text,
              romanization: w.romanization,
            );
          }
          break;
        }
      }
    }
    return words;
  }

  /// 首页数据：沐语 page/detail/all 的 columnInfoExs 三层结构。
  /// REA decompile(MusicHomePage@0x1404224e0) 实测：
  ///   columnInfoExs → contentSimpleInfos → contentID=pmf001
  ///     → childSimpleInfos → listRcmInfos（电台歌曲）
  /// 其余 column 按 contentID/contentType 分流为新歌 / 歌单 / 榜单 / Banner。
  /// 每个板块独立容错；接口无数据即空状态，绝不填假内容。
  Future<T> _withAuthRetry<T>(Future<T> Function() work) async {
    try {
      return await work();
    } catch (e) {
      if (!_isAuthFailure(e)) rethrow;
      final at = gateway.accountToken;
      if (at == null || at.isEmpty) {
        _authRetryBlockedUntil = DateTime.now().add(_authCooldown);
        rethrow;
      }
      final until = _authRetryBlockedUntil;
      if (until != null && DateTime.now().isBefore(until)) {
        AppLog.add('home', '990000 冷却中，跳过会话刷新');
        rethrow;
      }
      try {
        final pending = _sessionRefresh ??= gateway
            .exchangeMusicToken(at)
            .then<void>((_) {})
            .whenComplete(() => _sessionRefresh = null);
        await pending;
        AppLog.add('home', '990000 -> 会话已刷新，重试一次');
        return await work();
      } catch (retryError) {
        _authRetryBlockedUntil = DateTime.now().add(_authCooldown);
        AppLog.add('home', '990000 会话刷新失败，冷却 30 秒：$retryError');
        rethrow;
      }
    }
  }

  static bool _isAuthFailure(Object e) {
    final m = e.toString();
    final lower = m.toLowerCase();
    return m.contains('990000') ||
        m.contains('990006') ||
        RegExp(r'\b401\b').hasMatch(m) ||
        m.contains('鉴权失败') ||
        m.contains('登录已失效') ||
        m.contains('登录已过期') ||
        m.contains('会话已过期') ||
        m.contains('重新扫码') ||
        m.contains('重新登录华为账号') ||
        lower.contains('token expired') ||
        lower.contains('token has expired');
  }

  static String _errorCode(Object e) {
    final m = e.toString();
    final hit = RegExp(r'\b\d{6}\b').firstMatch(m);
    return hit?.group(0) ?? m;
  }

  /// 每个首页板块独立容错，并记录 ID / 数量 / 错误码，方便日志导出定位。
  Future<List<T>> _homeSoft<T>(
    String label,
    String id,
    Future<List<T>> Function() work,
  ) async {
    try {
      final items = await work();
      AppLog.add('home', '$label id=$id count=${items.length} code=000000');
      return items;
    } catch (e) {
      AppLog.add('home', '$label id=$id count=0 error=${_errorCode(e)}');
      return <T>[];
    }
  }

  /// 首页不是一条流：聚合页给骨架，其余板块各自请求；任何一路失败只留空。
  Future<DiscoverData> discover() async {
    final homeFuture = _withAuthRetry(() => gateway.get(HuaweiPaths.home));
    final dailyFuture = _homeSoft<Song>(
      'daily30',
      dailyPlaylistId,
      () => daily30(),
    );
    final playlistsFuture = _homeSoft<Playlist>(
      'recommendedPlaylists',
      'recommend/playlist',
      () => recommendedPlaylists(),
    );
    final chartFuture = _homeSoft<Song>(
      'chartSongs',
      hotChartId,
      () => chartSongs(hotChartId),
    );

    final homeJson = await homeFuture;
    final data = parseDiscover(homeJson);
    // `page/detail/all` 的 recom_exclusive 栏目可能带自己的真实栏目号；
    // 8011 只在聚合页没有给出可识别栏目号时兜底。
    final explicitRecommendedColumnId = recommendedColumnIdFrom(homeJson);
    final recommendedColumnId = explicitRecommendedColumnId ?? featuredColumnId;
    final featuredFuture = _homeSoft<Song>(
      'featuredSongs',
      recommendedColumnId,
      () => featuredSongs(columnId: recommendedColumnId, home: homeJson),
    );
    final featured = await featuredFuture;
    final daily = await dailyFuture;
    final recommendedLists = await playlistsFuture;
    final hotChartSongs = await chartFuture;

    final playlists = _mergePlaylists(<List<Playlist>>[
      recommendedLists,
      data.playlists,
    ]);
    if (!playlists.any((p) => p.id == dailyPlaylistId)) {
      playlists.add(
        const Playlist(id: dailyPlaylistId, name: '每日30首', kind: 'collected'),
      );
    }
    final charts = _mergePlaylists(<List<Playlist>>[data.charts]);
    if (!charts.any((p) => p.id == hotChartId)) {
      charts.add(const Playlist(id: hotChartId, name: '热歌榜', kind: 'chart'));
    }
    if (hotChartSongs.isNotEmpty) {
      final index = charts.indexWhere((p) => p.id == hotChartId);
      charts[index] = Playlist(
        id: hotChartId,
        name: '热歌榜',
        kind: 'chart',
        songCount: hotChartSongs.length,
      );
    }

    // 每个板块只吃自己的真实源：
    // listen=page/detail/all 中 pmf001 顶层直接歌曲，daily=a001，
    // hot=24926，heart/new=聚合页可证明归属的标签批次
    // （心动首屏/续播由服务层另行调用 heartFmFirstPage/privateFmPage），
    // recommended=8011/动态栏目。
    // 任一独立源为空就保持空态，禁止跨板块轮询填充。
    final listen = data.listen;
    // 8011 / 动态 recom_exclusive 栏目为空就保持空态；聚合页里的
    // data.recommended 只有在同一份 page 明确标出 recom_exclusive/8011
    // 栏目号时才算同源补充，绝不能用 pmf001/daily/hot/radio 填充。
    final embeddedRecommended =
        explicitRecommendedColumnId != null && data.recommended.isNotEmpty
        ? data.recommended
        : const <Song>[];
    final recommended = featured.isNotEmpty ? featured : embeddedRecommended;
    final hot = hotChartSongs.isNotEmpty ? hotChartSongs : data.hot;
    final heart = data.heart;
    final newSongs = data.newSongs;
    final dailySongs = daily.isNotEmpty ? daily : data.daily;

    final merged = data.copyWith(
      recommended: recommended,
      recommendedColumnId: recommendedColumnId,
      // 24926 是真实可用的 200 首榜单；热歌速递直接吃这份数据，
      // 不再使用 pmf001 剩余歌曲切出来的 ≤10 首推断列表。
      daily: dailySongs,
      listen: listen,
      heart: heart,
      newSongs: newSongs,
      hot: hot,
      playlists: playlists,
      charts: charts,
    );
    final result = _dedupeHomeSections(merged);
    AppLog.add(
      'home',
      'discover final listen=${result.listen.length} '
          'daily=${result.daily.length} heart=${result.heart.length} '
          'new=${result.newSongs.length} hot=${result.hot.length} '
          'recommended=${result.recommended.length} '
          'radio=${result.radio.length} playlists=${result.playlists.length}',
    );
    return result;
  }

  /// 每个板块只在本板块内去重。跨板块上游返回同一首歌时，各自保留在
  /// 自己的独立队列里；不能为了“看起来不同”把另一个板块整段删空。
  static DiscoverData _dedupeHomeSections(DiscoverData data) {
    return data.copyWith(
      daily: _dedupeSongs(data.daily),
      listen: _dedupeSongs(data.listen),
      recommended: _dedupeSongs(data.recommended),
      hot: _dedupeSongs(data.hot),
      heart: _dedupeSongs(data.heart),
      newSongs: _dedupeSongs(data.newSongs),
    );
  }

  static List<Playlist> _mergePlaylists(Iterable<List<Playlist>> groups) {
    final seen = <String>{};
    final out = <Playlist>[];
    for (final group in groups) {
      for (final p in group) {
        final key = p.id.isNotEmpty ? p.id : '${p.name}|${p.kind}';
        if (seen.add(key)) out.add(p);
      }
    }
    return out;
  }

  /// 「为你推荐」：recom_exclusive / 8011 → column/detail/bycolumnid。
  /// 调用方传入聚合页 `columnInfoExs` 解析出的动态栏目号；未传时用 8011。
  Future<List<Song>> featuredSongs({String? columnId, dynamic home}) async {
    var resolved = columnId?.trim() ?? '';
    if (resolved.isEmpty) {
      if (home != null) {
        resolved = recommendedColumnIdFrom(home) ?? '';
      }
      if (resolved.isEmpty) {
        try {
          final raw = await _withAuthRetry(() => gateway.get(HuaweiPaths.home));
          resolved = recommendedColumnIdFrom(raw) ?? '';
        } catch (e) {
          AppLog.add(
            'home',
            'featuredSongs column lookup error=${_safeLogError(e)}',
          );
        }
      }
    }
    if (resolved.isEmpty) resolved = featuredColumnId;
    final id = Uri.encodeQueryComponent(resolved);
    final json = await _withAuthRetry(
      () => gateway.get(
        '$featuredColumnPath?columnId=$id&start=0&limit=30&hasRecommend=1',
      ),
    );
    final songs = _songsFromColumnJson(json);
    final rawCount =
        _findNamedList(json, 'listRcmInfos').length +
        _findNamedList(json, 'songSimpleInfos').length +
        _findNamedList(json, 'contentSimpleInfos').length;
    AppLog.add(
      'home',
      'featuredSongs column=$resolved raw=$rawCount parsed=${songs.length} '
          'empty=${songs.isEmpty}',
    );
    return songs;
  }

  /// 每日30首：a001 → v3 musiclist/detail/bymusiclistid（GET）。
  Future<List<Song>> daily30({String id = dailyPlaylistId}) async {
    final json = await _withAuthRetry(
      () => gateway.get(
        '$dailyPlaylistPath?musicListID=${Uri.encodeQueryComponent(id)}'
        '&copyrightSwitch=1&start=0&limit=30',
      ),
    );
    return _dedupeSongs(
      deepList(json, const <String>[
        'playListSongInfoList',
        'songSimpleInfos',
        'contentSimpleInfos',
        'listRcmInfos',
        'songs',
        'list',
        'data',
      ]).map(parseSong),
    ).take(30).toList();
  }

  /// 每日推荐：请求体来自运行中 Muyu.exe 堆内真实 JSON。
  Future<List<Song>> dailySongs() async {
    final json = await gateway.request(
      HuaweiPaths.daily,
      body: const <String, dynamic>{
        'rcmScenario': '1',
        'termType': '1',
        'scenario': '1',
        'recommendStrategy': '0',
      },
    );
    return deepList(json, const [
      'dailySongs',
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  /// 私人电台单页：请求体字段来自 REA decompile(applicationRequest@0x1404225c0)。
  /// 证据（decompiled）：body 只有 `cadence` / `rcmMode` / `rcmScenario` /
  /// `refInfo` 四个字符串字段，没有 `next`。`rcmMode` 只接受 '1'/'2'/'3'，
  /// 非法值本地抛 ArgumentError，不发请求。
  ///
  /// `next` 参数保留只为兼容服务层：它是响应游标，不是请求字段。调用方没有
  /// 显式给 `refInfo` 时，把 `next` 当作续页游标映射到 `refInfo`（inference，
  /// 非 observed；`refInfo` 的真实非空格式仍 not-found）。显式 `refInfo` 优先。
  Future<HuaweiPrivateFmPage> privateFmPage({
    String mode = '1',
    String rcmScenario = '16',
    String refInfo = '',
    String next = '',
  }) async {
    final rcmMode = mode.trim();
    if (!const <String>{'1', '2', '3'}.contains(rcmMode)) {
      throw ArgumentError.value(mode, 'mode', 'rcmMode 只支持 1/2/3');
    }
    // 已证实的 rcmScenario 分支是 '16'/'21'；其他值不本地臆造，原样透传。
    final scenario = rcmScenario.trim().isEmpty ? '16' : rcmScenario.trim();
    // refInfo 必须是字符串（服务端对数组会 400）。显式 refInfo 优先；为空时
    // 才把旧参数 `next` 映射为续页游标。
    var requestRefInfo = refInfo.trim();
    if (requestRefInfo.isEmpty && next.trim().isNotEmpty) {
      requestRefInfo = next.trim();
    }
    final body = <String, dynamic>{
      'cadence': '',
      'rcmMode': rcmMode,
      'rcmScenario': scenario,
      'refInfo': requestRefInfo,
    };
    final json = await _withAuthRetry(
      () => gateway.request(HuaweiPaths.privateFm, body: body),
    );
    final page = _privateFmPageFromJson(
      json,
      requestRefInfo: requestRefInfo,
      scenario: scenario,
      mode: rcmMode,
    );
    // 只记录字段名 + 长度/布尔/数量：不输出游标或 refInfo 全文。
    AppLog.add(
      'home',
      'privateFmPage mode=$rcmMode scenario=$scenario '
          'refInfoLen=${requestRefInfo.length} nextLen=${page.next.length} '
          'more=${page.more} count=${page.songs.length}',
    );
    return page;
  }

  /// 心动模式首屏。请求体来自 REA decompile：
  /// `cadence:null`, `rcmMode:null`, `rcmScenario:"21"`, `refInfo` 由调用方
  /// 提供（行为 JSON 字符串，客户端不硬编码、不猜测内容）。不含 `next`。
  /// 这是 decompiled 契约，本轮没有 observed 200。
  Future<HuaweiPrivateFmPage> heartFmFirstPage({String refInfo = ''}) async {
    final body = <String, dynamic>{
      'cadence': null,
      'rcmMode': null,
      'rcmScenario': '21',
      'refInfo': refInfo,
    };
    final json = await _withAuthRetry(
      () => gateway.request(HuaweiPaths.privateFm, body: body),
    );
    final page = _privateFmPageFromJson(
      json,
      requestRefInfo: refInfo,
      scenario: '21',
      mode: 'heart',
    );
    // 不输出 refInfo / token 全文，只记录字段名与长度/布尔/数量。
    AppLog.add(
      'home',
      'heartFmFirstPage fields=cadence,rcmMode,rcmScenario,refInfo '
          'refInfoLen=${refInfo.length} more=${page.more} '
          'count=${page.songs.length}',
    );
    return page;
  }

  HuaweiPrivateFmPage _privateFmPageFromJson(
    Map<String, dynamic> json, {
    required String requestRefInfo,
    required String scenario,
    required String mode,
  }) {
    final songs = _dedupeSongs(
      deepList(json, const <String>[
        'listRcmInfos',
        'songSimpleInfos',
        'contentSimpleInfos',
        'songs',
        'list',
        'data',
      ]).map(parseSong),
    );
    final nextCursor = _cursorString(json, const <String>[
      'next',
      'nextIndex',
      'nextStart',
      'nextToken',
      'nextCursor',
    ]);
    final more = _cursorBool(json, const <String>[
      'more',
      'hasMore',
      'hasNext',
      'hasNextPage',
    ]);
    final responseRefInfo = _cursorString(json, const <String>['refInfo']);
    return HuaweiPrivateFmPage(
      songs: songs,
      next: nextCursor,
      more: more,
      refInfo: responseRefInfo.isEmpty ? requestRefInfo : responseRefInfo,
      rcmScenario: scenario,
      mode: mode,
    );
  }

  /// 兼容旧调用：只要单页歌曲，不暴露游标。
  Future<List<Song>> privateFm({String mode = '1'}) async =>
      (await privateFmPage(mode: mode)).songs;

  Future<List<Song>> privateRadio({String mode = '1'}) => privateFm(mode: mode);

  /// 推荐歌单：沐语 /recommend/playlist。
  /// REA decompile 给出的 body 是 `contentCodes`（字符串数组）、
  /// `limit`（数字）、`rcmScenario`（字符串）。该端点尚无 observed 200，
  /// 本轮标记为 decompiled-unverified；失败/空响应回退同账号真实歌单，
  /// 不让 live probe 整体中断。不要把这个 body 当成已验证可用。
  Future<List<Playlist>> recommendedPlaylists() async {
    try {
      final json = await _withAuthRetry(
        () => gateway.request(
          HuaweiPaths.recommendPlaylist,
          body: const <String, dynamic>{
            'contentCodes': <String>[],
            'limit': 12,
            'rcmScenario': '1',
          },
        ),
      );
      final parsed = deepList(json, const <String>[
        'playListInfos',
        'playlistInfos',
        'contentSimpleInfos',
        'songList',
        'list',
        'data',
      ]).map(_playlistFromRecommend).where((p) => p.id.isNotEmpty).toList();
      if (parsed.isNotEmpty) return parsed;
      AppLog.add(
        'home',
        'recommendedPlaylists empty contract=decompiled-unverified',
      );
    } catch (e) {
      AppLog.add(
        'home',
        'recommendedPlaylists error=${_safeLogError(e)} '
            'contract=decompiled-unverified',
      );
    }
    AppLog.add(
      'home',
      'recommend/playlist contract=decompiled-unverified '
          'fallback=accountPlaylists',
    );
    try {
      final fallback = await playlists();
      AppLog.add(
        'home',
        'recommendedPlaylists fallback count=${fallback.length}',
      );
      return fallback;
    } catch (e) {
      AppLog.add(
        'home',
        'recommendedPlaylists fallback error=${_safeLogError(e)}',
      );
      return const <Playlist>[];
    }
  }

  static Playlist _playlistFromRecommend(Map<String, dynamic> d) {
    final inner = d['miniMusicListInfoEx'];
    final map = inner is Map
        ? <String, dynamic>{...d, ...Map<String, dynamic>.from(inner)}
        : d;
    return parsePlaylist(map);
  }

  /// 榜单歌曲：chartID / chartCode 来自 REA 符号与堆字段。
  Future<List<Song>> chartSongs(String chartId) async {
    return _collectSongPages((start, limit) async {
      // 运行时实测：榜单详情必须 GET；POST 返回 405。
      final json = await _withAuthRetry(
        () => gateway.get(
          '${HuaweiPaths.chartDetail}?chartID=${Uri.encodeComponent(chartId)}'
          '&chartId=${Uri.encodeComponent(chartId)}'
          '&contentType=1&start=$start&limit=$limit',
        ),
      );
      return deepList(json, const [
        'listRcmInfos',
        'songSimpleInfos',
        'contentSimpleInfos',
        'songs',
        'list',
        'data',
      ]).map(parseSong).toList();
    });
  }

  /// 逐页读取直到短页 / 无新增；用 contentID 去重，防止接口忽略 start 时死循环。
  Future<List<Song>> _collectSongPages(
    Future<List<Song>> Function(int start, int limit) fetch, {
    int pageSize = 50,
    int maxItems = 5000,
  }) async {
    final out = <Song>[];
    final seen = <String>{};
    var start = 0;
    while (out.length < maxItems) {
      final page = await fetch(start, pageSize);
      var added = 0;
      for (final song in page) {
        final key = song.id.isNotEmpty
            ? song.id
            : '${song.name}|${song.artistText}';
        if (seen.add(key)) {
          out.add(song);
          added++;
        }
      }
      if (page.length < pageSize || added == 0) break;
      start += page.length;
    }
    return out;
  }

  /// 解析沐语首页 JSON。列名全部由 REA 反编译给出的字符串常量实测，不是猜测。
  static DiscoverData parseDiscover(dynamic root) {
    final columns = _findNamedList(root, 'columnInfoExs');
    final recommended = <Song>[];
    final sectionSongs = <Song>[];
    final a001Songs = <Song>[];
    final radio = <Song>[];
    final playlists = <Playlist>[];
    final charts = <Playlist>[];
    final albums = <Playlist>[];
    final banners = <DiscoverBanner>[];
    final features = <DiscoverFeature>[];
    final batches = <_HomeBatch>[];
    final pmfTopSongs = <Song>[];
    final recommendedColumnId = recommendedColumnIdFrom(root);

    void collectDirect(Map<String, dynamic> content, List<Song> out) {
      final type =
          HuaweiGateway.firstString(content, const ['contentType']) ?? '';
      final hasChildren = _directNamedList(
        content,
        'childSimpleInfos',
      ).isNotEmpty;
      final hasDirectSongList =
          content['listRcmInfos'] is List || content['songSimpleInfos'] is List;
      if (type == '1' || (type.isEmpty && !hasChildren && !hasDirectSongList)) {
        out.add(parseSong(content));
      }
      // 只读当前 Map 的直接列表，避免把 childSimpleInfos 里兄弟批次的
      // heart/new/hot 歌曲递归收集进顶层 listen。
      for (final item in _directNamedList(content, 'listRcmInfos')) {
        out.add(parseSong(item));
      }
      for (final item in _directNamedList(content, 'songSimpleInfos')) {
        out.add(parseSong(item));
      }
    }

    void collectNested(Map<String, dynamic> content, List<Song> out) {
      collectDirect(content, out);
      for (final child in _directNamedList(content, 'childSimpleInfos')) {
        final childType =
            HuaweiGateway.firstString(child, const ['contentType']) ?? '';
        if (childType == '2') continue;
        collectDirect(child, out);
      }
    }

    void collectPmf(Map<String, dynamic> content, String label) {
      final contentId = _contentIdFrom(content);
      final feature = _featureFrom(content);
      if (feature != null) features.add(feature);
      final top = _HomeBatch(
        contentId.isEmpty ? 'pmf001' : contentId,
        label,
        topLevel: true,
      );
      // 顶层只收 pmf001 自己的歌曲；带 heart/new/hot 标签的子批次各自
      // 独立成批，不能再被顶层“现在就听”整包吞掉。
      collectDirect(content, top.songs);
      if (top.songs.isNotEmpty) {
        batches.add(top);
        pmfTopSongs.addAll(top.songs);
      }
      for (final child in _directNamedList(content, 'childSimpleInfos')) {
        final childId = _contentIdFrom(child);
        final childBatch = _HomeBatch(
          childId.isEmpty ? 'pmf001' : childId,
          _contentLabel(child),
        );
        final childFeature = _featureFrom(child);
        if (childFeature != null) features.add(childFeature);
        collectNested(child, childBatch.songs);
        if (childBatch.songs.isNotEmpty) batches.add(childBatch);
      }
    }

    for (final column in columns) {
      final columnLabel = _columnLabel(column);
      final columnId = _columnIdFrom(column);
      final contents = _findNamedList(column, 'contentSimpleInfos');
      for (final content in contents) {
        final contentId = _contentIdFrom(content);
        final label = '$columnLabel ${_contentLabel(content)}'.trim();
        // 运行时实测 contentType 语义：
        // 1=歌曲 2=专辑 4=歌单 7=榜单 11=Banner/入口 12=功能卡
        // 96=分区（childSimpleInfos） 6/10/20=分类/MV/有声书。
        final type =
            HuaweiGateway.firstString(content, const ['contentType']) ?? '';
        // 真实电台种子卡只认 pmf001（不是旧实现里的 pfm001/pfm002）。
        if (contentId.toLowerCase() == 'pmf001') {
          collectPmf(content, label);
          continue;
        }
        switch (type) {
          case '1':
            final song = parseSong(content);
            if ((recommendedColumnId != null &&
                    columnId == recommendedColumnId) ||
                columnId == featuredColumnId ||
                _isRecommendedLabel(columnLabel)) {
              recommended.add(song);
            }
            break;
          case '2':
            albums.add(parseAlbum(content));
            break;
          case '4':
            playlists.add(_withKind(parsePlaylist(content), 'collected'));
            if (contentId == dailyPlaylistId) {
              collectNested(content, a001Songs);
            }
            break;
          case '7':
            charts.add(_withKind(parsePlaylist(content), 'chart'));
            break;
          case '11':
            final banner = _bannerFrom(content);
            if (banner != null) banners.add(banner);
            break;
          case '96':
            for (final child in _findNamedList(content, 'childSimpleInfos')) {
              final childType =
                  HuaweiGateway.firstString(child, const ['contentType']) ?? '';
              if (childType == '2') {
                albums.add(parseAlbum(child));
              } else {
                collectNested(child, sectionSongs);
              }
            }
            break;
          case '12':
            final feature = _featureFrom(content);
            if (feature != null) features.add(feature);
            collectNested(content, radio);
            break;
          default:
            collectNested(content, radio);
        }
      }
    }

    if (banners.isEmpty) banners.addAll(parseBanners(root));

    final embeddedAll = _dedupeSongs(batches.expand((b) => b.songs));
    radio.addAll(embeddedAll);

    String textOf(_HomeBatch b) => '${b.id} ${b.label}'.toLowerCase();
    bool isHeart(_HomeBatch b) =>
        textOf(b).contains('heart') || textOf(b).contains('心动');
    bool isNew(_HomeBatch b) =>
        textOf(b).contains('new') ||
        textOf(b).contains('新歌') ||
        textOf(b).contains('newsong');
    bool isHot(_HomeBatch b) =>
        textOf(b).contains('hot') || textOf(b).contains('热歌');

    List<Song> takeSemantic(bool Function(_HomeBatch) test) {
      final songs = <Song>[];
      for (final batch in batches) {
        // 顶层 pmf001 是「现在就听」；heart/new/hot 只认子批次标签。
        if (batch.topLevel || !test(batch)) continue;
        songs.addAll(batch.songs);
      }
      return _dedupeSongs(songs);
    }

    final heart = takeSemantic(isHeart);
    final newFromEmbedded = takeSemantic(isNew);
    final hot = takeSemantic(isHot);
    // 「现在就听」只来自 pmf001 当前层直接 listRcmInfos/songSimpleInfos；
    // 不递归 childSimpleInfos 子批次，也不拿其他板块兜底。
    final listen = _dedupeSongs(pmfTopSongs);

    final newSongs = _dedupeSongs(<Song>[...sectionSongs, ...newFromEmbedded]);
    final seenLists = <String>{};
    playlists.removeWhere((p) => p.id.isNotEmpty && !seenLists.add(p.id));
    charts.removeWhere((p) => p.id.isNotEmpty && !seenLists.add(p.id));
    albums.removeWhere((p) => p.id.isNotEmpty && !seenLists.add(p.id));
    final seenFeatures = <String>{};
    features.removeWhere((f) => f.id.isNotEmpty && !seenFeatures.add(f.id));

    return DiscoverData(
      banners: banners.take(8).toList(),
      newSongs: _dedupeSongs(newSongs).take(30).toList(),
      playlists: playlists,
      charts: charts,
      radio: _dedupeSongs(radio),
      albums: albums,
      recommended: _dedupeSongs(recommended).take(30).toList(),
      listen: _dedupeSongs(listen).take(30).toList(),
      heart: _dedupeSongs(heart).take(30).toList(),
      hot: _dedupeSongs(hot).take(10).toList(),
      recommendedColumnId: recommendedColumnId ?? featuredColumnId,
      features: features,
      daily: _dedupeSongs(a001Songs),
    );
  }

  static List<Song> _dedupeSongs(Iterable<Song> input) {
    final seen = <String>{};
    final out = <Song>[];
    for (final song in input) {
      if (song.name.isEmpty || song.name == '未知歌曲') continue;
      // 没有真实 contentCode 的条目无法取流；不要用时间戳假 ID 或
      // name 冒充歌曲码，列表里直接丢弃，避免“能点但一定播不了”。
      if (song.id.isEmpty) continue;
      final key = song.id;
      if (!seen.add(key)) continue;
      out.add(song);
    }
    return out;
  }

  static dynamic _findDeepKeyValue(dynamic root, String key) {
    if (root is Map) {
      if (root.containsKey(key)) return root[key];
      for (final value in root.values) {
        final found = _findDeepKeyValue(value, key);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final value in root) {
        final found = _findDeepKeyValue(value, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  static String _cursorString(dynamic root, List<String> keys) {
    for (final key in keys) {
      final value = _findDeepKeyValue(root, key);
      if (value is String) {
        final text = value.trim();
        if (text.isNotEmpty) return text;
      } else if (value is num) {
        return value.toString();
      }
    }
    return '';
  }

  static bool _cursorBool(dynamic root, List<String> keys) {
    for (final key in keys) {
      final value = _findDeepKeyValue(root, key);
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        switch (value.trim().toLowerCase()) {
          case '1':
          case 'true':
          case 'yes':
            return true;
          case '0':
          case 'false':
          case 'no':
            return false;
        }
      }
    }
    return false;
  }

  /// 日志只保留错误码或截断后的脱敏文本，不输出 Authorization / token。
  static String _safeLogError(Object e) {
    final redacted = e
        .toString()
        .replaceAllMapped(
          RegExp(
            r'(authorization|token|digest)(\s*[=:]\s*)[^,\s}]+',
            caseSensitive: false,
          ),
          (m) => '${m[1]}=***',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return redacted.length <= 160
        ? redacted
        : '${redacted.substring(0, 160)}...';
  }

  static String _columnLabel(Map<String, dynamic> column) {
    final parts = <String>[];
    final info = column['columnInfo'];
    if (info is Map) {
      _collectTextValues(Map<String, dynamic>.from(info), parts);
    }
    _collectTextValues(column, parts);
    return parts.join(' ').toLowerCase();
  }

  static String _contentLabel(Map<String, dynamic> content) {
    final parts = <String>[];
    _collectTextValues(content, parts);
    return parts.join(' ').toLowerCase();
  }

  static void _collectTextValues(Map<String, dynamic> map, List<String> out) {
    for (final key in const <String>[
      'columnKey',
      'columnId',
      'columnID',
      'columnName',
      'contentID',
      'contentId',
      'contentName',
      'name',
      'title',
    ]) {
      final value = map[key];
      if (value is String && value.isNotEmpty) out.add(value);
    }
  }

  static DiscoverFeature? _featureFrom(Map<String, dynamic> content) {
    var id = _contentIdFrom(content);
    var title =
        HuaweiGateway.firstString(content, const [
          'contentName',
          'keyName',
          'name',
          'title',
        ]) ??
        '';
    final rawInfo = content['contentExInfo'];
    Map<String, dynamic>? info;
    if (rawInfo is Map) {
      info = Map<String, dynamic>.from(rawInfo);
    } else if (rawInfo is String && rawInfo.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(rawInfo);
        if (decoded is Map) info = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final real = info?['realContentInfo'];
    if (real is Map) {
      final map = Map<String, dynamic>.from(real);
      id = id.isEmpty
          ? (HuaweiGateway.firstString(map, const [
                  'contentID',
                  'contentId',
                  'id',
                ]) ??
                '')
          : id;
      title =
          HuaweiGateway.firstString(map, const [
            'contentName',
            'keyName',
            'name',
            'title',
          ]) ??
          title;
    }
    if (id.isEmpty && title.isEmpty) return null;
    return DiscoverFeature(id: id, title: title, cover: coverOf(content));
  }

  static String _contentIdFrom(Map<String, dynamic> content) =>
      HuaweiGateway.firstString(content, const [
        'contentID',
        'contentId',
        'contentCode',
        'id',
      ]) ??
      '';

  static bool _isRecommendedLabel(String label) =>
      label.contains('recom_exclusive');

  /// 从 `page/detail/all` 的 columnInfoExs 找 recom_exclusive 栏目的真实号。
  /// 8011 只是兜底常量，不在聚合页里强行覆盖动态栏目号。
  static String? recommendedColumnIdFrom(dynamic root) {
    for (final column in _findNamedList(root, 'columnInfoExs')) {
      final id = _columnIdFrom(column);
      if (id == null || id.isEmpty) continue;
      if (id == featuredColumnId || _isRecommendedLabel(_columnLabel(column))) {
        return id;
      }
    }
    return null;
  }

  static String? _columnIdFrom(Map<String, dynamic> column) {
    final maps = <Map<String, dynamic>>[];
    final info = column['columnInfo'];
    if (info is Map) maps.add(Map<String, dynamic>.from(info));
    maps.add(column);
    for (final map in maps) {
      for (final key in const <String>[
        'columnId',
        'columnID',
        'contentID',
        'contentId',
        'id',
      ]) {
        final value = map[key];
        if (value is String && value.isNotEmpty && value != 'recom_exclusive') {
          return value;
        }
        if (value is num) return value.toString();
      }
    }
    return null;
  }

  /// 私享好歌栏目详情可能沿用首页 column 结构，也可能直接给
  /// listRcmInfos/songSimpleInfos；这里按真实字段递归收敛。
  static List<Song> _songsFromColumnJson(dynamic root) {
    final out = <Song>[];
    void addMap(Map<String, dynamic> map) {
      final type = HuaweiGateway.firstString(map, const ['contentType']) ?? '';
      if (type == '1') {
        out.add(parseSong(map));
        return;
      }
      if (type == '96' || type.isEmpty) {
        for (final child in _findNamedList(map, 'childSimpleInfos')) {
          addMap(child);
        }
      }
      for (final item in _findNamedList(map, 'listRcmInfos')) {
        out.add(parseSong(item));
      }
      for (final item in _findNamedList(map, 'songSimpleInfos')) {
        out.add(parseSong(item));
      }
    }

    for (final content in _findNamedList(root, 'contentSimpleInfos')) {
      addMap(content);
    }
    for (final item in _findNamedList(root, 'listRcmInfos')) {
      out.add(parseSong(item));
    }
    for (final item in _findNamedList(root, 'songSimpleInfos')) {
      out.add(parseSong(item));
    }
    return _dedupeSongs(out).take(30).toList();
  }

  static Playlist _withKind(Playlist p, String kind) => Playlist(
    id: p.id,
    name: p.name,
    cover: p.cover,
    songCount: p.songCount,
    kind: kind,
  );

  /// 严格按 key 查找嵌套数组；不会把任意子数组误当成目标 key。
  /// `deepList` 在遇到 List 根时会直接返回所有 Map，容易把 songSimpleInfos
  /// 误当成 listRcmInfos，因此首页解析必须用这个严格版本。
  static List<Map<String, dynamic>> _findNamedList(dynamic root, String key) {
    if (root is Map) {
      final direct = root[key];
      if (direct is List) {
        final maps = direct.whereType<Map<String, dynamic>>().toList();
        if (maps.isNotEmpty) return maps;
      }
      for (final value in root.values) {
        final found = _findNamedList(value, key);
        if (found.isNotEmpty) return found;
      }
    } else if (root is List) {
      for (final value in root) {
        final found = _findNamedList(value, key);
        if (found.isNotEmpty) return found;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  /// 只读 Map 的当前层字段，不递归子数组。
  /// pmf001 的子批次（heart/new/hot）必须各自成批，不能让顶层
  /// `listRcmInfos` 查询把第一个子批次的歌曲误当成自己的直接歌曲。
  static List<Map<String, dynamic>> _directNamedList(
    Map<String, dynamic> map,
    String key,
  ) {
    final value = map[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Opt-in live probe helper: inspect a named list without reimplementing
  /// Huawei's nested envelope in test code.
  static List<Map<String, dynamic>> debugFindNamedList(
    dynamic root,
    String key,
  ) => _findNamedList(root, key);

  static DiscoverBanner? _bannerFrom(Map<String, dynamic> d) {
    final url = coverOf(d, const <String>['imageUrl']);
    final title = HuaweiGateway.firstString(d, const [
      'contentName',
      'title',
      'name',
      'subTitle',
    ]);
    if (url == null ||
        title == null ||
        title.isEmpty ||
        !_bannerImageAllowed(url)) {
      return null;
    }
    return DiscoverBanner(
      title: title,
      subtitle:
          HuaweiGateway.firstString(d, const [
            'subTitle',
            'description',
            'summary',
          ]) ??
          '',
      imageUrl: url,
    );
  }

  /// 榜单 / 歌单通用解析（字段名来自 REA：chartID / songNum / picture）。
  static Playlist parsePlaylist(Map<String, dynamic> d) {
    return Playlist(
      id:
          HuaweiGateway.firstString(d, const [
            'chartID',
            'chartId',
            'chartCode',
            'playListID',
            'contentID',
            'id',
          ]) ??
          '',
      name:
          HuaweiGateway.firstString(d, const [
            'chartName',
            'playListName',
            'contentName',
            'name',
            'title',
          ]) ??
          '',
      cover: coverOf(d),
      songCount:
          HuaweiGateway.firstInt(d, const [
            'songNum',
            'totalCount',
            'songCount',
            'number',
          ]) ??
          0,
    );
  }

  /// 歌手结果（字段来自 catalog.Artist / artistInfoEx / artistNamePairs）。
  static Artist parseArtist(Map<String, dynamic> d) {
    return Artist(
      id:
          HuaweiGateway.firstString(d, const [
            'artistCode',
            'artistID',
            'artistId',
            'contentID',
            'contentCode',
            'id',
          ]) ??
          '',
      name:
          HuaweiGateway.firstString(d, const [
            'artistName',
            'contentName',
            'name',
            'artNM',
            'NM',
            'title',
          ]) ??
          '',
      cover: coverOf(d, const <String>['avatar', 'headPictureURL']),
      desc:
          HuaweiGateway.firstString(d, const [
            'description',
            'artistDesc',
            'summary',
            'subTitle',
          ]) ??
          '',
    );
  }

  /// 专辑结果（字段来自 catalog.AlbumSongs / albumInfoEx）。
  static Playlist parseAlbum(Map<String, dynamic> d) {
    return Playlist(
      id:
          HuaweiGateway.firstString(d, const [
            'albumCode',
            'albumID',
            'albumId',
            'contentID',
            'contentCode',
            'id',
          ]) ??
          '',
      name:
          HuaweiGateway.firstString(d, const [
            'albumName',
            'contentName',
            'name',
            'albNM',
            'title',
          ]) ??
          '',
      cover: coverOf(d),
      songCount:
          HuaweiGateway.firstInt(d, const [
            'songNum',
            'totalCount',
            'songCount',
            'number',
          ]) ??
          0,
      kind: 'album',
    );
  }

  /// 从首页响应的 banner / column 数据中抓真实活动图。
  static List<DiscoverBanner> parseBanners(dynamic root) {
    final out = <DiscoverBanner>[];
    void visit(dynamic node, [String parentHint = '']) {
      if (node is List) {
        for (final v in node) {
          visit(v, parentHint);
        }
        return;
      }
      if (node is! Map) return;
      final hint = parentHint.toLowerCase();
      final inBannerContainer =
          hint.contains('banner') ||
          hint.contains('column') ||
          hint.contains('card') ||
          hint.contains('activity');
      // 当前节点本身就是 columns/banner 数组里的一个卡片。
      if (inBannerContainer && out.length < 8) {
        final self = Map<String, dynamic>.from(node);
        final url = HuaweiGateway.firstUrl(self, const [
          'picture',
          'imageUrl',
          'imgUrl',
          'cover',
          'picUrl',
        ]);
        final title = HuaweiGateway.firstString(self, const [
          'title',
          'name',
          'contentName',
          'subTitle',
        ]);
        if (url != null &&
            _bannerImageAllowed(url) &&
            title != null &&
            title.isNotEmpty) {
          out.add(
            DiscoverBanner(
              title: title,
              subtitle:
                  HuaweiGateway.firstString(self, const [
                    'subtitle',
                    'description',
                    'summary',
                  ]) ??
                  '',
              imageUrl: url,
            ),
          );
        }
      }
      for (final entry in node.entries) {
        final key = entry.key.toLowerCase();
        final value = entry.value;
        final isBanner =
            key.contains('banner') || (key.contains('column') && value is Map);
        if ((isBanner || inBannerContainer) && value is Map && out.length < 8) {
          final m = Map<String, dynamic>.from(value);
          final url = HuaweiGateway.firstUrl(m, const [
            'picture',
            'imageUrl',
            'imgUrl',
            'cover',
            'picUrl',
          ]);
          final title = HuaweiGateway.firstString(m, const [
            'title',
            'name',
            'contentName',
            'subTitle',
          ]);
          if (url != null &&
              _bannerImageAllowed(url) &&
              title != null &&
              title.isNotEmpty) {
            out.add(
              DiscoverBanner(
                title: title,
                subtitle:
                    HuaweiGateway.firstString(m, const [
                      'subtitle',
                      'description',
                      'summary',
                    ]) ??
                    '',
                imageUrl: url,
              ),
            );
          }
        }
        visit(value, key);
      }
    }

    visit(root);
    return out;
  }

  static bool _bannerImageAllowed(Uri url) {
    if (url.scheme != 'https') return false;
    final host = url.host.toLowerCase();
    return const [
      '.dbankcdn.cn',
      '.tingmall.com',
      '.kuke.com',
    ].any((s) => host.endsWith(s) && host.length > s.length);
  }

  /// 在任意嵌套层里找第一个指定 key 的数组。
  static List<Map<String, dynamic>> deepList(dynamic root, List<String> keys) {
    if (root is List) {
      final mapped = root.whereType<Map<String, dynamic>>().toList();
      if (mapped.isNotEmpty) return mapped;
      for (final item in root) {
        final found = deepList(item, keys);
        if (found.isNotEmpty) return found;
      }
      return const <Map<String, dynamic>>[];
    }
    if (root is! Map) return const <Map<String, dynamic>>[];
    final map = Map<String, dynamic>.from(root);
    for (final k in keys) {
      final v = map[k];
      if (v is List) {
        final mapped = v.whereType<Map<String, dynamic>>().toList();
        if (mapped.isNotEmpty) return mapped;
      }
      if (v is Map) {
        final found = deepList(v, keys);
        if (found.isNotEmpty) return found;
      }
    }
    for (final v in map.values) {
      if (v is Map || v is List) {
        final found = deepList(v, keys);
        if (found.isNotEmpty) return found;
      }
    }
    return const <Map<String, dynamic>>[];
  }
}
