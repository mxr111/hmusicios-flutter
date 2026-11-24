import 'dart:convert';
import 'dart:math';

import '../models.dart';
import 'qq_gateway.dart';

/// QQ 音乐业务层（端点来自 Muyu 2.0.4 二进制，字段按真实响应容错解析）。
class QqApi {
  QqApi({QqGateway? gateway}) : gateway = gateway ?? QqGateway();

  final QqGateway gateway;

  bool get isLoggedIn => gateway.isLoggedIn;

  String get displayName => gateway.displayName;

  void signInWithCookies(Map<String, dynamic> cookies) =>
      gateway.signInWithCookies(cookies);

  void signOut() => gateway.signOut();

  void dispose() => gateway.dispose();

  static const String searchEndpoint = QqEndpoints.search;
  static const String lyricEndpoint = QqEndpoints.lyric;
  static const String albumEndpoint = QqEndpoints.album;
  static const String commentEndpoint = QqEndpoints.comment;
  static const String musicuEndpoint = QqEndpoints.musicu;
  static const String signedMusicuEndpoint = QqEndpoints.musics;
  static const String audioCdn = QqEndpoints.audioCdn;
  static const String loginPage = QqEndpoints.loginPage;

  static const String searchModule = 'music.vkey.GetVkey';
  static const String vkeyMethod = 'UrlGetVkey';
  static const String playlistBaseModule = 'music.musicasset.PlaylistBaseRead';
  static const String playlistDetailModule = 'music.srfDissInfo.DissInfo';
  static const String homeSongsModule = 'music.radioProxy.MbTrackRadioSvr';
  static const String homePlaylistModule = 'music.playlist.PlaylistSquare';

  static final Random _random = Random.secure();

  /// 搜索单曲（c.y.qq.com `data.song.list`）。
  Future<List<Song>> search(
    String keyword, {
    int limit = 30,
    int page = 1,
  }) async {
    final text = keyword.trim();
    if (text.isEmpty) throw const QqException('搜索关键词不能为空');
    final json = await gateway.getJson(
      Uri.https(
        'c.y.qq.com',
        '/soso/fcgi-bin/search_for_qq_cp',
        <String, String>{
          'format': 'json',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
          'notice': '0',
          'platform': 'yqq.json',
          'needNewCode': '0',
          'g_tk': '5381',
          't': '0',
          'p': '$page',
          'n': '$limit',
          'w': text,
          'cr': '1',
        },
      ),
    );
    _checkTopCode(json);
    return parseSearch(json);
  }

  /// 当前账号歌单。
  Future<List<Playlist>> userPlaylists() async {
    _requireLoginInstance();
    final uin = gateway.session?.uin ?? '';
    if (uin.isEmpty) {
      throw const QqException('QQ 音乐 Cookie 缺少 uin，请重新复制完整 Cookie');
    }
    final json = await _rpc(<String, dynamic>{
      'module': playlistBaseModule,
      'method': 'GetPlaylistByUin',
      'param': <String, dynamic>{'uin': uin},
    }, preferSigned: true);
    return parsePlaylists(json);
  }

  /// 歌单歌曲。
  Future<List<Song>> playlistTracks(String id) async {
    final number = int.tryParse(id.trim());
    if (number == null) throw const QqException('QQ 歌单编号无效');
    final json = await _rpc(<String, dynamic>{
      'module': playlistDetailModule,
      'method': 'CgiGetDiss',
      'param': <String, dynamic>{
        'disstid': number,
        'dirid': 0,
        'tag': 1,
        'song_begin': 0,
        'song_num': 1000,
        'userinfo': 1,
        'orderlist': true,
      },
    });
    return parsePlaylistSongs(json);
  }

