// Phase 2 on-device checks against real DhakaFlix files (read-only).
// Run: flutter test integration_test/player_test.dart -d <device>
// The network-drop test prints "DROP_NOW"; the driver script then turns the
// network off for ~10 s (see tool/verify_player.sh).

import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:dhakaflix_player/data/store.dart';
import 'package:dhakaflix_player/player/player_controller.dart';
import 'package:dhakaflix_player/player/player_screen.dart';
import 'package:dhakaflix_player/player/sidecar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

const root = '/DHAKA-FLIX-14/';
const h264Mp4 = '${root}Animation%20Movies/%282003%29/Tokyo%20Godfathers%20%282003%29%20720p/';
const hevcSeries =
    '${root}KOREAN%20TV%20%26%20WEB%20Series/18%20Again%20%28TV%20Series%202020%29%20720p%20%5BDual%20Audio%5D/Season%201/';
const ac3Ass = '${root}Animation%20Movies/%282004%29/Appleseed%20%282004%29%20720p%20%5BDual%20Audio%5D/';
const dts10gb =
    '${root}English%20Movies%20%281080p%29/%281995%29%201080p%20%26%20Before/Pulp%20Fiction%20%281994%29%201080p/';
const sidecarFolder =
    '${root}Animation%20Movies/%282013%29/Batman-The%20Dark%20Knight%20Returns%2C%20Part%202%20%282013%29%20720p/';

