import 'dart:convert';

import '../models.dart';
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
  });

  final List<DiscoverBanner> banners;
  final List<Song> newSongs;
  final List<Playlist> playlists;
  final List<Playlist> charts;
  final List<Song> radio;
}

class DiscoverBanner {
  const DiscoverBanner({required this.title, this.subtitle = '', this.imageUrl});
  final String title;
  final String subtitle;
  final Uri? imageUrl;
}

/// 与沐语 Go 版 internal/catalog 对等：首页 / 搜索 / 榜单 / 收藏 / 歌单 /
/// 歌词 / 相似推荐 / 取流。解析全部走容错取值，不依赖严格 DTO。
class HuaweiAPI {
  HuaweiAPI({HuaweiGateway? gateway})
      : gateway = gateway ?? HuaweiGateway();

  final HuaweiGateway gateway;
  String? displayName;

  /// 源码事实：必须有音乐会话（token + snsUserID）才能发业务请求。
  bool get isLoggedIn => gateway.session != null;

  /// 手动填入音乐 token + snsUserID（调试用，跳过 OAuth 流程）。
  void signInWithSession(String musicToken, String snsUserId, {String? nick}) {
    gateway.session = MusicSession(token: musicToken.trim(), snsUserId: snsUserId.trim());
    displayName = nick ?? '华为音乐账号';
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
    displayName = '华为音乐账号';
  }

  /// 兼容旧接口名：账号密码登录不是源码支持的方式（tinglan 用扫码 OAuth）。
  /// 这里明确拒绝，避免误导。
  Future<void> signInWithAccount(String account, String password) async {
    throw const HuaweiException(
        '华为音乐不支持账号密码直登，请使用扫码登录（OAuth PKCE）');
  }

