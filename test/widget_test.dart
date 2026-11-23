// 协议回归测试：重点验证 REA 运行时取证发现的 URL 拼接规则。
// 早期 iOS 版把带 ?query 的路径当 path component 拼接，导致 ? 被编码成 %3F → HTTP 404。

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/models.dart';
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

  test('鉴权头是 Digest，不是 Bearer（tinglan 源码事实）', () {
    final gateway = HuaweiGateway();
    gateway.session = MusicSession(token: 'music-token', snsUserId: 'u1');
    final headers = gateway.headers();
    expect(headers['Authorization'], contains('Digest username=app-music-baseline'));
    expect(headers['Authorization'], contains('token=music-token'));
    expect(headers['Authorization']!.toLowerCase().contains('bearer'), isFalse);
    gateway.dispose();
  });

  test('无会话调用 Digest 头不含 token 段', () {
    final gateway = HuaweiGateway();
    final h = gateway.digestHeader('');
    expect(h, contains('Digest username=app-music-baseline'));
    expect(h.contains('token='), isFalse);
    gateway.dispose();
  });

  test('逐字 HMRC 解析（tinglan/hmrc.go 格式）', () {
    final lines = HuaweiAPI.parseHmrc(
      '[1000,3000]<0,500>我<500,500>爱<1000,500>你\n[5000,2000]<0,400>hello ^你好',
    );
    expect(lines.length, 2);
    expect(lines[0].text, '我爱你');
    expect(lines[0].words.length, 3);
    expect(lines[0].words[0].time.inMilliseconds, 1000);
    expect(lines[0].words[1].time.inMilliseconds, 1500);
    expect(lines[1].translation, '你好');
  });

  test('音质档位取流参数 qualityType 为 1/3', () {
    expect(AudioQuality.standard.typeCode, '1');
    expect(AudioQuality.lossless.typeCode, '3');
    expect(AudioQuality.hiRes.typeCode, '3');
  });
}
