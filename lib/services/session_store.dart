import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 需要跨启动恢复的登录态与少量界面偏好。
class SessionSnapshot {
  const SessionSnapshot({
    this.source = 'huawei',
    this.huaweiToken = '',
    this.huaweiUserId = '',
    this.huaweiAccountToken = '',
    this.huaweiNickname = '',
    this.huaweiAvatar = '',
    this.huaweiMemberLabel = '',
    this.huaweiIsMember = false,
    this.neteaseMusicU = '',
    this.neteaseCsrf = '',
    this.neteaseNickname = '',
    this.neteaseUserId = '',
    this.kugouCookies = const <String, String>{},
    this.qqCookies = const <String, String>{},
    this.themeIndex = 0,
  });

  final String source;
  final String huaweiToken;
  final String huaweiUserId;
  final String huaweiAccountToken;
  final String huaweiNickname;
  final String huaweiAvatar;
  final String huaweiMemberLabel;
  final bool huaweiIsMember;
  final String neteaseMusicU;
  final String neteaseCsrf;
  final String neteaseNickname;
  final String neteaseUserId;
  final Map<String, String> kugouCookies;
  final Map<String, String> qqCookies;
  final int themeIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source': source,
        'huaweiToken': huaweiToken,
        'huaweiUserId': huaweiUserId,
        'huaweiAccountToken': huaweiAccountToken,
        'huaweiNickname': huaweiNickname,
        'huaweiAvatar': huaweiAvatar,
        'huaweiMemberLabel': huaweiMemberLabel,
        'huaweiIsMember': huaweiIsMember,
        'neteaseMusicU': neteaseMusicU,
        'neteaseCsrf': neteaseCsrf,
        'neteaseNickname': neteaseNickname,
        'neteaseUserId': neteaseUserId,
        'kugouCookies': kugouCookies,
        'qqCookies': qqCookies,
        'themeIndex': themeIndex,
      };

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    return SessionSnapshot(
      source: '${json['source'] ?? 'huawei'}',
      huaweiToken: '${json['huaweiToken'] ?? ''}',
      huaweiUserId: '${json['huaweiUserId'] ?? ''}',
      huaweiAccountToken: '${json['huaweiAccountToken'] ?? ''}',
      huaweiNickname: '${json['huaweiNickname'] ?? ''}',
      huaweiAvatar: '${json['huaweiAvatar'] ?? ''}',
      huaweiMemberLabel: '${json['huaweiMemberLabel'] ?? ''}',
      huaweiIsMember: json['huaweiIsMember'] == true,
      neteaseMusicU: '${json['neteaseMusicU'] ?? ''}',
      neteaseCsrf: '${json['neteaseCsrf'] ?? ''}',
      neteaseNickname: '${json['neteaseNickname'] ?? ''}',
      neteaseUserId: '${json['neteaseUserId'] ?? ''}',
      kugouCookies: _stringMap(json['kugouCookies']),
      qqCookies: _stringMap(json['qqCookies']),
      themeIndex: json['themeIndex'] is int ? json['themeIndex'] as int : 0,
    );
  }

  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        '${entry.key}': '${entry.value}',
    };
  }
}

abstract class SessionStore {
  Future<SessionSnapshot?> read();
  Future<void> write(SessionSnapshot snapshot);
  Future<void> clear();
}

/// 生产实现：SharedPreferences(JSON) 持久化，避免每次启动重新扫码。
class PreferencesSessionStore implements SessionStore {
  PreferencesSessionStore({SharedPreferences? preferences})
      : _preferences = preferences == null ? null : Future.value(preferences);

  static const String key = 'muyu.session.v1';
  Future<SharedPreferences>? _preferences;

  Future<SharedPreferences> get _prefs =>
      _preferences ??= SharedPreferences.getInstance();

  @override
  Future<SessionSnapshot?> read() async {
    final raw = (await _prefs).getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return SessionSnapshot.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(SessionSnapshot snapshot) async {
    await (await _prefs).setString(key, jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear() async => (await _prefs).remove(key);
}

/// 测试用内存实现。
class MemorySessionStore implements SessionStore {
  SessionSnapshot? _snapshot;

  @override
  Future<SessionSnapshot?> read() async => _snapshot;

  @override
  Future<void> write(SessionSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<void> clear() async => _snapshot = null;
}
