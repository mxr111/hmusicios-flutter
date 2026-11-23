import 'dart:convert';

import '../models.dart';
import 'endpoints.dart';
import 'huawei_gateway.dart';

/// 与沐语 Go 版 internal/catalog 对等：首页 / 搜索 / 榜单 / 收藏 / 歌单 /
/// 歌词 / 相似推荐 / 取流。解析全部走容错取值，不依赖严格 DTO。
class HuaweiAPI {
  HuaweiAPI({HuaweiGateway? gateway})
      : gateway = gateway ?? HuaweiGateway();

  final HuaweiGateway gateway;
  String? displayName;

  bool get isLoggedIn => gateway.accessToken != null;

  /// 手动填入凭据：签名算法未还原时用于调试与抓包。
  void signInWithToken(String token, {String? nick}) {
    gateway.accessToken = token.trim();
    displayName = nick;
  }

  /// REA 观察到的账号登录接口（字段为推断，服务端签名未还原时可能失败）。
  Future<void> signInWithAccount(String account, String password) async {
    final json = await gateway.request(HuaweiPaths.userInfo, body: <String, dynamic>{
      'account': account,
      'password': password,
      'client_id': HuaweiPaths.clientId,
    });
    final token = _findStringDeep(json,
        const ['accessToken', 'access_token', 'token', 'atToken']);
    if (token == null) {
      throw const HuaweiException(
          '该登录方式未返回凭据，请改用「手动填入 access_token」');
    }
    gateway.accessToken = token;
    displayName = _findStringDeep(json,
            const ['nickname', 'displayName', 'userName', 'nickName']) ??
        account;
  }

  void signOut() {
    gateway.accessToken = null;
    displayName = null;
  }

  Future<List<Song>> homeSongs() async {
    final json = await gateway.request(HuaweiPaths.home, body: <String, dynamic>{
      'pageType': 7,
      'hasRecommend': 1,
      'contentType': 1,
    });
    var raw = deepList(json, const [
      'dailyRecInfos', 'songSimpleInfos', 'contentSimpleInfos', 'songs',
      'songlist', 'list', 'recommendSongs'
    ]);
    if (raw.isEmpty) {
      final daily = await gateway.request(HuaweiPaths.daily,
          body: const <String, dynamic>{'contentType': 1});
      raw = deepList(daily, const [
        'dailyRecInfos', 'dailySongs', 'songSimpleInfos', 'songs', 'list'
      ]);
    }
    return raw.map(parseSong).toList();
  }

