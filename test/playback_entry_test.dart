import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_log.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/services/session_store.dart';

/// 不发真实网络请求的播放器替身。iOS 上 hiRes FLAC 在 setSource 阶段
/// 失败，这里用 mimeType 精确模拟，验证音频层会继续降档到 MP3。
class _FakePlayer extends AudioPlayer {
  _FakePlayer();

  final List<String?> mimeTypes = <String?>[];
  final List<Source> sources = <Source>[];
  int playCalls = 0;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {
    playCalls++;
    sources.add(source);
    mimeTypes.add(source.mimeType);
    if (source.mimeType == 'audio/flac') {
      throw PlatformException(
        code: 'DarwinAudioError',
        message: 'AVPlayerItem.Status.failed on setSourceUrl',
      );
    }
  }

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> dispose() async {}
}

/// 真实 audioFiles 链路：7=142411，5/3=FLAC，1=MP3。
class _TierGateway extends HuaweiGateway {
  final List<String> requestedTypes = <String>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    if (path != HuaweiPaths.playUrl) throw StateError('unexpected $path');
    final type = '${body['qualityType']}';
    requestedTypes.add(type);
    if (type == '7') {
      return <String, dynamic>{
        'result': <String, dynamic>{
          'resultCode': '142411',
          'resultMessage': 'Only super diamond vip user can play the content!',
        },
      };
    }
    final url = switch (type) {
      '5' => 'https://test.dbankcdn.cn/1092974-HR-1000K-FTD.flac',
      '3' => 'https://test.dbankcdn.cn/1092974-FLAC-1000K-FTD.flac',
      _ => 'https://test.dbankcdn.cn/1092974-MP3-128K-FTD.mp3',
    };
    return <String, dynamic>{
      'result': <String, dynamic>{'resultCode': '000000'},
      'qualityType': type,
      'fileURL': url,
    };
  }
}

/// 所有档位都返回 990000，必须立即中止，不能被 142411 降档逻辑吞掉。
class _AuthGateway extends HuaweiGateway {
  final List<String> requestedTypes = <String>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    requestedTypes.add('${body['qualityType']}');
    return <String, dynamic>{
      'result': <String, dynamic>{
        'resultCode': '990000',
        'resultMessage': '鉴权失败',
      },
    };
  }
}

/// 只记录歌曲 ID，返回标准档，用于验证搜索/榜单/歌单/首页/歌手
/// 五个入口都走同一套按 ID 取流逻辑。
class _RecordingApi extends HuaweiAPI {
  _RecordingApi() : super(gateway: HuaweiGateway());

  final List<String> requestedSongs = <String>[];

  @override
  Future<List<HuaweiAudioFile>> audioFiles(
    String songCode, {
    Set<AudioQuality>? upstreamQualities,
  }) async {
    requestedSongs.add(songCode);
    return <HuaweiAudioFile>[
      HuaweiAudioFile(
        quality: AudioQuality.standard,
        qualityType: '1',
        url: Uri.parse('https://test.dbankcdn.cn/$songCode-MP3-128K-FTD.mp3'),
        sizeBytes: 4000000,
      ),
    ];
  }
}

/// 首页 fake：discover 返回指定板块；心动首屏走 heartFmFirstPage；
/// privatefm 只应由心动续页调用，点卡片本身不应请求它。
class _HomeApi extends _RecordingApi {
  _HomeApi(this.home, {this.heartPage, this.heartError});

  final DiscoverData home;
  final HuaweiPrivateFmPage? heartPage;
  final Object? heartError;
  final List<Map<String, String>> privateFmRequests =
      <Map<String, String>>[];
  int heartFmCalls = 0;
  int privateRadioCalls = 0;
  int privateRadioMode2Calls = 0;

  @override
  Future<DiscoverData> discover() async => home;

  @override
  Future<List<Song>> daily30({String id = HuaweiAPI.dailyPlaylistId}) async =>
      const <Song>[];

  @override
  Future<List<Song>> chartSongs(String chartId) async => const <Song>[];

  @override
  Future<HuaweiPrivateFmPage> heartFmFirstPage({String refInfo = ''}) async {
    heartFmCalls++;
    final failure = heartError;
    if (failure != null) throw failure;
    return heartPage ?? const HuaweiPrivateFmPage();
  }

  @override
  Future<HuaweiPrivateFmPage> privateFmPage({
    String mode = '1',
    String rcmScenario = '16',
    String refInfo = '',
    String next = '',
  }) async {
    privateFmRequests.add(<String, String>{
      'mode': mode,
      'rcmScenario': rcmScenario,
      'refInfo': refInfo,
      'next': next,
    });
    return const HuaweiPrivateFmPage();
  }