  /// 专辑歌曲（端点来自 Muyu 二进制）。
  Future<List<Song>> albumTracks(String albummid) async {
    final mid = albummid.trim();
    if (mid.isEmpty) throw const QqException('QQ 专辑编号不能为空');
    final json = await gateway.getJson(
      Uri.https(
        'c.y.qq.com',
        '/v8/fcg-bin/fcg_v8_album_info_cp.fcg',
        <String, String>{
          'albummid': mid,
          'format': 'json',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
          'notice': '0',
          'platform': 'yqq.json',
          'needNewCode': '0',
          'g_tk': '5381',
        },
      ),
    );
    _checkTopCode(json);
    return parsePlaylistSongs(json);
  }

  /// LRC 歌词（支持 base64、`trans`/`tran`/`tlyric` 翻译）。
  Future<List<LyricLine>> lyrics(String songmid) async {
    final mid = songmid.trim();
    if (mid.isEmpty) throw const QqException('QQ 歌曲编号不能为空');
    final json = await gateway.getJson(
      Uri.https(
        'c.y.qq.com',
        '/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
        <String, String>{
          'songmid': mid,
          'pcachetime': '${DateTime.now().millisecondsSinceEpoch}',
          'g_tk': '5381',
          'loginUin': gateway.session?.uin ?? '0',
          'hostUin': '0',
          'format': 'json',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
          'notice': '0',
          'platform': 'yqq',
          'needNewCode': '0',
        },
      ),
    );
    _checkTopCode(json);
    return parseLyrics(json);
  }

  /// 取流：music.vkey.GetVkey / UrlGetVkey。
  Future<List<HuaweiAudioFile>> audioFiles(
    Song song, {
    AudioQuality? quality,
  }) async {
    if (song.id.trim().isEmpty) throw const QqException('QQ 歌曲编号不能为空');
    final files = _vkeyFilenamesFor(song, quality);
    final module = buildVkeyModule(
      song.id,
      uin: gateway.session?.uin ?? '0',
      filenames: files,
    );
    final json = await _rpc(module);
    final results = _extractVkeyFiles(json, files);
    if (results.isEmpty) {
      throw const QqException('QQ 音乐未返回播放地址（可能无版权或需要会员）');
    }
    if (quality == null) return results;
    return results.where((file) => file.quality == quality).toList();
  }

  /// 歌曲评论。
  Future<List<Comment>> comments(String id, {int limit = 20}) async {
    final topid = id.trim();
    if (topid.isEmpty) throw const QqException('QQ 评论对象编号不能为空');
    final json = await gateway.getJson(
      Uri.https(
        'c.y.qq.com',
        '/base/fcgi-bin/fcg_global_comment_h5.fcg',
        <String, String>{
          'biztype': '1',
          'topid': topid,
          'cmd': '6',
          'pagenum': '0',
          'pagesize': '$limit',
          'loginUin': gateway.session?.uin ?? '0',
          'hostUin': '0',
          'format': 'json',
          'inCharset': 'utf8',
          'outCharset': 'utf-8',
          'notice': '0',
          'platform': 'yqq.json',
          'needNewCode': '0',
          'g_tk': '5381',
        },
      ),
    );
    _checkTopCode(json);
    return parseComments(json).take(limit).toList();
  }

  /// 首页推荐歌曲（Muyu `qq.Client.HomeSongs`）。
  Future<List<Song>> homeSongs() async {
    final json = await _rpc(<String, dynamic>{
      'module': homeSongsModule,
      'method': 'get_radio_track',
      'param': <String, dynamic>{
        'id': 99,
        'num': 20,
        'from': 0,
        'scene': 0,
        'song_ids': <dynamic>[],
      },
    }, preferSigned: isLoggedIn);
    final songs = parsePlaylistSongs(json);
    if (songs.isEmpty) throw const QqException('QQ 音乐首页未返回歌曲');
    return songs;
  }

  /// 首页推荐歌单。
  ///
  /// 模块名来自 QQ 公开 CGI 约定；Muyu 二进制只能确认该 CGI 主机，方法名
  /// 待更多真实响应验证（代码注释标记「待验证」），失败会抛 QqException。
  Future<List<Playlist>> homePlaylists() async {
    final json = await _rpc(<String, dynamic>{
      'module': homePlaylistModule,
      'method': 'GetRecommendFeed',
      'param': <String, dynamic>{'From': 0, 'Size': 20},
    });
    final playlists = parsePlaylists(json);
    if (playlists.isEmpty) throw const QqException('QQ 音乐首页未返回歌单');
    return playlists;
  }