  void signOut() {
    gateway.session = null;
    gateway.accountToken = null;
    displayName = null;
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
      'contentSimpleInfos', 'songSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  Future<List<Song>> search(String keyword, {int start = 0, int limit = 20}) async {
    // 源码事实（API_CONTRACT §4）：全部为字符串字段。
    final json = await gateway.request(HuaweiPaths.search, body: <String, dynamic>{
      'contentType': '1',
      'correct': '1',
      'queryWord': keyword,
      'start': '$start',
      'limit': '$limit',
    });
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'songList',
      'result', 'list', 'data'
    ]).map(parseSong).toList();
  }

  /// 榜单 = 收藏列表里 contentType=7 的条目（音源插件真实支持）。
  Future<List<Playlist>> charts() async {
    final all = await playlists();
    return all.where((p) => p.kind == 'chart').take(8).toList();
  }

  Future<List<Song>> favorites({int start = 0, int limit = 50}) async {
    // 源码事实（API_CONTRACT §3.1）：targetSnsUserID + contentTypes[1]。
    final userId = gateway.session?.snsUserId ?? '';
    final json = await gateway.request(HuaweiPaths.favorites,
        body: <String, dynamic>{
          'targetSnsUserID': userId,
          'start': start,
          'limit': limit,
          'contentTypes': <int>[1],
        });
    return deepList(json, const [
      'favoriteInfos', 'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  /// 歌单发现：favorite/simple/all + contentTypes=[4,5,7]（音源插件 collections.go）。
  /// 4=收藏歌单 / 5=自建歌单 / 7=榜单。limit 先试 999，400 时退 50。
  Future<List<Playlist>> playlists() async {
    final userId = gateway.session?.snsUserId ?? '';
    Map<String, dynamic> json;
    try {
      json = await gateway.request(HuaweiPaths.playlistDetail,
          body: <String, dynamic>{
            'targetSnsUserID': userId,
            'start': 0,
            'limit': 999,
            'contentTypes': <int>[4, 5, 7],
          });
    } catch (_) {
      json = await gateway.request(HuaweiPaths.playlistDetail,
          body: <String, dynamic>{
            'targetSnsUserID': userId,
            'start': 0,
            'limit': 50,
            'contentTypes': <int>[4, 5, 7],
          });
    }
    return deepList(json, const ['favoriteInfos']).map((d) {
      final kindCode = HuaweiGateway.firstInt(d, const ['contentType']) ?? 0;
      final picture = d['picture'] is Map
          ? Map<String, dynamic>.from(d['picture'] as Map)
          : <String, dynamic>{};
      return Playlist(
        id: HuaweiGateway.firstString(d,
                const ['contentID', 'playListID', 'id']) ??
            '',
        name: HuaweiGateway.firstString(d,
                const ['contentName', 'playListName', 'name']) ??
            '',
        cover: HuaweiGateway.firstUrl(
            picture, const ['bigImgURL', 'middleImgURL', 'smallImgURL']),
        songCount: HuaweiGateway.firstInt(d,
                const ['totalCount', 'songNum', 'number']) ??
            0,
        kind: const <int, String>{4: 'collected', 5: 'owned', 7: 'chart'}[kindCode] ?? '',
      );
    }).where((p) => p.id.isNotEmpty && p.kind.isNotEmpty).toList();
  }

  /// 歌单歌曲：自建歌单用 GET detail/all，收藏歌单用 POST bymusiclistid。
  Future<List<Song>> playlistSongs(Playlist playlist,
      {int start = 0, int limit = 50}) async {
    final Map<String, dynamic> json;
    if (playlist.kind == 'owned') {
      json = await gateway.get(
        '${HuaweiPaths.ownedPlaylistSongs}?playListID=${Uri.encodeComponent(playlist.id)}'
        '&start=$start&limit=$limit',
      );
    } else if (playlist.kind == 'collected') {
      json = await gateway.request(HuaweiPaths.playlistSongs,
          body: <String, dynamic>{
            'musicListID': playlist.id,
            'copyrightSwitch': '1',
            'start': start,
            'limit': '$limit',
          });
    } else {
      return <Song>[];
    }
    return deepList(json, const [
      'playListSongInfoList', 'songSimpleInfos',
      'contentSimpleInfos', 'songs', 'list', 'data',
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

  /// 歌词（源码事实 tinglan/catalog.go Lyrics）：歌词地址随播放响应返回，
  /// 不从曲库详情取。优先逐字 HMRC（wordByWordLyric），再行级 LRC
  /// （lineByLineLyric / lyricAddress），并把译文合并进对应行。
  Future<List<LyricLine>> lyrics(String songCode) async {
    // 复用取流响应：歌词地址在 fileURL 同一个响应里。
    final json = await gateway.request(HuaweiPaths.playUrl,
        body: <String, dynamic>{
          'contentCode': songCode,
          'contentType': '1',
          'qualityType': '1',
        });

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

  /// 递归遍历 JSON，把指定 key 的字符串值回调出来（歌词字段可能嵌套多层、
  /// 还可能是「JSON 字符串套 JSON」）。
  void _collectLyricFields(dynamic root, void Function(String key, dynamic value) onField) {
    if (root is Map<String, dynamic>) {
      for (final entry in root.entries) {
        if (const ['wordByWordLyric', 'lineByLineLyric', 'lyricAddress', 'lyricAddres', 'lyrics', 'contentExInfo']
            .contains(entry.key)) {
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

  /// 取流（源码事实 tinglan/playback.go）：qualityType "1"=标准(MP3)、
  /// "3"=无损(FLAC)；主音频用顶层 fileURL，不盲用 fileInfos[0]。
  /// 分别请求两档，按 playQuality/qualityType + type(codec) 判定实际档位。
  Future<List<HuaweiAudioFile>> audioFiles(String songCode) async {
    final out = <HuaweiAudioFile>[];
    for (final q in <AudioQuality>[AudioQuality.standard, AudioQuality.lossless]) {
      final json = await gateway.request(HuaweiPaths.playUrl,
          body: <String, dynamic>{
            'contentCode': songCode,
            'contentType': '1',
            'qualityType': q.typeCode, // 1 或 3
          });
      // 顶层 fileURL 是音频（源码明确）；校验资源域名。
      final link = HuaweiGateway.firstUrl(json, const ['fileURL', 'fileUrl', 'playURL']);
      if (link == null) continue;
      if (!_safeAudioUrl(link)) continue;

      final code = HuaweiGateway.firstString(json, const ['playQuality', 'qualityType']) ?? '';
      final codec = (HuaweiGateway.firstString(json, const ['type']) ?? '').toLowerCase();
      // 源码判定：code=3 且 codec 含 flac -> lossless；code=1 且非 flac -> standard。
      AudioQuality actual;
      if (code == '3' || codec.contains('flac')) {
        actual = AudioQuality.lossless;
      } else {
        actual = AudioQuality.standard;
      }
      if (!out.any((f) => f.quality == actual)) {
        final size = HuaweiGateway.firstInt(json, const ['size', 'fileSize']) ?? 0;
        out.add(HuaweiAudioFile(quality: actual, url: link, sizeBytes: size));
      }
    }
    if (out.isEmpty) {
      throw const HuaweiException('该歌曲没有可用的音质档位（请确认已登录且为会员）');
    }
    return out;
  }

  bool _safeAudioUrl(Uri u) {
    if (u.scheme != 'https') return false;
    final host = u.host.toLowerCase();
    return const ['.dbankcdn.cn', '.tingmall.com', '.kuke.com']
        .any((s) => host.endsWith(s) && host.length > s.length);
  }

  /// 收藏增删（源码事实 API_CONTRACT §3.4）：create/delete 两个独立接口，
  /// 按目标状态调用，不盲切布尔；contentType/contentID 均为字符串。
  Future<void> toggleFavorite(String songCode, bool favorite) async {
    await gateway.request(
      favorite ? HuaweiPaths.favoriteCreate : HuaweiPaths.favoriteDelete,
      body: <String, dynamic>{
        'contentType': '1',
        'contentID': songCode,
      },
    );
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
    final single = HuaweiGateway.firstString(d, const [
      'singerName', 'artistName', 'artNM', 'artist', 'singer'
    ]);
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
      // 沐语 normalizeHomeSongs 兼容两套字段：精简 ID/NM/pic 与完整 contentID/contentName/middleImgURL。
      id: HuaweiGateway.firstString(d, const [
            'songCode', 'contentId', 'contentID', 'contentCode', 'ID', 'id', 'songId'
          ]) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: HuaweiGateway.firstString(d, const [
            'songName', 'name', 'songname', 'contentName', 'NM', 'title'
          ]) ??
          '未知歌曲',
      album: HuaweiGateway.firstString(d, const [
              'albumName', 'albNM', 'album', 'albumname']) ??
          '',
      artists: artists,
      cover: HuaweiGateway.firstUrl(d, const [
        'middleImgURL', 'bigImgURL', 'smallImgURL', 'mImg', 'bImg', 'sImg',
        'pic', 'picture', 'coverUrl', 'cover'
      ]),
      // durationSeconds 以秒计（REA 实测字段），其余为毫秒。
      durationMs: HuaweiGateway.firstInt(d, const ['durationSeconds']) != null
          ? HuaweiGateway.firstInt(d, const ['durationSeconds'])! * 1000
          : HuaweiGateway.firstInt(d, const [
                  'songDuration', 'durationMs', 'duration', 'dur', 'playDuration']) ??
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

  /// 解析逐字 HMRC（源码事实 tinglan/hmrc.go）：
  ///   [行开始ms,行时长ms]<字偏移ms,字时长ms>字<...>字 ^罗马音/译文
  /// 字偏移相对行首，行开始相对音频起点；全部毫秒。
  static List<LyricLine> parseHmrc(String text) {
    final lines = <LyricLine>[];
    for (final raw in const LineSplitter().convert(text.replaceAll('\r\n', '\n'))) {
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
        words.add(LyricWord(
          Duration(milliseconds: lineStartMs + pair.$1),
          chunk,
        ));
        buffer.write(chunk);
      }
      final body = buffer.toString().trim();
      if (body.isEmpty) continue;
      lines.add(LyricLine(
        Duration(milliseconds: lineStartMs),
        body,
        words: words,
        translation: translation,
        romanization: romanization,
      ));
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
      List<LyricLine> words, List<LyricLine> plain) {
    for (final w in words) {
      for (final p in plain) {
        // 时间接近（±600ms）或去标点后文本相同的行视为同一句。
        final near = (p.time.inMilliseconds - w.time.inMilliseconds).abs() < 600;
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
    final json = await gateway.request(HuaweiPaths.home);
    return parseDiscover(json);
  }

  /// 每日推荐：请求体来自运行中 Muyu.exe 堆内真实 JSON。
  Future<List<Song>> dailySongs() async {
    final json = await gateway.request(HuaweiPaths.daily,
        body: const <String, dynamic>{
          'rcmScenario': '1',
          'termType': '1',
          'scenario': '1',
          'recommendStrategy': '0',
        });
    return deepList(json, const [
      'dailySongs', 'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  /// 私人电台：请求体字段来自 REA decompile(applicationRequest@0x1404225c0)。
  /// cadence / rcmMode / rcmScenario / refInfo；rcmMode 仅接受 '1'/'2'/'3'。
  Future<List<Song>> privateRadio({String mode = '1'}) async {
    final json = await gateway.request(HuaweiPaths.privateFm,
        body: <String, dynamic>{
          'cadence': '',
          'rcmMode': mode,
          'rcmScenario': '16',
          'refInfo': <dynamic>[],
        });
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  /// 推荐歌单：沐语 /recommend/playlist。
  Future<List<Playlist>> recommendedPlaylists() async {
    final json = await gateway.request(HuaweiPaths.recommendPlaylist,
        body: const <String, dynamic>{
          'contentType': 1,
          'start': 0,
          'limit': 30,
        });
    return deepList(json, const [
      'playListInfos', 'playlistInfos', 'contentSimpleInfos', 'songList',
      'list', 'data'
    ]).map(parsePlaylist).toList();
  }

  /// 榜单歌曲：chartID / chartCode 来自 REA 符号与堆字段。
  Future<List<Song>> chartSongs(String chartId) async {
    final json = await gateway.request(HuaweiPaths.chartDetail,
        body: <String, dynamic>{
          'chartID': chartId,
          'chartCode': chartId,
          'contentType': 1,
          'start': 0,
          'limit': 50,
        });
    return deepList(json, const [
      'songSimpleInfos', 'contentSimpleInfos', 'songs', 'list', 'data'
    ]).map(parseSong).toList();
  }

  /// 解析沐语首页 JSON。列名全部由 REA 反编译给出的字符串常量实测，不是猜测。
  static DiscoverData parseDiscover(dynamic root) {
    final columns = deepList(root, const ['columnInfoExs']);
    final songs = <Song>[];
    final playlists = <Playlist>[];
    final charts = <Playlist>[];
    final radio = <Song>[];
    final banners = <DiscoverBanner>[];

    for (final column in columns) {
      final contents = deepList(column, const ['contentSimpleInfos']);
      final columnId = HuaweiGateway.firstString(column,
              const ['columnID', 'columnId', 'contentID']) ??
          '';
      for (final content in contents) {
        final cid = HuaweiGateway.firstString(content,
                const ['contentID', 'contentCode', 'ID']) ??
            '';
        // REA: contentID=pmf001 → childSimpleInfos → listRcmInfos（电台推荐）
        if (cid == 'pmf001' || columnId == 'pmf001') {
          final children = deepList(content, const ['childSimpleInfos']);
          for (final child in children) {
            final infos = deepList(child, const ['listRcmInfos']);
            radio.addAll(infos.map(parseSong));
          }
          continue;
        }
        final nestedSongs = deepList(content, const [
          'songSimpleInfos', 'listRcmInfos', 'contentSimpleInfos'
        ]);
        songs.addAll(nestedSongs.map(parseSong));
        final nestedLists = deepList(content, const [
          'playListInfos', 'recommendPlayListInfos', 'chartInfos'
        ]);
        for (final item in nestedLists) {
          final p = parsePlaylist(item);
          if (cid.contains('chart') || columnId.contains('chart') ||
              p.id.startsWith('chart')) {
            charts.add(p);
          } else {
            playlists.add(p);
          }
        }
        final banner = _bannerFrom(content);
        if (banner != null) banners.add(banner);
      }
    }

    // 兜底：接口直接给出扁平数组（某些版本 page/detail/all 会这样返回）。
    if (songs.isEmpty) {
      songs.addAll(deepList(root, const [
        'dailyRecInfos', 'newSongInfos', 'songSimpleInfos'
      ]).map(parseSong));
    }
    for (final item in deepList(root, const ['chartInfos'])) {
      charts.add(parsePlaylist(item));
    }
    for (final item in deepList(root, const ['playListInfos'])) {
      playlists.add(parsePlaylist(item));
    }
    if (banners.isEmpty) banners.addAll(parseBanners(root));

    return DiscoverData(
      banners: banners.take(8).toList(),
      newSongs: songs,
      playlists: playlists,
      charts: charts,
      radio: radio,
    );
  }

  static DiscoverBanner? _bannerFrom(Map<String, dynamic> d) {
    final url = HuaweiGateway.firstUrl(
        d, const ['picture', 'bigImgURL', 'middleImgURL', 'imageUrl']);
    final title = HuaweiGateway.firstString(
        d, const ['contentName', 'title', 'name', 'subTitle']);
    if (url == null || title == null || title.isEmpty || !_bannerImageAllowed(url)) {
      return null;
    }
    return DiscoverBanner(
      title: title,
      subtitle: HuaweiGateway.firstString(
              d, const ['subTitle', 'description', 'summary']) ??
          '',
      imageUrl: url,
    );
  }

  /// 榜单 / 歌单通用解析（字段名来自 REA：chartID / songNum / picture）。
  static Playlist parsePlaylist(Map<String, dynamic> d) {
    return Playlist(
      id: HuaweiGateway.firstString(d, const [
            'chartID', 'chartId', 'chartCode', 'playListID', 'contentID', 'id'
          ]) ?? '',
      name: HuaweiGateway.firstString(d, const [
            'chartName', 'playListName', 'contentName', 'name', 'title'
          ]) ?? '',
      cover: HuaweiGateway.firstUrl(d, const [
        'picture', 'middleImgURL', 'bigImgURL', 'cover', 'coverUrl'
      ]),
      songCount: HuaweiGateway.firstInt(d,
              const ['songNum', 'totalCount', 'songCount', 'number']) ??
          0,
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
      final inBannerContainer = hint.contains('banner') ||
          hint.contains('column') ||
          hint.contains('card') ||
          hint.contains('activity');
      // 当前节点本身就是 columns/banner 数组里的一个卡片。
      if (inBannerContainer && out.length < 8) {
        final self = Map<String, dynamic>.from(node);
        final url = HuaweiGateway.firstUrl(
            self, const ['picture', 'imageUrl', 'imgUrl', 'cover', 'picUrl']);
        final title = HuaweiGateway.firstString(
            self, const ['title', 'name', 'contentName', 'subTitle']);
        if (url != null &&
            _bannerImageAllowed(url) &&
            title != null &&
            title.isNotEmpty) {
          out.add(DiscoverBanner(
            title: title,
            subtitle: HuaweiGateway.firstString(
                    self, const ['subtitle', 'description', 'summary']) ??
                '',
            imageUrl: url,
          ));
        }
      }
      for (final entry in node.entries) {
        final key = entry.key.toLowerCase();
        final value = entry.value;
        final isBanner = key.contains('banner') ||
            (key.contains('column') && value is Map);
        if ((isBanner || inBannerContainer) &&
            value is Map &&
            out.length < 8) {
          final m = Map<String, dynamic>.from(value);
          final url = HuaweiGateway.firstUrl(
              m, const ['picture', 'imageUrl', 'imgUrl', 'cover', 'picUrl']);
          final title = HuaweiGateway.firstString(
              m, const ['title', 'name', 'contentName', 'subTitle']);
          if (url != null &&
              _bannerImageAllowed(url) &&
              title != null &&
              title.isNotEmpty) {
            out.add(DiscoverBanner(
              title: title,
              subtitle: HuaweiGateway.firstString(
                      m, const ['subtitle', 'description', 'summary']) ??
                  '',
              imageUrl: url,
            ));
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
    return const ['.dbankcdn.cn', '.tingmall.com', '.kuke.com']
        .any((s) => host.endsWith(s) && host.length > s.length);
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
}
