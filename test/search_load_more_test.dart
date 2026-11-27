import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';
import 'package:muyu_flutter/services/app_state.dart';
import 'package:muyu_flutter/services/audio_controller.dart';
import 'package:muyu_flutter/services/session_store.dart';

class _NoopPlayer extends AudioPlayer {
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

class _SearchApi extends HuaweiAPI {
  _SearchApi() : super(gateway: HuaweiGateway());

  final List<int> starts = <int>[];
  final List<int> limits = <int>[];
  final List<bool> includePlaylistsCalls = <bool>[];
  bool failMore = false;

  Song song(String id) => Song(
    id: id,
    name: id,
    qualities: const <AudioQuality>{AudioQuality.standard},
  );

  Artist artist(String id) => Artist(id: id, name: id);

  Playlist playlist(String id) => Playlist(id: id, name: id);

  @override
  Future<HuaweiSearchResult> searchAll(
    String keyword, {
    int start = 0,
    int limit = 30,
    bool includePlaylists = true,
  }) async {
    starts.add(start);
    limits.add(limit);
    includePlaylistsCalls.add(includePlaylists);
    if (failMore && start > 0) {
      throw const HuaweiException('搜索加载更多失败');
    }
    if (start == 0) {
      return HuaweiSearchResult(
        songs: <Song>[for (var i = 0; i < 30; i++) song('song-$i')],
        artists: <Artist>[artist('artist-0')],
        albums: <Playlist>[playlist('album-0')],
        playlists: <Playlist>[playlist('playlist-0'), playlist('playlist-1')],
      );
    }
    return HuaweiSearchResult(
      songs: <Song>[
        song('song-29'),
        song('song-30'),
        song('song-31'),
        song('song-31'),
      ],
      artists: <Artist>[artist('artist-0'), artist('artist-1')],
      albums: <Playlist>[playlist('album-1')],
      playlists: <Playlist>[
        playlist('playlist-1'),
        playlist('playlist-2'),
        playlist('playlist-3'),
      ],
    );
  }
}

AppState _state(_SearchApi api) {
  final audio = MuyuAudioController(api, player: _NoopPlayer());
  return AppState(
    sessionStore: MemorySessionStore(),
    huaweiApi: api,
    audioController: audio,
  );
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
  });

  test('loadMoreSearch 按 start/limit 分页、四类去重追加并更新 hasMore', () async {
    final api = _SearchApi();
    final state = _state(api);

    await state.doSearch('周杰伦');
    expect(state.searchStart, 30);
    expect(state.hasMoreSearch, isTrue);
    expect(state.searchResults.length, 30);
    expect(state.searchPlaylists.length, 2);

    await state.loadMoreSearch();

    expect(api.starts, <int>[0, 30]);
    expect(api.limits, <int>[30, 30]);
    expect(api.includePlaylistsCalls, <bool>[true, true]);
    expect(state.searchResults.map((song) => song.id).toList(), <String>[
      for (var i = 0; i < 30; i++) 'song-$i',
      'song-30',
      'song-31',
    ]);
    expect(state.searchArtists.map((artist) => artist.id).toList(), <String>[
      'artist-0',
      'artist-1',
    ]);
    expect(state.searchAlbums.map((album) => album.id).toList(), <String>[
      'album-0',
      'album-1',
    ]);
    expect(state.searchPlaylists.map((playlist) => playlist.id).toList(), <String>[
      'playlist-0',
      'playlist-1',
      'playlist-2',
      'playlist-3',
    ]);
    expect(state.hasMoreSearch, isFalse);
    expect(state.loadingMoreSearch, isFalse);
    expect(state.searchStart, 60);
    expect(state.error, isNull);
    state.dispose();
  });

  test('loadMoreSearch 失败保留已有列表和游标，error 可读', () async {
    final api = _SearchApi();
    final state = _state(api);

    await state.doSearch('周杰伦');
    final before = state.searchResults.map((song) => song.id).toList();
    api.failMore = true;

    await state.loadMoreSearch();

    expect(state.searchResults.map((song) => song.id).toList(), before);
    expect(state.hasMoreSearch, isTrue);
    expect(state.searchStart, 30);
    expect(state.loadingMoreSearch, isFalse);
    expect(state.error, '搜索加载更多失败');
    expect(state.error, isNot(contains('Bad state:')));
    state.dispose();
  });
}
