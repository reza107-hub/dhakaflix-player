// "Kill the app, reopen, resume" check. Driven by tool/verify_resume_kill.sh:
//   step=play   : opens a file from a fresh on-disk test database and keeps
//                 playing, logging POS every second; the script force-stops
//                 the process (a real kill, no clean shutdown).
//   step=resume : a new process opens the same file and must resume near the
//                 last logged position.
// Uses its own database file, never the user's history.
import 'dart:io';

import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:dhakaflix_player/data/store.dart';
import 'package:dhakaflix_player/player/player_controller.dart';
import 'package:dhakaflix_player/player/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const step = String.fromEnvironment('step');
const dbName = 'resume_kill_test.db';
const folder =
    '/DHAKA-FLIX-14/KOREAN%20TV%20%26%20WEB%20Series/18%20Again%20%28TV%20Series%202020%29%20720p%20%5BDual%20Audio%5D/Season%201/';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();
  final source = DhakaFlixSource(defaultBaseUrl);

  Future<Entry> episode() async =>
      (await DhakaFlixClient(source).list(folder)).firstWhere((e) => e.name.contains('S01E04'));

  testWidgets('resume after kill: $step', (tester) async {
    if (step == 'play') {
      // Start clean so the resume step can only pass via this run's saves.
      final dbFile = File(p.join((await getApplicationSupportDirectory()).path, dbName));
      if (dbFile.existsSync()) dbFile.deleteSync();
    }
    final store = await Store.open(fileName: dbName);
    final e = await episode();
    final c = PlayerController(source: source, store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(controller: c, entry: e),
      ),
    );

    if (step == 'play') {
      for (var i = 0; i < 40 && c.player.state.position < const Duration(seconds: 1); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      await c.seekTo(const Duration(minutes: 20));
      debugPrint('RK KILL_ME');
      // Keep playing until the script kills the process.
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        debugPrint('RK POS ${c.player.state.position.inMilliseconds}');
      }
      fail('process was not killed');
    } else {
      final saved = await store.progress(source.id, source.relativePath(e.href), e.size!);
      debugPrint('RK SAVED ${saved?.position.inMilliseconds}');
      expect(saved, isNotNull, reason: 'nothing was saved before the kill');
      var resumed = Duration.zero;
      for (var i = 0; i < 60 && resumed < const Duration(minutes: 1); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        resumed = c.player.state.position;
      }
      debugPrint('RK RESUMED ${resumed.inMilliseconds}');
      expect((resumed - saved!.position).inSeconds.abs(), lessThan(5));
      await tester.pumpWidget(const SizedBox());
      await store.close();
    }
  });
}
