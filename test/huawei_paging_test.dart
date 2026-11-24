import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

/// 模拟分页接口：总数固定，短页结束。
class _PagedGateway extends HuaweiGateway {
  _PagedGateway({this.favoriteTotal = 137});

  final int favoriteTotal;
  static const int artistTotal = 73;
  final List<int> favoriteStarts = <int>[];
  final List<int> artistStarts = <int>[];

  Map<String, dynamic> _song(int i) => <String, dynamic>{
        'contentID': 'song-$i',
        'contentName': '歌曲 $i',
        'artistNamePairs': <Map<String, dynamic>>[
          <String, dynamic>{'artistID': 'artist-1', 'artistName': '歌手'},
        ],
      };

  List<Map<String, dynamic>> _page(int total, int start, int limit) {
    final end = (start + limit) > total ? total : start + limit;
    return <Map<String, dynamic>>[
      for (var i = start; i < end; i++) _song(i),
    ];
  }

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    if (path == HuaweiPaths.favorites) {
      final start = body['start'] as int? ?? 0;
      final limit = body['limit'] as int? ?? 50;
      favoriteStarts.add(start);
      return <String, dynamic>{
        'favoriteInfos': _page(favoriteTotal, start, limit),
      };
    }
    if (path == HuaweiPaths.artistSongs) {
      throw StateError('artistSongs should use GET');
    }
    if (path == HuaweiPaths.search) {
      switch ('${body['contentType']}') {
        case '2':
          return <String, dynamic>{
            'albumSimpleInfos': <Map<String, dynamic>>[
              <String, dynamic>{
                'contentID': 'al1',
                'contentName': '叶惠美',
                'totalCount': 11,
              },
            ],
          };
        case '3':
          return <String, dynamic>{
            'artistSimpleInfos': <Map<String, dynamic>>[
              <String, dynamic>{
                'artistCode': 'a1',
                'artistName': '周杰伦',
                'bigImgURL': 'https://test.dbankcdn.cn/a.jpg',
              },
            ],
          };
        default:
          return <String, dynamic>{
            'songSimpleInfos': <Map<String, dynamic>>[
              <String, dynamic>{'contentID': 's1', 'contentName': '晴天'},
            ],
          };
      }
    }
    throw StateError('unexpected path: $path');
  }

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path.startsWith(HuaweiPaths.artistSongs)) {
      final uri = Uri.parse('https://x$path');
      final start = int.tryParse(uri.queryParameters['start'] ?? '0') ?? 0;
      final limit = int.tryParse(uri.queryParameters['limit'] ?? '30') ?? 30;
      artistStarts.add(start);
      return <String, dynamic>{
        'songSimpleInfos': _page(artistTotal, start, limit),
      };
    }
    throw StateError('unexpected get: $path');
  }
}

void main() {
  test('收藏全量分页：不截断在前 50 首', () async {
    final gateway = _PagedGateway(favoriteTotal: 137);
    final api = HuaweiAPI(gateway: gateway);
    final songs = await api.favorites();

    expect(songs.length, 137);
    expect(songs.first.id, 'song-0');
    expect(songs.last.id, 'song-136');
    // 50 + 50 + 37，第三次短页后停止。
    expect(gateway.favoriteStarts, <int>[0, 50, 100]);
  });

  test('歌手歌曲全量分页', () async {
    final gateway = _PagedGateway();
    final api = HuaweiAPI(gateway: gateway);
    final songs = await api.artistSongs('artist-1');

    expect(songs.length, 73);
    expect(gateway.artistStarts, <int>[0, 50]);
  });

  test('分页遇到重复内容会停止，不会无限循环', () async {
    final gateway = _StuckGateway();
    final api = HuaweiAPI(gateway: gateway);
    final songs = await api.favorites();

    expect(songs.length, 50);
    expect(gateway.calls, 2);
  });

  test('搜索同时解析歌曲 / 歌手 / 专辑', () async {
    final api = HuaweiAPI(gateway: _PagedGateway());
    final result = await api.searchAll('周杰伦');

    expect(result.songs.single.name, '晴天');
    expect(result.artists.single.name, '周杰伦');
    expect(result.artists.single.id, 'a1');
    expect(result.albums.single.name, '叶惠美');
    expect(result.albums.single.kind, 'album');
    expect(result.albums.single.songCount, 11);
  });
}

/// 服务端忽略 start，每次都返回同一页。
class _StuckGateway extends HuaweiGateway {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> request(String path,
      {Map<String, dynamic> body = const <String, dynamic>{}}) async {
    calls++;
    return <String, dynamic>{
      'favoriteInfos': <Map<String, dynamic>>[
        for (var i = 0; i < 50; i++)
          <String, dynamic>{'contentID': 'same-$i', 'contentName': '歌 $i'},
      ],
    };
  }
}