  Future<Map<String, dynamic>> _rpc(
    Map<String, dynamic> module, {
    bool preferSigned = false,
  }) async {
    Object? firstError;
    final attempts = <bool>[preferSigned, !preferSigned];
    for (final signed in attempts) {
      if (signed && !isLoggedIn) continue;
      try {
        final json = await gateway.musicu(
          moduleKey: 'req_0',
          module: module,
          signed: signed,
        );
        final req = _asMap(json['req_0']);
        if (req == null) {
          firstError = const QqException('QQ 音乐模块响应缺少 req_0');
          continue;
        }
        final code = _firstInt(req, const <String>[
          'code',
          'retcode',
          'retCode',
        ]);
        if (code != null && code != 0 && code != 200) {
          firstError = QqException(_errorMessage(req), code: '$code');
          continue;
        }
        return json;
      } on QqException catch (error) {
        firstError = error;
      }
    }
    if (firstError is QqException) throw firstError;
    throw QqException(
      firstError == null ? 'QQ 音乐请求失败' : 'QQ 音乐请求失败：$firstError',
    );
  }

  void _requireLoginInstance() {
    if (!isLoggedIn) throw const QqException('请先登录 QQ 音乐');
  }

  static void _checkTopCode(Map<String, dynamic> json) {
    final code = _firstInt(json, const <String>[
      'code',
      'retcode',
      'retCode',
      'status',
    ]);
    if (code != null && code != 0 && code != 200) {
      throw QqException(_errorMessage(json), code: '$code');
    }
  }

  static String _errorMessage(Map<String, dynamic> json) {
    final message = _firstString(json, const <String>[
      'msg',
      'message',
      'errMsg',
      'subcode',
      'tips',
    ]);
    final code = _firstInt(json, const <String>[
      'code',
      'retcode',
      'retCode',
      'status',
    ]);
    if (message != null) return 'QQ 音乐请求失败：$message';
    return code == null ? 'QQ 音乐请求失败' : 'QQ 音乐请求失败（$code）';
  }

  /// 搜索响应解析。
  static List<Song> parseSearch(dynamic root) {
    final map = _asMap(root);
    final data = map == null ? null : _asMap(map['data']);
    final song = data == null ? null : _asMap(data['song']);
    final list = song?['list'];
    if (list is List) return _songsFromList(list);
    return parseSongs(root);
  }

  /// 歌单/首页歌曲响应解析，兼容 `songlist` / `tracks` / `songInfoList`。
  static List<Song> parsePlaylistSongs(dynamic root) {
    final map = _asMap(root);
    if (map != null) {
      for (final key in const <String>[
        'songlist',
        'tracks',
        'songInfoList',
        'songList',
      ]) {
        final value = map[key];
        if (value is List) {
          final songs = _songsFromList(value);
          if (songs.isNotEmpty) return songs;
        }
      }
      for (final reqKey in const <String>['req_0', 'req_1', 'data']) {
        final req = _asMap(map[reqKey]);
        if (req == null) continue;
        final data = _asMap(req['data']) ?? req;
        for (final key in const <String>[
          'songlist',
          'tracks',
          'songInfoList',
          'songList',
        ]) {
          final value = data[key];
          if (value is List) {
            final songs = _songsFromList(value);
            if (songs.isNotEmpty) return songs;
          }
        }
      }
    }
    return parseSongs(root);
  }

  /// 递归解析歌曲；专辑/歌手对象不会误判成歌曲。
  static List<Song> parseSongs(dynamic root) {
    final out = <Song>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (node is List) {
        for (final value in node) {
          walk(value);
        }
        return;
      }
      final map = _asMap(node);
      if (map == null) return;
      if (_looksLikeSong(map)) {
        final song = _song(map);
        if (song != null && seen.add(song.id)) out.add(song);
      }
      for (final value in map.values) {
        if (value is Map || value is List) walk(value);
      }
    }

