/// Playback logic around media_kit: resume, progress saving, track choice,
/// sidecar subtitles and recovery from network drops. No UI here.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import '../core/dhakaflix_client.dart';
import '../core/media_names.dart';
import '../core/source.dart';
import '../data/store.dart';
import 'sidecar.dart';

/// Subtitle codecs we hide in v1 (image based).
const imageSubtitleCodecs = {'hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle', 'xsub'};

/// A subtitle choice shown in the menu: embedded track or sidecar file.
class SubtitleOption {
  const SubtitleOption._(this.key, this.label, {this.track, this.sidecar});
  static const off = SubtitleOption._('off', 'Off');

  /// Stable key stored in history: `off`, `emb:<id>:<lang>` or `ext:<href>`.
  final String key;
  final String label;
  final SubtitleTrack? track;
  final Entry? sidecar;
}

class PlayerController extends ChangeNotifier {
  PlayerController({required this.source, required this.store, Player? player})
    : player =
          player ??
          Player(
            configuration: PlayerConfiguration(
              title: 'DhakaFlix Player',
              bufferSize: 64 * 1024 * 1024,
              libass: true,
              libassAndroidFont: 'assets/fonts/NotoSans-Regular.ttf',
              libassAndroidFontName: 'Noto Sans',
              // Only plain network protocols: no file://, data:, etc.
              protocolWhitelist: const ['http', 'https', 'tcp', 'tls'],
            ),
          ) {
    _subs.addAll([
      this.player.stream.tracks.listen((_) => notifyListeners()),
      this.player.stream.playing.listen(_onPlaying),
      this.player.stream.completed.listen(_onCompleted),
      this.player.stream.error.listen(_onError),
      this.player.stream.position.listen(_onPosition),
    ]);
    _configureMpv();
  }

  final DhakaFlixSource source;
  final Store store;
  final Player player;
  final _subs = <StreamSubscription<Object?>>[];

  Entry? _current;
  List<Entry> _siblings = const [];
  List<SubtitleOption> _sidecars = const [];
  String _subtitleKey = SubtitleOption.off.key;
  Timer? _saveTimer;
  Duration _lastGood = Duration.zero;
  Duration _knownDuration = Duration.zero;
  bool _seeking = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  Duration _watchPos = Duration.zero;
  int _stuckSeconds = 0;
  bool _disposed = false;

  /// Seconds without progress while "playing" before we call it a lost
  /// connection. mpv does not always report buffering when the network dies.
  static const stallSeconds = 12;

  /// Non-null while recovering from a network drop.
  String? reconnecting;

  /// Set when the file cannot be played at all.
  String? fatalError;

  /// Called when the file reaches its natural end (used for auto-next later).
  VoidCallback? onFinished;

  Entry? get current => _current;

  /// Other resolutions of the current file in the same folder (empty if none).
  List<Entry> get versions => _current == null ? const [] : versionsOf(_current!, _siblings);

  /// The next episode in the same folder, if the current file is an episode.
  Entry? get nextUp => _current == null ? null : nextEpisode(_current!, _siblings);

  /// Reopens another version of the current file at the same position.
  Future<void> switchVersion(Entry e) async {
    if (e.href == _current?.href) return;
    final at = player.state.position;
    await open(e, siblings: _siblings, startAt: at);
  }

  /// Plays the next episode from where it was left (or the start).
  Future<void> playNext() async {
    final n = nextUp;
    if (n != null) await open(n, siblings: _siblings);
  }

  String get subtitleKey => _subtitleKey;

  /// The audio track actually playing. media_kit reports "auto" until a track
  /// is chosen, so ask mpv which one it picked.
  String? _audioId;
  String? get currentAudioId => _audioId;

  Future<void> _refreshAudioId() async {
    final p = player.platform;
    if (p is NativePlayer) _audioId = await p.getProperty('aid');
  }

  Duration seekStep = const Duration(seconds: 10);
  double _subScale = 1.0;
  double _subDelay = 0.0;
  double get subtitleScale => _subScale;
  double get subtitleDelay => _subDelay;

