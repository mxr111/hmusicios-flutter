import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models.dart';
import '../models_skin.dart';
import '../protocol/huawei_api.dart';
import '../protocol/kugou_api.dart';
import '../protocol/netease_api.dart';
import '../protocol/qq_api.dart';
import 'app_log.dart';
import 'lease_proxy.dart';
import 'playback_clock.dart';

/// 与沐语 MyGo audio.Player 对等：取流 → 租约代理 → 播放器。
class MuyuAudioController extends ChangeNotifier {
  MuyuAudioController(
    this.api, {
    NeteaseApi? netease,
    KugouApi? kugou,
    QqApi? qq,
    AudioPlayer? player,
  }) : netease = netease ?? NeteaseApi(),
       kugou = kugou ?? KugouApi(),
       qq = qq ?? QqApi(),
       _player = player ?? AudioPlayer() {
    _player.onPositionChanged.listen((p) {
      if (!_activePlayback || _startingPlayback) return;
      _clock.sync(p, playing: _clock.isPlaying);
      _publishPosition();
      // 高频进度只通知进度条；歌词用 Ticker 自行外推到屏幕刷新率，
      // 不再让整棵 widget 树跟着播放器事件重建。
    });
    _player.onDurationChanged.listen((d) {
      if (_startingPlayback && _acceptStartingDuration) {
        _pendingDuration = d;
      } else if (_activePlayback) {
        _applyDuration(d);
      }
    });
    _player.onPlayerStateChanged.listen((s) {
      if (_activePlayback && !_startingPlayback) {
        _setPlaying(s == PlayerState.playing);
      }
    });
    _player.onPlayerComplete.listen((_) {
      if (!_activePlayback || _startingPlayback) return;
      _activePlayback = false;
      _setPlaying(false);
      next();
    });
  }

  final HuaweiAPI api;
  final NeteaseApi netease;
  final KugouApi kugou;
  final QqApi qq;
  MusicSource source = MusicSource.huawei;
  final AudioPlayer _player;

  Song? current;

  /// 与沐语 `quality: hires` 一致：默认请求上游最高档；实际档位由
  /// `playSong` 根据该歌曲上游可用档位回退，不会强行把每首歌降成 MP3。
  AudioQuality quality = AudioQuality.hiRes;
  List<Song> queue = <Song>[];
  int index = -1;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool get playing => _clock.isPlaying;

  /// 当前点歌入口（favorites/search/chart/playlist/artist/home/...）。
  /// 由 AppState.play 在调用前写入，只用于日志，不参与业务判断。
  String playEntry = '';

  /// 队列尾部续播回调。只在「心动模式」队列启用；普通歌单和「现在就听」
  /// 必须为 null，避免播完后错误地继续拉心动 privatefm 续页。
  Future<List<Song>> Function()? onQueueExhausted;

  /// 最近一次 playSong 最终尝试的档位 / 是否有完整 URL / 错误码。
  /// 供 AppState 记录“每次点歌”的完整诊断行，也便于测试断言。
  String? lastQualityType;
  bool lastHasUrl = false;
  String? lastErrorCode;

  /// 低频进度通知（播放器回调频率），仅给进度条等轻量组件监听。
  final ValueNotifier<Duration> positionNotifier = ValueNotifier<Duration>(
    Duration.zero,
  );

  /// 歌词内容/时间线版本。切歌、刷新歌词、修改校准偏移后递增，
  /// 让歌词列表用新 key 重建，避免继续复用旧歌的滚动/高亮状态。
  final ValueNotifier<int> lyricRevision = ValueNotifier<int>(0);

  /// 播放设置版本（音量/音效/音质/歌词偏移），供设置页和播放器同步刷新。
  final ValueNotifier<int> settingsRevision = ValueNotifier<int>(0);
  final PlaybackClock _clock = PlaybackClock();
  bool _activePlayback = false;
  bool _startingPlayback = false;
  bool _acceptStartingDuration = false;
  Duration? _pendingDuration;
  int _trackGeneration = 0;
  Future<void> _playerQueue = Future<void>.value();

  /// 歌词校准偏移：正值让歌词提前，负值让歌词延后。
  Duration lyricOffset = Duration.zero;
  static const Duration maxLyricOffset = Duration(seconds: 5);

  /// 高频歌词位置：单调时钟外推，不受系统时间调整/加载延迟影响。
  Duration get displayPosition => _clock.position;
  Duration get lyricPosition => _clock.adjusted(lyricOffset);

  void _setPlaying(bool next) {
    final wasPlaying = _clock.isPlaying;
    final previousPosition = _clock.position;
    _clock.setPlaying(next);
    _publishPosition();
    if (wasPlaying != next || previousPosition != position) {
      notifyListeners();
    }
  }

