import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'kugou_gateway.dart';

export 'kugou_gateway.dart'
    show
        KugouException,
        KugouGateway,
        KugouSession,
        kugouAndroidSalt,
        kugouPlaybackKey,
        kugouSearchSignature,
        kugouSignature;

/// 搜索结果中的酷狗私有字段。`Song.id` 固定为 hash，
/// album_audio_id / 专辑 ID / 各档位 hash 只保存在这里。
class KugouTrackExtra {
  const KugouTrackExtra({
    required this.hash,
    this.albumAudioId = '',
    this.albumId = '',
    this.qualityHashes = const <AudioQuality, String>{},
    this.qualityFormats = const <AudioQuality, String>{},
  });

  final String hash;
  final String albumAudioId;
  final String albumId;
  final Map<AudioQuality, String> qualityHashes;
  final Map<AudioQuality, String> qualityFormats;

  String hashFor(AudioQuality quality) => qualityHashes[quality] ?? '';

  String formatFor(AudioQuality quality) =>
      qualityFormats[quality] ??
      switch (quality) {
        AudioQuality.hiRes => 'high',
        AudioQuality.lossless => 'flac',
        AudioQuality.standard => '128',
      };
}

class _ParsedSong {
  const _ParsedSong(this.song, this.extra);
  final Song song;
  final KugouTrackExtra extra;
}

/// 酷狗音乐业务层。端点取自 Muyu 2.0.4 字符串表：
/// complexsearch/v2/search/song、gateway/v5/url、v7/get_all_list、
/// pubsongs/v2/get_other_list_file_nofilt、v2/get_res_privilege/lite、
/// mcomment/v1/cmtlist、v3/get_my_info、krcs.kugou.com 等。
class KugouApi {
  KugouApi({KugouGateway? gateway}) : gateway = gateway ?? KugouGateway();

  final KugouGateway gateway;
  final Map<String, KugouTrackExtra> _extras = <String, KugouTrackExtra>{};

  bool get isLoggedIn => gateway.isLoggedIn;

  String get displayName {
    final nickname = gateway.session?.nickname ?? '';
    return nickname.isEmpty ? '酷狗音乐账号' : nickname;
  }

  void signInWithCookies(Map<String, dynamic> cookies) {
    gateway.signInWithCookies(cookies);
    _extras.clear();
  }

  void signOut() {
    gateway.signOut();
    _extras.clear();
  }

  /// 拉取账号资料，补全昵称/头像/会员标记。非必需接口，失败不影响搜索。
  Future<void> refreshProfile() async {
    if (!isLoggedIn) throw const KugouException('请先登录酷狗音乐');
    final json = await gateway.request(
      KugouGateway.gatewayBase,
      '/v3/get_my_info',
    );
    final data = json['data'];
    if (data is! Map) {
      throw const KugouException('酷狗账号信息缺少 data');
    }
    final map = Map<String, dynamic>.from(data);
    final nickname = _firstString(map, const [
      'nickname',
      'nick',
      'user_name',
      'username',
    ]);
    final avatar = _firstString(map, const [
      'avatar',
      'avatar_url',
      'user_pic',
      'pic',
    ]);
    final vipType = _firstInt(map, const [
      'vip_type',
      'vipType',
      'viptype',
      'vip',
    ]);
    final current = gateway.session;
    if (current == null) return;
    gateway.session = current.copyWith(
      nickname: nickname ?? current.nickname,
      avatarUrl: avatar ?? current.avatarUrl,
      vipType: vipType ?? current.vipType,
    );
  }

  Future<List<Song>> search(
    String keyword, {
    int page = 1,
    int limit = 30,
  }) async {
    if (keyword.trim().isEmpty) {
      throw const KugouException('搜索关键词不能为空');
    }
    final json = await gateway.request(
      KugouGateway.searchBase,
      '/v2/search/song',
      params: <String, String>{
        'keyword': keyword.trim(),
        'page': '$page',
        'pagesize': '$limit',
        'platform': 'AndroidFilter',
        'iscorrection': '1',
        'privilegefilter': '0',
        'area_code': '1',
        'dopicfull': '1',
        'albumhide': '0',
        'nocollect': '0',
      },
      userAgent: kugouSearchUserAgent,
      xRouter: 'complexsearch.kugou.com',
    );
    return _rememberSongs(json);
  }

