import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// 从文件内嵌标签读出的最小元数据。
class LocalTags {
  const LocalTags({this.title = '', this.artist = '', this.album = ''});
  final String title;
  final String artist;
  final String album;
}

/// 本地音乐库：导入 → 解析 ID3v2 / FLAC Vorbis 标签 → 复制进应用沙箱 → 持久化。
/// 与沐语 internal/localmedia 对齐：只读取用户主动选择的文件，不扫描全盘。
class LocalLibrary extends ChangeNotifier {
  static const String storageKey = 'muyu.local.v1';

  final List<Song> songs = <Song>[];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final path = '${map['path'] ?? ''}';
        if (path.isEmpty) continue;
        if (!await File(path).exists()) continue;
        songs.add(_toSong(map, path));
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 打开系统文件选择器，支持多选；返回成功导入的数量。
  Future<int> importFromPicker() async {
    error = null;
    loading = true;
    notifyListeners();
    try {
      // file_picker 13：pickFiles 固定返回列表，多选由调用方逐项处理。
      final picked = await FilePicker.pickFiles(type: FileType.audio);
      if (picked.isEmpty) return 0;
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory('${docs.path}/local_music');
      await folder.create(recursive: true);

      var added = 0;
      for (final file in picked) {
        final sourcePath = file.path;
        if (sourcePath == null || sourcePath.isEmpty) continue;
        final safeName = _safeFileName(file.name);
        final dest = File('${folder.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName');
        await File(sourcePath).copy(dest.path);
        final bytes = await dest.readAsBytes();
        final tags = readLocalTags(bytes, fallbackName: file.name);
        final song = Song(
          id: 'local:${dest.path}',
          name: tags.title.isEmpty ? _stem(file.name) : tags.title,
          album: tags.album,
          artists: tags.artist.isEmpty
              ? const <String>['未知歌手']
              : <String>[tags.artist],
          durationMs: 0,
          qualities: <AudioQuality>{
            _isLossless(file.name) ? AudioQuality.lossless : AudioQuality.standard,
          },
          source: MusicSourceLabel.local,
          localPath: dest.path,
        );
        songs.add(song);
        added++;
      }
      if (added > 0) await _save();
      return added;
    } catch (e) {
      error = e.toString();
      return 0;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> remove(Song song) async {
    songs.removeWhere((s) => s.id == song.id);
    final path = song.localPath;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // 文件被系统占用时只移除索引，不阻塞 UI。
      }
    }
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(<Map<String, dynamic>>[
        for (final s in songs)
          <String, dynamic>{
            'path': s.localPath ?? '',
            'title': s.name,
            'artist': s.artists.isEmpty ? '' : s.artists.first,
            'album': s.album,
            'lossless': s.qualities.contains(AudioQuality.lossless),
          },
      ]),
    );
  }

  static Song _toSong(Map<String, dynamic> map, String path) {
    final artist = '${map['artist'] ?? ''}';
    return Song(
      id: 'local:$path',
      name: '${map['title'] ?? _stem(path)}',
      album: '${map['album'] ?? ''}',
      artists: artist.isEmpty ? const <String>['未知歌手'] : <String>[artist],
      qualities: <AudioQuality>{
        map['lossless'] == true ? AudioQuality.lossless : AudioQuality.standard,
      },
      source: MusicSourceLabel.local,
      localPath: path,
    );
  }

  static String _stem(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static String _safeFileName(String name) {
    final base = name.split(RegExp(r'[/\\]')).last;
    return base.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
  }

  static bool _isLossless(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.flac') || lower.endsWith('.wav') || lower.endsWith('.alac');
  }
}

/// 纯函数：解析 MP3 ID3v2 或 FLAC Vorbis Comment。无法识别时返回空标签。
LocalTags readLocalTags(Uint8List bytes, {String fallbackName = ''}) {
  if (bytes.length > 10 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    final id3 = _readId3(bytes);
    if (id3 != null) return id3;
  }
  if (bytes.length > 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4c &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43) {
    final flac = _readFlac(bytes);
    if (flac != null) return flac;
  }
  return LocalTags(title: LocalLibrary._stem(fallbackName));
}

