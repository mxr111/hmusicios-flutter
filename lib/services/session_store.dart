import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:shared_preferences/shared_preferences.dart';

/// 华为账号密码。仅作为 OAuth 授权页的自动填充/重新登录辅助，
/// 不是账号密码直登，也不会参与华为业务接口鉴权。
class HuaweiCredentials {
  const HuaweiCredentials({required this.account, required this.password});

  final String account;
  final String password;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HuaweiCredentials &&
          other.account == account &&
          other.password == password;

  @override
  int get hashCode => Object.hash(account, password);
}

/// 需要跨启动恢复的登录态与少量界面偏好。
class SessionSnapshot {
  const SessionSnapshot({
    this.source = 'huawei',
    this.huaweiToken = '',
    this.huaweiUserId = '',
    this.huaweiAccountToken = '',
    this.huaweiRefreshToken = '',
    this.huaweiExpireTime = '',
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
    this.huaweiAccountEncrypted = '',
    this.huaweiPasswordEncrypted = '',
    this.credentialKey = '',
    this.credentialIv = '',
    this.autoLoginEnabled = false,
    this.lastReloginEpoch = 0,
    this.volume = 1.0,
    this.effect = '清晰增强',
    this.qualityIndex = 2,
    this.qualityName = 'hiRes',
    this.lyricOffsetMs = 0,
    this.lyricStyleAlign = 0,
    this.lyricStyleBold = true,
    this.lyricStyleColumns = 1,
    this.lyricStyleFontScale = 1.0,
    this.lyricStyleFont = '鸿蒙黑体',
    this.lyricStyleFollowCoverColor = true,
    this.glassIndex = 1,
    this.glowColorArgb = 0xFF548BF0,
    this.glassPress = true,
    this.glassSlide = true,
  });

  final String source;
  final String huaweiToken;
  final String huaweiUserId;

  /// OAuth 账号 access token。只用于换音乐会话，绝不能冒充 refresh token。
  final String huaweiAccountToken;

  /// OAuth refresh token（与账号 access token 分开持久化）。
  final String huaweiRefreshToken;