  void _publishPosition() {
    position = _clock.position;
    positionNotifier.value = position;
  }

  void _applyDuration(Duration value) {
    duration = value < Duration.zero ? Duration.zero : value;
    _clock.duration = duration;
    // duration 更新时 PlaybackClock 会同步夹紧锚点；进度条也立刻同步，
    // 避免歌词时钟与低频位置通知暂时落在不同范围。
    _publishPosition();
    notifyListeners();
  }

  Future<void> _enqueuePlayerOperation(Future<void> Function() operation) {
    final result = _playerQueue.then((_) => operation());
    _playerQueue = result.catchError((Object _) {});
    return result;
  }

  void invalidateLyrics() {
    lyricRevision.value++;
  }

  Future<void> setLyricOffset(Duration offset) async {
    lyricOffset = PlaybackClock.clampOffset(offset, limit: maxLyricOffset);
    notifyListeners();
    invalidateLyrics();
    settingsRevision.value++;
  }

  Future<void> adjustLyricOffset(Duration delta) =>
      setLyricOffset(lyricOffset + delta);

  Future<void> resetLyricOffset() => setLyricOffset(Duration.zero);
  double volume = 1.0;
  bool shuffle = false;
  String? error;

  /// REA 观察：播放模式为列表循环 / 随机 / 单曲（文案「随机模式播放结束后未继续下一首」）。
  PlayMode playMode = PlayMode.listLoop;

  /// REA 观察：播放器音效 8 种（清晰增强/现场余韵/低频增厚/交响厅堂/近场监听/人声聚焦/环绕漫游）。
  static const List<String> kEffects = <String>[
    '清晰增强',
    '现场余韵',
    '低频增厚',
    '交响厅堂',
    '近场监听',
    '人声聚焦',
    '环绕漫游',
  ];
  String effect = '清晰增强';

  /// REA 观察：定时停止（「X 分钟后停止 / 取消定时」）。
  Duration? sleepTimer;
  DateTime? _sleepDeadline;
  Timer? _sleepTicker;

  static const List<AudioQuality> kQualityOrder = <AudioQuality>[
    AudioQuality.hiRes,
    AudioQuality.lossless,
    AudioQuality.standard,
  ];

  /// 默认选用户/沐语设置的档位；该歌曲没有这个档位时，选上游能提供的
  /// 最高档。默认 quality 是 hiRes，因此新会话默认拿最高可播档。
  static AudioQuality chooseQuality(
    AudioQuality requested,
    Iterable<AudioQuality> supported,
  ) {
    final set = supported.toSet();
    if (set.isEmpty) return requested;
    if (set.contains(requested)) return requested;
    return set.reduce((a, b) => a.index > b.index ? a : b);
  }