    walk(root);
    return out;
  }

  static List<Song> _songsFromList(List<dynamic> list) {
    final out = <Song>[];
    final seen = <String>{};
    for (final item in list) {
      final map = _asMap(item);
      if (map == null) continue;
      final song = _song(map);
      if (song != null && seen.add(song.id)) out.add(song);
    }
    return out;
  }

  static bool _looksLikeSong(Map<String, dynamic> map) {
    final mid = _firstString(map, const <String>['songmid', 'songMid', 'mid']);
    if (mid == null || mid.isEmpty) return false;
    final name = _firstString(map, const <String>[
      'songname',
      'songName',
      'name',
      'title',
    ]);
    if (name == null || name.isEmpty) return false;
    return map.containsKey('singer') ||
        map.containsKey('singers') ||
        map.containsKey('Singers') ||
        map.containsKey('interval') ||
        map.containsKey('albumname') ||
        map.containsKey('albummid') ||
        map.containsKey('size128') ||
        map.containsKey('size320') ||
        map.containsKey('sizeflac') ||
        map.containsKey('file') ||
        map.containsKey('pay');
  }

  static Song? _song(Map<String, dynamic> map) {
    final id = _firstString(map, const <String>['songmid', 'songMid', 'mid']);
    if (id == null || id.isEmpty) return null;
    final name = _firstString(map, const <String>[
      'songname',
      'songName',
      'name',
      'title',
    ]);
    if (name == null || name.isEmpty) return null;

    final artists = <String>[];
    final artistIds = <String>[];
    final singers = map['singer'] ?? map['singers'] ?? map['Singers'];
    if (singers is List) {
      for (final item in singers) {
        final singer = _asMap(item);
        if (singer == null) continue;
        final artist = _firstString(singer, const <String>[
          'name',
          'title',
          'singerName',
          'artistName',
        ]);
        final artistId = _firstString(singer, const <String>[
          'mid',
          'id',
          'singerId',
        ]);
        if (artist != null && artist.isNotEmpty) artists.add(artist);
        if (artistId != null && artistId.isNotEmpty) artistIds.add(artistId);
      }
    }
    if (artists.isEmpty) {
      final text = _firstString(map, const <String>[
        'singerName',
        'artistName',
        'artist',
        'singername',
      ]);
      if (text != null) {
        artists.addAll(
          text
              .split(RegExp(r'[/,、&]'))
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
        );
      }
    }

    final albumMap = _asMap(map['album']);
    final album =
        _firstString(map, const <String>[
          'albumname',
          'albumName',
          'album_name',
        ]) ??
        (albumMap == null
            ? null
            : _firstString(albumMap, const <String>['name', 'title']));
    final albumMid =
        _firstString(map, const <String>[
          'albummid',
          'albumMid',
          'album_mid',
        ]) ??
        (albumMap == null
            ? null
            : _firstString(albumMap, const <String>['mid', 'id']));
    final explicitCover = _firstString(map, const <String>[
      'cover',
      'pic',
      'picUrl',
      'coverUrl',
      'img',
      'image',
    ]);
    final cover = explicitCover != null && explicitCover.isNotEmpty
        ? _uri(explicitCover)
        : (albumMid != null && albumMid.isNotEmpty
              ? _uri(QqGateway.imageUrlForAlbumMid(albumMid))
              : null);

    final ms = _firstInt(map, const <String>[
      'durationMs',
      'duration_ms',
      'songDuration',
    ]);
    final seconds = _firstNum(map, const <String>[
      'interval',
      'seconds',
      'timelen',
      'duration',
    ]);
    final durationMs =
        ms ??
        (seconds == null
            ? 0
            : seconds <= 36000
            ? (seconds * 1000).round()
            : seconds.round());

    final pay = _asMap(map['pay']);
    final payPlay =
        _firstInt(map, const <String>[
          'payplay',
          'pay_play',
          'pay_month',
          'fee',
        ]) ??
        (pay == null
            ? 0
            : _firstInt(pay, const <String>[
                    'payplay',
                    'pay_play',
                    'pay_month',
                  ]) ??
                  0);
    final hiResSize = _sizeValue(map, const <String>['size_hires']);

    return Song(
      id: id,
      name: name,
      album: album ?? '',
      artists: artists,
      artistIds: artistIds,
      cover: cover,
      durationMs: durationMs,
      qualities: _qualitiesFromSong(map),
      source: MusicSourceLabel.qq,
      member:
          payPlay > 0 ||
          hiResSize > 0 ||
          map['isVip'] == true ||
          map['vip'] == true,
    );
  }

  static Set<AudioQuality> _qualitiesFromSong(Map<String, dynamic> map) {
    final out = <AudioQuality>{};
    if (_sizeValue(map, const <String>['size128', 'size_128mp3']) > 0) {
      out.add(AudioQuality.standard);
    }
    if (_sizeValue(map, const <String>['size320', 'size_320mp3']) > 0) {
      out.add(AudioQuality.lossless);
    }
    if (_sizeValue(map, const <String>['sizeflac', 'size_flac']) > 0) {
      out.add(AudioQuality.lossless);
    }
    if (_sizeValue(map, const <String>['size_hires', 'sizehires']) > 0) {
      out.add(AudioQuality.hiRes);
    }
    return out.isEmpty ? <AudioQuality>{AudioQuality.standard} : out;
  }

  static int _sizeValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final direct = _toInt(map[key]);
      if (direct != null && direct > 0) return direct;
    }
    final file = _asMap(map['file']);
    if (file != null) {
      for (final key in keys) {
        final value = _toInt(file[key]);
        if (value != null && value > 0) return value;
      }
    }
    return 0;
  }

  /// 歌单/首页歌手列表解析。
  static List<Playlist> parsePlaylists(dynamic root) {
    final out = <Playlist>[];
    final seen = <String>{};

    void walk(dynamic node) {
      if (node is List) {
        for (final value in node) {
          walk(value);
        }
        return;
      }
      final map = _asMap(node);
      if (map == null) return;
      final playlist = _playlist(map);
      if (playlist != null && seen.add(playlist.id)) out.add(playlist);
      for (final value in map.values) {
        if (value is Map || value is List) walk(value);
      }
    }

    walk(root);
    return out;
  }

  static Playlist? _playlist(Map<String, dynamic> map) {
    if (map.containsKey('songmid') || _asMap(map['album']) != null) return null;
    final id = _firstString(map, const <String>[
      'tid',
      'dirId',
      'dirid',
      'dissid',
      'dissId',
      'listid',
      'id',
      'global_collection_id',
      'content_id',
    ]);
    if (id == null || id.isEmpty || id == '0' || id == 'null') return null;
    final name = _firstString(map, const <String>[
      'dirName',
      'dissname',
      'name',
      'title',
    ]);
    if (name == null || name.isEmpty) return null;
    final hasPlaylistSignal =
        map.containsKey('dirName') ||
        map.containsKey('dirId') ||
        map.containsKey('songNum') ||
        map.containsKey('songnum') ||
        map.containsKey('trackCount') ||
        map.containsKey('coverImgUrl') ||
        map.containsKey('picUrl') ||
        map.containsKey('global_collection_id');
    if (!hasPlaylistSignal) return null;

    final cover = _firstString(map, const <String>[
      'cover',
      'pic',
      'picUrl',
      'bigpicUrl',
      'coverImgUrl',
      'coverUrl',
      'imgurl',
    ]);
    final count =
        _firstInt(map, const <String>[
          'songNum',
          'songnum',
          'trackCount',
          'count',
          'total',
        ]) ??
        0;
    final kind = map.containsKey('dirId') || map.containsKey('dirName')
        ? 'owned'
        : 'collected';
    return Playlist(
      id: id,
      name: name,
      cover: cover == null ? null : _uri(cover),
      songCount: count,
      kind: kind,
    );
  }

  /// 评论解析，兼容 `comment.commentlist` 与 `hot_comment.commentlist`。
  static List<Comment> parseComments(dynamic root) {
    final out = <Comment>[];
    final seen = <String>{};

    void addGroup(dynamic group) {
      final map = _asMap(group);
      final list = group is List
          ? group
          : (map == null
                ? null
                : (map['commentlist'] ?? map['comments'] ?? map['list']));
      if (list is! List) return;
      for (var index = 0; index < list.length; index++) {
        final item = _asMap(list[index]);
        if (item == null) continue;
        final comment = _comment(item, index);
        if (comment != null && seen.add(comment.id)) out.add(comment);
      }
    }

    final map = _asMap(root);
    if (map != null) {
      addGroup(map['hot_comment']);
      addGroup(map['hotComment']);
      addGroup(map['comment']);
      addGroup(map['comments']);
      for (final value in map.values) {
        if (value is Map &&
            (value['commentlist'] != null || value['comments'] != null)) {
          addGroup(value);
        }
      }
    }
    return out;
  }

  static Comment? _comment(Map<String, dynamic> map, int index) {
    final user =
        _asMap(map['user']) ??
        _asMap(map['userinfo']) ??
        _asMap(map['userInfo']);
    final content = _firstString(map, const <String>[
      'rootcommentcontent',
      'content',
      'text',
      'comment',
    ]);
    if (content == null || content.trim().isEmpty) return null;
    final id =
        _firstString(map, const <String>[
          'commentid',
          'commentId',
          'cmtid',
          'id',
        ]) ??
        'qq-$index';
    final author =
        (user == null
            ? null
            : _firstString(user, const <String>['nick', 'nickname', 'name'])) ??
        _firstString(map, const <String>['nick', 'nickname', 'uin']) ??
        '匿名用户';
    final avatar =
        (user == null
            ? null
            : _firstString(user, const <String>[
                'avatarurl',
                'avatar',
                'headimg',
                'icon',
              ])) ??
        _firstString(map, const <String>[
          'avatarurl',
          'avatar',
          'headimg',
          'avatarUrl',
        ]);
    final time =
        _firstString(map, const <String>[
          'time',
          'addtime',
          'createTime',
          'commenttime',
        ]) ??
        '';
    final likes =
        _firstInt(map, const <String>[
          'praisenum',
          'praise_num',
          'likedCount',
          'likes',
        ]) ??
        0;
    return Comment(
      id: id,
      author: author,
      content: content,
      avatar: avatar == null ? null : _uri(avatar),
      time: time,
      likes: likes,
    );
  }

  /// 歌词解析，兼容 `lyric` / `lrc.lyric` / `trans` / `tran` / `tlyric`。
  static List<LyricLine> parseLyrics(Map<String, dynamic> json) {
    var lyric = _firstString(json, const <String>['lyric', 'lrc']);
    var translation = _firstString(json, const <String>[
      'trans',
      'tran',
      'translation',
      'tlyric',
    ]);
    final lrc = _asMap(json['lrc']);
    final tlyric = _asMap(json['tlyric']);
    if (lrc != null && lrc['lyric'] is String) lyric = lrc['lyric'] as String;
    if (tlyric != null && tlyric['lyric'] is String) {
      translation = tlyric['lyric'] as String;
    }
    final original = decodeQqText(lyric ?? '');
    final translated = decodeQqText(translation ?? '');
    if (original.trim().isEmpty) return <LyricLine>[];
    return parseLrcWithTranslation(original, translated);
  }

  /// QQ 歌词可能是普通文本或 base64，按内容安全解码。
  static String decodeQqText(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.contains('[')) return raw;
    if (!RegExp(r'^[A-Za-z0-9+/_=\s-]+$').hasMatch(text)) return raw;
    try {
      final normalized = text
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      final padding = (4 - normalized.length % 4) % 4;
      final bytes = base64.decode(normalized + '=' * padding);
      final decoded = utf8.decode(bytes, allowMalformed: true);
      return decoded.trim().isEmpty ? raw : decoded;
    } catch (_) {
      return raw;
    }
  }

  static List<LyricLine> parseLrc(String text) =>
      parseLrcWithTranslation(text, '');

  static List<LyricLine> parseLrcWithTranslation(
    String text,
    String translation,
  ) {
    final translations = <int, String>{};
    for (final line in _parseRawLrc(translation)) {
      translations[line.time.inMilliseconds] = line.text;
    }
    final points = _parseRawLrc(text);
    return points
        .map(
          (line) => LyricLine(
            line.time,
            line.text,
            translation: _translationAt(translations, line.time.inMilliseconds),
          ),
        )
        .toList();
  }

  static List<LyricLine> _parseRawLrc(String text) {
    final lines = <LyricLine>[];
    final tagRegex = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
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
          line.startsWith('[kana:')) {
        continue;
      }
      final tags = tagRegex.allMatches(line).toList();
      if (tags.isEmpty) continue;
      final content = line.substring(tags.last.end).trim();
      if (content.isEmpty) continue;
      for (final match in tags) {
        final minute = int.tryParse(match.group(1) ?? '0') ?? 0;
        final second = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fraction = match.group(3) ?? '0';
        final millisecond =
            int.tryParse(fraction.padRight(3, '0').substring(0, 3)) ?? 0;
        lines.add(
          LyricLine(
            Duration(
              minutes: minute,
              seconds: second,
              milliseconds: millisecond,
            ),
            content,
          ),
        );
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  static String _translationAt(
    Map<int, String> translations,
    int milliseconds,
  ) {
    if (translations.isEmpty) return '';
    final exact = translations[milliseconds];
    if (exact != null) return exact;
    var best = '';
    var distance = 151;
    for (final entry in translations.entries) {
      final diff = (entry.key - milliseconds).abs();
      if (diff < distance) {
        distance = diff;
        best = entry.value;
      }
    }
    return distance <= 150 ? best : '';
  }

  /// 公开的四档文件名（m4a 128/320、FLAC、Hi-Res）。
  static List<String> vkeyFilenames(String songmid, {AudioQuality? quality}) {
    final tiers = switch (quality) {
      AudioQuality.standard => <_QqTier>[_QqTier.aac128],
      AudioQuality.lossless => <_QqTier>[_QqTier.aac320, _QqTier.flac],
      AudioQuality.hiRes => <_QqTier>[_QqTier.hiRes],
      null => <_QqTier>[
        _QqTier.aac128,
        _QqTier.aac320,
        _QqTier.flac,
        _QqTier.hiRes,
      ],
    };
    return tiers.map((tier) => tier.filename(songmid)).toList();
  }

  static List<String> _vkeyFilenamesFor(Song song, AudioQuality? quality) {
    final tiers = <_QqTier>[_QqTier.aac128, _QqTier.mp3128];
    final allowed = quality == null ? song.qualities : <AudioQuality>{quality};
    if (allowed.contains(AudioQuality.lossless)) {
      tiers.addAll(<_QqTier>[_QqTier.aac320, _QqTier.mp3320, _QqTier.flac]);
    }
    if (allowed.contains(AudioQuality.hiRes)) tiers.add(_QqTier.hiRes);
    return tiers.map((tier) => tier.filename(song.id)).toSet().toList();
  }

  /// music.vkey.GetVkey / UrlGetVkey 模块请求。
  static Map<String, dynamic> buildVkeyModule(
    String songmid, {
    String uin = '0',
    String? guid,
    List<String>? filenames,
  }) {
    final resolved = filenames ?? vkeyFilenames(songmid);
    final requestGuid = guid ?? _guid();
    return <String, dynamic>{
      'module': searchModule,
      'method': vkeyMethod,
      'param': <String, dynamic>{
        'uin': uin.isEmpty ? '0' : uin,
        'filename': resolved,
        'guid': requestGuid,
        'songmid': List<String>.filled(resolved.length, songmid),
        'songtype': List<int>.filled(resolved.length, 0),
        'ctx': 0,
      },
    };
  }

  /// 按 Muyu 规则取 `sip[0] + purl`。
  static String resolveVkeyUrl(List<String> sip, String purl) {
    if (purl.startsWith('http://') || purl.startsWith('https://')) return purl;
    final base = sip.isEmpty || sip.first.isEmpty ? audioCdn : sip.first;
    final path = purl.startsWith('/') ? purl.substring(1) : purl;
    return base.endsWith('/') ? '$base$path' : '$base/$path';
  }

  static List<HuaweiAudioFile> _extractVkeyFiles(
    Map<String, dynamic> json,
    List<String> requestedFiles,
  ) {
    final vkey = _findVkeyData(json);
    if (vkey == null) return <HuaweiAudioFile>[];
    final sip = (vkey['sip'] is List)
        ? (vkey['sip'] as List)
              .map((value) => '$value')
              .where((value) => value.isNotEmpty)
              .toList()
        : <String>[];
    final infos =
        vkey['midurlinfo'] ?? vkey['midUrlInfo'] ?? vkey['midurlinfoList'];
    if (infos is! List) return <HuaweiAudioFile>[];

    final out = <HuaweiAudioFile>[];
    final seen = <String>{};
    for (var index = 0; index < infos.length; index++) {
      final info = _asMap(infos[index]);
      if (info == null) continue;
      final purl = _firstString(info, const <String>['purl', 'url', 'playUrl']);
      if (purl == null || purl.isEmpty) continue;
      final url = resolveVkeyUrl(sip, purl);
      if (!seen.add(url)) continue;
      final filename =
          _firstString(info, const <String>['filename', 'fileName', 'file']) ??
          (index < requestedFiles.length ? requestedFiles[index] : '');
      final quality = _qualityForFilename(filename.isEmpty ? purl : filename);
      final size =
          _firstInt(info, const <String>[
            'filesize',
            'fileSize',
            'file_size',
            'size',
          ]) ??
          0;
      out.add(
        HuaweiAudioFile(quality: quality, url: Uri.parse(url), sizeBytes: size),
      );
    }
    return out;
  }

  static Map<String, dynamic>? _findVkeyData(dynamic node) {
    final map = _asMap(node);
    if (map != null) {
      if (map.containsKey('midurlinfo') && map.containsKey('sip')) return map;
      for (final value in map.values) {
        final found = _findVkeyData(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findVkeyData(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  static AudioQuality _qualityForFilename(String filename) {
    if (filename.startsWith('RS01') || filename.contains('hires')) {
      return AudioQuality.hiRes;
    }
    if (filename.startsWith('F000') ||
        filename.startsWith('C600') ||
        filename.startsWith('M800') ||
        filename.contains('.flac')) {
      return AudioQuality.lossless;
    }
    return AudioQuality.standard;
  }

  static String _guid() => (1000000000 + _random.nextInt(900000000)).toString();

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) return value;
      if (value is num) return '$value';
    }
    return null;
  }

  static int? _firstInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = _toInt(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  static num? _firstNum(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) return value;
      if (value is String) {
        final parsed = num.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Uri? _uri(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('//')) value = 'https:$value';
    return Uri.tryParse(value);
  }
}

enum _QqTier {
  aac128('C400', '.m4a'),
  aac320('C600', '.m4a'),
  flac('F000', '.flac'),
  hiRes('RS01', '.flac'),
  mp3128('M500', '.mp3'),
  mp3320('M800', '.mp3');

  const _QqTier(this.prefix, this.extension);

  final String prefix;
  final String extension;

  String filename(String songmid) => '$prefix$songmid$songmid$extension';
}
