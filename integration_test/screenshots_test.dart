// Renders key screens at phone and desktop sizes into build/screenshots/ for
// visual review. Live DhakaFlix data; separate test database.
// Run: flutter test integration_test/screenshots_test.dart -d linux
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dhakaflix_player/app.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:dhakaflix_player/data/store.dart';
import 'package:dhakaflix_player/player/player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();
  final outDir = Directory('build/screenshots')..createSync(recursive: true);
  final key = GlobalKey();

  Future<void> shot(WidgetTester t, String name) async {
    await t.pump(const Duration(milliseconds: 600));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(p.join(outDir.path, '$name.png')).writeAsBytesSync(bytes!.buffer.asUint8List());
    debugPrint('SHOT $name');
  }

  Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4 && f.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  for (final (label, size) in [('phone', const Size(400, 860)), ('desktop', const Size(1280, 800))]) {
    testWidgets('screens $label', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = size;
      addTearDown(t.view.reset);
      final dbFile = File(p.join((await getApplicationSupportDirectory()).path, 'shots_$label.db'));
      if (dbFile.existsSync()) dbFile.deleteSync();
      final store = await Store.open(fileName: 'shots_$label.db');
      // Seed Continue watching with one real episode.
      await store.saveProgress(
        sourceId: 'df14',
        relPath: 'x',
        size: 404455447,
        href: '/DHAKA-FLIX-14/KOREAN%20TV%20%26%20WEB%20Series/18%20Again%20%28TV%20Series%202020%29%20720p%20%5BDual%20Audio%5D/Season%201/18%20Again%20S01E01%20%20720p%20AMZN%20WEBRip%20x265%20HEVC%20ESub%20%5BDual%20Audio%5D%5BHindi%202.0%2BKorean%202.0%5D%20-MsMod.mkv',
        position: const Duration(minutes: 41),
        duration: const Duration(minutes: 66),
      );
      final app = AppState(store, SourceList.load(null));
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: DhakaFlixApp(state: app),
        ),
      );
      await waitFor(t, find.text('Hindi Movies'));
      await shot(t, '${label}_1_home');

      await t.enterText(find.byType(TextField), 'godfather');
      await waitFor(t, find.textContaining(' results'));
      for (var i = 0; i < 240 && find.textContaining('waiting for').evaluate().isNotEmpty; i++) {
        await t.pump(const Duration(milliseconds: 250)); // All servers answered.
      }
      await shot(t, '${label}_2_search');

      await t.tap(find.byTooltip('Clear'));
      await t.pump(const Duration(milliseconds: 500));
      await t.tap(find.text('KOREAN TV & WEB Series'));
      await waitFor(t, find.textContaining('18 Again (TV Series 2020)'));
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.textContaining('18 Again (TV Series 2020)').last);
      await waitFor(t, find.text('Season 1'));
      await t.tap(find.text('Season 1'));
      await waitFor(t, find.textContaining('S01E10'));
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${label}_3_episodes');

      await t.tap(find.textContaining('S01E01').last);
      await waitFor(t, find.byType(PlayerScreen));
      await t.pump(const Duration(seconds: 6));
      // Desktop controls appear on mouse movement.
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset(size.width / 2, size.height / 2));
      await mouse.moveTo(Offset(size.width / 2 + 20, size.height / 2 + 20));
      await t.pump(const Duration(milliseconds: 400));
      await shot(t, '${label}_4_player');
      await t.tap(find.byTooltip('Audio, subtitles, speed'));
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${label}_5_player_menu');
      // One audio track must be marked as playing.
      expect(find.byIcon(Icons.radio_button_checked), findsNWidgets(2)); // Audio + subtitle "Off".
      await t.tapAt(const Offset(10, 10)); // Close sheet.
      await t.pump(const Duration(milliseconds: 500));
      t.state<NavigatorState>(find.byType(Navigator).first)
        ..pop()
        ..pop()
        ..pop()
        ..pop();
      await t.pump(const Duration(seconds: 1));
      await t.tap(find.byTooltip('Settings'));
      await t.pump(const Duration(seconds: 1));
      await shot(t, '${label}_6_settings');
      await store.close();
    });
  }
}