  Future<void> _configureMpv() async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    await p.setProperty('user-agent', userAgent);
    await p.setProperty('network-timeout', '20');
    // Keep memory modest: forward cache + a little back-buffer for quick rewinds.
    await p.setProperty('demuxer-max-back-bytes', '${32 * 1024 * 1024}');
    // Let ffmpeg retry dropped HTTP connections before mpv gives up.
    await p.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10',
    );
    await p.setProperty('sub-ass-override', 'scale'); // Size slider also scales ASS.
  }

  /// Audio tracks of the current file (real tracks only).
  List<AudioTrack> get audioTracks => player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();

  /// Text subtitle options: embedded tracks then sidecar files. Image subs hidden.
  List<SubtitleOption> get subtitleOptions => [
    SubtitleOption.off,
    for (final t in player.state.tracks.subtitle)
      if (t.id != 'auto' && t.id != 'no' && !t.uri && !t.data && !imageSubtitleCodecs.contains(t.codec))
        SubtitleOption._('emb:${t.id}:${t.language ?? ''}', trackLabel(t.language, t.title, t.id), track: t),
    ..._sidecars,
  ];

  /// Opens [entry] (a video file inside the source) and resumes it.
  /// [startAt] overrides the saved position (used when switching versions).
  Future<void> open(Entry entry, {List<Entry> siblings = const [], Duration? startAt}) async {
    if (entry.sourceId != source.id) throw ArgumentError('Entry is from another server: ${entry.sourceId}');
    final url = source.urlFor(entry.href);
    if (!source.allows(url)) throw ArgumentError('Refusing to play outside DhakaFlix: $url');
    await _saveNow();
    _current = entry;
    _siblings = siblings;
    fatalError = null;
    reconnecting = null;
    _reconnectAttempt = 0;
    _knownDuration = Duration.zero;
    _sidecars = [
      for (final s in sidecarsFor(entry, siblings))
        SubtitleOption._('ext:${s.href}', '${sidecarLanguage(s.name) ?? 'External'} · ${s.name}', sidecar: s),
    ];
    seekStep = Duration(seconds: int.tryParse(await store.setting(Settings.seekSeconds) ?? '') ?? 10);
    final saved = await store.progress(source.id, source.relativePath(entry.href), entry.size ?? 0);
    final start = startAt ?? ((saved != null && !saved.watched) ? saved.position : Duration.zero);
    _lastGood = start;
    await _openAt(url, start);
    if (_disposed) return; // Closed (e.g. Back pressed) while loading.
    await _applyTrackChoices(saved);
    if (_disposed) return;
    await _refreshAudioId();
    if (_disposed) return;
    _startSaving();
    notifyListeners();
  }

  Future<void> _openAt(Uri url, Duration start) async {
    await player.open(Media(url.toString(), start: start > Duration.zero ? start : null));
    // Wait for tracks/duration so choices and seeks apply to this file.
    await player.stream.duration
        .firstWhere((d) => d > Duration.zero, orElse: () => Duration.zero) // Stream ends if closed meanwhile.
        .timeout(const Duration(seconds: 30), onTimeout: () => Duration.zero);
    _knownDuration = player.state.duration;
  }

  Future<void> _applyTrackChoices(HistoryItem? saved) async {
    // Audio: this file's last choice, else the preferred language, else default.
    final audio = audioTracks;
    final wanted = saved?.audioTrack ?? await store.setting(Settings.preferredAudioLanguage);
    if (wanted != null && audio.length > 1) {
      final match = _findAudio(audio, wanted);
      if (match != null) await player.setAudioTrack(match);
    }
    // Subtitles: this file's last choice, else the "on by default" setting, else off.
    final options = subtitleOptions;
    String? key = saved?.subtitleTrack;
    if (key == null && await store.setting(Settings.subtitlesOnByDefault) == 'true' && options.length > 1) {
      key = options[1].key;
    }
    final opt = key == null ? null : _findSubtitle(options, key);
    await selectSubtitle(opt ?? SubtitleOption.off, remember: false);
  }

  /// Stored as `id:lang`; matches by id+lang first, then by language.
  AudioTrack? _findAudio(List<AudioTrack> tracks, String stored) {
    final parts = stored.split(':');
    final lang = parts.length > 1 ? parts.sublist(1).join(':') : parts.first;
    if (parts.length > 1) {
      for (final t in tracks) {
        if (t.id == parts.first && (t.language ?? '') == lang) return t;
      }
    }
    for (final t in tracks) {
      if (lang.isNotEmpty && t.language == lang) return t;
    }
    return null;
  }

  SubtitleOption? _findSubtitle(List<SubtitleOption> options, String key) {
    for (final o in options) {
      if (o.key == key) return o;
    }
    // Embedded track id changed? Fall back to same language.
    if (key.startsWith('emb:')) {
      final lang = key.split(':').last;
      for (final o in options) {
        if (o.track != null && lang.isNotEmpty && o.track!.language == lang) return o;
      }
    }
    return null;
  }

  Future<void> selectAudio(AudioTrack t) async {
    await player.setAudioTrack(t);
    _audioId = t.id;
    final key = '${t.id}:${t.language ?? ''}';
    if (t.language != null && t.language!.isNotEmpty) {
      await store.setSetting(Settings.preferredAudioLanguage, t.language!);
    }
    await _saveNow(audioTrack: key);
    notifyListeners();
  }

  Future<void> selectSubtitle(SubtitleOption o, {bool remember = true}) async {
    if (o.track != null) {
      await player.setSubtitleTrack(o.track!);
    } else if (o.sidecar != null) {
      final url = source.urlFor(o.sidecar!.href);
      if (!source.allows(url)) return;
      await player.setSubtitleTrack(SubtitleTrack.uri(url.toString(), title: o.label));
    } else {
      await player.setSubtitleTrack(SubtitleTrack.no());
    }
    _subtitleKey = o.key;
    if (remember) await _saveNow(subtitleTrack: o.key);
    notifyListeners();
  }

  Future<void> setSubtitleScale(double v) async {
    _subScale = v.clamp(0.5, 3.0);
    await _mpv('sub-scale', _subScale.toStringAsFixed(2));
    notifyListeners();
  }

  Future<void> setSubtitleDelay(double seconds) async {
    _subDelay = (seconds * 10).roundToDouble() / 10;
    await _mpv('sub-delay', _subDelay.toStringAsFixed(1));
    notifyListeners();
  }

  Future<void> setSpeed(double rate) async {
    await player.setRate(rate);
    notifyListeners();
  }

  Future<void> _mpv(String k, String v) async {
    final p = player.platform;
    if (p is NativePlayer) await p.setProperty(k, v);
  }

  Future<void> seekBy(Duration d) => seekTo(player.state.position + d);

  Future<void> seekTo(Duration target) async {
    final dur = player.state.duration;
    var t = target < Duration.zero ? Duration.zero : target;
    if (dur > Duration.zero && t > dur) t = dur;
    _seeking = true;
    await player.seek(t);
    _seeking = false;
    _lastGood = t;
    await _saveNow();
  }

  // ---- Progress saving ----

  void _startSaving() {
    _watchdog?.cancel();
    _stuckSeconds = 0;
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _checkStall());
    _saveTimer?.cancel();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.state.playing) _saveNow();
    });
  }

  void _checkStall() {
    final pos = player.state.position;
    final shouldMove = player.state.playing && !_seeking && reconnecting == null && fatalError == null;
    if (!shouldMove || pos != _watchPos) {
      _watchPos = pos;
      _stuckSeconds = 0;
      return;
    }
    if (++_stuckSeconds >= stallSeconds) {
      _stuckSeconds = 0;
      debugPrint('stall: no progress for ${stallSeconds}s at $pos');
      _scheduleReconnect('Connection lost');
    }
  }

  void _onPlaying(bool playing) {
    if (!playing) _saveNow(); // Save on pause.
    notifyListeners();
  }

  void _onPosition(Duration p) {
    if (p > Duration.zero && reconnecting == null && !_seeking) _lastGood = p;
    if (player.state.duration > Duration.zero) _knownDuration = player.state.duration;
  }

  /// Saves now. Also used on app background / exit.
  Future<void> saveNow() => _saveNow();

  Future<void> _saveNow({String? audioTrack, String? subtitleTrack}) async {
    final e = _current;
    final dur = _knownDuration;
    if (e == null || dur <= Duration.zero || _disposed) return;
    await store.saveProgress(
      sourceId: source.id,
      relPath: source.relativePath(e.href),
      size: e.size ?? 0,
      href: e.href,
      position: _lastGood,
      duration: dur,
      audioTrack: audioTrack,
      subtitleTrack: subtitleTrack,
    );
  }

  // ---- End of file and recovery ----

  void _onCompleted(bool completed) {
    if (!completed || _current == null) return;
    final dur = _knownDuration;
    // A true end is near the duration; an early "end" means the stream broke.
    if (dur > Duration.zero && _lastGood < dur - const Duration(seconds: 15)) {
      _scheduleReconnect('Connection lost');
      return;
    }
    _lastGood = dur;
    _saveNow();
    onFinished?.call();
  }

  void _onError(String message) {
    debugPrint('player error: $message');
    if (_current == null) return;
    // Before anything played, an error means the file itself is unplayable,
    // unless the server is unreachable (then retry).
    if (_knownDuration == Duration.zero && _lastGood == Duration.zero) {
      _probeServer().then((up) {
        if (up) {
          fatalError = 'This file cannot be played.\n$message';
          notifyListeners();
        } else {
          _scheduleReconnect(unreachableMessage);
        }
      });
      return;
    }
    _scheduleReconnect('Connection lost');
  }

  void _scheduleReconnect(String reason) {
    if (_disposed || _reconnectTimer?.isActive == true) return;
    reconnecting = '$reason. Reconnecting…';
    notifyListeners();
    final delay = Duration(seconds: [2, 3, 5, 10, 15][_reconnectAttempt.clamp(0, 4)]);
    _reconnectAttempt++;
    _reconnectTimer = Timer(delay, _reconnect);
  }

  Future<void> _reconnect() async {
    final e = _current;
    if (e == null || _disposed) return;
    if (!await _probeServer()) {
      reconnecting = null; // Allow rescheduling.
      _scheduleReconnect(unreachableMessage);
      return;
    }
    final at = _lastGood;
    debugPrint('reconnect: server up, reopening at $at');
    await _openAt(source.urlFor(e.href), at);
    debugPrint(
      'reconnect: opened, duration=${player.state.duration} pos=${player.state.position} playing=${player.state.playing}',
    );
    // Re-apply current choices (open() resets tracks).
    await _applyTrackChoices(await store.progress(source.id, source.relativePath(e.href), e.size ?? 0));
    await _refreshAudioId();
    if (player.state.duration > Duration.zero) {
      reconnecting = null;
      _reconnectAttempt = 0;
      await player.play();
    } else {
      reconnecting = null;
      _scheduleReconnect('Connection lost');
    }
    notifyListeners();
  }

  /// Cheap reachability check: a 1-byte Range GET on the current file.
  Future<bool> _probeServer() async {
    final e = _current;
    if (e == null) return false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(source.urlFor(e.href));
      req.headers
        ..set(HttpHeaders.rangeHeader, 'bytes=0-0')
        ..set(HttpHeaders.userAgentHeader, userAgent);
      final res = await req.close().timeout(const Duration(seconds: 5));
      await res.drain<void>();
      return res.statusCode == 206 || res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Saves progress, then releases the player. Call instead of [dispose].
  Future<void> close() async {
    if (_disposed) return;
    await _saveNow();
    _disposed = true;
    _saveTimer?.cancel();
    _reconnectTimer?.cancel();
    _watchdog?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await player.dispose();
    dispose();
  }
}