void log(String s) => debugPrint('PH2 $s');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Draw every frame so the video is visible on the device while tests run
  // (the default only draws when the test pumps, which shows a black screen).
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();
  final source = DhakaFlixSource(defaultBaseUrl);
  final client = DhakaFlixClient(source);
  late Store store;

  setUpAll(() async => store = await Store.open(inMemory: true));

  /// First video in [folder] whose name contains [contains], plus its siblings.
  Future<(Entry, List<Entry>)> pick(String folder, [String contains = '']) async {
    final items = await client.list(folder);
    return (items.firstWhere((e) => isVideo(e) && e.name.contains(contains)), items);
  }

  Future<String?> prop(PlayerController c, String k) async {
    try {
      return await (c.player.platform as NativePlayer).getProperty(k);
    } catch (_) {
      return null;
    }
  }

  Future<bool> until(bool Function() ok, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (ok()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return ok();
  }

  /// Playing and the clock moved past [after] + 1 s.
  Future<bool> advancing(PlayerController c, Duration after, {int seconds = 30}) => until(
    () => c.player.state.playing && c.player.state.position > after + const Duration(seconds: 1),
    seconds: seconds,
  );

  /// Waits for any subtitle text to appear (proves the track renders).
  Future<String?> subtitleText(PlayerController c, {int seconds = 40}) async {
    for (var i = 0; i < seconds * 2; i++) {
      final t = await prop(c, 'sub-text');
      if (t != null && t.trim().isNotEmpty) return t.trim().replaceAll('\n', ' ');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  Future<PlayerController> start(WidgetTester tester, Entry e, List<Entry> sibs) async {
    final c = PlayerController(source: source, store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(controller: c, entry: e, siblings: sibs),
      ),
    );
    final sw = Stopwatch()..start();
    expect(await advancing(c, Duration.zero, seconds: 40), isTrue, reason: 'playback did not start: ${e.name}');
    log(
      '[${e.name.substring(0, e.name.length.clamp(0, 40))}] start ${sw.elapsedMilliseconds}ms '
      'vcodec=${await prop(c, 'video-format')} ${c.player.state.width}x${c.player.state.height} '
      'hwdec=${await prop(c, 'hwdec-current')} acodec=${await prop(c, 'audio-codec-name')}',
    );
    return c;
  }

  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox()); // Disposes the screen -> controller.close().
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> deepSeek(PlayerController c, double fraction) async {
    final target = c.player.state.duration * fraction;
    final sw = Stopwatch()..start();
    await c.seekTo(target);
    expect(await advancing(c, target, seconds: 30), isTrue, reason: 'seek to $target');
    log(
      '  seek ${(fraction * 100).round()}% (${target.inMinutes}m) ok in ${sw.elapsedMilliseconds}ms, '
      'drops=${await prop(c, 'decoder-frame-drop-count')}/${await prop(c, 'frame-drop-count')}',
    );
  }

  testWidgets('H.264 MP4: play, seek, speed, ±10 s', (tester) async {
    final (e, sibs) = await pick(h264Mp4);
    final c = await start(tester, e, sibs);
    await deepSeek(c, 0.5);
    final before = c.player.state.position;
    await c.seekBy(c.seekStep);
    expect(await until(() => c.player.state.position >= before + const Duration(seconds: 9)), isTrue);
    await c.setSpeed(2.0);
    expect(await prop(c, 'speed'), startsWith('2.0'));
    await c.setSpeed(1.0);
    log('  ±10s and speed ok');
    await stop(tester);
  });

  testWidgets('HEVC 10-bit MKV: two AAC tracks switch live, embedded SRT renders, preferred language kept', (
    tester,
  ) async {
    final (e, sibs) = await pick(hevcSeries, 'S01E01');
    final c = await start(tester, e, sibs);
    await deepSeek(c, 0.3);
    final audio = c.audioTracks;
    expect(audio.length, 2);
    final pos = c.player.state.position;
    await c.selectAudio(audio[1]);
    expect(await advancing(c, pos), isTrue);
    expect(await prop(c, 'aid'), audio[1].id);
    log('  audio switched to ${audio[1].language} without restart');
    final srt = c.subtitleOptions.firstWhere((o) => o.track?.codec == 'subrip');
    await c.selectSubtitle(srt);
    final text = await subtitleText(c);
    expect(text, isNotNull, reason: 'no subtitle text appeared');
    log('  SRT text: "${text!.substring(0, text.length.clamp(0, 50))}"');
    await c.setSubtitleDelay(0.5);
    await c.setSubtitleScale(1.3);
    expect(await prop(c, 'sub-delay'), startsWith('0.5'));
    await stop(tester);
    expect(await store.setting(Settings.preferredAudioLanguage), audio[1].language);

    // Episode 2 should open with the preferred (second) language, not the default.
    final (e2, _) = await pick(hevcSeries, 'S01E02');
    final c2 = await start(tester, e2, sibs);
    expect(await prop(c2, 'aid'), c2.audioTracks.firstWhere((t) => t.language == audio[1].language).id);
    log('  next file opened with preferred audio ${audio[1].language}');
    await stop(tester);
  });

  testWidgets('AC3 x4 + embedded ASS (libass), PGS hidden', (tester) async {
    final (e, sibs) = await pick(ac3Ass, 'Appleseed');
    final c = await start(tester, e, sibs);
    expect(await prop(c, 'audio-codec-name'), 'ac3');
    expect(c.audioTracks.length, 4);
    final pos = c.player.state.position;
    await c.selectAudio(c.audioTracks[1]);
    expect(await advancing(c, pos), isTrue);
    final opts = c.subtitleOptions;
    expect(opts.where((o) => o.track?.codec == 'hdmv_pgs_subtitle'), isEmpty, reason: 'PGS must be hidden');
    final ass = opts.firstWhere((o) => o.track?.codec == 'ass');
    await deepSeek(c, 0.2);
    await c.selectSubtitle(ass);
    final text = await subtitleText(c);
    expect(text, isNotNull);
    log('  ASS text: "${text!.substring(0, text.length.clamp(0, 50))}" (${opts.length - 1} text options)');
    await stop(tester);
  });

  testWidgets('HEVC 10-bit 1080p DTS, 10 GB: deep seeks', (tester) async {
    final (e, sibs) = await pick(dts10gb, 'DTS');
    expect(e.size!, greaterThan(9 * 1024 * 1024 * 1024));
    final c = await start(tester, e, sibs);
    expect(await prop(c, 'audio-codec-name'), 'dts');
    await deepSeek(c, 0.9);
    await deepSeek(c, 0.1);
    await deepSeek(c, 0.6);
    await stop(tester);
  });

  testWidgets('sidecar SRT with a non-matching name is offered and renders', (tester) async {
    final (e, sibs) = await pick(sidecarFolder);
    final c = await start(tester, e, sibs);
    final ext = c.subtitleOptions.where((o) => o.sidecar != null).toList();
    expect(ext, hasLength(1));
    await deepSeek(c, 0.25);
    await c.selectSubtitle(ext.single);
    final text = await subtitleText(c);
    expect(text, isNotNull);
    log('  sidecar "${ext.single.sidecar!.name}" text: "${text!.substring(0, text.length.clamp(0, 50))}"');
    await stop(tester);
  });

  testWidgets('resume: reopening continues from the saved position with saved tracks', (tester) async {
    final (e, sibs) = await pick(hevcSeries, 'S01E03');
    var c = await start(tester, e, sibs);
    await deepSeek(c, 0.4);
    await c.selectSubtitle(c.subtitleOptions[1]);
    await Future<void>.delayed(const Duration(seconds: 6)); // Periodic save.
    final saved = c.player.state.position;
    await stop(tester);
    final row = await store.progress(source.relativePath(e.href), e.size!);
    expect((row!.position - saved).inSeconds.abs(), lessThan(7));
    c = await start(tester, e, sibs);
    final resumedAt = c.player.state.position;
    expect(
      (resumedAt - row.position).inSeconds.abs(),
      lessThan(8),
      reason: 'resumed at $resumedAt, saved ${row.position}',
    );
    expect(c.subtitleKey, row.subtitleTrack);
    log('  resumed at ${resumedAt.inSeconds}s (saved ${row.position.inSeconds}s), subtitle ${c.subtitleKey}');
    await stop(tester);
  });

  testWidgets('network drop: reconnects and continues from the same spot', (tester) async {
    final (e, sibs) = await pick(dts10gb, 'DTS');
    final c = await start(tester, e, sibs);
    await deepSeek(c, 0.5);
    final before = c.player.state.position;
    log('DROP_NOW');
    // Driver turns the network off now and back on 90 s later: longer than the
    // buffer lasts, so playback really stalls and must recover.
    final dropped = await until(() => c.reconnecting != null, seconds: 85);
    final stalledAt = c.player.state.position;
    log(
      '  stall noticed: $dropped at ${stalledAt.inSeconds}s reconnecting="${c.reconnecting}" buffering=${c.player.state.buffering}',
    );
    expect(dropped, isTrue, reason: 'playback never stalled; outage shorter than the buffer?');
    final recovered = await until(
      () =>
          c.reconnecting == null &&
          c.player.state.playing &&
          c.player.state.position > before + const Duration(seconds: 5),
      seconds: 300,
    );
    final after = c.player.state.position;
    log('  end state: reconnecting="${c.reconnecting}" playing=${c.player.state.playing} '
        'buffering=${c.player.state.buffering} pos=${after.inSeconds}s '
        'idle=${await prop(c, 'idle-active')} cache=${await prop(c, 'paused-for-cache')} path=${(await prop(c, 'path'))?.length}');
    expect(recovered, isTrue, reason: 'did not recover; pos=$after');
    // Resumed near where it stalled: no restart from 0, no big jump.
    expect((after - stalledAt).inSeconds, inInclusiveRange(0, 60), reason: 'stalled $stalledAt, now $after');
    log('  recovered: dropped at ${before.inSeconds}s, stalled at ${stalledAt.inSeconds}s, now ${after.inSeconds}s');
    await stop(tester);
  });
}
