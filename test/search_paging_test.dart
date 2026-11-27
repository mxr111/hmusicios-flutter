import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

class _SearchGateway extends HuaweiGateway {
  _SearchGateway({this.failTypes = const <String>{}});

  final Set<String> failTypes;
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const <String, dynamic>{},
  }) async {
    if (path != HuaweiPaths.search) {
      throw StateError('unexpected post $path');
    }
    bodies.add(Map<String, dynamic>.from(body));
    final type = '${body['contentType']}';
    if (failTypes.contains(type)) {
      throw const HuaweiException('HTTP 400');
    }
    switch (type) {
      case '2':
        return <String, dynamic>{
          'albumSimpleInfos': <dynamic>[
            <String, dynamic>{'albumID': 'al-1', 'albumName': '专辑一'},
          ],
        };
      case '3':
        return <String, dynamic>{
          'artistSimpleInfos': <dynamic>[
            <String, dynamic>{'artistID': 'ar-1', 'artistName': '歌手一'},
          ],
        };
      case '4':
        return <String, dynamic>{
          'playListInfos': <dynamic>[
            <String, dynamic>{
              'playListID': 'pl-1',
              'playListName': '歌单一',
              'songNum': 42,
            },
          ],
        };
      default:
        return <String, dynamic>{
          'songSimpleInfos': <dynamic>[
            <String, dynamic>{'contentID': 'song-1', 'contentName': '歌曲一'},
          ],
        };
    }
  }
}

void main() {
  test('searchAll 按 start/limit 字符串字段分页并请求 contentType=1/2/3/4', () async {
    final gateway = _SearchGateway();
    final api = HuaweiAPI(gateway: gateway);

    await api.searchAll('周杰伦', start: 30, limit: 30);

    expect(gateway.bodies.length, 4);
    expect(
      gateway.bodies.map((body) => body['contentType']).toSet(),
      <String>{'1', '2', '3', '4'},
    );
    for (final body in gateway.bodies) {
      expect(body['correct'], '1');
      expect(body['queryWord'], '周杰伦');
      expect(body['start'], '30');
      expect(body['limit'], '30');
    }
  });

  test('contentType=4 歌单解析到 result.playlists', () async {
    final api = HuaweiAPI(gateway: _SearchGateway());
    final result = await api.searchAll('周杰伦');

    expect(result.playlists.single.id, 'pl-1');
    expect(result.playlists.single.name, '歌单一');
    expect(result.playlists.single.songCount, 42);
    expect(result.playlists.single.kind, 'playlist');
  });

  test('单类失败只留该类空结果，其他类型继续', () async {
    final api = HuaweiAPI(
      gateway: _SearchGateway(failTypes: const <String>{'3'}),
    );
    final result = await api.searchAll('周杰伦');

    expect(result.songs.single.id, 'song-1');
    expect(result.albums.single.id, 'al-1');
    expect(result.playlists.single.id, 'pl-1');
    expect(result.artists, isEmpty);
  });

  test('全部类型失败时抛可读错误，不静默返回空结果', () async {
    final api = HuaweiAPI(
      gateway: _SearchGateway(
        failTypes: const <String>{'1', '2', '3', '4'},
      ),
    );

    await expectLater(
      api.searchAll('周杰伦'),
      throwsA(
        isA<HuaweiException>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('华为搜索失败'), contains('1/2/3/4')),
        ),
      ),
    );
  });

  test('includePlaylists=false 时不请求 contentType=4', () async {
    final gateway = _SearchGateway();
    final api = HuaweiAPI(gateway: gateway);

    final result = await api.searchAll('周杰伦', includePlaylists: false);

    expect(result.playlists, isEmpty);
    expect(
      gateway.bodies.map((body) => body['contentType']),
      isNot(contains('4')),
    );
  });
}
