import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../protocol/huawei_api.dart';
import 'lease_proxy.dart';

/// 与沐语 MyGo audio.Player 对等：取流 → 租约代理 → 播放器。
class MuyuAudioController extends ChangeNotifier {
  MuyuAudioController(this.api) {
    _player.onPositionChanged.listen((p) {
      position = p;
      notifyListeners();
    });
    _player.onDurationChanged.listen((d) {
      duration = d;
      notifyListeners();
    });
    _player.onPlayerStateChanged.listen((s) {
      playing = s == PlayerState.playing;
      notifyListeners();
    });
    _player.onPlayerComplete.listen((_) => next());
  }

  final HuaweiAPI api;
  final AudioPlayer _player = AudioPlayer();

  Song? current;
  AudioQuality quality = AudioQuality.standard;
  List<Song> queue = <Song>[];
  int index = -1;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  double volume = 1.0;
  bool shuffle = false;
  String? error;

  static const List<AudioQuality> kQualityOrder = <AudioQuality>[
    AudioQuality.hiRes,
    AudioQuality.lossless,
    AudioQuality.standard,
  ];

  Future<void> playSong(Song song, {List<Song>? list}) async {
    if (list != null && list.isNotEmpty) {
      queue = List<Song>.of(list);
      index = queue.indexWhere((s) => s.id == song.id);
      if (index < 0) {
        queue.insert(0, song);
        index = 0;
      }
    } else if (queue.isEmpty) {
      queue = <Song>[song];
      index = 0;
    }
    current = song;
    error = null;
    position = Duration.zero;
    duration = Duration.zero;
    notifyListeners();

    try {
      final files = await api.audioFiles(song.id);
      final wanted = song.qualities.contains(quality)
          ? quality
          : AudioQuality.standard;
      HuaweiAudioFile chosen = files.firstWhere(
        (f) => f.quality == wanted,
        orElse: () => files.first,
      );
      // 切歌前撤销旧租约，避免旧签名 URL 被复用
      LeaseProxy.instance.revoke();
      final local = await LeaseProxy.instance.publish(chosen.url);
      await _player.stop();
      await _player.setVolume(volume);
      await _player.play(UrlSource(local.toString()));
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggle() async {
    if (playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> seek(Duration to) async {
    await _player.seek(to);
    position = to;
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    await _player.setVolume(volume);
    notifyListeners();
  }

  Future<void> setQuality(AudioQuality q) async {
    quality = q;
    notifyListeners();
    final song = current;
    if (song != null) await playSong(song, list: queue);
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    final nextIndex = shuffle
        ? (DateTime.now().millisecondsSinceEpoch % queue.length)
        : (index + 1) % queue.length;
    index = nextIndex;
    await playSong(queue[nextIndex]);
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    index = (index - 1 + queue.length) % queue.length;
    await playSong(queue[index]);
  }

  Future<void> stop() async {
    await _player.stop();
    LeaseProxy.instance.revoke();
    playing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