  Future<List<Playlist>> userPlaylists() async {
    if (!isLoggedIn) throw const KugouException('请先登录酷狗音乐');
    final current = gateway.session!;
    final out = <Playlist>[];
    final seen = <String>{};
    const pageSize = 30;

    for (var page = 1; page <= 100; page++) {
      final body = <String, dynamic>{
        'userid': int.tryParse(current.userId) ?? 0,
        'token': current.token,
        'total_ver': 979,
        'type': 2,
        'page': page,
        'pagesize': pageSize,
      };
      final json = await gateway.request(
        KugouGateway.gatewayBase,
        '/v7/get_all_list',
        method: 'POST',
        params: const <String, String>{'plat': '1'},
        body: body,
        xRouter: 'cloudlist.service.kugou.com',
      );
      final data = json['data'];
      if (data is! Map) {
        throw const KugouException('酷狗歌单目录缺少 data');
      }
      final rows = data['info'];
      if (rows is! List) {
        throw const KugouException('酷狗歌单目录缺少 data.info');
      }
      final batch = parsePlaylists(rows, kind: 'owned');
      if (batch.isEmpty && rows.isNotEmpty) {
        throw const KugouException('酷狗歌单字段格式不兼容');
      }
      var added = 0;
      for (final playlist in batch) {
        if (seen.add(playlist.id)) {
          out.add(playlist);
          added++;
        }
      }
      final total = _firstInt(Map<String, dynamic>.from(data), const [
        'total',
        'count',
      ]);
      if (rows.isEmpty ||
          rows.length < pageSize ||
          added == 0 ||
          (total != null && out.length >= total)) {
        break;
      }
    }
    return out;
  }

  Future<List<Song>> playlistTracks(String id) async {
    final playlistId = id.trim();
    if (playlistId.isEmpty) {
      throw const KugouException('酷狗歌单 ID 不能为空');
    }
    final out = <Song>[];
    final seen = <String>{};

    for (var page = 0; page < 100; page++) {
      final params = <String, String>{
        'area_code': '1',
        'begin_idx': '${page * 100}',
        'plat': '1',
        'type': '1',
        'mode': '1',
        'personal_switch': '1',
        'extend_fields': 'abtags,hot_cmt,popularization',
        'pagesize': '100',
      };
      if (playlistId.startsWith('collection_')) {
        params['global_collection_id'] = playlistId;
      } else {
        params['listid'] = playlistId;
        params['specialid'] = playlistId;
      }
      final json = await gateway.request(
        KugouGateway.gatewayBase,
        '/pubsongs/v2/get_other_list_file_nofilt',
        params: params,
        xRouter: 'pubsongscdn.kugou.com',
      );
      final data = json['data'];
      if (data is! Map) {
        throw const KugouException('酷狗歌单详情缺少 data');
      }
      final dataMap = Map<String, dynamic>.from(data);
      final rows =
          dataMap['songs'] ??
          dataMap['info'] ??
          dataMap['list'] ??
          dataMap['lists'];
      if (rows is! List) {
        throw const KugouException('酷狗歌单详情字段格式不兼容');
      }
      final batch = _rememberSongs(rows);
      if (batch.isEmpty && rows.isNotEmpty) {
        throw const KugouException('酷狗歌单歌曲字段格式不兼容');
      }
      var added = 0;
      for (final song in batch) {
        if (seen.add(song.id.toUpperCase())) {
          out.add(song);
          added++;
        }
      }
      final total = _firstInt(dataMap, const ['count', 'total']);
      if (rows.isEmpty ||
          added == 0 ||
          (total != null && (page + 1) * 100 >= total)) {
        break;
      }
    }
    return out;
  }

  Future<List<LyricLine>> lyrics(String hash) async {
    final normalized = hash.trim();
    if (normalized.isEmpty) {
      throw const KugouException('酷狗歌词缺少歌曲 hash');
    }
    final search = await gateway.getJson(
      KugouGateway.lyricsSearchUri(hash: normalized),
    );
    final candidates = search['candidates'];
    if (candidates is! List || candidates.isEmpty) return <LyricLine>[];

    String? lastError;
    for (final item in candidates.whereType<Map>()) {
      final candidate = Map<String, dynamic>.from(item);
      final id = _firstString(candidate, const ['id', 'lyric_id']);
      final accessKey = _firstString(candidate, const [
        'accesskey',
        'access_key',
      ]);
      if (id == null || accessKey == null) continue;
      for (final format in const ['krc', 'lrc']) {
        try {
          final download = await gateway.getJson(
            KugouGateway.lyricsDownloadUri(
              id: id,
              accessKey: accessKey,
              format: format,
            ),
          );
          final content = download['content'];
          if (content is! String || content.trim().isEmpty) continue;
          final bytes = base64Decode(content.replaceAll(RegExp(r'\s'), ''));
          final text = format == 'krc'
              ? _decodeKrc(bytes)
              : utf8.decode(bytes, allowMalformed: true);
          final lines = parseLyrics(text);
          if (lines.isNotEmpty) return lines;
        } on KugouException catch (error) {
          lastError = error.message;
        } catch (error) {
          lastError = '$error';
        }
      }
    }
    if (lastError != null) throw KugouException('酷狗歌词下载失败：$lastError');
    return <LyricLine>[];
  }