LocalTags? _readId3(Uint8List bytes) {
  final version = bytes[3];
  final headerSize = 10 + _syncSafe(bytes, 6);
  var offset = 10;
  String title = '';
  String artist = '';
  String album = '';
  while (offset + 10 <= bytes.length && offset < headerSize) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
    final size = version == 4
        ? _syncSafe(bytes, offset + 4)
        : _be32(bytes, offset + 4);
    final dataStart = offset + 10;
    if (size < 0 || dataStart + size > bytes.length) break;
    if (size == 0) {
      offset = dataStart;
      continue;
    }
    final data = Uint8List.sublistView(bytes, dataStart, dataStart + size);
    if (id == 'TIT2') title = _decodeText(data);
    if (id == 'TPE1') artist = _decodeText(data);
    if (id == 'TALB') album = _decodeText(data);
    offset = dataStart + size;
  }
  if (title.isEmpty && artist.isEmpty && album.isEmpty) return null;
  return LocalTags(title: title, artist: artist, album: album);
}

LocalTags? _readFlac(Uint8List bytes) {
  var offset = 4;
  var last = false;
  String title = '';
  String artist = '';
  String album = '';
  while (!last && offset + 4 <= bytes.length) {
    final header = bytes[offset];
    last = (header & 0x80) != 0;
    final type = header & 0x7f;
    final length = (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    final start = offset + 4;
    final end = start + length;
    if (length < 0 || end > bytes.length) break;
    if (type == 4) {
      final comments = _readVorbis(Uint8List.sublistView(bytes, start, end));
      title = comments['TITLE'] ?? '';
      artist = comments['ARTIST'] ?? '';
      album = comments['ALBUM'] ?? '';
    }
    offset = end;
  }
  if (title.isEmpty && artist.isEmpty && album.isEmpty) return null;
  return LocalTags(title: title, artist: artist, album: album);
}

Map<String, String> _readVorbis(Uint8List data) {
  final out = <String, String>{};
  var offset = 0;
  int readLe32() {
    if (offset + 4 > data.length) return -1;
    final v = data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
    offset += 4;
    return v;
  }

  final vendorLen = readLe32();
  if (vendorLen < 0 || offset + vendorLen > data.length) return out;
  offset += vendorLen;
  final count = readLe32();
  if (count < 0) return out;
  for (var i = 0; i < count && i < 512; i++) {
    final len = readLe32();
    if (len <= 0 || offset + len > data.length) break;
    final raw = utf8.decode(
      Uint8List.sublistView(data, offset, offset + len),
      allowMalformed: true,
    );
    offset += len;
    final eq = raw.indexOf('=');
    if (eq <= 0) continue;
    final key = raw.substring(0, eq).toUpperCase();
    if (key == 'TITLE' || key == 'ARTIST' || key == 'ALBUM') {
      out[key] = raw.substring(eq + 1).trim();
    }
  }
  return out;
}

String _decodeText(Uint8List data) {
  if (data.isEmpty) return '';
  final encoding = data[0];
  final body = Uint8List.sublistView(data, 1);
  String text;
  switch (encoding) {
    case 0:
      text = latin1.decode(body, allowInvalid: true);
      break;
    case 3:
      text = utf8.decode(body, allowMalformed: true);
      break;
    case 1:
    case 2:
      text = _decodeUtf16(body, bigEndian: encoding == 2);
      break;
    default:
      text = utf8.decode(body, allowMalformed: true);
  }
  return text.replaceAll('\x00', '').trim();
}

String _decodeUtf16(Uint8List body, {required bool bigEndian}) {
  var start = 0;
  var be = bigEndian;
  if (body.length >= 2 && body[0] == 0xff && body[1] == 0xfe) {
    start = 2;
    be = false;
  } else if (body.length >= 2 && body[0] == 0xfe && body[1] == 0xff) {
    start = 2;
    be = true;
  }
  final units = <int>[];
  for (var i = start; i + 1 < body.length; i += 2) {
    units.add(be ? (body[i] << 8) | body[i + 1] : body[i] | (body[i + 1] << 8));
  }
  return String.fromCharCodes(units);
}

int _syncSafe(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return 0;
  return ((bytes[offset] & 0x7f) << 21) |
      ((bytes[offset + 1] & 0x7f) << 14) |
      ((bytes[offset + 2] & 0x7f) << 7) |
      (bytes[offset + 3] & 0x7f);
}

int _be32(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return 0;
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}
