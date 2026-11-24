import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
import 'package:muyu_flutter/protocol/netease_gateway.dart';

void main() {
  test('weapi 加密产出 params/encSecKey/csrf_token 三个字段', () {
    final gw = NeteaseGateway();
    final form = gw.weapiForm(<String, dynamic>{
      's': '测试',
      'type': 1,
    });
    expect(form.containsKey('params'), isTrue);
    expect(form['params']!.isNotEmpty, isTrue);
    expect(form.containsKey('encSecKey'), isTrue);
    expect(form.containsKey('csrf_token'), isTrue);
    gw.dispose();
  });

  test('weapi encSecKey 为 128 字节 RSA hex（网易云 weapi 标准长度）', () {
    final gw = NeteaseGateway();
    final enc = gw.weapiForm(<String, dynamic>{'id': 123})['encSecKey']!;
    expect(enc.length, 256); // 1024-bit RSA = 128 字节 = 256 hex 字符
    expect(enc, matches(RegExp(r'^[0-9a-f]+$')));
    gw.dispose();
  });

  test('华为/Netease 共用音质模型：网易 level → 档位', () {
    expect(AudioQuality.fromCode('standard'), AudioQuality.standard);
    expect(AudioQuality.fromCode('exhigh'), AudioQuality.lossless);
    expect(AudioQuality.fromCode('hires'), AudioQuality.hiRes);
    expect(AudioQuality.fromBitrate(990000), AudioQuality.hiRes);
  });
}
