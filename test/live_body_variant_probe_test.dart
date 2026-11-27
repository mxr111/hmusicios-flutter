// Opt-in live probe for request-body variants. Token comes only from the
// process environment and is never printed.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

class _Result {
  const _Result(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';

  test(
    'live privatefm / recommend-playlist / bycontentcode body variants',
    () async {
      final gateway = HuaweiGateway();
      gateway.session = MusicSession(token: token, snsUserId: 'probe');
      final client = HttpClient()..autoUncompress = true;

      String scrub(String input) {
        var s = input;
        s = s.replaceAll(
          RegExp(r'security:[^\s<>,;]+'),
          '***REDACTED***',
        );
        s = s.replaceAll(
          RegExp(
            r'Authorization\s*[:=]\s*[^,\r\n]+',
            caseSensitive: false,
          ),
          'Authorization=***REDACTED***',
        );
        s = s.replaceAll(
          RegExp(
            r'(?:access[_-]?token|refresh[_-]?token|music[_-]?token|huawei[_-]?token|token)\s*[:=]\s*[^,\s}]+',
            caseSensitive: false,
          ),
          'token=***REDACTED***',
        );
        s = s.replaceAllMapped(
          RegExp(r'(https?://[^\s?]+)\?[^\s]+'),
          (m) => '${m[1]}?***REDACTED***',
        );
        s = s.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
        s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
        if (s.length > 180) s = s.substring(0, 180);
        return s.trim();
      }

      String fieldTypes(Map<String, dynamic> body) => body.entries.map((e) {
        final v = e.value;
        final type = v is String
            ? 'String(len=${v.length})'
            : v.runtimeType.toString();
        return '${e.key}:$type';
      }).join('|');

      Future<_Result> post(String path, Map<String, dynamic> body) async {
        try {
          final uri = Uri.https(HuaweiPaths.host, path);
          final req = await client.postUrl(uri);
          gateway.headers().forEach((k, v) => req.headers.set(k, v));
          req.headers.contentType = ContentType.parse(
            'application/json;charset=UTF-8',
          );
          req.add(utf8.encode(jsonEncode(body)));
          final resp = await req.close();
          final bytes = await resp.fold<List<int>>(
            <int>[],
            (previous, chunk) => previous..addAll(chunk),
          );
          return _Result(
            resp.statusCode,
            utf8.decode(bytes, allowMalformed: true),
          );
        } catch (e) {
          return _Result(-1, scrub('request-error=$e'));
        }
      }

      Map<String, dynamic>? decode(String body) {
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map) return Map<String, dynamic>.from(decoded);
        } catch (_) {}
        return null;
      }

      String businessCode(Map<String, dynamic>? json) {
        if (json == null) return '-';
        final result = json['result'];
        final resultMap = result is Map
            ? Map<String, dynamic>.from(result)
            : <String, dynamic>{};
        final code =
            resultMap['resultCode'] ??
            json['resultCode'] ??
            json['code'] ??
            json['errorCode'];
        return code?.toString() ?? '-';
      }

      int countNamed(Map<String, dynamic>? json, List<String> keys) {
        if (json == null) return 0;
        for (final key in keys) {
          final count = HuaweiAPI.debugFindNamedList(json, key).length;
          if (count > 0) return count;
        }
        return 0;
      }

      bool hasKey(dynamic root, String key) {
        if (root is Map) {
          if (root.containsKey(key)) return true;
          for (final value in root.values) {
            if (hasKey(value, key)) return true;
          }
        } else if (root is List) {
          for (final value in root) {
            if (hasKey(value, key)) return true;
          }
        }
        return false;
      }

      Future<void> report(
        String endpoint,
        String id,
        Map<String, dynamic> body,
        List<String> countKeys, {
        bool privateFm = false,
        bool playUrl = false,
      }) async {
        final result = await post(endpoint, body);
        final json = decode(result.body);
        final hasPlayUrl = json != null &&
            (hasKey(json, 'fileURL') ||
                hasKey(json, 'fileUrl') ||
                hasKey(json, 'playURL') ||
                hasKey(json, 'url'));
        final count = playUrl
            ? (hasPlayUrl ? 1 : countNamed(json, countKeys))
            : countNamed(json, countKeys);
        final ok = result.statusCode == 200;
        final extra = StringBuffer();
        if (privateFm && ok) {
          extra.write(' next=${hasKey(json, 'next')}');
          extra.write(' more=${hasKey(json, 'more')}');
          extra.write(' refInfo=${hasKey(json, 'refInfo')}');
        }
        if (playUrl && ok) {
          extra.write(' url=$hasPlayUrl');
        }
        final error = ok
            ? '-'
            : scrub(result.body.isEmpty ? '<empty-body>' : result.body);
        // ignore: avoid_print
        print(
          'VARIANT endpoint=$endpoint id=$id '
          'fields=${fieldTypes(body)} http=${result.statusCode} '
          'code=${businessCode(json)} count=$count ok=$ok'
          '$extra err=$error',
        );
      }

      const privateFmKeys = <String>[
        'listRcmInfos',
        'songSimpleInfos',
        'contentSimpleInfos',
        'songs',
        'list',
        'data',
      ];
      const playlistKeys = <String>[
        'playListInfos',
        'playlistInfos',
        'contentSimpleInfos',
        'songList',
        'list',
        'data',
      ];
      const fileKeys = <String>['fileInfos', 'list', 'data'];

      try {
        final fmBase = <String, dynamic>{
          'cadence': '',
          'rcmMode': '1',
          'rcmScenario': '16',
          'refInfo': '',
        };
        await report(
          HuaweiPaths.privateFm,
          'A1',
          fmBase,
          privateFmKeys,
          privateFm: true,
        );
        await report(
          HuaweiPaths.privateFm,
          'A2',
          <String, dynamic>{...fmBase, 'rcmScenario': '21'},
          privateFmKeys,
          privateFm: true,
        );
        const refInfoVariants = <String, String>{
          'A3a': '0',
          'A3b': '{}',
          'A3c': '[]',
        };
        for (final entry in refInfoVariants.entries) {
          await report(
            HuaweiPaths.privateFm,
            entry.key,
            <String, dynamic>{...fmBase, 'refInfo': entry.value},
            privateFmKeys,
            privateFm: true,
          );
        }
        await report(
          HuaweiPaths.privateFm,
          'A4a',
          <String, dynamic>{...fmBase, 'next': ''},
          privateFmKeys,
          privateFm: true,
        );
        await report(
          HuaweiPaths.privateFm,
          'A4b',
          <String, dynamic>{...fmBase, 'next': '0'},
          privateFmKeys,
          privateFm: true,
        );
        for (final mode in const <String>['2', '3']) {
          for (final scenario in const <String>['16', '21']) {
            await report(
              HuaweiPaths.privateFm,
              'A5-$mode-$scenario',
              <String, dynamic>{
                ...fmBase,
                'rcmMode': mode,
                'rcmScenario': scenario,
              },
              privateFmKeys,
              privateFm: true,
            );
          }
        }

        final playlistCurrent = <String, dynamic>{
          'contentType': 1,
          'start': 0,
          'limit': 30,
        };
        final playlistCandidate = <String, dynamic>{
          'rcmScenario': '1',
          'termType': '1',
          'scenario': '1',
          'recommendStrategy': '0',
        };
        await report(
          HuaweiPaths.recommendPlaylist,
          'B1',
          playlistCurrent,
          playlistKeys,
        );
        await report(
          HuaweiPaths.recommendPlaylist,
          'B2',
          playlistCandidate,
          playlistKeys,
        );
        await report(
          HuaweiPaths.recommendPlaylist,
          'B3',
          <String, dynamic>{
            ...playlistCandidate,
            'contentType': '4',
            'start': '0',
            'limit': '30',
          },
          playlistKeys,
        );
        await report(
          HuaweiPaths.recommendPlaylist,
          'B4',
          <String, dynamic>{
            'contentType': '4',
            'start': '0',
            'limit': '30',
          },
          playlistKeys,
        );
        await report(
          HuaweiPaths.recommendPlaylist,
          'B5',
          <String, dynamic>{...playlistCandidate, 'countryCode': 'CN'},
          playlistKeys,
        );
        await report(
          HuaweiPaths.recommendPlaylist,
          'B6',
          <String, dynamic>{
            ...playlistCandidate,
            'contentType': '4',
            'start': '0',
            'limit': '30',
            'countryCode': 'CN',
          },
          playlistKeys,
        );

        await report(
          HuaweiPaths.playUrl,
          'C1',
          <String, dynamic>{
            'contentCode': '1092974',
            'contentType': '1',
            'qualityType': '1',
          },
          fileKeys,
          playUrl: true,
        );
      } finally {
        client.close(force: true);
      }
    },
    skip: token.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