  Future<List<Song>> search(String keyword) async {
    final json = await gateway.request(HuaweiPaths.search, body: <String, dynamic>{
      'queryWord': keyword,
      'keyword': keyword,
      'contentType': 1,
      'pageNo': 1,
      'pageSize': 30,
    });
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'songList',
      'result', 'list', 'data'
    ]).map(parseSong).toList();
  }

  Future<List<Playlist>> charts() async {
    final json = await gateway.request(HuaweiPaths.home,
        body: const <String, dynamic>{'pageType': 7});
    final raw = deepList(json, const ['chartInfos', 'charts', 'toplist']);
    return raw.take(8).map((d) {
      return Playlist(
        id: HuaweiGateway.firstString(d,
                const ['chartId', 'chartCode', 'id']) ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: HuaweiGateway.firstString(d,
                const ['chartName', 'name', 'title']) ??
            '榜单',
        cover: HuaweiGateway.firstUrl(d,
            const ['middleImgURL', 'bigImgURL', 'cover']),
        songCount: HuaweiGateway.firstInt(d,
                const ['songNum', 'songCount', 'totalCount']) ??
            0,
      );
    }).toList();
  }

  Future<List<Song>> favorites() async {
    final json = await gateway.request(HuaweiPaths.favorites,
        body: const <String, dynamic>{'contentType': 1});
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  Future<List<Playlist>> playlists() async {
    final json = await gateway.request(HuaweiPaths.playlistDetail,
        body: const <String, dynamic>{'contentType': 1});
    return deepList(json, const [
      'playListInfos', 'playlistInfos', 'playlists', 'list', 'data'
    ]).map((d) {
      return Playlist(
        id: HuaweiGateway.firstString(d,
                const ['playListID', 'musicListID', 'id']) ??
            '',
        name: HuaweiGateway.firstString(d,
                const ['playListName', 'musicListName', 'name']) ??
            '歌单',
        cover: HuaweiGateway.firstUrl(d,
            const ['middleImgURL', 'bigImgURL', 'coverImgUrl']),
        songCount: HuaweiGateway.firstInt(d,
                const ['songNum', 'songCount', 'totalCount']) ??
            0,
      );
    }).toList();
  }

  Future<List<Song>> playlistSongs(String playlistId) async {
    final json = await gateway.request(HuaweiPaths.playlistSongs,
        body: <String, dynamic>{'playListID': playlistId, 'contentType': 1});
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  Future<List<Song>> similarSongs(String songCode) async {
    final json = await gateway.request(HuaweiPaths.similar,
        body: <String, dynamic>{'contentCode': songCode, 'contentType': 1});
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  Future<Song> songDetail(String songCode) async {
    final json = await gateway.request(HuaweiPaths.songDetail,
        body: <String, dynamic>{'songCodes': [songCode]});
    final first = deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]);
    return first.isEmpty ? Song(id: songCode, name: '未知歌曲') : parseSong(first.first);
  }

  Future<List<LyricLine>> lyrics(String songCode) async {
    final detail = await gateway.request(HuaweiPaths.songDetail,
        body: <String, dynamic>{'songCodes': [songCode]});
    final addr = _findUrlDeep(detail, const [
      'lyricAddress', 'lyricUrl', 'lrcUrl', 'lyricAddr'
    ]);
    if (addr == null) return <LyricLine>[];
    final text = await gateway.fetchText(addr);
    return parseLrc(text);
  }

  /// 取流：REA 观察到 /music-play-service/v3/service/file/bycontentcode
  Future<List<HuaweiAudioFile>> audioFiles(String songCode) async {
    final json = await gateway.request(HuaweiPaths.playUrl,
        body: <String, dynamic>{
          'contentCode': songCode,
          'songCode': songCode,
          'contentType': 1,
          'quality': 'h',
        });
    final infos = deepList(json, const [
      'fileInfos', 'audioFiles', 'files', 'list', 'data'
    ]);
    final out = <HuaweiAudioFile>[];
    for (final info in infos) {
      final link = HuaweiGateway.firstUrl(info, const [
        'playURL', 'url', 'downloadUrl', 'fileUrl', 'link', 'h', 'sq', 'hr'
      ]);
      if (link == null) continue;
      final tier = HuaweiGateway.firstString(info,
              const ['quality', 'qualityType', 'fileType', 'tier']) ??
          'h';
      final size = HuaweiGateway.firstInt(info, const [
            'size_320mp3', 'size_flac', 'size_hires', 'size', 'fileSize'
          ]) ??
          0;
      out.add(HuaweiAudioFile(
          quality: AudioQuality.fromCode(tier), url: link, sizeBytes: size));
    }
    // 顶层档位键兜底
    for (final q in AudioQuality.values) {
      final link = HuaweiGateway.firstUrl(json, [q.code, q.sizeKey]);
      if (link != null && !out.any((f) => f.quality == q)) {
        out.add(HuaweiAudioFile(
          quality: q,
          url: link,
          sizeBytes: HuaweiGateway.firstInt(json, [q.sizeKey]) ?? 0,
        ));
      }
    }
    if (out.isEmpty) {
      throw const HuaweiException('该歌曲没有可用的音质档位');
    }
    return out;
  }

  Future<void> toggleFavorite(String songCode, bool favorite) async {
    await gateway.request(HuaweiPaths.favoriteWrite, body: <String, dynamic>{
      'contentId': songCode,
      'contentType': 1,
      'operate': favorite ? 1 : 2,
    });
  }

  Future<String> membership() async {
    final json = await gateway.request(HuaweiPaths.subscription);
    return HuaweiGateway.firstString(json,
            const ['iVipFlag', 'HugeVip', 'vipFlag']) ??
        '';
  }

  // MARK: - 容错解析

  static Song parseSong(Map<String, dynamic> d) {
    final artists = <String>[];
    final single = HuaweiGateway.firstString(d,
        const ['singerName', 'artistName', 'singer', 'artist']);
    if (single != null) {
      artists.addAll(single
          .split(RegExp(r'[/,、&]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty));
    } else {
      final pairs = d['artistNamePairs'];
      if (pairs is List) {
        for (final p in pairs) {
          if (p is Map<String, dynamic>) {
            final n = HuaweiGateway.firstString(
                p, const ['artistName', 'name']);
            if (n != null) artists.add(n);
          }
        }
      }
    }
    final qualities = <AudioQuality>{AudioQuality.standard};
    for (final q in AudioQuality.values) {
      final v = d[q.sizeKey];
      if (v != null && v != 0 && v != '0') qualities.add(q);
    }
    final tier = HuaweiGateway.firstString(d,
        const ['quality', 'playQuality', 'minPrivilege']);
    if (tier != null) qualities.add(AudioQuality.fromCode(tier));

    return Song(
      id: HuaweiGateway.firstString(d, const [
            'songCode', 'contentId', 'contentCode', 'id', 'songId'
          ]) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: HuaweiGateway.firstString(d, const [
            'songName', 'name', 'songname', 'contentName', 'title'
          ]) ??
          '未知歌曲',
      album: HuaweiGateway.firstString(d,
              const ['albumName', 'album', 'albumname']) ??
          '',
      artists: artists,
      cover: HuaweiGateway.firstUrl(d, const [
        'middleImgURL', 'bigImgURL', 'smallImgURL', 'coverUrl', 'cover'
      ]),
      durationMs: HuaweiGateway.firstInt(d,
              const ['songDuration', 'duration', 'playDuration']) ??
          0,
      qualities: qualities,
      lyricUrl: HuaweiGateway.firstUrl(d,
          const ['lyricAddress', 'lyricUrl', 'lrcUrl']),
      favorite: d['favorite'] == true || d['isFavorite'] == true,
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
        lines.add(LyricLine(
            Duration(minutes: min, seconds: sec, milliseconds: ms), content));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// 在任意嵌套层里找第一个指定 key 的数组。
  static List<Map<String, dynamic>> deepList(
      dynamic root, List<String> keys) {
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

  static String? _findStringDeep(dynamic root, List<String> keys) {
    if (root is Map) {
      final m = Map<String, dynamic>.from(root);
      final direct = HuaweiGateway.firstString(m, keys);
      if (direct != null) return direct;
      for (final v in m.values) {
        final found = _findStringDeep(v, keys);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final v in root) {
        final found = _findStringDeep(v, keys);
        if (found != null) return found;
      }
    }
    return null;
  }

  static Uri? _findUrlDeep(dynamic root, List<String> keys) {
    if (root is Map) {
      final m = Map<String, dynamic>.from(root);
      final direct = HuaweiGateway.firstUrl(m, keys);
      if (direct != null) return direct;
      for (final v in m.values) {
        final found = _findUrlDeep(v, keys);
        if (found != null) return found;
      }
    } else if (root is List) {
      for (final v in root) {
        final found = _findUrlDeep(v, keys);
        if (found != null) return found;
      }
    }
    return null;
  }
}