  /// 音乐会话过期时间，原样保存上游字符串。
  final String huaweiExpireTime;

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
  final String huaweiAccountEncrypted;
  final String huaweiPasswordEncrypted;
  final String credentialKey;
  final String credentialIv;
  final bool autoLoginEnabled;
  final int lastReloginEpoch;
  final double volume;
  final String effect;
  final int qualityIndex;
  final String qualityName;
  final int lyricOffsetMs;
  final int lyricStyleAlign;
  final bool lyricStyleBold;
  final int lyricStyleColumns;
  final double lyricStyleFontScale;
  final String lyricStyleFont;
  final bool lyricStyleFollowCoverColor;
  final int glassIndex;
  final int glowColorArgb;
  final bool glassPress;
  final bool glassSlide;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'source': source,
        'huaweiToken': huaweiToken,
        'huaweiUserId': huaweiUserId,
        'huaweiAccountToken': huaweiAccountToken,
        'huaweiRefreshToken': huaweiRefreshToken,
        'huaweiExpireTime': huaweiExpireTime,
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
        'huaweiAccountEncrypted': huaweiAccountEncrypted,
        'huaweiPasswordEncrypted': huaweiPasswordEncrypted,
        'credentialKey': credentialKey,
        'credentialIv': credentialIv,
        'autoLoginEnabled': autoLoginEnabled,
        'lastReloginEpoch': lastReloginEpoch,
        'volume': volume,
        'effect': effect,
        'qualityIndex': qualityIndex,
        'qualityName': qualityName,
        'lyricOffsetMs': lyricOffsetMs,
        'lyricStyleAlign': lyricStyleAlign,
        'lyricStyleBold': lyricStyleBold,
        'lyricStyleColumns': lyricStyleColumns,
        'lyricStyleFontScale': lyricStyleFontScale,
        'lyricStyleFont': lyricStyleFont,
        'lyricStyleFollowCoverColor': lyricStyleFollowCoverColor,
        'glassIndex': glassIndex,
        'glowColorArgb': glowColorArgb,
        'glassPress': glassPress,
        'glassSlide': glassSlide,
      };

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    return SessionSnapshot(
      source: '${json['source'] ?? 'huawei'}',
      huaweiToken: '${json['huaweiToken'] ?? ''}',
      huaweiUserId: '${json['huaweiUserId'] ?? ''}',
      huaweiAccountToken: '${json['huaweiAccountToken'] ?? ''}',
      huaweiRefreshToken: '${json['huaweiRefreshToken'] ?? ''}',
      huaweiExpireTime: '${json['huaweiExpireTime'] ?? ''}',
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
      themeIndex: _int(json['themeIndex'], 0),
      huaweiAccountEncrypted: '${json['huaweiAccountEncrypted'] ?? ''}',
      huaweiPasswordEncrypted: '${json['huaweiPasswordEncrypted'] ?? ''}',
      credentialKey: '${json['credentialKey'] ?? ''}',
      credentialIv: '${json['credentialIv'] ?? ''}',
      autoLoginEnabled: _bool(json['autoLoginEnabled'], false),
      lastReloginEpoch: _int(json['lastReloginEpoch'], 0),
      volume: _double(json['volume'], 1.0).clamp(0.0, 1.0).toDouble(),
      effect: '${json['effect'] ?? '清晰增强'}',
      qualityIndex: _int(json['qualityIndex'], 2).clamp(0, 2),
      qualityName: '${json['qualityName'] ?? 'hiRes'}',
      lyricOffsetMs: _int(json['lyricOffsetMs'], 0),
      lyricStyleAlign: _int(json['lyricStyleAlign'], 0),
      lyricStyleBold: _bool(json['lyricStyleBold'], true),
      lyricStyleColumns: _int(json['lyricStyleColumns'], 1).clamp(1, 3),
      lyricStyleFontScale: _double(json['lyricStyleFontScale'], 1.0)
          .clamp(0.5, 2.0)
          .toDouble(),
      lyricStyleFont: '${json['lyricStyleFont'] ?? '鸿蒙黑体'}',
      lyricStyleFollowCoverColor: _bool(
        json['lyricStyleFollowCoverColor'],
        true,
      ),
      glassIndex: _int(json['glassIndex'], 1).clamp(0, 3),
      glowColorArgb: _int(json['glowColorArgb'], 0xFF548BF0),
      glassPress: _bool(json['glassPress'], true),
      glassSlide: _bool(json['glassSlide'], true),
    );
  }

  static Map<String, String> _stringMap(dynamic raw) {
    if (raw is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in raw.entries)
        '${entry.key}': '${entry.value}',
    };
  }

  static bool _bool(dynamic raw, bool fallback) =>
      raw is bool ? raw : fallback;

  static int _int(dynamic raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? ''}') ?? fallback;
  }

  static double _double(dynamic raw, double fallback) {
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}') ?? fallback;
  }
}

abstract class SessionStore {
  Future<SessionSnapshot?> read();
  Future<void> write(SessionSnapshot snapshot);
  Future<void> clear();
  Future<HuaweiCredentials?> readCredentials();
  Future<void> writeCredentials(HuaweiCredentials credentials);
  Future<void> clearCredentials();
}

/// 生产实现：SharedPreferences(JSON) 持久化，避免每次启动重新扫码。
class PreferencesSessionStore implements SessionStore {
  PreferencesSessionStore({SharedPreferences? preferences})
      : _preferences = preferences == null ? null : Future.value(preferences);