  Future<void> playSong(Song song, {List<Song>? list}) async {
    final generation = ++_trackGeneration;
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
    final hasPreset = song.localPath != null && song.localPath!.isNotEmpty;
    current = song;
    invalidateLyrics();
    error = null;
    lastQualityType = null;
    lastHasUrl = false;
    lastErrorCode = null;
    _activePlayback = false;
    _startingPlayback = false;
    _acceptStartingDuration = false;
    _pendingDuration = null;
    _clock.duration = Duration.zero;
    _clock.reset(Duration.zero);
    position = Duration.zero;
    duration = Duration.zero;
    positionNotifier.value = Duration.zero;
    AppLog.add(
      'play',
      'entry=$_entryLabel song=${song.id} source=${song.source.name} '
          'presetUrl=$hasPreset queue=${queue.length}',
    );
    notifyListeners();

    try {
      // 先串行停止旧曲，加载期间忽略旧播放器迟到的位置/时长/状态回调。
      await _enqueuePlayerOperation(() async {
        if (generation == _trackGeneration) await _player.stop();
      });
      if (generation != _trackGeneration) return;

      // 本地音乐：直接播放沙箱文件，不需要签名 / 租约代理。
      final localPath = song.localPath;
      if (localPath != null && localPath.isNotEmpty) {
        LeaseProxy.instance.revoke();
        await _enqueuePlayerOperation(() async {
          if (generation != _trackGeneration) return;
          _startingPlayback = true;
          _acceptStartingDuration = false;
          _pendingDuration = null;
          await _player.setVolume(volume);
          _acceptStartingDuration = true;
          await _player.play(
            DeviceFileSource(localPath, mimeType: mimeTypeForPath(localPath)),
          );
          _finishStartingPlayback(generation);
        });
        lastQualityType = 'local';
        lastHasUrl = true;
        lastErrorCode = '000000';
        notifyListeners();
        AppLog.add(
          'play',
          'done entry=$_entryLabel song=${song.id} '
              'source=${song.source.name} presetUrl=true qualityType=local '
              'hasUrl=true code=000000',
        );
        return;
      }

      if (song.id.trim().isEmpty) {
        throw StateError('歌曲缺少 contentCode（列表解析异常），无法取流');
      }

      // 档位由上游决定：把 Song 从上游字段解析出的档位集合传给取流层。
      final List<HuaweiAudioFile> files = switch (source) {
        MusicSource.netease => await netease.audioFiles(song, quality: quality),
        MusicSource.kugou => await kugou.audioFiles(song),
        MusicSource.qq => await qq.audioFiles(song),
        MusicSource.huawei => await api.audioFiles(
          song.id,
          upstreamQualities: song.qualities,
        ),
      };
      if (files.isEmpty) {
        throw StateError('该音源未返回可播放地址');
      }
      if (generation != _trackGeneration) return;

      final supported = files.map((f) => f.quality).toSet();
      final wanted = chooseQuality(quality, supported);
      // 先试用户/默认最高档；如果 AVPlayer/ExoPlayer 在该容器上
      // setSource 失败（日志里的 hiRes FLAC），继续降档，最终用
      // standard MP3 兜底。仅解析出 URL 不够，必须真的能开播。
      final candidates = playbackCandidates(files, wanted);
      String? lastFailure;
      for (final file in candidates) {
        if (generation != _trackGeneration) return;
        lastQualityType = file.qualityType;
        lastHasUrl = true;
        final mime = mimeTypeFor(file.url);
        AppLog.add(
          'play',
          'attempt entry=$_entryLabel song=${song.id} '
              'source=${song.source.name} presetUrl=false '
              'quality=${file.quality.name} qualityType=${file.qualityType} '
              'hasUrl=true mime=${mime ?? '-'}',
        );

        final Uri local;
        try {
          local = await LeaseProxy.instance.publish(file.url);
        } catch (e) {
          lastFailure = e.toString();
          lastErrorCode = playbackErrorCode(e);
          AppLog.add(
            'play',
            'lease-failed entry=$_entryLabel song=${song.id} '
                'qualityType=${file.qualityType} hasUrl=true '
                'code=$lastErrorCode error=${_shortError(e)}; 尝试下一档',
          );
          continue;
        }
        if (generation != _trackGeneration) return;

        try {
          await _enqueuePlayerOperation(() async {
            if (generation != _trackGeneration) return;
            _startingPlayback = true;
            _acceptStartingDuration = false;
            _pendingDuration = null;
            await _player.setVolume(volume);
            _acceptStartingDuration = true;
            await _player.play(UrlSource(local.toString(), mimeType: mime));
            _finishStartingPlayback(generation);
          });
          if (generation != _trackGeneration) return;
          error = null;
          lastErrorCode = '000000';
          notifyListeners();
          AppLog.add(
            'play',
            'done entry=$_entryLabel song=${song.id} '
                'source=${song.source.name} presetUrl=false '
                'quality=${file.quality.name} qualityType=${file.qualityType} '
                'hasUrl=true code=000000 mime=${mime ?? '-'} '
                'url=${file.url.scheme}://${file.url.host}${file.url.path}',
          );
          return;
        } catch (e) {
          if (generation != _trackGeneration) return;
          lastFailure = e.toString();
          lastErrorCode = playbackErrorCode(e);
          _startingPlayback = false;
          _acceptStartingDuration = false;
          _activePlayback = false;
          AppLog.add(
            'play',
            'decode-failed entry=$_entryLabel song=${song.id} '
                'quality=${file.quality.name} qualityType=${file.qualityType} '
                'hasUrl=true code=$lastErrorCode error=${_shortError(e)}; '
                '尝试下一档',
          );
          // 失败后显式 stop，避免播放器仍停在 failed item 上影响下一档。
          await _enqueuePlayerOperation(() async {
            if (generation == _trackGeneration) await _player.stop();
          }).catchError((Object _) {});
        }
      }

      throw StateError(
        '该歌曲所选音质在当前设备无法播放'
        '（已尝试 ${candidates.length} 档）'
        '${lastFailure == null ? '' : '：${_shortError(lastFailure)}'}',
      );
    } catch (e) {
      if (generation != _trackGeneration) return;
      _startingPlayback = false;
      _acceptStartingDuration = false;
      _activePlayback = false;
      lastErrorCode = playbackErrorCode(e);
      error = _errorText(e);
      AppLog.add(
        'play',
        'error entry=$_entryLabel song=${song.id} '
            'source=${song.source.name} presetUrl=$hasPreset '
            'quality=${quality.name} qualityType=${lastQualityType ?? '-'} '
            'hasUrl=$lastHasUrl code=$lastErrorCode: $e',
      );
      notifyListeners();
    }
  }