  Future<List<HuaweiAudioFile>> audioFiles(Song song) async {
    final key = song.id.toUpperCase();
    final extra =
        _extras[key] ??
        KugouTrackExtra(
          hash: song.id,
          qualityHashes: <AudioQuality, String>{AudioQuality.standard: song.id},
          qualityFormats: const <AudioQuality, String>{
            AudioQuality.standard: '128',
          },
        );
    final common = gateway.commonParams();
    final mid = common['mid'] ?? '';
    final userId = common['userid'] ?? '0';
    final dfid = common['dfid'] ?? '-';
    final clientTime = common['clienttime'];
    final qualities =
        (song.qualities.isEmpty
                ? <AudioQuality>[AudioQuality.standard]
                : song.qualities.toList())
            .toList()
          ..sort((a, b) => b.index.compareTo(a.index));

    final out = <HuaweiAudioFile>[];
    final seen = <String>{};
    String? lastError;
    for (final quality in qualities) {
      final hash = extra.hashFor(quality);
      if (hash.isEmpty) continue;
      final format = extra.formatFor(quality);
      final params = <String, String>{
        'hash': hash,
        'album_id': extra.albumId,
        'album_audio_id': extra.albumAudioId,
        'quality': format,
        'area_code': '1',
        'ssa_flag': 'is_fromtrack',
        'version': '11430',
        'page_id': '151369488',
        'behavior': 'play',
        'pid': '2',
        'cmd': '26',
        'pidversion': '3001',
        'IsFreePart': '0',
        'ppage_id': '463467626,350369493,788954147',
        'cdnBackup': '1',
        'module': '',
        'clientver': '11430',
        'key': kugouPlaybackKey(hash: hash, mid: mid, userId: userId),
      };
      try {
        final json = await gateway.request(
          KugouGateway.gatewayBase,
          '/v5/url',
          params: params,
          xRouter: 'trackercdn.kugou.com',
          clientTime: clientTime,
          clientVersion: '11430',
        );
        for (final file in parseAudioFiles(json, quality: quality)) {
          if (seen.add(file.url.toString())) out.add(file);
        }
      } on KugouException catch (error) {
        lastError = error.message;
      }
    }

    if (out.isEmpty) {
      try {
        final json = await gateway.getJson(
          KugouGateway.getdataUri(
            hash: song.id,
            albumId: extra.albumId,
            mid: mid,
            dfid: dfid,
          ),
        );
        for (final file in parseAudioFiles(
          json,
          quality: AudioQuality.standard,
        )) {
          if (seen.add(file.url.toString())) out.add(file);
        }
      } on KugouException catch (error) {
        lastError = error.message;
      }
    }

    if (out.isEmpty) {
      throw KugouException(
        '酷狗未返回播放地址（请确认登录、会员和歌曲版权）'
        '${lastError == null ? '' : '：$lastError'}',
      );
    }
    return out;
  }

  Future<List<Comment>> comments(String hash) async {
    final normalized = hash.trim();
    if (normalized.isEmpty) {
      throw const KugouException('酷狗评论缺少歌曲 hash');
    }
    final extra = _extras[normalized.toUpperCase()];
    var mixSongId = extra?.albumAudioId ?? '';
    if (mixSongId.isEmpty) {
      mixSongId = await _resolveAudioId(normalized);
    }
    if (mixSongId.isEmpty) {
      throw const KugouException('酷狗评论缺少 mixsongid');
    }
    final params = <String, String>{
      'mixsongid': mixSongId,
      'need_show_image': '1',
      'p': '1',
      'pagesize': '30',
      'show_classify': '1',
      'show_hotword_list': '1',
      'extdata': '0',
      'code': 'fc4be23b4e972707f36b8a828a93ba8a',
    };
    Map<String, dynamic> json;
    try {
      json = await gateway.request(
        KugouGateway.gatewayBase,
        '/mcomment/v1/cmtlist',
        method: 'POST',
        params: params,
        xRouter: 'mcomment.service.kugou.com',
      );
    } on KugouException {
      json = await gateway.request(
        KugouGateway.gatewayBase,
        '/mcomment/v1/cmtlist',
        params: params,
        xRouter: 'mcomment.service.kugou.com',
      );
    }
    return parseComments(json);
  }

