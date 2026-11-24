// Opt-in: MUYU_HUAWEI_TOKEN=security:... flutter test test/live_playback_scan_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';
  test('scan home songs playback availability', () async {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: token, snsUserId: 'probe');
    final api = HuaweiAPI(gateway: gateway);
    final home = await api.discover();
    // ignore: avoid_print
    print('HOME songs=${home.newSongs.length}');
    var printedRaw = 0;
    for (final song in home.newSongs.take(12)) {
      try {
        final files = await api.audioFiles(
          song.id,
          upstreamQualities: const <AudioQuality>{AudioQuality.standard},
        );
        // ignore: avoid_print
        print('OK ${song.name} [${song.id}] -> ${files.first.quality.name} '
            '${files.first.url.path.split('/').last}');
      } catch (e) {
        // ignore: avoid_print
        print('ERR ${song.name} [${song.id}] -> $e');
        if (printedRaw < 2) {
          printedRaw++;
          try {
            final raw = await gateway.request(
              '/music-play-service/v3/service/file/bycontentcode',
              body: <String, dynamic>{
                'contentCode': song.id,
                'contentType': '1',
                'qualityType': '1',
              },
            );
            // ignore: avoid_print
            print('RAW ${song.name} -> $raw');
          } catch (rawError) {
            // ignore: avoid_print
            print('RAW_ERR ${song.name} -> $rawError');
          }
        }
      }
    }

    final search = await api.searchAll('周杰伦');
    for (final song in search.songs.take(3)) {
      try {
        final files = await api.audioFiles(song.id);
        // ignore: avoid_print
        print('SEARCH_OK ${song.name} -> ${files.first.quality.name} '
            '${files.first.url.path.split('/').last}');
      } catch (e) {
        // ignore: avoid_print
        print('SEARCH_ERR ${song.name} [${song.id}] -> $e');
      }
    }
    final chart = await api.chartSongs('24926');
    for (final song in chart.take(3)) {
      try {
        final files = await api.audioFiles(song.id);
        // ignore: avoid_print
        print('CHART_OK ${song.name} -> ${files.first.quality.name} '
            '${files.first.url.path.split('/').last}');
      } catch (e) {
        // ignore: avoid_print
        print('CHART_ERR ${song.name} [${song.id}] -> $e');
      }
    }
  }, skip: token.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}