  String get _entryLabel => playEntry.isEmpty ? 'queue' : playEntry;

  /// 按“目标档位 → 更低档”排序。目标档位之上不试，避免用户选标准
  /// 时又偷偷拉 Hi-Res；目标档位本身失败后逐级降，最终一定包含 standard。
  @visibleForTesting
  static List<HuaweiAudioFile> playbackCandidates(
    List<HuaweiAudioFile> files,
    AudioQuality wanted,
  ) {
    final sorted = List<HuaweiAudioFile>.of(files)
      ..sort((a, b) => b.quality.index.compareTo(a.quality.index));
    final start = sorted.indexWhere((f) => f.quality == wanted);
    if (start < 0) return sorted;
    return sorted.sublist(start);
  }

  /// 明确告诉播放器容器格式：音频 URL 在租约代理下没有扩展名，不能
  /// 只靠 URL 猜；FLAC 的 audio/x-flac 在 iOS 上也可能识别失败。
  @visibleForTesting
  static String? mimeTypeFor(Uri url) {
    final path = url.path.toLowerCase();
    if (path.endsWith('.mp3')) return 'audio/mpeg';
    if (path.endsWith('.flac')) return 'audio/flac';
    if (path.endsWith('.m4a') || path.endsWith('.mp4')) return 'audio/mp4';
    if (path.endsWith('.aac')) return 'audio/aac';
    if (path.endsWith('.wav')) return 'audio/wav';
    if (path.endsWith('.ogg') || path.endsWith('.oga')) return 'audio/ogg';
    return null;
  }

  @visibleForTesting
  static String? mimeTypeForPath(String path) => mimeTypeFor(Uri.file(path));

  /// 从异常里提取 6 位业务码；平台解码错误统一记为 decode。
  @visibleForTesting
  static String playbackErrorCode(Object error) {
    final text = error.toString();
    final hit = RegExp(r'\b\d{6}\b').firstMatch(text);
    if (hit != null) return hit.group(0)!;
    if (text.contains('DarwinAudioError') ||
        text.contains('Failed to set') ||
        text.contains('AVPlayerItem')) {
      return 'decode';
    }
    return 'unknown';
  }

  static String _shortError(Object error) =>
      error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// UI SnackBar 不显示 Dart 的 "Bad state:" 前缀，错误保持可读。
  static String _errorText(Object error) {
    final text = _shortError(error);
    return text.startsWith('Bad state: ') ? text.substring(11) : text;
  }

  void _finishStartingPlayback(int generation) {
    _startingPlayback = false;
    _acceptStartingDuration = false;
    if (generation != _trackGeneration) {
      _pendingDuration = null;
      return;
    }
    _activePlayback = true;
    final pendingDuration = _pendingDuration;
    _pendingDuration = null;
    if (pendingDuration != null) {
      duration = pendingDuration < Duration.zero
          ? Duration.zero
          : pendingDuration;
      _clock.duration = duration;
      _publishPosition();
    }
    _setPlaying(true);
  }

  Future<void> toggle() async {
    final generation = _trackGeneration;
    await _enqueuePlayerOperation(() async {
      if (generation != _trackGeneration || !_activePlayback) return;
      final shouldPause = _clock.isPlaying;
      if (shouldPause) {
        await _player.pause();
      } else {
        await _player.resume();
      }
      if (generation == _trackGeneration) _setPlaying(!shouldPause);
    });
  }