  @override
  Future<List<Song>> privateRadio({String mode = '1'}) async {
    privateRadioCalls++;
    if (mode == '2') privateRadioMode2Calls++;
    return <Song>[
      Song(
        id: 'private-radio-$mode',
        name: '错误兜底电台 $mode',
        qualities: <AudioQuality>{AudioQuality.standard},
      ),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async => 0,
    );
    messenger.setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers.global/events'),
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
    messenger.setMockStreamHandler(
      const EventChannel('xyz.luan/audioplayers.events'),
      MockStreamHandler.inline(onListen: (args, sink) {}),
    );
    AppLog.clear();
  });

  test('收藏本地文件走预置路径，不请求取流', () async {
    final api = _RecordingApi();
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final song = Song(
      id: 'fav-local',
      name: '本地收藏',
      localPath: '/tmp/fav-local.mp3',
    );

    await audio.playSong(song, list: <Song>[song]);

    expect(api.requestedSongs, isEmpty);
    expect(player.sources.single, isA<DeviceFileSource>());
    expect(player.sources.single.mimeType, 'audio/mpeg');
    expect(audio.lastQualityType, 'local');
    expect(audio.lastHasUrl, isTrue);
    expect(audio.error, isNull);
    audio.dispose();
  });

  test('收藏歌曲只有 ID 时也按 contentCode 取标准档并播放', () async {
    final api = _RecordingApi();
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final song = Song(
      id: 'fav-1',
      name: '收藏一',
      qualities: <AudioQuality>{AudioQuality.standard},
    );

    await audio.playSong(song, list: <Song>[song]);

    expect(api.requestedSongs, <String>['fav-1']);
    expect(player.mimeTypes, <String?>['audio/mpeg']);
    expect(audio.lastQualityType, '1');
    expect(audio.lastHasUrl, isTrue);
    expect(audio.error, isNull);
    expect(AppLog.exportText(), contains('presetUrl=false'));
    audio.dispose();
  });

  test('搜索/榜单/歌单/首页/歌手入口只有 ID 都能解析并播放', () async {
    final api = _RecordingApi();
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );
    Song song(String id) => Song(
      id: id,
      name: '歌曲 $id',
      qualities: const <AudioQuality>{AudioQuality.standard},
    );

    final search = <Song>[song('search-1')];
    state.searchResults = search;
    await state.play(search.single, queue: search);
    expect(audio.playEntry, 'search');

    final chart = <Song>[song('chart-1')];
    state.chartSongs = chart;
    await state.play(chart.single, queue: chart);
    expect(audio.playEntry, 'chart');

    final playlist = <Song>[song('playlist-1')];
    state.playlistSongsList = playlist;
    await state.play(playlist.single, queue: playlist);
    expect(audio.playEntry, 'playlist');

    final home = <Song>[song('home-1')];
    state.discover = DiscoverData(hot: home);
    await state.play(home.single, queue: home);
    expect(audio.playEntry, 'home/hot');

    final artist = <Song>[song('artist-1')];
    state.artistSongsList = artist;
    await state.play(artist.single, queue: artist);
    expect(audio.playEntry, 'artist');

    expect(
      api.requestedSongs,
      <String>['search-1', 'chart-1', 'playlist-1', 'home-1', 'artist-1'],
    );
    expect(state.error, isNull);
    state.dispose();
  });

  test('142411 继续取档：hiRes/lossless FLAC 失败后 standard MP3 可播', () async {
    final gateway = _TierGateway();
    final api = HuaweiAPI(gateway: gateway);
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final song = Song(
      id: '1092974',
      name: '晴天',
      qualities: <AudioQuality>{
        AudioQuality.hiRes,
        AudioQuality.lossless,
        AudioQuality.standard,
      },
    );

    await audio.playSong(song, list: <Song>[song]);

    expect(gateway.requestedTypes, <String>['7', '5', '3', '1']);
    expect(player.mimeTypes, <String?>[
      'audio/flac',
      'audio/flac',
      'audio/mpeg',
    ]);
    expect(audio.lastQualityType, '1');
    expect(audio.lastHasUrl, isTrue);
    expect(audio.lastErrorCode, '000000');
    expect(audio.error, isNull);
    final log = AppLog.exportText();
    expect(log, contains('qualityType=7'));
    expect(log, contains('decode-failed'));
    expect(log, contains('qualityType=1'));
    expect(log, isNot(contains('_AQ')));
    audio.dispose();
  });

  test('990000 不降档、不跳歌，错误要求重新登录', () async {
    final gateway = _AuthGateway();
    final api = HuaweiAPI(gateway: gateway);
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );
    final expired = Song(
      id: 'expired',
      name: '鉴权失效',
      qualities: <AudioQuality>{AudioQuality.hiRes},
    );
    final nextSong = Song(id: 'next', name: '下一首');

    await state.play(expired, queue: <Song>[expired, nextSong]);

    // 取流失败后歌词不得再触发一次 qualityType=1 的 playUrl。
    expect(gateway.requestedTypes, <String>['7']);
    expect(player.playCalls, 0);
    expect(state.audio.current?.id, 'expired');
    expect(state.error, contains('990000'));
    expect(state.error, contains('重新登录'));
    expect(AppState.looksUnplayable(state.error), isFalse);
    state.dispose();
  });

  test('队列下一首同样按 ID 解析，不沿用上一首 URL', () async {
    final api = _RecordingApi();
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final first = Song(
      id: 'queue-1',
      name: '队列一',
      qualities: <AudioQuality>{AudioQuality.standard},
    );
    final second = Song(
      id: 'queue-2',
      name: '队列二',
      qualities: <AudioQuality>{AudioQuality.standard},
    );

    await audio.playSong(first, list: <Song>[first, second]);
    await audio.next();

    expect(api.requestedSongs, <String>['queue-1', 'queue-2']);
    expect(audio.playEntry, 'next');
    expect(audio.current?.id, 'queue-2');
    expect(player.playCalls, 2);
    expect(audio.error, isNull);
    audio.dispose();
  });

  test('radio 只播放 discover.listen，不调用 privateFmPage/privateRadio', () async {
    final api = _HomeApi(
      DiscoverData(
        listen: <Song>[
          Song(id: 'listen-1', name: '现在就听一'),
          Song(id: 'listen-2', name: '现在就听二'),
        ],
        daily: <Song>[Song(id: 'daily-only', name: '每日')],
        hot: <Song>[Song(id: 'hot-only', name: '热歌')],
        heart: <Song>[Song(id: 'heart-only', name: '心动')],
        radio: <Song>[Song(id: 'legacy-radio', name: '旧电台字段')],
      ),
    );
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.loadHome();
    await state.playCard('radio');

    expect(state.discover.listen.map((song) => song.id), <String>[
      'listen-1',
      'listen-2',
    ]);
    expect(audio.queue.map((song) => song.id), <String>[
      'listen-1',
      'listen-2',
    ]);
    expect(state.audio.current?.id, 'listen-1');
    expect(api.heartFmCalls, 0);
    expect(api.privateFmRequests, isEmpty);
    expect(api.privateRadioCalls, 0);
    // 现在就听是独立普通队列，播完不能续心动 privatefm。
    expect(state.audio.onQueueExhausted, isNull);
    expect(state.error, isNull);
    state.dispose();
  });

  test('radio 独立板块为空时只报错，不拿 radio/daily/hot/heart 填充', () async {
    final api = _HomeApi(
      DiscoverData(
        daily: <Song>[Song(id: 'daily-only', name: '每日')],
        hot: <Song>[Song(id: 'hot-only', name: '热歌')],
        newSongs: <Song>[Song(id: 'new-only', name: '新歌')],
        heart: <Song>[Song(id: 'heart-only', name: '心动')],
        radio: <Song>[Song(id: 'legacy-radio', name: '旧电台字段')],
      ),
    );
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.loadHome();
    await state.playCard('radio');

    expect(state.discover.listen, isEmpty);
    expect(state.audio.current, isNull);
    expect(state.error, contains('「现在就听」独立板块未返回歌曲'));
    expect(api.privateFmRequests, isEmpty);
    expect(api.heartFmCalls, 0);
    expect(api.privateRadioCalls, 0);
    state.dispose();
  });

  test('heart 调用 heartFmFirstPage 并写回本板块，不调用 privateRadio', () async {
    final api = _HomeApi(
      DiscoverData(
        listen: <Song>[Song(id: 'listen-only', name: '现在就听')],
        radio: <Song>[Song(id: 'legacy-radio', name: '旧电台字段')],
        hot: <Song>[Song(id: 'hot-only', name: '热歌')],
      ),
      heartPage: HuaweiPrivateFmPage(
        songs: <Song>[
          Song(id: 'heart-1', name: '心动一'),
          Song(id: 'heart-2', name: '心动二'),
        ],
        next: 'heart-next-1',
        more: true,
        refInfo: 'heart-ref-1',
        rcmScenario: '21',
        mode: '1',
      ),
    );
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.loadHome();
    await state.playCard('heart');

    expect(api.heartFmCalls, 1);
    // 首屏只走 heartFmFirstPage，不应直接请求 privatefm 或旧 privateRadio。
    expect(api.privateFmRequests, isEmpty);
    expect(api.privateRadioCalls, 0);
    expect(api.privateRadioMode2Calls, 0);
    expect(state.discover.heart.map((song) => song.id), <String>[
      'heart-1',
      'heart-2',
    ]);
    expect(state.discover.listen.map((song) => song.id), <String>[
      'listen-only',
    ]);
    expect(state.audio.current?.id, 'heart-1');
    expect(state.radioNext, 'heart-next-1');
    expect(state.radioMore, isTrue);
    expect(state.radioRefInfo, 'heart-ref-1');
    expect(state.radioScenario, '16');
    expect(state.radioMode, '1');
    expect(state.audio.onQueueExhausted, isNotNull);
    expect(state.error, isNull);
    state.dispose();
  });

  test('heartFmFirstPage 返回空时只回退 discover.heart 缓存', () async {
    final api = _HomeApi(
      DiscoverData(
        heart: <Song>[Song(id: 'cached-heart', name: '缓存心动')],
        listen: <Song>[Song(id: 'listen-only', name: '现在就听')],
        radio: <Song>[Song(id: 'legacy-radio', name: '旧电台字段')],
        daily: <Song>[Song(id: 'daily-only', name: '每日')],
        hot: <Song>[Song(id: 'hot-only', name: '热歌')],
      ),
      heartPage: const HuaweiPrivateFmPage(),
    );
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.loadHome();
    await state.playCard('heart');

    expect(api.heartFmCalls, 1);
    expect(api.privateRadioCalls, 0);
    expect(state.audio.current?.id, 'cached-heart');
    expect(audio.queue.map((song) => song.id), <String>['cached-heart']);
    expect(state.discover.heart.map((song) => song.id), <String>[
      'cached-heart',
    ]);
    expect(state.error, isNull);
    state.dispose();
  });

  test('heartFmFirstPage 失败且本板块为空时只报错，不猜 privateRadio(mode: 2)', () async {
    final api = _HomeApi(
      DiscoverData(
        listen: <Song>[Song(id: 'listen-only', name: '现在就听')],
        radio: <Song>[Song(id: 'legacy-radio', name: '旧电台字段')],
        daily: <Song>[Song(id: 'daily-only', name: '每日')],
        hot: <Song>[Song(id: 'hot-only', name: '热歌')],
      ),
      heartError: const HuaweiException('HTTP 400'),
    );
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.loadHome();
    await state.playCard('heart');

    expect(api.heartFmCalls, 1);
    expect(api.privateRadioCalls, 0);
    expect(api.privateRadioMode2Calls, 0);
    expect(state.audio.current, isNull);
    expect(state.error, contains('「心动模式」独立板块未返回歌曲'));
    state.dispose();
  });

  test('缺少真实 ID 的歌曲不再生成时间戳假 ID', () {
    final song = HuaweiAPI.parseSong(<String, dynamic>{
      'contentName': '没有 code 的歌',
    });
    expect(song.id, isEmpty);
  });

  test('从心动切到 radio 会清空续播回调，listen 不会被当成心动续页', () async {
    final api = _HomeApi(
      DiscoverData(
        listen: <Song>[Song(id: 'listen-1', name: '现在就听')],
      ),
      heartPage: HuaweiPrivateFmPage(
        songs: <Song>[Song(id: 'heart-1', name: '心动')],
        next: 'heart-next-1',
        more: true,
        refInfo: 'heart-ref-1',
      ),
    );
    final player = _FakePlayer();
    final audio = MuyuAudioController(api, player: player);
    final state = AppState(
      sessionStore: MemorySessionStore(),
      huaweiApi: api,
      audioController: audio,
    );

    await state.loadHome();
    await state.playCard('heart');
    expect(state.audio.onQueueExhausted, isNotNull);

    await state.playCard('radio');

    expect(state.audio.onQueueExhausted, isNull);
    expect(state.audio.current?.id, 'listen-1');
    expect(api.privateFmRequests, isEmpty);
    expect(state.discover.listen.map((song) => song.id), <String>[
      'listen-1',
    ]);
    expect(state.discover.heart.map((song) => song.id), <String>['heart-1']);
    state.dispose();
  });

  test('全部档位 URL 都不是 30/60 秒试听片段', () async {
    final api = HuaweiAPI(gateway: _TierGateway());
    final files = await api.audioFiles(
      '1092974',
      upstreamQualities: const <AudioQuality>{
        AudioQuality.hiRes,
        AudioQuality.lossless,
        AudioQuality.standard,
      },
    );
    expect(files, isNotEmpty);
    for (final file in files) {
      expect(file.preview, isFalse);
      expect(file.url.toString(), isNot(contains('_AQ')));
      expect(file.url.toString(), isNot(contains('_PV')));
    }
  });
}