  /// 每日推荐。Muyu 的推荐链路使用 everydayrec 路由。
  Future<List<Song>> homeSongs() async {
    final json = await gateway.request(
      KugouGateway.gatewayBase,
      '/everyday_song_recommend',
      method: 'POST',
      params: const <String, String>{'platform': 'ios'},
      xRouter: 'everydayrec.service.kugou.com',
    );
    return _rememberSongs(json);
  }

  /// 首页热歌榜。默认 8888 = 酷狗 TOP500，可传其它 rank_id。
  Future<List<Song>> homeRank({int rankId = 8888}) async {
    final json = await gateway.request(
      KugouGateway.gatewayBase,
      '/openapi/kmr/v2/rank/audio',
      method: 'POST',
      body: <String, dynamic>{
        'show_portrait_mv': 1,
        'show_type_total': 1,
        'filter_original_remarks': 1,
        'area_code': 1,
        'pagesize': 100,
        'rank_cid': 0,
        'type': 1,
        'page': 1,
        'rank_id': rankId,
      },
      extraHeaders: const <String, String>{'kg-tid': '369'},
    );
    return _rememberSongs(json);
  }

  Future<String> _resolveAudioId(String hash) async {
    final common = gateway.commonParams();
    final json = await gateway.getJson(
      KugouGateway.getdataUri(
        hash: hash,
        mid: common['mid'] ?? '',
        dfid: common['dfid'] ?? '-',
      ),
    );
    final data = json['data'];
    if (data is! Map) return '';
    final map = Map<String, dynamic>.from(data);
    return _firstString(map, const [
          'album_audio_id',
          'audio_id',
          'mixsongid',
          'songid',
        ]) ??
        '';
  }

  List<Song> _rememberSongs(dynamic root) {
    final out = <Song>[];
    final seen = <String>{};
    for (final map in _songMaps(root)) {
      final parsed = _parseSongMap(map);
      if (parsed == null) continue;
      final id = parsed.song.id.toUpperCase();
      if (!seen.add(id)) continue;
      _extras[id] = parsed.extra;
      out.add(parsed.song);
    }
    return out;
  }

  static List<Song> parseSongs(dynamic root) {
    final out = <Song>[];
    final seen = <String>{};
    for (final map in _songMaps(root)) {
      final parsed = _parseSongMap(map);
      if (parsed == null) continue;
      if (seen.add(parsed.song.id.toUpperCase())) out.add(parsed.song);
    }
    return out;
  }

  static List<Song> parseSearchSongs(Map<String, dynamic> json) =>
      parseSongs(json);

  static List<Playlist> parsePlaylists(dynamic root, {String kind = ''}) {
    final out = <Playlist>[];
    final seen = <String>{};
    for (final map in _playlistMaps(root)) {
      final id = _playlistId(map);
      final name = _playlistName(map);
      if (id.isEmpty || name.isEmpty || !seen.add(id)) continue;
      final cover = _imageUrl(map, const [
        'pic_url',
        'sizable_cover',
        'imgurl',
        'img',
        'cover',
        'cover_url',
        'image',
      ]);
      out.add(
        Playlist(
          id: id,
          name: name,
          cover: cover,
          songCount:
              _firstInt(map, const [
                'count',
                'song_count',
                'songcount',
                'total',
              ]) ??
              0,
          kind: kind,
        ),
      );
    }
    return out;
  }

  static List<Comment> parseComments(dynamic root) {
    final out = <Comment>[];
    final seen = <String>{};
    for (final map in _mapListDeep(root)) {
      final content = _firstString(map, const [
        'content',
        'comment_content',
        'commentContent',
        'text',
      ]);
      if (content == null || content.isEmpty) continue;
      final id =
          _firstString(map, const ['commentid', 'comment_id', 'cid', 'id']) ??
          '${content.hashCode}';
      if (!seen.add(id)) continue;
      final author =
          _firstString(map, const [
            'nick',
            'nickname',
            'username',
            'user_name',
            'author',
          ]) ??
          '酷狗用户';
      final avatar = _imageUrl(map, const [
        'avatarurl',
        'avatar_url',
        'avatar',
        'user_pic',
        'headurl',
      ]);
      final timestamp = _firstInt(map, const [
        'addtime',
        'add_time',
        'time',
        'timestamp',
        'created_at',
      ]);
      out.add(
        Comment(
          id: id,
          author: author,
          content: content,
          avatar: avatar,
          time: _formatTimestamp(timestamp),
          likes:
              _firstInt(map, const [
                'praisenum',
                'like_count',
                'liked_count',
                'likes',
              ]) ??
              0,
        ),
      );
    }
    return out;
  }

