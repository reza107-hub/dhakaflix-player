// Phase 3 end-to-end UI checks against the real DhakaFlix (read-only).
// Uses its own database file, never the user's history.
// Run: flutter test integration_test/ui_flow_test.dart -d linux
import 'dart:io';

import 'package:dhakaflix_player/app.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:dhakaflix_player/data/store.dart';
import 'package:dhakaflix_player/player/player_controller.dart';
import 'package:dhakaflix_player/player/player_screen.dart';
import 'package:dhakaflix_player/ui/folder_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void log(String s) => debugPrint('UI3 $s');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  MediaKit.ensureInitialized();

  late Store store;
  late AppState app;

  setUpAll(() async {
    final f = File(p.join((await getApplicationSupportDirectory()).path, 'ui_test.db'));
    if (f.existsSync()) f.deleteSync();
    store = await Store.open(fileName: 'ui_test.db');
    app = AppState(store, defaultBaseUrl);
  });

  /// Pumps until [finder] matches or [seconds] pass.
  Future<bool> waitFor(WidgetTester t, Finder finder, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
      if (finder.evaluate().isNotEmpty) return true;
    }
    return false;
  }

  Future<bool> until(WidgetTester t, bool Function() ok, {int seconds = 30}) async {
    for (var i = 0; i < seconds * 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
      if (ok()) return true;
    }
    return ok();
  }

  PlayerController player(WidgetTester t) => t.widget<PlayerScreen>(find.byType(PlayerScreen)).controller;

  Future<void> back(WidgetTester t) async {
    final nav = t.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('search -> folder -> play -> version switch -> continue watching -> remove', (t) async {
    await t.pumpWidget(DhakaFlixApp(state: app));
    expect(await waitFor(t, find.text('Hindi Movies')), isTrue, reason: 'root folders not shown');
    log('home shows categories');

    // Type a big query then quickly the real one: the old search must be cancelled
    // and must not overwrite the new results.
    final box = find.byType(TextField);
    await t.enterText(box, 'the');
    await t.pump(const Duration(milliseconds: 350)); // Debounce fires, big search starts.
    await t.enterText(box, 'khamoshi');
    expect(await waitFor(t, find.textContaining('Khamoshi-The Musical (1996) 1080p')), isTrue);
    await t.pump(const Duration(seconds: 8)); // Give the cancelled big search time to (not) land.
    expect(find.textContaining('results'), findsOneWidget);
    expect(find.textContaining('Khamoshi'), findsWidgets);
    final countText = t.widget<Text>(find.textContaining(' results')).data!;
    log('search results: "$countText"');
    expect(int.parse(countText.split(' ').first), lessThan(50), reason: 'stale big search overwrote results');

    // Open the folder, then the 720p file.
    await t.tap(find.text('Khamoshi-The Musical (1996) 1080p').first);
    final inFolder = find.descendant(of: find.byType(FolderPage), matching: find.textContaining('720p WEBRip'));
    expect(await waitFor(t, inFolder), isTrue);
    await t.pump(const Duration(seconds: 1)); // Let the page transition finish.
    await t.tap(inFolder.first);
    expect(await waitFor(t, find.byType(PlayerScreen)), isTrue);
    final c = player(t);
    expect(
      await until(t, () => c.player.state.playing && c.player.state.position > const Duration(seconds: 1)),
      isTrue,
    );
    log('playing ${c.current!.name}');

    // Versions menu data and switching keeps the position.
    expect(c.versions.map((e) => e.name.contains('1080p')), [true, false]);
    await c.seekTo(const Duration(minutes: 30));
    expect(await until(t, () => c.player.state.position > const Duration(minutes: 30, seconds: 1)), isTrue);
    final before = c.player.state.position;
    await c.switchVersion(c.versions.first);
    expect(
      await until(t, () => c.current!.name.contains('1080p') && c.player.state.position > before, seconds: 40),
      isTrue,
    );
    log('switched to 1080p at ${c.player.state.position.inSeconds}s (was ${before.inSeconds}s)');
    await t.pump(const Duration(seconds: 6)); // Periodic save.

    // Back to home: Continue watching lists the files watched, most recent first.
    await back(t); // player
    await back(t); // folder
    await t.tap(find.byTooltip('Clear'));
    final saved = await store.continueWatching();
    log(
      'saved history: ${saved.map((h) => '${h.relPath.split('/').last} @${h.position.inSeconds}s/${h.duration.inSeconds}s')}',
    );
    final shown = await waitFor(t, find.text('Continue watching'));
    if (!shown) {
      log('visible texts: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).take(15).toList()}');
    }
    expect(shown, isTrue);
    final first = find.descendant(of: find.byType(ListTile), matching: find.textContaining('Khamoshi'));
    expect(first, findsNWidgets(2));
    expect(t.widget<Text>(first.first).data, contains('1080p'));
    log('continue watching shows both versions, 1080p first');

    // Remove one item.
    await t.tap(find.byTooltip('Remove from Continue watching').first);
    await t.pump(const Duration(seconds: 1));
    expect(find.descendant(of: find.byType(ListTile), matching: find.textContaining('Khamoshi')), findsOneWidget);
    log('remove works');
  });

  testWidgets('auto-play next episode with countdown', (t) async {
    await t.pumpWidget(DhakaFlixApp(state: app));
    await t.enterText(find.byType(TextField), '18 again');
    expect(await waitFor(t, find.text('18 Again (TV Series 2020) 720p [Dual Audio]')), isTrue);
    await t.tap(find.text('18 Again (TV Series 2020) 720p [Dual Audio]'));
    expect(await waitFor(t, find.text('Season 1')), isTrue);
    await t.tap(find.text('Season 1'));
    expect(await waitFor(t, find.textContaining('S01E01')), isTrue);
    await t.tap(find.textContaining('S01E01').first);
    expect(await waitFor(t, find.byType(PlayerScreen)), isTrue);
    final c = player(t);
    expect(await until(t, () => c.player.state.playing && c.player.state.duration > Duration.zero), isTrue);
    expect(c.nextUp!.name, contains('S01E02'));
    await c.seekTo(c.player.state.duration - const Duration(seconds: 4));
    expect(await waitFor(t, find.textContaining('Next episode in'), seconds: 30), isTrue, reason: 'no countdown');
    log('countdown shown');
    expect(await until(t, () => c.current!.name.contains('S01E02') && c.player.state.playing, seconds: 30), isTrue);
    log('auto-played ${c.current!.name}');
    final ep1 = (await store.history()).firstWhere((h) => h.relPath.contains('S01E01'));
    expect(ep1.watched, isTrue, reason: 'finished episode must be marked watched');
    await back(t);
  });

  testWidgets('unreachable address shows the ISP-network message, then recovers', (t) async {
    await app.setBaseUrl('http://127.0.0.1:9/DHAKA-FLIX-14/');
    await t.pumpWidget(DhakaFlixApp(state: app));
    expect(await waitFor(t, find.text('DhakaFlix is not reachable. Connect to the ISP network.')), isTrue);
    log('unreachable message shown');
    await app.setBaseUrl(defaultBaseUrl);
    await t.pump();
    expect(await waitFor(t, find.text('Hindi Movies')), isTrue);
    log('recovered after restoring the address');
  });
}
