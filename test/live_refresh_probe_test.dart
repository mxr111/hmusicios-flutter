// Opt-in: MUYU_HUAWEI_TOKEN=security:... flutter test test/live_refresh_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';
  test('home refresh params', () async {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: token, snsUserId: 'probe');
    final now = DateTime.now().millisecondsSinceEpoch;
    final variants = <String, String>{
      'base': HuaweiPaths.home,
      't': '${HuaweiPaths.home}&_t=$now',
      'requestId': '${HuaweiPaths.home}&requestId=$now',
      'refresh': '${HuaweiPaths.home}&refresh=1',
      'timestamp': '${HuaweiPaths.home}&timestamp=$now',
      'page2': '${HuaweiPaths.home}&pageNum=2',
    };
    for (final entry in variants.entries) {
      try {
        final json = await gateway.get(entry.value);
        final data = HuaweiAPI.parseDiscover(json);
        // ignore: avoid_print
        print('${entry.key}: ${data.newSongs.take(4).map((s) => '${s.id}:${s.name}').toList()}');
      } catch (e) {
        // ignore: avoid_print
        print('${entry.key}: ERR $e');
      }
    }
  }, skip: token.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}