  static List<HuaweiAudioFile> parseAudioFiles(
    Map<String, dynamic> json, {
    AudioQuality? quality,
  }) {
    final out = <HuaweiAudioFile>[];
    final seen = <String>{};
    for (final map in _audioMaps(json)) {
      if (_truthy(map['is_free_part']) || _truthy(map['free_part'])) {
        continue;
      }
      final url = _audioUrl(map);
      if (url == null || !seen.add(url.toString())) continue;
      final bitrate = _firstInt(map, const [
        'bitrate',
        'bitRate',
        'br',
        'audio_bitrate',
      ]);
      final extension =
          (_firstString(map, const ['extname', 'extName', 'ext']) ?? '')
              .toLowerCase();
      var actual =
          quality ??
          (bitrate != null
              ? AudioQuality.fromBitrate(bitrate)
              : AudioQuality.standard);
      if (quality == null) {
        if (extension.contains('flac') && (bitrate ?? 0) >= 900000) {
          actual = AudioQuality.hiRes;
        } else if (extension.contains('flac') || (bitrate ?? 0) >= 320000) {
          actual = AudioQuality.lossless;
        }
      }
      out.add(
        HuaweiAudioFile(
          quality: actual,
          url: url,
          sizeBytes:
              _firstInt(map, const [
                'filesize',
                'fileSize',
                'size',
                'FileSize',
              ]) ??
              0,
        ),
      );
    }
    return out;
  }

  /// 解析 KRC / LRC 文本，返回统一的逐行/逐字歌词。
  static List<LyricLine> parseLyrics(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final hasKrc = normalized
        .split('\n')
        .any((line) => RegExp(r'^\[\d+,\d+\]').hasMatch(line.trim()));
    return hasKrc ? _parseKrc(normalized) : _parseLrc(normalized);
  }

  static List<LyricLine> _parseKrc(String text) {
    final out = <LyricLine>[];
    final linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
    final wordPattern = RegExp(r'<(\d+),(\d+)(?:,\d+)?>([^<]*)');
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      final match = linePattern.firstMatch(line);
      if (match == null) continue;
      final lineStart = int.tryParse(match.group(1) ?? '') ?? 0;
      var rest = (match.group(3) ?? '').replaceAll(
        RegExp(r'\[[a-zA-Z_]+:[^\]]*\]'),
        '',
      );
      final words = <LyricWord>[];
      final buffer = StringBuffer();
      for (final word in wordPattern.allMatches(rest)) {
        final offset = int.tryParse(word.group(1) ?? '') ?? 0;
        final value = word.group(3) ?? '';
        if (value.isEmpty) continue;
        words.add(LyricWord(Duration(milliseconds: lineStart + offset), value));
        buffer.write(value);
      }
      if (words.isNotEmpty) {
        rest = buffer.toString();
      }
      final body = rest.trim();
      if (body.isEmpty) continue;
      out.add(LyricLine(Duration(milliseconds: lineStart), body, words: words));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static List<LyricLine> _parseLrc(String text) {
    final out = <LyricLine>[];
    final pattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)');
    for (final rawLine in text.split('\n')) {
      for (final match in pattern.allMatches(rawLine)) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fraction = (match.group(3) ?? '0').padRight(3, '0');
        final millis = int.tryParse(fraction.substring(0, 3)) ?? 0;
        final content = (match.group(4) ?? '').trim();
        if (content.isEmpty) continue;
        out.add(
          LyricLine(
            Duration(minutes: minutes, seconds: seconds, milliseconds: millis),
            content,
          ),
        );
      }
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static String _decodeKrc(List<int> bytes) {
    if (bytes.length <= 4) return '';
    final header = ascii.decode(bytes.sublist(0, 4), allowInvalid: true);
    if (header != 'krc1') {
      return utf8.decode(bytes, allowMalformed: true);
    }
    const key = <int>[
      0x40,
      0x47,
      0x61,
      0x77,
      0x5e,
      0x32,
      0x74,
      0x47,
      0x51,
      0x36,
      0x31,
      0x2d,
      0xce,
      0xd2,
      0x6e,
      0x69,
    ];
    final decrypted = <int>[];
    for (var index = 4; index < bytes.length; index++) {
      decrypted.add(bytes[index] ^ key[(index - 4) % key.length]);
    }
    try {
      final inflated = ZLibDecoder().convert(decrypted);
      return utf8.decode(inflated, allowMalformed: true);
    } catch (_) {
      return utf8.decode(decrypted, allowMalformed: true);
    }
  }

  static List<Map<String, dynamic>> _songMaps(dynamic root) {
    final out = <Map<String, dynamic>>[];
    void visit(dynamic node) {
      if (node is List) {
        for (final value in node) {
          visit(value);
        }
        return;
      }
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node);
      if (_hashOf(map).isNotEmpty &&
          (_firstString(map, const [
                'songname',
                'SongName',
                'song_name',
                'audio_name',
                'AudioName',
                'FileName',
                'filename',
                'name',
              ]) !=
              null)) {
        out.add(map);
      }
      for (final value in map.values) {
        if (value is Map || value is List) visit(value);
      }
    }

    visit(root);
    return out;
  }

