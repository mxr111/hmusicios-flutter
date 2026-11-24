import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/kugou_api.dart';

void main() {
  const hash = '0123456789ABCDEF0123456789ABCDEF';
  const flacHash = 'ABCDEF0123456789ABCDEF0123456789';
  const highHash = 'FEDCBA9876543210FEDCBA9876543210';

  test('酷狗安卓签名：盐包裹 + key 排序 + UTF-8 MD5', () {
    expect(
      kugouSignature(<String, String>{'z': '中文', 'a': '1'}),
      '13ce91da070687f4ece7f615ba458ddf',
    );
    expect(
      kugouSignature(
        <String, String>{'hash': hash},
        body: '{"page":1}',
        salt: 'test-salt',
      ),
      isNot(kugouSignature(<String, String>{'hash': hash}, salt: 'test-salt')),
    );
  });

  test('v5/url 的 key 参数使用 hash+salt+appid+mid+userid', () {
    expect(
      kugouPlaybackKey(hash: hash, mid: 'mid123', userId: '0'),
      'ed43485067b49fd0678338efaa8351b7',
    );
  });

  test('搜索 URL 使用真实端点、签名和正确编码', () {
    final uri = KugouGateway.searchUri(
      keyword: '周杰伦',
      page: 2,
      pageSize: 15,
      mid: 'mid123',
      dfid: 'dfid123',
      clientTime: '1700000000',
    );

    expect(uri.host, 'complexsearch.kugou.com');
    expect(uri.path, '/v2/search/song');
    expect(uri.queryParameters['keyword'], '周杰伦');
    expect(uri.queryParameters['page'], '2');
    expect(uri.queryParameters['pagesize'], '15');
    expect(uri.queryParameters['platform'], 'AndroidFilter');
    expect(uri.queryParameters['clienttime'], '1700000000');
    expect(uri.queryParameters['signature'], hasLength(32));

    final unsigned = Map<String, String>.from(uri.queryParameters)
      ..remove('signature');
    expect(uri.queryParameters['signature'], kugouSignature(unsigned));
  });

  test('v5/url 构造带 album_audio_id、key 和 signature', () {
    final uri = KugouGateway.urlUri(
      hash: hash,
      albumAudioId: '987654',
      albumId: '123',
      quality: 'flac',
      mid: 'mid123',
      dfid: 'dfid123',
      userId: '42',
      clientTime: '1700000000',
    );

    expect(uri.host, 'gateway.kugou.com');
    expect(uri.path, '/v5/url');
    expect(uri.queryParameters['hash'], hash);
    expect(uri.queryParameters['album_audio_id'], '987654');
    expect(uri.queryParameters['album_id'], '123');
    expect(uri.queryParameters['quality'], 'flac');
    expect(uri.queryParameters['key'], hasLength(32));
    expect(
      uri.queryParameters['key'],
      kugouPlaybackKey(hash: hash, mid: 'mid123', userId: '42'),
    );

    final unsigned = Map<String, String>.from(uri.queryParameters)
      ..remove('signature');
    expect(uri.queryParameters['signature'], kugouSignature(unsigned));
  });

  test('getdata、歌词搜索和下载 URL 来自真实端点', () {
    final getdata = KugouGateway.getdataUri(
      hash: hash,
      albumId: '123',
      mid: 'mid123',
    );
    expect(getdata.host, 'wwwapi.kugou.com');
    expect(getdata.queryParameters['r'], 'play/getdata');
    expect(getdata.queryParameters['platid'], '4');

    final search = KugouGateway.lyricsSearchUri(hash: hash, durationMs: 269000);
    expect(search.host, 'krcs.kugou.com');
    expect(search.path, '/search');
    expect(search.queryParameters['hash'], hash);

    final download = KugouGateway.lyricsDownloadUri(
      id: '88',
      accessKey: 'key',
      format: 'krc',
    );
    expect(download.host, 'krcs.kugou.com');
    expect(download.path, '/download');
    expect(download.queryParameters['fmt'], 'krc');
  });

  test('Cookie Map 兼容逐项字段和整段 Cookie', () {
    final session = KugouSession.fromCookies(<String, dynamic>{
      'Cookie': 'token=t1; userid=42; dfid=d1; mid=m1; nickname=小明',
    });
    expect(session.token, 't1');
    expect(session.userId, '42');
    expect(session.dfid, 'd1');
    expect(session.mid, 'm1');
    expect(session.nickname, '小明');
    expect(session.cookieHeader, contains('token=t1'));
    expect(session.cookieHeader, contains('userid=42'));
  });

  test('登录状态与 displayName 来自手动 Cookie', () {
    final gateway = KugouGateway(mid: 'fixed-mid');
    final api = KugouApi(gateway: gateway);
    expect(api.isLoggedIn, isFalse);

    api.signInWithCookies(<String, dynamic>{
      'token': 'token-1',
      'userid': '42',
      'dfid': 'dfid-1',
      'mid': 'fixed-mid',
      'nickname': '酷狗用户',
    });
    expect(api.isLoggedIn, isTrue);
    expect(api.displayName, '酷狗用户');

    api.signOut();
    expect(api.isLoggedIn, isFalse);
    gateway.dispose();
  });

  test('搜索响应按 data.info 解析真实字段', () {
    final songs = KugouApi.parseSearchSongs(<String, dynamic>{
      'data': <String, dynamic>{
        'info': <dynamic>[
          <String, dynamic>{
            'hash': hash,
            'songname': '晴天',
            'singername': '周杰伦',
            'album_name': '叶惠美',
            'duration': 269,
            'album_id': '123',
            'audio_id': 987654,
            'privilege': 10,
            'hash_flac': flacHash,
            'hash_high': highHash,
            'img': 'http://imge.kugou.com/{size}/cover.jpg',
          },
        ],
      },
    });

    expect(songs, hasLength(1));
    final song = songs.single;
    expect(song.id, hash);
    expect(song.name, '晴天');
    expect(song.album, '叶惠美');
    expect(song.artistText, '周杰伦');
    expect(song.durationMs, 269000);
    expect(
      song.qualities,
      containsAll(<AudioQuality>[
        AudioQuality.standard,
        AudioQuality.lossless,
        AudioQuality.hiRes,
      ]),
    );
    expect(song.cover.toString(), 'https://imge.kugou.com/400/cover.jpg');
    expect(song.source, MusicSourceLabel.kugou);
  });

  test('歌单响应按 data.info 解析并保留封面/数量', () {
    final playlists = KugouApi.parsePlaylists(<String, dynamic>{
      'data': <String, dynamic>{
        'info': <dynamic>[
          <String, dynamic>{
            'global_collection_id': 'collection_3_1_2_0',
            'listname': '我喜欢的音乐',
            'count': 12,
            'pic_url': 'http://imge.kugou.com/{size}/list.jpg',
          },
        ],
      },
    }, kind: 'owned');

    expect(playlists, hasLength(1));
    expect(playlists.single.id, 'collection_3_1_2_0');
    expect(playlists.single.name, '我喜欢的音乐');
    expect(playlists.single.songCount, 12);
    expect(playlists.single.kind, 'owned');
    expect(
      playlists.single.cover.toString(),
      'https://imge.kugou.com/400/list.jpg',
    );
  });

  test('评论响应按 commentlist 解析并容错', () {
    final comments = KugouApi.parseComments(<String, dynamic>{
      'data': <String, dynamic>{
        'commentlist': <dynamic>[
          <String, dynamic>{
            'commentid': 1,
            'content': '好听',
            'nick': '小明',
            'avatarurl': 'https://imge.kugou.com/avatar.jpg',
            'addtime': 1700000000,
            'praisenum': 3,
          },
          <String, dynamic>{'content': ''},
        ],
      },
    });

    expect(comments, hasLength(1));
    expect(comments.single.content, '好听');
    expect(comments.single.author, '小明');
    expect(comments.single.likes, 3);
    expect(comments.single.time, isNotEmpty);
  });

  test('取流响应兼容 url 数组、大小和试听过滤', () {
    final files = KugouApi.parseAudioFiles(<String, dynamic>{
      'data': <dynamic>[
        <String, dynamic>{
          'url': <String>['https://fs.kugou.com/a.flac'],
          'bitrate': 990000,
          'extname': 'flac',
          'filesize': 12345,
        },
        <String, dynamic>{
          'url': 'https://fs.kugou.com/trial.mp3',
          'is_free_part': 1,
        },
      ],
    }, quality: AudioQuality.hiRes);

    expect(files, hasLength(1));
    expect(files.single.quality, AudioQuality.hiRes);
    expect(files.single.sizeBytes, 12345);
    expect(files.single.url.toString(), 'https://fs.kugou.com/a.flac');
  });

  test('歌词同时支持 LRC 与 KRC 逐字行', () {
    final lrc = KugouApi.parseLyrics('[00:01.50]第一行\n[00:03.00]第二行');
    expect(lrc, hasLength(2));
    expect(lrc.first.time, const Duration(milliseconds: 1500));
    expect(lrc.last.text, '第二行');

    final krc = KugouApi.parseLyrics('[1000,500]<0,200,0>你<200,300,0>好');
    expect(krc, hasLength(1));
    expect(krc.single.text, '你好');
    expect(krc.single.words, hasLength(2));
    expect(krc.single.words.first.time, const Duration(milliseconds: 1000));
    expect(krc.single.words.last.time, const Duration(milliseconds: 1200));
  });
}