/// Human label for a track: "Hindi · Title" or "Track 2".
String trackLabel(String? lang, String? title, String id) {
  final name = languageName(lang);
  final t = (title ?? '').trim();
  // Release-group noise like "MoviesMod.plus" is not useful.
  final useful = t.isNotEmpty && !RegExp(r'\.(plus|com|org|net|in|me)\b', caseSensitive: false).hasMatch(t);
  if (name != null && useful) return '$name · $t';
  if (name != null) return name;
  if (useful) return t;
  return 'Track $id';
}

/// ISO 639-1/-2 codes to names for the languages seen on DhakaFlix.
String? languageName(String? code) {
  if (code == null || code.isEmpty || code == 'und') return null;
  const names = {
    'en': 'English',
    'eng': 'English',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'bn': 'Bengali',
    'ben': 'Bengali',
    'ko': 'Korean',
    'kor': 'Korean',
    'ja': 'Japanese',
    'jpn': 'Japanese',
    'ta': 'Tamil',
    'tam': 'Tamil',
    'te': 'Telugu',
    'tel': 'Telugu',
    'ml': 'Malayalam',
    'mal': 'Malayalam',
    'kn': 'Kannada',
    'kan': 'Kannada',
    'mr': 'Marathi',
    'mar': 'Marathi',
    'ur': 'Urdu',
    'urd': 'Urdu',
    'zh': 'Chinese',
    'chi': 'Chinese',
    'zho': 'Chinese',
    'ar': 'Arabic',
    'ara': 'Arabic',
    'es': 'Spanish',
    'spa': 'Spanish',
    'fr': 'French',
    'fre': 'French',
    'fra': 'French',
    'de': 'German',
    'ger': 'German',
    'deu': 'German',
    'it': 'Italian',
    'ita': 'Italian',
    'ru': 'Russian',
    'rus': 'Russian',
    'pt': 'Portuguese',
    'por': 'Portuguese',
    'tr': 'Turkish',
    'tur': 'Turkish',
    'th': 'Thai',
    'tha': 'Thai',
    'vi': 'Vietnamese',
    'vie': 'Vietnamese',
    'id': 'Indonesian',
    'ind': 'Indonesian',
    'fa': 'Persian',
    'per': 'Persian',
  };
  return names[code.toLowerCase()] ?? code;
}