  static _ParsedSong? _parseSongMap(Map<String, dynamic> d) {
    final hash = _hashOf(d);
    if (hash.isEmpty) return null;
    final fileName = _firstString(d, const ['FileName', 'filename']) ?? '';
    var title =
        _firstString(d, const [
          'songname',
          'SongName',
          'song_name',
          'audio_name',
          'AudioName',
          'name',
        ]) ??
        '';
    var fileArtist = '';
    if (title.isEmpty) {
      final pair = _splitFileTitle(fileName);
      fileArtist = pair.$1;
      title = pair.$2;
    }
    if (title.isEmpty) title = fileName;
    if (title.isEmpty) return null;

    final artists = <String>[];
    final artistIds = <String>[];
    for (final key in const [
      'singerinfo',
      'singers',
      'Singers',
      'authors',
      'artist',
    ]) {
      final value = d[key];
      if (value is! List) continue;
      for (final item in value) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final base = map['base'] is Map
            ? Map<String, dynamic>.from(map['base'] as Map)
            : map;
        final name = _firstString(base, const [
          'name',
          'author_name',
          'artist_name',
          'singer_name',
        ]);
        final id = _firstString(base, const [
          'id',
          'author_id',
          'artist_id',
          'singer_id',
        ]);
        if (name != null) artists.add(name);
        if (id != null) artistIds.add(id);
      }
      if (artists.isNotEmpty) break;
    }
    if (artists.isEmpty) {
      final single = _firstString(d, const [
        'singername',
        'SingerName',
        'singer',
        'author_name',
        'AuthorName',
        'artist_name',
      ]);
      if (single != null) {
        artists.addAll(_splitArtists(single));
      } else if (fileArtist.isNotEmpty) {
        artists.addAll(_splitArtists(fileArtist));
      }
    }
    if (artistIds.isEmpty) {
      final singleId = _firstString(d, const [
        'author_id',
        'AuthorId',
        'singerid',
        'singer_id',
      ]);
      if (singleId != null) artistIds.add(singleId);
    }

    final albumMap = _nestedMap(d, const ['album_info', 'albuminfo', 'album']);
    final album =
        _firstString(d, const ['album_name', 'AlbumName', 'albumname']) ??
        (albumMap == null
            ? ''
            : _firstString(albumMap, const [
                    'album_name',
                    'albumname',
                    'name',
                  ]) ??
                  '');
    final albumId =
        _firstString(d, const ['album_id', 'AlbumID', 'albumid']) ??
        _firstString(_nestedMap(d, const ['base', 'audio_info']) ?? d, const [
          'album_id',
          'AlbumID',
          'albumid',
        ]) ??
        '';
    final albumAudioId =
        _firstString(d, const [
          'album_audio_id',
          'MixSongID',
          'mixsongid',
          'AlbumAudioID',
          'audio_id',
          'Audioid',
        ]) ??
        _firstString(_nestedMap(d, const ['base', 'audio_info']) ?? d, const [
          'album_audio_id',
          'mixsongid',
          'audio_id',
        ]) ??
        '';