  static const String key = 'muyu.session.v1';
  static const List<String> _credentialKeys = <String>[
    'huaweiAccountEncrypted',
    'huaweiPasswordEncrypted',
    'credentialKey',
    'credentialIv',
    'autoLoginEnabled',
    'lastReloginEpoch',
  ];
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
    final prefs = await _prefs;
    final existing = _decodeObject(prefs.getString(key));
    final incoming = snapshot.toJson();
    final merged = <String, dynamic>{...?existing, ...incoming};
    final hasNewEnvelope =
        '${incoming['huaweiAccountEncrypted'] ?? ''}'.isNotEmpty &&
        '${incoming['huaweiPasswordEncrypted'] ?? ''}'.isNotEmpty &&
        '${incoming['credentialKey'] ?? ''}'.isNotEmpty &&
        '${incoming['credentialIv'] ?? ''}'.isNotEmpty;
    if (!hasNewEnvelope && existing != null) {
      // 普通持久化不能覆盖已保存的加密凭据。
      for (final credentialKey in _credentialKeys) {
        if (existing.containsKey(credentialKey)) {
          merged[credentialKey] = existing[credentialKey];
        } else {
          merged.remove(credentialKey);
        }
      }
    }
    await prefs.setString(key, jsonEncode(merged));
  }

  @override
  Future<void> clear() async => (await _prefs).remove(key);

  @override
  Future<HuaweiCredentials?> readCredentials() async {
    final snapshot = await read();
    if (snapshot == null ||
        !snapshot.autoLoginEnabled ||
        snapshot.huaweiAccountEncrypted.isEmpty ||
        snapshot.huaweiPasswordEncrypted.isEmpty ||
        snapshot.credentialKey.isEmpty ||
        snapshot.credentialIv.isEmpty) {
      return null;
    }
    try {
      final key = encrypt.Key.fromBase64(snapshot.credentialKey);
      final iv = encrypt.IV.fromBase64(snapshot.credentialIv);
      if (key.length != 32 || iv.bytes.length != 16) return null;
      final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );
      final account = encrypter.decrypt64(
        snapshot.huaweiAccountEncrypted,
        iv: iv,
      );
      final password = encrypter.decrypt64(
        snapshot.huaweiPasswordEncrypted,
        iv: iv,
      );
      if (account.isEmpty || password.isEmpty) return null;
      return HuaweiCredentials(account: account, password: password);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeCredentials(HuaweiCredentials credentials) async {
    final prefs = await _prefs;
    final existing = _decodeObject(prefs.getString(key)) ?? <String, dynamic>{};
    final encryptionKey = encrypt.Key.fromSecureRandom(32);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encryptionKey, mode: encrypt.AESMode.cbc),
    );
    existing['huaweiAccountEncrypted'] = encrypter.encrypt(
      credentials.account,
      iv: iv,
    ).base64;
    existing['huaweiPasswordEncrypted'] = encrypter.encrypt(
      credentials.password,
      iv: iv,
    ).base64;
    existing['credentialKey'] = encryptionKey.base64;
    existing['credentialIv'] = iv.base64;
    existing['autoLoginEnabled'] = true;
    existing['lastReloginEpoch'] = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(key, jsonEncode(existing));
  }

  @override
  Future<void> clearCredentials() async {
    final prefs = await _prefs;
    final existing = _decodeObject(prefs.getString(key));
    if (existing == null) return;
    for (final credentialKey in _credentialKeys) {
      existing.remove(credentialKey);
    }
    await prefs.setString(key, jsonEncode(existing));
  }

  static Map<String, dynamic>? _decodeObject(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// 测试用内存实现。
class MemorySessionStore implements SessionStore {
  SessionSnapshot? _snapshot;
  HuaweiCredentials? _credentials;

  @override
  Future<SessionSnapshot?> read() async => _snapshot;

  @override
  Future<void> write(SessionSnapshot snapshot) async => _snapshot = snapshot;

  @override
  Future<void> clear() async {
    _snapshot = null;
    _credentials = null;
  }

  @override
  Future<HuaweiCredentials?> readCredentials() async => _credentials;

  @override
  Future<void> writeCredentials(HuaweiCredentials credentials) async {
    _credentials = credentials;
  }

  @override
  Future<void> clearCredentials() async {
    _credentials = null;
  }
}
