// Opt-in: MUYU_HUAWEI_TOKEN=security:... flutter test test/live_account_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  final token = Platform.environment['MUYU_HUAWEI_TOKEN'] ?? '';
  test('huawei account profile endpoints', () async {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: token, snsUserId: 'probe');
    final attempts = <String, Future<Map<String, dynamic>> Function()>{
      'userinfo GET': () =>
          gateway.get('/music-odpapp-service/v5/service/userinfo'),
      'userinfo POST': () => gateway.request(
            '/music-odpapp-service/v5/service/userinfo',
            body: const <String, dynamic>{},
          ),
      'userconfig': () => gateway.request(
            '/music-user-service/v1/service/userconfig/detail/all',
            body: const <String, dynamic>{},
          ),
      'subscription': () => gateway.request(
            '/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6',
          ),
      'userconfig GET': () =>
          gateway.get('/music-user-service/v1/service/userconfig/detail/all'),
      'subscription GET': () => gateway.get(
          '/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6'),
      'userinfo get': () =>
          gateway.get('/music-odpapp-service/v5/service/userinfo/get'),
      'userinfo detail': () =>
          gateway.get('/music-odpapp-service/v5/service/userinfo/detail'),
      'userinfo service': () =>
          gateway.get('/music-user-service/v1/service/userinfo'),
    };
    for (final entry in attempts.entries) {
      try {
        final json = await entry.value();
        // ignore: avoid_print
        print('${entry.key}: OK keys=${json.keys.take(20).toList()}');
        // ignore: avoid_print
        print('${entry.key}: $json');
      } catch (e) {
        // ignore: avoid_print
        print('${entry.key}: ERR $e');
      }
    }
  }, skip: token.isEmpty, timeout: const Timeout(Duration(minutes: 3)));
}