    final standard = hash;
    final hash320 =
        _qualityHash(d, const [
          'hash_320',
          '320hash',
          'HQFileHash',
          'hash320',
          '320',
        ]) ??
        '';
    final hashFlac =
        _qualityHash(d, const [
          'hash_flac',
          'sqhash',
          'SQFileHash',
          'hashflac',
          'flac',
        ]) ??
        '';
    final hashHigh =
        _qualityHash(d, const [
          'hash_high',
          'hireshash',
          'ResFileHash',
          'hash_hires',
          'hashhigh',
          'hires',
        ]) ??
        '';
    final lossless = hashFlac.isNotEmpty ? hashFlac : hash320;
    final qualityHashes = <AudioQuality, String>{
      AudioQuality.standard: standard,
      if (lossless.isNotEmpty) AudioQuality.lossless: lossless,
      if (hashHigh.isNotEmpty) AudioQuality.hiRes: hashHigh,
    };
    final qualityFormats = <AudioQuality, String>{
      AudioQuality.standard: '128',
      if (hashFlac.isNotEmpty)
        AudioQuality.lossless: 'flac'
      else if (hash320.isNotEmpty)
        AudioQuality.lossless: '320',
      if (hashHigh.isNotEmpty) AudioQuality.hiRes: 'high',
    };
    final qualities = <AudioQuality>{
      ...qualityHashes.keys,
      if (_qualityFlag(d, '320') || _qualityFlag(d, 'sq'))
        AudioQuality.lossless,
      if (_qualityFlag(d, 'flac')) AudioQuality.lossless,
      if (_qualityFlag(d, 'hires') || _qualityFlag(d, 'hr')) AudioQuality.hiRes,
    };
    final cover = _imageUrl(d, const [
      'Image',
      'img',
      'sizable_cover',
      'pic',
      'pic_url',
      'cover',
      'cover_url',
      'album_sizable_cover',
      'trans_param.union_cover',
    ]);
    final duration = _durationMs(d);
    final privilege = _firstInt(d, const ['privilege', 'Privilege']) ?? 0;
    final member =
        _truthy(d['is_vip']) ||
        _truthy(d['vip']) ||
        _truthy(d['member']) ||
        (_firstInt(d, const ['pay_type', 'payType', 'fee']) ?? 0) > 0 ||
        // 酷狗搜索结果 privilege=10 表示会员/付费曲目，待真机验证。
        privilege == 10;

