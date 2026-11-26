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

/// 首页 contentType=998 的功能卡（现在就听/每日30首/心动模式/新歌推荐/热歌速递/私藏馆）。
class DiscoverFeature {
  const DiscoverFeature({
    required this.id,
    required this.title,
    required this.serviceType,
    this.cover,
  });

  final String id;
  final String title;
  final String serviceType;
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

/// 一次华为搜索返回的三类结果。
class HuaweiSearchResult {
  const HuaweiSearchResult({
    this.songs = const <Song>[],
    this.artists = const <Artist>[],
    this.albums = const <Playlist>[],
  });
  final List<Song> songs;
  final List<Artist> artists;

  /// 专辑复用 Playlist 卡片模型，kind 固定为 'album'。
  final List<Playlist> albums;
}

/// 与沐语 Go 版 internal/catalog 对等：首页 / 搜索 / 榜单 / 收藏 / 歌单 /
/// 歌词 / 相似推荐 / 取流。解析全部走容错取值，不依赖严格 DTO。
class HuaweiAPI {
  HuaweiAPI({HuaweiGateway? gateway}) : gateway = gateway ?? HuaweiGateway();

  final HuaweiGateway gateway;
  String? displayName;
  String? avatarUrl;
  String? memberLabel;
  bool isMember = false;
  void Function()? onProfileChanged;

