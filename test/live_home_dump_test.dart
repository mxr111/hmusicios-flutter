// Opt-in live probe:
//   MUYU_HUAWEI_TOKEN=security:... flutter test test/live_home_dump_test.dart
// Prints the real home column shape + recommendation sources. Never hardcodes
// a token; skipped in CI.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';

  test('live home columns and playback quality', () async {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: token, snsUserId: 'probe');
    final api = HuaweiAPI(gateway: gateway);

    final raw = await gateway.get(HuaweiPaths.home);
    final columns = HuaweiAPI.debugFindNamedList(raw, 'columnInfoExs');
    // ignore: avoid_print
    print('HOME columns=${columns.length}');
    for (final column in columns) {
      final info = column['columnInfo'];
      final infoMap = info is Map ? Map<String, dynamic>.from(info) : null;
      final contents = HuaweiAPI.debugFindNamedList(
          column, 'contentSimpleInfos');
      // ignore: avoid_print
      print(
        'HOME COL key=${infoMap?['columnKey']} id=${infoMap?['contentID']} '
        'name=${infoMap?['contentName']} type=${infoMap?['contentType']} '
        'view=${infoMap?['viewType']} contents=${contents.length}',
      );
      for (final content in contents.take(8)) {
        // ignore: avoid_print
        print(
          '  content type=${content['contentType']} id=${content['contentID'] ?? content['contentId']} '
          'name=${content['contentName'] ?? content['name']} '
          'child=${HuaweiAPI.debugFindNamedList(content, 'childSimpleInfos').length} '
          'rcm=${HuaweiAPI.debugFindNamedList(content, 'listRcmInfos').length} '
          'songs=${HuaweiAPI.debugFindNamedList(content, 'songSimpleInfos').length}',
        );
      }
    }

    final data = await api.discover();
    // ignore: avoid_print
    print(
      'DISCOVER new=${data.newSongs.length} rec=${data.recommended.length} '
      'listen=${data.listen.length} heart=${data.heart.length} '
      'hot=${data.hot.length} radio=${data.radio.length} '
      'playlists=${data.playlists.length} charts=${data.charts.length} '
      'column=${data.recommendedColumnId}',
    );
    for (final song in data.recommended.take(8)) {
      // ignore: avoid_print
      print('REC ${song.id} ${song.name} qualities=${song.qualities}');
    }

    final probes = <String>[
      '?columnId=8011&start=0&limit=30&hasRecommend=1',
      '?columnID=8011&start=0&limit=30&hasRecommend=1',
      '?columnId=NokMgDwyY3Y-i_Gln&start=0&limit=30&hasRecommend=1',
    ];
    for (final query in probes) {
      try {
        final json = await gateway.get(
          '/music-operation-service/v1/service/column/detail/bycolumnid$query',
        );
        final songs = HuaweiAPI.debugFindNamedList(json, 'listRcmInfos');
        final content = HuaweiAPI.debugFindNamedList(
            json, 'contentSimpleInfos');
        // ignore: avoid_print
        print(
          'COLUMN PROBE $query keys=${json.keys.toList()} '
          'content=${content.length} rcm=${songs.length} '
          'rcmNames=${songs.take(5).map((e) => e['name'] ?? e['contentName']).toList()}',
        );
      } catch (e) {
        // ignore: avoid_print
        print('COLUMN PROBE $query ERR $e');
      }
      try {
        final json = await gateway.get(
          '/music-operation-service/v1/service/column/detail/bycolumnid$query',
        );
        // ignore: avoid_print
        print('COLUMN BODY $query ${json.toString()}');
      } catch (_) {}
    }

    for (final mode in const <String>['1', '2', '3']) {
      try {
        final songs = await api.privateRadio(mode: mode);
        // ignore: avoid_print
        print('PRIVATE FM mode=$mode count=${songs.length} '
            'first=${songs.take(3).map((s) => s.name).toList()}');
      } catch (e) {
        // ignore: avoid_print
        print('PRIVATE FM mode=$mode ERR $e');
      }
    }

    for (final id in const <String>['a001', 'a003', 'a004', 'a006']) {
      try {
        final songs = await api.playlistSongs(
          Playlist(id: id, name: id, kind: 'collected'),
          fetchAll: false,
          limit: 30,
        );
        // ignore: avoid_print
        print('PLAYLIST $id count=${songs.length} '
            'first=${songs.take(3).map((s) => '${s.name}(${s.qualities})').toList()}');
      } catch (e) {
        // ignore: avoid_print
        print('PLAYLIST $id ERR $e');
      }
    }

    final seed = data.recommended.isNotEmpty
        ? data.recommended.first
        : (data.listen.isNotEmpty
            ? data.listen.first
            : (data.newSongs.isNotEmpty ? data.newSongs.first : null));
    if (seed == null) {
      // ignore: avoid_print
      print('NO SEED SONG');
      return;
    }
    // ignore: avoid_print
    print('SEED ${seed.id} ${seed.name} qualities=${seed.qualities}');
    for (final code in const <String>['1', '2', '3', '5', '7']) {
      try {
        final json = await gateway.request(
          HuaweiPaths.playUrl,
          body: <String, dynamic>{
            'contentCode': seed.id,
            'contentType': '1',
            'qualityType': code,
          },
        );
        final result = json['result'];
        final url = HuaweiGateway.firstUrl(json, const [
          'fileURL',
          'fileUrl',
          'playURL',
          'url',
        ]);
        // ignore: avoid_print
        print(
          'PLAY q=$code result=$result quality=${json['playQuality'] ?? json['qualityType']} '
          'size=${json['size'] ?? json['fileSize']} url=${url?.host}${url?.path} '
          'audition=${json['auditionEnd']} fragment=${json['playFragmentFlag']}',
        );
      } catch (e) {
        // ignore: avoid_print
        print('PLAY q=$code ERR $e');
      }
    }
  }, skip: token.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}