    final song = Song(
      id: hash,
      name: title,
      album: album,
      artists: artists,
      artistIds: artistIds,
      cover: cover,
      durationMs: duration,
      qualities: qualities,
      source: MusicSourceLabel.kugou,
      member: member,
    );
    return _ParsedSong(
      song,
      KugouTrackExtra(
        hash: hash,
        albumAudioId: albumAudioId,
        albumId: albumId,
        qualityHashes: Map<AudioQuality, String>.unmodifiable(qualityHashes),
        qualityFormats: Map<AudioQuality, String>.unmodifiable(qualityFormats),
      ),
    );
  }

  static String _hashOf(Map<String, dynamic> map) {
    final direct = _firstString(map, const [
      'hash',
      'Hash',
      'FileHash',
      'filehash',
    ]);
    if (_validHash(direct)) return direct!;
    for (final key in const ['audio_info', 'audioInfo', 'base', 'audio']) {
      final nested = map[key];
      if (nested is! Map) continue;
      final value = _firstString(Map<String, dynamic>.from(nested), const [
        'hash',
        'Hash',
        'FileHash',
        'hash_128',
        'hash128',
      ]);
      if (_validHash(value)) return value!;
    }
    return '';
  }

  static bool _validHash(String? value) {
    if (value == null || value.length != 32) return false;
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value);
  }

  static String? _qualityHash(Map<String, dynamic> map, List<String> keys) {
    final direct = _firstString(map, keys);
    if (_validHash(direct)) return direct;
    for (final name in const ['audio_info', 'audioInfo', 'relate_goods']) {
      final nested = map[name];
      if (nested is! Map) continue;
      final value = _firstString(Map<String, dynamic>.from(nested), keys);
      if (_validHash(value)) return value;
    }
    return null;
  }

  static bool _qualityFlag(Map<String, dynamic> map, String key) {
    if (_truthy(map[key])) return true;
    final privilege = map['privilege'] ?? map['Privilege'];
    if (privilege is Map) {
      return _truthy(Map<String, dynamic>.from(privilege)[key]);
    }
    return false;
  }

  static int _durationMs(Map<String, dynamic> map) {
    final ms = _firstInt(map, const [
      'timelength',
      'timeLength',
      'timelength_ms',
    ]);
    if (ms != null && ms > 0) return ms;
    final raw = _firstInt(map, const [
      'duration',
      'Duration',
      'time_length',
      'song_duration',
    ]);
    if (raw == null || raw <= 0) return 0;
    return raw < 10000 ? raw * 1000 : raw;
  }

  static (String, String) _splitFileTitle(String fileName) {
    final index = fileName.indexOf(' - ');
    if (index <= 0) return ('', fileName.trim());
    return (
      fileName.substring(0, index).trim(),
      fileName.substring(index + 3).trim(),
    );
  }

  static List<String> _splitArtists(String value) {
    return value
        .split(RegExp(r'\s*(?:、|/|&|;|；)\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static Map<String, dynamic>? _nestedMap(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is Map) return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static List<Map<String, dynamic>> _mapListDeep(dynamic root) {
    final out = <Map<String, dynamic>>[];
    void visit(dynamic node) {
      if (node is List) {
        for (final value in node) {
          visit(value);
        }
        return;
      }
      if (node is! Map) return;
      final map = Map<String, dynamic>.from(node);
      out.add(map);
      for (final value in map.values) {
        if (value is Map || value is List) visit(value);
      }
    }

    visit(root);
    return out;
  }

  static List<Map<String, dynamic>> _playlistMaps(dynamic root) {
    final direct = <Map<String, dynamic>>[];
    if (root is List) {
      direct.addAll(root.whereType<Map>().map(Map<String, dynamic>.from));
    } else if (root is Map) {
      for (final key in const ['info', 'lists', 'list', 'data']) {
        final value = root[key];
        if (value is List) {
          direct.addAll(value.whereType<Map>().map(Map<String, dynamic>.from));
        }
      }
    }
    final nested = _mapListDeep(root).where((map) {
      final specificId = const [
        'global_collection_id',
        'gid',
        'listid',
        'specialid',
        'list_create_gid',
      ].any(map.containsKey);
      final specificName = const [
        'specialname',
        'listname',
        'playlist_name',
      ].any(map.containsKey);
      if (!specificId && !specificName) return false;
      if (_playlistId(map).isEmpty || _playlistName(map).isEmpty) return false;
      if (map.containsKey('hash') ||
          map.containsKey('songname') ||
          map.containsKey('SongName')) {
        return false;
      }
      return true;
    }).toList();
    return <Map<String, dynamic>>[...direct, ...nested];
  }

  static List<Map<String, dynamic>> _audioMaps(dynamic root) {
    return _mapListDeep(root).where((map) {
      return map.containsKey('url') ||
          map.containsKey('play_url') ||
          map.containsKey('play_backup_url') ||
          map.containsKey('backup_url') ||
          map.containsKey('src');
    }).toList();
  }

  static String _playlistId(Map<String, dynamic> map) {
    return _firstString(map, const [
          'global_collection_id',
          'gid',
          'listid',
          'specialid',
          'list_create_gid',
          'id',
        ]) ??
        '';
  }

  static String _playlistName(Map<String, dynamic> map) {
    return _firstString(map, const [
          'specialname',
          'listname',
          'name',
          'title',
          'playlist_name',
        ]) ??
        '';
  }

  static Uri? _imageUrl(Map<String, dynamic> map, List<String> keys) {
    String? raw;
    for (final key in keys) {
      final value = key.contains('.')
          ? _pathValue(map, key.split('.'))
          : map[key];
      if (value is String && value.trim().isNotEmpty) {
        raw = value.trim();
        break;
      }
    }
    if (raw == null || raw.isEmpty) return null;
    var text = raw
        .replaceAll('{size}', '400')
        .replaceAll('http://', 'https://');
    if (!text.startsWith('http')) {
      text = 'https://$text';
    }
    return Uri.tryParse(text);
  }

  static dynamic _pathValue(Map<String, dynamic> map, List<String> path) {
    dynamic current = map;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current;
  }

  static Uri? _audioUrl(Map<String, dynamic> map) {
    for (final key in const [
      'url',
      'backup_url',
      'play_url',
      'play_backup_url',
      'src',
    ]) {
      final value = map[key];
      final candidates = value is List ? value : <dynamic>[value];
      for (final candidate in candidates) {
        if (candidate is! String || candidate.trim().isEmpty) continue;
        final uri = Uri.tryParse(candidate.trim());
        if (uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty) {
          return uri;
        }
      }
    }
    return null;
  }

  static String _formatTimestamp(int? raw) {
    if (raw == null || raw <= 0) return '';
    final millis = raw > 10000000000 ? raw : raw * 1000;
    final date = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static bool _truthy(dynamic value) {
    if (value == true) return true;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == '1' || lower == 'true' || lower == 'yes';
    }
    return false;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return '$value';
    }
    return null;
  }

  static int? _firstInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}