  /// 源码事实：必须有音乐会话（token + snsUserID）才能发业务请求。
  bool get isLoggedIn => gateway.session != null;

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
    String? nick,
  }) {
    if (musicToken.trim().isEmpty || snsUserId.trim().isEmpty) return;
    gateway.session = MusicSession(
      token: musicToken.trim(),
      snsUserId: snsUserId.trim(),
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

  /// 搜索一次请求，同时解析歌曲 / 歌手 / 专辑。
  /// 华为 fuzzysearch 以 songSimpleInfos 为主；若响应携带
  /// artistSimpleInfos / albumSimpleInfos 则一并展示，没有就不造数据。
  Future<HuaweiSearchResult> searchAll(
    String keyword, {
    int start = 0,
    int limit = 30,
  }) async {
    Future<Map<String, dynamic>?> searchType(String type) async {
      try {
        return await _searchJson(
          keyword,
          start: start,
          limit: limit,
          contentType: type,
        );
      } catch (_) {
        return null;
      }
    }

    // 运行时实测：contentType 1=歌曲、2=专辑、3=歌手、4=歌单。
    final results = await Future.wait<Map<String, dynamic>?>(
      <Future<Map<String, dynamic>?>>[
        searchType('1'),
        searchType('2'),
        searchType('3'),
      ],
    );
    final songJson = results[0] ?? const <String, dynamic>{};
    final albumJson = results[1] ?? const <String, dynamic>{};
    final artistJson = results[2] ?? const <String, dynamic>{};
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
    return HuaweiSearchResult(songs: songs, artists: artists, albums: albums);
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
  /// 不从曲库详情取。优先逐字 HMRC（wordByWordLyric），再行级 LRC
  /// （lineByLineLyric / lyricAddress），并把译文合并进对应行。
  Future<List<LyricLine>> lyrics(String songCode) async {
    // 复用取流响应：歌词地址在 fileURL 同一个响应里。
    final json = await gateway.request(
      HuaweiPaths.playUrl,
      body: <String, dynamic>{
        'contentCode': songCode,
        'contentType': '1',
        'qualityType': '1',
      },
    );

    Uri? wordUrl; // 逐字 HMRC
    Uri? plainUrl; // 行级 LRC
    String? plainText; // 内嵌 LRC 文本
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

    List<LyricLine> lines = <LyricLine>[];
    final wu = wordUrl;
    if (wu != null) {
      try {
        lines = parseHmrc(await gateway.fetchText(wu));
      } catch (_) {}
    }
    final pu = plainUrl;
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
    for (final q in wanted) {
      Map<String, dynamic>? json;
      Uri? link;
      String? requestedCode;
      for (final typeCode in typeCodes[q] ?? const <String>['1']) {
        final result = await gateway.request(
          HuaweiPaths.playUrl,
          body: <String, dynamic>{
            'contentCode': songCode,
            'contentType': '1',
            'qualityType': typeCode,
          },
        );
        final candidate = HuaweiGateway.firstUrl(result, const [
          'fileURL',
          'fileUrl',
          'playURL',
          'url',
        ]);
        if (candidate != null &&
            _safeAudioUrl(candidate) &&
            !_isAudition(result, candidate)) {
          json = result;
          link = candidate;
          requestedCode = typeCode;
          break;
        }
      }
      if (json == null || link == null) continue;

      // 以实际请求到的 qualityType 为准：5/7=Hi-Res，3=SQ，1/2=标准。
      AudioQuality actual = switch (requestedCode) {
        '7' || '5' => AudioQuality.hiRes,
        '3' => AudioQuality.lossless,
        _ => AudioQuality.standard,
      };
      if (!out.any((f) => f.quality == actual)) {
        out.add(
          HuaweiAudioFile(
            quality: actual,
            url: link,
            sizeBytes:
                HuaweiGateway.firstInt(json, const ['size', 'fileSize']) ?? 0,
          ),
        );
      }
    }
    if (out.isEmpty) {
      throw const HuaweiException('该歌曲没有可用的音质档位（请确认已登录且为会员）');
    }
    return out;
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
  /// 30/60 秒，`auditionEnd`/`auditionTime` 或 URL 的 `_AQ`/`_PV` 后缀可判定。
  /// 这类地址绝不能当成完整歌曲交给播放器。
  static bool _isAudition(Map<String, dynamic> json, Uri url) {
    final path = url.path.toLowerCase();
    if (path.endsWith('_aq.mp3') ||
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

      final highest = HuaweiGateway.firstString(
        map,
        const ['highestQuality', 'highestReportedQuality', 'maxQuality'],
      );
      if (highest != null) out.add(fromTier(highest));

      final audio = map['huaweiAudioFiles'];
      if (audio is Map) {
        final files = Map<String, dynamic>.from(audio);
        final types =
            HuaweiGateway.firstInt(files, const ['types', 'type', 'qualityTypes']) ??
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
          final tier = HuaweiGateway.firstString(
            file,
            const ['qualityType', 'quality', 'playQuality', 'level'],
          );
          if (tier != null) out.add(fromTier(tier));
          final bitRate =
              HuaweiGateway.firstInt(file, const ['bitRate', 'br', 'maxbr']);
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
          DateTime.now().microsecondsSinceEpoch.toString(),
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
  Future<DiscoverData> discover() async {
    // 运行时实测：首页聚合接口必须 GET；POST 返回 405。
    final json = await gateway.get(HuaweiPaths.home);
    final data = parseDiscover(json);
    // 2.0.4 真实首页把 6 个入口放在 contentType=998 功能卡里；
    // 有功能卡时不要再请求 8011 空栏目，交给上层按 a001/a003/a004/a006 拉各自曲库。
    if (data.features.isNotEmpty) return data;
    if (data.recommended.isEmpty && data.recommendedColumnId != null) {
      final extra = await _fetchRecommendationColumn(data.recommendedColumnId!);
      if (extra.isNotEmpty) {
        return data.copyWith(
          recommended: extra,
          listen: data.listen.isEmpty ? extra : data.listen,
        );
      }
    }
    return data;
  }

  /// 首页「为你推荐」是独立的私享好歌栏目。REA 常量：
  /// `recom_exclusive` / `8011` / `column/detail/bycolumnid?`。
  /// 首页 JSON 有栏目编号时直接用；否则按 8011 兜底。
  Future<List<Song>> _fetchRecommendationColumn(String columnId) async {
    final id = Uri.encodeQueryComponent(columnId);
    final paths = <String>[
      '/music-operation-service/v1/service/column/detail/bycolumnid'
          '?columnId=$id&start=0&limit=30&hasRecommend=1',
      '/music-operation-service/v1/service/column/detail/bycolumnid'
          '?columnID=$id&start=0&limit=30&hasRecommend=1',
    ];
    for (final path in paths) {
      try {
        final json = await gateway.get(path);
        final songs = _songsFromColumnJson(json);
        if (songs.isNotEmpty) {
          AppLog.add('api', '首页私享好歌 column=$columnId -> ${songs.length} 首');
          return songs;
        }
      } catch (e) {
        AppLog.add('api', '首页私享好歌 column=$columnId 失败：$e');
      }
    }
    return const <Song>[];
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

  /// 私人电台：请求体字段来自 REA decompile(applicationRequest@0x1404225c0)。
  /// cadence / rcmMode / rcmScenario / refInfo；rcmMode 仅接受 '1'/'2'/'3'。
  Future<List<Song>> privateRadio({String mode = '1'}) async {
    final json = await gateway.request(
      HuaweiPaths.privateFm,
      body: <String, dynamic>{
        'cadence': '',
        'rcmMode': mode,
        'rcmScenario': '16',
        'refInfo': <dynamic>[],
      },
    );
    return deepList(json, const [
      'songSimpleInfos',
      'contentSimpleInfos',
      'songs',
      'list',
      'data',
    ]).map(parseSong).toList();
  }

  /// 推荐歌单：沐语 /recommend/playlist。
  Future<List<Playlist>> recommendedPlaylists() async {
    final json = await gateway.request(
      HuaweiPaths.recommendPlaylist,
      body: const <String, dynamic>{'contentType': 1, 'start': 0, 'limit': 30},
    );
    return deepList(json, const [
      'playListInfos',
      'playlistInfos',
      'contentSimpleInfos',
      'songList',
      'list',
      'data',
    ]).map(parsePlaylist).toList();
  }

  /// 榜单歌曲：chartID / chartCode 来自 REA 符号与堆字段。
  Future<List<Song>> chartSongs(String chartId) async {
    return _collectSongPages((start, limit) async {
      // 运行时实测：榜单详情必须 GET；POST 返回 405。
      final json = await gateway.get(
        '${HuaweiPaths.chartDetail}?chartID=${Uri.encodeComponent(chartId)}'
        '&chartId=${Uri.encodeComponent(chartId)}'
        '&contentType=1&start=$start&limit=$limit',
      );
      return deepList(json, const [
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
    final genericSongs = <Song>[];
    final recommended = <Song>[];
    final listenSongs = <Song>[];
    final heartSongs = <Song>[];
    final newSongs = <Song>[];
    final hotSongs = <Song>[];
    final playlists = <Playlist>[];
    final charts = <Playlist>[];
    final albums = <Playlist>[];
    final radio = <Song>[];
    final banners = <DiscoverBanner>[];
    final features = <DiscoverFeature>[];
    String? recommendedColumnId;

    void addSong(Song song, String label) {
      if (song.name.isEmpty || song.name == '未知歌曲') return;
      genericSongs.add(song);
      final text = label.toLowerCase();
      if (_isRecommendedLabel(text)) recommended.add(song);
      if (_isListenLabel(text)) listenSongs.add(song);
      if (_isHeartLabel(text)) heartSongs.add(song);
      if (_isNewLabel(text)) newSongs.add(song);
      if (_isHotLabel(text)) hotSongs.add(song);
    }

    void addSongMap(Map<String, dynamic> content, String label) {
      addSong(parseSong(content), label);
    }

    for (final column in columns) {
      final columnLabel = _columnLabel(column);
      if (_isRecommendedLabel(columnLabel)) {
        recommendedColumnId ??= _columnIdFrom(column);
      }
      final contents = _findNamedList(column, 'contentSimpleInfos');
      for (final content in contents) {
        final label = '$columnLabel ${_contentLabel(content)}'.trim();
        // 运行时实测 contentType 语义：
        // 1=歌曲 2=专辑 4=歌单 7=榜单 11=Banner/入口 12=功能卡
        // 96=分区（childSimpleInfos） 6/10/20=分类/MV/有声书。
        final type =
            HuaweiGateway.firstString(content, const ['contentType']) ?? '';
        switch (type) {
          case '1':
            addSongMap(content, label);
            break;
          case '2':
            albums.add(parseAlbum(content));
            break;
          case '4':
            playlists.add(_withKind(parsePlaylist(content), 'collected'));
            break;
          case '7':
            charts.add(_withKind(parsePlaylist(content), 'chart'));
            break;
          case '11':
            final banner = _bannerFrom(content);
            if (banner != null) banners.add(banner);
            break;
          case '96':
            final children = _findNamedList(content, 'childSimpleInfos');
            for (final child in children) {
              final childType =
                  HuaweiGateway.firstString(child, const ['contentType']) ?? '';
              if (childType == '2') {
                albums.add(parseAlbum(child));
              } else {
                addSongMap(child, '$label ${_contentLabel(child)}');
              }
            }
            break;
          case '12':
            // 功能卡本身不进入列表，但「现在就听/心动模式」卡内可能
            // 带 listRcmInfos/songSimpleInfos，仍属于该栏目真实曲库。
            for (final item in _findNamedList(content, 'listRcmInfos')) {
              final song = parseSong(item);
              radio.add(song);
              addSong(song, label);
            }
            for (final item in _findNamedList(content, 'songSimpleInfos')) {
              addSongMap(item, label);
            }
            break;
          case '998':
            final feature = _featureFrom(content);
            if (feature != null) features.add(feature);
            break;
          default:
            // 仅当明确带 listRcmInfos（电台推荐）时才取歌。
            final radioInfos = _findNamedList(content, 'listRcmInfos');
            if (radioInfos.isNotEmpty) {
              for (final item in radioInfos) {
                final song = parseSong(item);
                radio.add(song);
                addSong(song, label);
              }
            }
            // 兼容 1.2.0 的旧结构：content 直接带 songSimpleInfos。
            final nestedSongs = _findNamedList(content, 'songSimpleInfos');
            if (nestedSongs.isNotEmpty) {
              for (final item in nestedSongs) {
                addSongMap(item, label);
              }
            }
        }
      }
    }

    if (banners.isEmpty) banners.addAll(parseBanners(root));
    recommendedColumnId ??= _findRecommendedColumnId(columns);

    final allSongs = _dedupeSongs(genericSongs);
    final recSongs = _dedupeSongs(recommended);
    final listen = _dedupeSongs(listenSongs);
    final heart = _dedupeSongs(heartSongs);
    final hot = _dedupeSongs(hotSongs);
    final newOnly = _dedupeSongs(newSongs);
    final radioSongs = _dedupeSongs(radio);
    // 私享好歌必须是独立栏目；为空时交给 discover() 用 8011 拉栏目详情，
    // 不能拿电台/新歌冒充「为你推荐」。
    final recommendedFinal = recSongs.take(30).toList();
    final listenFinal = listen.isNotEmpty
        ? listen.take(30).toList()
        : recommendedFinal;
    final newFinal = newOnly.isNotEmpty ? newOnly : allSongs;

    final seenLists = <String>{};
    playlists.removeWhere((p) => p.id.isNotEmpty && !seenLists.add(p.id));
    charts.removeWhere((p) => p.id.isNotEmpty && !seenLists.add(p.id));
    albums.removeWhere((p) => p.id.isNotEmpty && !seenLists.add(p.id));

    return DiscoverData(
      banners: banners.take(8).toList(),
      newSongs: newFinal,
      playlists: playlists,
      charts: charts,
      radio: radioSongs,
      albums: albums,
      recommended: recommendedFinal,
      listen: listenFinal,
      heart: heart.isNotEmpty ? heart.take(30).toList() : radioSongs,
      hot: hot.take(10).toList(),
      recommendedColumnId: recommendedColumnId ?? '8011',
      features: features,
      daily: const <Song>[],
    );
  }

  static List<Song> _dedupeSongs(Iterable<Song> input) {
    final seen = <String>{};
    final out = <Song>[];
    for (final song in input) {
      if (song.name.isEmpty || song.name == '未知歌曲') continue;
      final key = song.id.isNotEmpty ? song.id : '${song.name}|${song.artistText}';
      if (!seen.add(key)) continue;
      out.add(song);
    }
    return out;
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

  static void _collectTextValues(
      Map<String, dynamic> map, List<String> out) {
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
    final title = HuaweiGateway.firstString(
          content,
          const ['contentName', 'keyName', 'name', 'title'],
        ) ??
        '';
    String? serviceType;
    String id = '';
    String realTitle = title;
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
      id = HuaweiGateway.firstString(
            map,
            const ['contentID', 'contentId', 'id'],
          ) ??
          '';
      realTitle = HuaweiGateway.firstString(
            map,
            const ['contentName', 'keyName', 'name', 'title'],
          ) ??
          realTitle;
      final extend = map['extendInfo'];
      if (extend is Map) {
        serviceType = HuaweiGateway.firstString(
          Map<String, dynamic>.from(extend),
          const ['serviceType'],
        );
      } else if (extend is String && extend.trim().startsWith('{')) {
        try {
          final decoded = jsonDecode(extend);
          if (decoded is Map) {
            serviceType = HuaweiGateway.firstString(
              Map<String, dynamic>.from(decoded),
              const ['serviceType'],
            );
          }
        } catch (_) {}
      }
    }
    if (id.isEmpty && title.isEmpty) return null;
    return DiscoverFeature(
      id: id,
      title: realTitle.isEmpty ? title : realTitle,
      serviceType: serviceType ?? '',
      cover: coverOf(content),
    );
  }

  static bool _isRecommendedLabel(String label) =>
      label.contains('recom_exclusive') ||
      label.contains('私享好歌') ||
      label.contains('为你推荐');

  static bool _isListenLabel(String label) =>
      label.contains('home-listen') ||
      label.contains('listen') ||
      label.contains('现在就听') ||
      label.contains('music fm');

  static bool _isHeartLabel(String label) =>
      label.contains('home-heart') ||
      label.contains('heart') ||
      label.contains('心动');

  static bool _isNewLabel(String label) =>
      label.contains('home-new') ||
      label.contains('new-songs') ||
      label.contains('newsong') ||
      label.contains('新歌');

  static bool _isHotLabel(String label) =>
      label.contains('home-hot') ||
      label.contains('hot-song') ||
      label.contains('热歌');

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
        if (value is String &&
            value.isNotEmpty &&
            value != 'recom_exclusive') {
          return value;
        }
        if (value is num) return value.toString();
      }
    }
    return null;
  }

  static String? _findRecommendedColumnId(
      List<Map<String, dynamic>> columns) {
    for (final column in columns) {
      if (!_isRecommendedLabel(_columnLabel(column))) continue;
      final id = _columnIdFrom(column);
      if (id != null) return id;
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

  /// Opt-in live probe helper: inspect a named list without reimplementing
  /// Huawei's nested envelope in test code.
  static List<Map<String, dynamic>> debugFindNamedList(
          dynamic root, String key) =>
      _findNamedList(root, key);

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
