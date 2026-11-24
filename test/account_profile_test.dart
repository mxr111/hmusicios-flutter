import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_flutter/protocol/endpoints.dart';
import 'package:muyu_flutter/protocol/huawei_api.dart';
import 'package:muyu_flutter/protocol/huawei_gateway.dart';

class _ProfileGateway extends HuaweiGateway {
  bool musicProfile = false;

  @override
  Future<Map<String, dynamic>> get(String path) async {
    if (path == HuaweiPaths.subscription) {
      if (musicProfile) return <String, dynamic>{};
      return <String, dynamic>{
        'result': <String, dynamic>{'resultCode': '000000'},
        'domainSubInfos': <dynamic>[
          <String, dynamic>{
            'domainType': 1,
            'hadVIPs': <String, dynamic>{'vipFlag': 1},
            'subInfos': <dynamic>[
              <String, dynamic>{
                'productInfo': <String, dynamic>{'productName': '超级音乐VIP'},
              },
            ],
          },
        ],
      };
    }
    throw StateError('unexpected get $path');
  }

  @override
  Future<Map<String, dynamic>> accountUserInfo(String accessToken) async {
    if (musicProfile) throw const HuaweiException('no oauth profile');
    return <String, dynamic>{
      'nickname': '土豆',
      'headPictureURL': 'https://contentcenter-drcn.dbankcdn.cn/avatar.jpg',
    };
  }

  @override
  Future<Map<String, dynamic>?> musicUserInfo() async {
    if (!musicProfile) return null;
    return <String, dynamic>{
      'data': <String, dynamic>{
        'profile': <String, dynamic>{
          'nickname': '真实昵称',
          'avatarUrl': 'https://contentcenter-drcn.dbankcdn.cn/real-avatar.jpg',
        },
      },
    };
  }
}

void main() {
  test('真实账号资料：昵称/头像/会员名称来自华为接口', () async {
    final gateway = _ProfileGateway()..accountToken = 'account-token';
    final api = HuaweiAPI(gateway: gateway);

    await api.refreshProfile();

    expect(api.displayName, '土豆');
    expect(api.avatarUrl, contains('avatar.jpg'));
    expect(api.memberLabel, '超级音乐VIP');
    expect(api.isMember, isTrue);
  });

  test('OAuth 资料不可用时回退到音乐侧 userinfo', () async {
    final gateway = _ProfileGateway()
      ..musicProfile = true
      ..session = MusicSession(token: 'music-token', snsUserId: '123456');
    final api = HuaweiAPI(gateway: gateway);

    await api.refreshProfile();

    expect(api.displayName, '真实昵称');
    expect(api.avatarUrl, contains('real-avatar.jpg'));
  });
}
