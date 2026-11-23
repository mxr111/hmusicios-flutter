// 协议回归测试：重点验证 REA 运行时取证发现的 URL 拼接规则。
// 早期 iOS 版把带 ?query 的路径当 path component 拼接，导致 ? 被编码成 %3F → HTTP 404。

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

void main() {
  test('makeUrl 保留 query 且不编码问号', () {
    final gateway = HuaweiGateway();
    final uri = gateway.makeUrl(
      '/music-operation-service/v1/service/page/detail/all?pageType=7&hasRecommend=1',
    );
    expect(uri.scheme, 'https');
    expect(uri.host, 'api-drcn.music.dbankcloud.cn');
    expect(uri.path, '/music-operation-service/v1/service/page/detail/all');
    expect(uri.query, 'pageType=7&hasRecommend=1');
    expect(uri.toString().contains('%3F'), isFalse);
    gateway.dispose();
  });

  test('makeUrl 支持重复参数与完整 URL', () {
    final gateway = HuaweiGateway();
    final subscription = gateway.makeUrl(
      '/music-order-service/v4/service/subscription/detail?domainTypes=1&domainTypes=6',
    );
    expect(subscription.query, 'domainTypes=1&domainTypes=6');
    final full = gateway.makeUrl('https://cdn.example.com/a.lrc?token=x');
    expect(full.host, 'cdn.example.com');
    gateway.dispose();
  });

  test('parseLrc 解析时间轴与文本', () {
    final lines = HuaweiAPI.parseLrc('[00:12.34]第一行\n[01:02]第二行');
    expect(lines.length, 2);
    expect(lines[0].text, '第一行');
    expect(lines[0].time.inMilliseconds, 12340);
    expect(lines[1].text, '第二行');
  });

  test('容错解析不因字段缺失而失败', () {
    final song = HuaweiAPI.parseSong(<String, dynamic>{
      'songCode': 'abc',
      'songName': '夜的第七章',
      'singerName': '周杰伦/潘儿',
    });
    expect(song.id, 'abc');
    expect(song.name, '夜的第七章');
    expect(song.artistText.contains('周杰伦'), isTrue);
  });
}
