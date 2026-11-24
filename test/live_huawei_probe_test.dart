// Opt-in live probe. Run with a real music token:
//   $env:MUYU_HUAWEI_TOKEN='security:...'
//   flutter test test/live_huawei_probe_test.dart
// Without the env var the test is skipped, so CI stays offline.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';

  test('live Huawei v5 + home + search + playback', () async {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: token, snsUserId: 'probe');
    final api = HuaweiAPI(gateway: gateway);

    final favorites = await api.favorites(fetchAll: false, limit: 3);
    expect(favorites, isNotEmpty);

    final home = await api.discover();
    expect(home.newSongs, isNotEmpty);
    expect(home.playlists, isNotEmpty);
    expect(home.charts, isNotEmpty);
    expect(home.newSongs.first.cover, isNotNull);

    final search = await api.searchAll('周杰伦');
    expect(search.songs, isNotEmpty);
    expect(search.artists, isNotEmpty);
    expect(search.albums, isNotEmpty);

    final daily = await api.playlistSongs(
      const Playlist(id: 'a001', name: '每日30首', kind: 'collected'),
      fetchAll: false,
      limit: 5,
    );
    expect(daily, isNotEmpty);

    final albumTracks = await api.albumSongs(search.albums.first.id);
    expect(albumTracks, isNotEmpty);

    final artist = await api.artistDetail(search.artists.first.id);
    expect(artist.name, isNotEmpty);
    final artistTracks = await api.artistSongs(search.artists.first.id);
    expect(artistTracks, isNotEmpty);

    final files = await api.audioFiles(favorites.first.id);
    expect(files, isNotEmpty);
    expect(files.first.url.toString(), contains('http'));

    // Hi-Res 无权限时网关会给 30s 试听；必须回退到完整档位而不是试听。
    final hiRes = await api.audioFiles(favorites.first.id,
        upstreamQualities: const <AudioQuality>{AudioQuality.hiRes});
    expect(hiRes, isNotEmpty);
    expect(hiRes.first.url.path.toLowerCase(), isNot(contains('_aq')));
    expect(hiRes.first.url.path.toLowerCase(), isNot(contains('_pv')));
  }, skip: token.isEmpty, timeout: const Timeout(Duration(minutes: 2)));
}
