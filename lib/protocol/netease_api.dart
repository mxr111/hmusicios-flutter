import '../models.dart';
import '../models_home.dart';
import 'huawei_api.dart';
import 'netease_gateway.dart';

/// 网易云音乐业务层（REA 对 Muyu.exe internal/providers/netease 反编译复刻）。
/// 端点全部来自二进制实测（见 NETEASE_AND_QUALITY_DECOMPILED.md）：
/// /weapi/login/qrcode/unikey + /weapi/login/qrcode/client/loginQQ、
/// /weapi/search/get、/weapi/v6/playlist/detail、/weapi/user/playlist、
/// /weapi/song/enhance/player/url/v1、/weapi/song/lyric 等。
class NeteaseApi {
  NeteaseApi({NeteaseGateway? gateway})
      : gateway = gateway ?? NeteaseGateway();

  final NeteaseGateway gateway;
  bool get isLoggedIn => gateway.isLoggedIn;

  void signInWithCookies(String musicU,
      {String csrf = '', String nickname = '', String userId = ''}) {
    gateway.signIn(NeteaseSession(
      musicU: musicU.trim(),
      csrf: csrf.trim(),
      nickname: nickname,
      userId: userId,
    ));
  }

  void signOut() => gateway.signOut();

  /// 网易云独立首页：并行拉取真实推荐数据，单个板块失败不影响其他板块。
  /// 这些接口均来自 EXE / 官方 weapi 实测，未登录也能拿到公开推荐；
  /// 登录后 /weapi/v3/discovery/recommend/songs 会返回个性化日推。
  Future<NeteaseHomeData> homeFeed({
    int playlistOffset = 0,
    int playlistLimit = 18,
  }) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      _soft<dynamic>(_homeBanners(), <NeteaseHomeBanner>[]),
      _soft<dynamic>(homePlaylists(offset: playlistOffset, limit: playlistLimit), <Playlist>[]),
      _soft<dynamic>(dailySongs(), <Song>[]),
      _soft<dynamic>(newSongs(), <Song>[]),
      _soft<dynamic>(privateFm(), <Song>[]),
      _soft<dynamic>(privateContents(), <NeteaseHomeSpecial>[]),
    ]);
    final data = NeteaseHomeData(
      banners: results[0] as List<NeteaseHomeBanner>,
      playlists: results[1] as List<Playlist>,
      dailySongs: results[2] as List<Song>,
      newSongs: results[3] as List<Song>,
      radioSongs: results[4] as List<Song>,
      specials: results[5] as List<NeteaseHomeSpecial>,
    );
    if (data.isEmpty) {
      throw const NeteaseException('网易云推荐流未返回任何数据，请检查网络后重试');
    }
    return data;
  }

  /// 首页歌单流：/weapi/playlist/list，支持 offset 翻页（换一批）。
  Future<List<Playlist>> homePlaylists({int offset = 0, int limit = 18}) async {
    final json = await gateway.post('/weapi/playlist/list', <String, dynamic>{
      'cat': '全部',
      'order': 'hot',
      'limit': limit,
      'offset': offset,
      'total': true,
    });
    final raw = json['playlists'];
    if (raw is! List) return <Playlist>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(parsePlaylist)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  /// 首页轮播：/weapi/v2/banner/get（clientType=pc 才有数据）。
  Future<List<NeteaseHomeBanner>> _homeBanners() async {
    final json = await gateway.post('/weapi/v2/banner/get', <String, dynamic>{
      'clientType': 'pc',
    });
    return parseBanners(json);
  }

  /// 推荐新歌：/weapi/personalized/newsong。
  Future<List<Song>> newSongs({int limit = 30}) async {
    final json = await gateway.post('/weapi/personalized/newsong', <String, dynamic>{
      'type': 'recommend',
      'limit': limit,
    });
    // 服务端可能忽略 limit；客户端再截断，避免推荐流一次塞入过多卡片。
    return _deepSongs(json['result'] ?? json).take(limit).toList();
  }

  /// 私人 FM：/weapi/v1/radio/get。
  Future<List<Song>> privateFm() async {
    final json = await gateway.post('/weapi/v1/radio/get', <String, dynamic>{});
    return _deepSongs(json['data'] ?? json);
  }

  /// 独家放送：/weapi/personalized/privatecontent。
  Future<List<NeteaseHomeSpecial>> privateContents() async {
    final json = await gateway.post('/weapi/personalized/privatecontent',
        <String, dynamic>{});
    return parseSpecials(json['result'] ?? json);
  }

  /// 解析轮播；独立成静态方法便于离线测试与容错解析。
  static List<NeteaseHomeBanner> parseBanners(Map<String, dynamic> json) {
    final raw = json['banners'];
    if (raw is! List) return <NeteaseHomeBanner>[];
    final out = <NeteaseHomeBanner>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final title = _firstString(item, const ['title', 'typeTitle', 'name']) ?? '';
      final subtitle =
          _firstString(item, const ['subtitle', 'copywriter', 'description']) ?? '';
      final image = _firstString(item, const [
            'imageUrl',
            'pic',
            'sPicUrl',
            'sPic',
            'coverImgUrl',
          ]) ??
          '';
      if (title.isEmpty && image.isEmpty) continue;
      out.add(NeteaseHomeBanner(
        title: title.isEmpty ? '网易云推荐' : title,
        subtitle: subtitle,
        imageUrl: _uri(image),
        targetId: _firstString(item, const ['targetId', 'id']) ?? '',
      ));
    }
    return out;
  }

  /// 解析歌单卡片（/weapi/playlist/list 与推荐歌单共用）。
  static Playlist parsePlaylist(Map<String, dynamic> p) {
    return Playlist(
      id: '${p['id'] ?? ''}',
      name: '${p['name'] ?? '歌单'}',
      cover: _uri(_firstString(p, const ['coverImgUrl', 'picUrl', 'cover']) ?? ''),
      songCount: (p['trackCount'] is num)
          ? (p['trackCount'] as num).toInt()
          : 0,
      kind: 'collected',
    );
  }

  /// 解析独家放送卡。
  static List<NeteaseHomeSpecial> parseSpecials(dynamic raw) {
    if (raw is! List) return <NeteaseHomeSpecial>[];
    final out = <NeteaseHomeSpecial>[];
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final title = _firstString(item, const ['name', 'title']) ?? '';
      if (title.isEmpty) continue;
      out.add(NeteaseHomeSpecial(
        id: _firstString(item, const ['id']) ?? '',
        title: title,
        subtitle: _firstString(item, const ['copywriter', 'subtitle']) ?? '',
        cover: _uri(_firstString(item, const ['picUrl', 'sPicUrl', 'cover']) ?? ''),
      ));
    }
    return out;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && '$value'.isNotEmpty) return '$value';
    }
    return null;
  }

  Future<T> _soft<T>(Future<T> work, T fallback) async {
    try {
      return await work;
    } catch (_) {
      return fallback;
    }
  }

  /// ① 申请二维码登录 key：/weapi/login/qrcode/unikey。
  /// 返回 unikey，UI 用 `https://music.163.com/login?codekey=<unikey>` 展示二维码。
  Future<String> newQrKey() async {
    final json = await gateway.post('/weapi/login/qrcode/unikey',
        <String, dynamic>{'type': 1}, withCookies: false);
    final key = json['unikey'] ?? json['data']?['unikey'];
    if (key is! String || key.isEmpty) {
      throw const NeteaseException('网易云未返回有效二维码');
    }
    return key;
  }

  /// ② 轮询二维码状态：/weapi/login/qrcode/client/loginQQ。
  /// status: 801 等待扫码 / 802 待确认 / 800 已过期 / 803 授权成功（含 cookies）。
  Future<({int status, NeteaseSession? session})> checkQr(String unikey) async {
    final json = await gateway.post(
        '/weapi/login/qrcode/client/loginQQ',
        <String, dynamic>{'key': unikey, 'type': 1},
        withCookies: false);
    final status = json['status'] is int ? json['status'] as int : -1;
    if (status != 803) return (status: status, session: null);
    final cookies = json['cookies'];
    String musicU = '';
    String csrf = '';
    if (cookies is List) {
      for (final c in cookies) {
        if (c is! Map) continue;
        final name = '${c['name'] ?? ''}';
        final value = '${c['value'] ?? ''}';
        if (name == 'MUSIC_U') musicU = value;
        if (name == '__csrf' || name == 'csrf_token') csrf = value;
      }
    }
    if (musicU.isEmpty) musicU = '${json['MUSIC_U'] ?? ''}';
    if (musicU.isEmpty) {
      throw const NeteaseException('网易云二维码已授权但未返回 MUSIC_U');
    }
    final s = NeteaseSession(musicU: musicU, csrf: csrf);
    gateway.signIn(s);
    return (status: status, session: s);
  }

  /// 搜索：/weapi/search/get（type 1=单曲，10=歌手，100=专辑，1000=歌单）。
  Future<List<Song>> search(String keyword, {int type = 1, int limit = 30}) async {
    final json = await gateway.post('/weapi/search/get', <String, dynamic>{
      's': keyword,
      'type': type,
      'limit': limit,
      'offset': 0,
    });
    final songs = _deepSongs(json['result'] ?? json);
    return songs;
  }

  /// 歌单详情：/weapi/v6/playlist/detail。
  Future<List<Song>> playlistTracks(String playlistId) async {
    final json = await gateway.post('/weapi/v6/playlist/detail', <String, dynamic>{
      'id': playlistId,
      'n': 1000,
    });
    final playlist = json['playlist'] ?? json['result'] ?? json;
    final tracks = playlist is Map ? (playlist['tracks'] ?? playlist['songs']) : null;
    return _deepSongs(tracks);
  }

  /// 用户歌单：/weapi/user/playlist。
  Future<List<Playlist>> userPlaylists(String userId) async {
    final json = await gateway.post('/weapi/user/playlist', <String, dynamic>{
      'uid': userId,
      'limit': 100,
      'offset': 0,
    });
    final raw = json['playlist'];
    if (raw is! List) return <Playlist>[];
    return raw.whereType<Map<String, dynamic>>().map((p) {
      return Playlist(
        id: '${p['id'] ?? ''}',
        name: '${p['name'] ?? '歌单'}',
        cover: _uri(p['coverImgUrl'] ?? p['picUrl']),
        songCount: (p['trackCount'] is num) ? (p['trackCount'] as num).toInt() : 0,
        kind: 'collected',
      );
    }).where((p) => p.id.isNotEmpty && p.id != 'null').toList();
  }

  /// 每日推荐：/weapi/v3/discovery/recommend/songs。
  Future<List<Song>> dailySongs() async {
    final json = await gateway.post(
        '/weapi/v3/discovery/recommend/songs', <String, dynamic>{});
    return _deepSongs(json['data'] ?? json);
  }

  /// 推荐歌单：优先走官方首页歌单流（实测可用），旧端点失败时兜底。
  Future<List<Playlist>> recommendedPlaylists() async {
    try {
      final lists = await homePlaylists(limit: 30);
      if (lists.isNotEmpty) return lists;
    } catch (_) {
      // 旧端点在部分账号下返回 301，继续尝试解析历史响应。
    }
    final json = await gateway.post(
        '/weapi/v1/discovery/recommend/resource', <String, dynamic>{});
    final raw = json['recommend'];
    if (raw is! List) return <Playlist>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(parsePlaylist)
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  /// 取流：/weapi/song/enhance/player/url/v1。
  /// level 由上游档位决定（standard/exhigh/lossless/hires 等），
  /// 响应 br/level/type 决定实际档位（与 EXE locateQuality 一致）。
  Future<List<HuaweiAudioFile>> audioFiles(Song song,
      {AudioQuality? quality}) async {
    // 不超过上游声明的最高档（与华为侧 audioFiles 同策略）。
    var target = quality ?? AudioQuality.lossless;
    if (song.qualities.isNotEmpty &&
        !song.qualities.contains(target)) {
      target = song.qualities.reduce(
          (a, b) => a.index > b.index ? a : b);
    }
    final level = _levelFor(target);
    final json = await gateway.post(
        '/weapi/song/enhance/player/url/v1', <String, dynamic>{
      'ids': '[${song.id}]',
      'level': level,
      'encodeType': 'aac',
    });
    final data = json['data'];
    if (data is! List || data.isEmpty) {
      throw const NeteaseException('网易云未返回播放地址（请确认已登录 / 会员）');
    }
    final out = <HuaweiAudioFile>[];
    for (final item in data) {
      if (item is! Map) continue;
      final url = item['url'];
      if (url is! String || url.isEmpty) continue;
      final br = (item['br'] is num) ? (item['br'] as num).toInt() : 0;
      final type = '${item['type'] ?? ''}'.toLowerCase();
      final actual = br >= 900000 || type.contains('flac')
          ? AudioQuality.hiRes
          : AudioQuality.fromBitrate(br);
      out.add(HuaweiAudioFile(
        quality: actual,
        url: Uri.parse(url),
        sizeBytes: (item['size'] is num) ? (item['size'] as num).toInt() : 0,
      ));
    }
    if (out.isEmpty) {
      throw const NeteaseException('网易云该歌曲无可用音质档位');
    }
    return out;
  }

  /// 歌词：/weapi/song/lyric（lv=行级 LRC，tv=译文，kv=逐字卡拉OK）。
  Future<List<LyricLine>> lyrics(String songId) async {
    final json = await gateway.post('/weapi/song/lyric', <String, dynamic>{
      'id': songId,
      'lv': 1,
      'tv': 1,
      'kv': 1,
    });
    final lrc = json['lrc']?['lyric'] ?? '';
    final klyric = json['klyric']?['lyric'] ?? '';
    var lines = klyric is String && klyric.isNotEmpty
        ? HuaweiAPI.parseHmrc(klyric)
        : <LyricLine>[];
    final plain = lrc is String && lrc.isNotEmpty ? HuaweiAPI.parseLrc(lrc) : <LyricLine>[];
    if (lines.isEmpty) {
      lines = plain;
    } else if (plain.isNotEmpty) {
      lines = HuaweiAPI.mergeTranslations(lines, plain);
    }
    return lines;
  }

  /// 评论：/weapi/v1/resource/comments/R_SO_4_ 加歌曲 ID。
  Future<List<Comment>> comments(String songId, {int limit = 20}) async {
    final json = await gateway.post(
        '/weapi/v1/resource/comments/R_SO_4_$songId', <String, dynamic>{
      'limit': limit,
      'offset': 0,
    });
    final raw = json['comments'];
    if (raw is! List) return <Comment>[];
    return raw.whereType<Map<String, dynamic>>().map((c) => Comment(
          id: '${c['commentId'] ?? ''}',
          author: '${(c['user'] as Map?)?['nickname'] ?? '匿名用户'}',
          content: '${c['content'] ?? ''}',
          avatar: _uri((c['user'] as Map?)?['avatarUrl']),
          time: '',
          likes: (c['likedCount'] is num) ? (c['likedCount'] as num).toInt() : 0,
        )).where((c) => c.content.isNotEmpty).toList();
  }

  /// 收藏：/weapi/song/like/get（状态）+ /weapi/radio/like（心动）。
  Future<bool> isFavorite(String songId) async {
    try {
      final json = await gateway.post('/weapi/song/like/get',
          <String, dynamic>{'ids': '[$songId]'});
      final ids = json['ids'];
      if (ids is List) return ids.contains(int.tryParse(songId));
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 测试入口：递归收集单曲（兼容 songs / tracks 等不同包装）。
  static List<Song> parseSongs(dynamic root) => _deepSongs(root);

  /// 内部：递归收集单曲，不把 album / artist 对象误判成歌曲。
  static List<Song> _deepSongs(dynamic root) {
    final out = <Song>[];
    void walk(dynamic node) {
      if (node is List) {
        for (final v in node) {
          walk(v);
        }
      } else if (node is Map<String, dynamic>) {
        // 仅凭 id + name 会把 album / artist 对象误判成歌曲（实测会多出上百首）。
        // 真正的歌曲对象一定带歌手、专辑、时长或特权字段之一。
        final hasSongKey = node.containsKey('id') &&
            (node.containsKey('artists') ||
                node.containsKey('ar') ||
                node.containsKey('album') ||
                node.containsKey('al') ||
                node.containsKey('dt') ||
                node.containsKey('duration') ||
                node.containsKey('privilege') ||
                node.containsKey('fee'));
        final nested = node['song'];
        final hasNestedSong = nested is Map &&
            nested['id'] != null &&
            (nested['name'] != null || nested['artists'] != null || nested['ar'] != null);
        // personalized/newsong 的外层卡片带 id/name，但同时包着完整 song；
        // 只解析内层，避免同一首歌出现两次。
        if (hasSongKey && !hasNestedSong) out.add(_song(node));
        for (final v in node.values) {
          if (v is Map || v is List) walk(v);
        }
      }
    }

    walk(root);
    final seen = <String>{};
    return out.where((s) => s.id.isNotEmpty && seen.add(s.id)).toList();
  }

  /// 网易云歌曲 → 统一 Song。音质由上游 privilege 决定（HuaweiAPI.qualitiesFromUpstream）。
  static Song _song(Map<String, dynamic> d) {
    final artists = <String>[];
    final ids = <String>[];
    final ar = d['artists'] ?? d['ar'];
    if (ar is List) {
      for (final a in ar) {
        if (a is Map<String, dynamic>) {
          final n = a['name'];
          if (n != null) artists.add('$n');
          if (a['id'] != null) ids.add('${a['id']}');
        }
      }
    }
    final album = d['album'] ?? d['al'];
    final cover = album is Map<String, dynamic>
        ? _uri(album['picUrl'] ?? album['blurPicUrl'])
        : null;
    final privilege = d['privilege'];
    final merged = <String, dynamic>{...d};
    if (privilege is Map<String, dynamic>) {
      for (final k in const ['level', 'maxbr', 'br', 'chargeInfoList']) {
        if (merged[k] == null && privilege[k] != null) merged[k] = privilege[k];
      }
    }
    final duration = d['duration'] ?? d['dt'];
    return Song(
      id: '${d['id'] ?? ''}',
      name: '${d['name'] ?? '未知歌曲'}',
      album: album is Map<String, dynamic> ? '${album['name'] ?? ''}' : '',
      artists: artists,
      artistIds: ids,
      cover: cover,
      durationMs: duration is num ? duration.toInt() : 0,
      qualities: HuaweiAPI.qualitiesFromUpstream(merged),
      source: MusicSourceLabel.netease,
      member: (d['fee'] is num && (d['fee'] as num) > 0),
    );
  }

  String _levelFor(AudioQuality q) => switch (q) {
        AudioQuality.hiRes => 'hires',
        AudioQuality.lossless => 'lossless',
        AudioQuality.standard => 'standard',
      };

  static Uri? _uri(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }
}