  Future<void> seek(Duration to) async {
    final generation = _trackGeneration;
    final previousPosition = _clock.position;
    _clock.seek(to);
    _publishPosition();
    notifyListeners();
    try {
      await _enqueuePlayerOperation(() async {
        if (generation == _trackGeneration && _activePlayback) {
          await _player.seek(_clock.position);
        }
      });
    } catch (_) {
      if (generation == _trackGeneration) {
        _clock.seek(previousPosition);
        _publishPosition();
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> setVolume(double v) async {
    volume = v.clamp(0.0, 1.0);
    settingsRevision.value++;
    notifyListeners();
    await _player.setVolume(volume);
  }

  Future<void> setQuality(AudioQuality q) async {
    quality = q;
    settingsRevision.value++;
    notifyListeners();
    final song = current;
    if (song != null) await playSong(song, list: queue);
  }

  /// REA 观察：播放模式三态切换（列表循环 / 随机 / 单曲）。
  void cyclePlayMode() {
    playMode = PlayMode.values[(playMode.index + 1) % PlayMode.values.length];
    shuffle = playMode == PlayMode.shuffle;
    notifyListeners();
  }

  void setEffect(String value) {
    if (kEffects.contains(value)) {
      effect = value;
      settingsRevision.value++;
      notifyListeners();
    }
  }

  /// REA 观察：定时停止，X 分钟后暂停（真实定时器，到点暂停播放）。
  void setSleepTimer(int minutes) {
    _sleepTicker?.cancel();
    _sleepTicker = null;
    if (minutes <= 0) {
      sleepTimer = null;
      _sleepDeadline = null;
    } else {
      sleepTimer = Duration(minutes: minutes);
      _sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
      _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        final deadline = _sleepDeadline;
        if (deadline == null) return;
        if (DateTime.now().isAfter(deadline)) {
          final generation = _trackGeneration;
          _enqueuePlayerOperation(() async {
            if (generation == _trackGeneration && _activePlayback) {
              await _player.pause();
              if (generation == _trackGeneration) _setPlaying(false);
            }
          }).catchError((Object _) {});
          sleepTimer = null;
          _sleepDeadline = null;
          _sleepTicker?.cancel();
          _sleepTicker = null;
          notifyListeners();
        } else {
          notifyListeners(); // 刷新剩余时间显示
        }
      });
    }
    notifyListeners();
  }

  Duration? get sleepRemaining {
    final deadline = _sleepDeadline;
    if (deadline == null) return null;
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  Future<void> next() async {
    if (queue.isEmpty) return;
    // REA 观察：单曲循环时播到结尾重播当前曲。
    if (playMode == PlayMode.single && current != null) {
      playEntry = 'next';
      await playSong(current!, list: queue);
      return;
    }

    // 只有到达队列真实尾部才请求续播；普通歌单没有回调，保持原循环语义。
    if (index >= queue.length - 1 && onQueueExhausted != null) {
      final before = queue.length;
      var more = const <Song>[];
      try {
        more = await onQueueExhausted!();
      } catch (e) {
        AppLog.add('play', 'queue-exhausted 失败，继续本地循环：$e');
      }
      final seen = queue
          .map((song) => song.id)
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final song in more) {
        if (song.id.isEmpty || seen.add(song.id)) queue.add(song);
      }
      if (queue.length > before) {
        playEntry = 'next';
        await _playForward(before);
        return;
      }
    }

    final nextIndex = playMode == PlayMode.shuffle
        ? (DateTime.now().millisecondsSinceEpoch % queue.length)
        : (index < 0 ? 0 : (index + 1) % queue.length);
    playEntry = 'next';
    await _playForward(nextIndex);
  }

  Future<void> previous() async {
    if (queue.isEmpty) return;
    playEntry = 'previous';
    final start = index <= 0 ? queue.length - 1 : index - 1;
    final attempts = queue.length < 5 ? queue.length : 5;
    String? lastError;
    for (var i = 0; i < attempts; i++) {
      final candidate = (start - i) % queue.length;
      index = candidate;
      await playSong(queue[candidate]);
      if (error == null) return;
      lastError = error;
      await stop();
    }
    error = lastError ?? '上一首无法播放';
    notifyListeners();
  }

  /// 从 start 开始最多尝试 5 首；失败后显式 stop 再前进，绝不递归 next()。
  Future<void> _playForward(int start) async {
    final attempts = queue.length < 5 ? queue.length : 5;
    String? lastError;
    for (var i = 0; i < attempts; i++) {
      final candidate = (start + i) % queue.length;
      index = candidate;
      await playSong(queue[candidate]);
      if (error == null) return;
      lastError = error;
      await stop();
    }
    error = lastError ?? '队列中的歌曲均无法播放';
    notifyListeners();
  }

  Future<void> stop() async {
    final generation = ++_trackGeneration;
    _activePlayback = false;
    _startingPlayback = false;
    _acceptStartingDuration = false;
    _pendingDuration = null;
    LeaseProxy.instance.revoke();
    _clock.duration = Duration.zero;
    _clock.reset(Duration.zero);
    position = Duration.zero;
    duration = Duration.zero;
    positionNotifier.value = Duration.zero;
    notifyListeners();
    await _enqueuePlayerOperation(() async {
      if (generation == _trackGeneration) await _player.stop();
    });
  }

  @override
  void dispose() {
    _sleepTicker?.cancel();
    positionNotifier.dispose();
    lyricRevision.dispose();
    settingsRevision.dispose();
    _player.dispose();
    super.dispose();
  }
}
