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
import 'package:dhakaflix_player/ui/settings_page.dart';
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
    app = AppState(store, SourceList.load(null));
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

  /// Like [waitFor], but scrolls the home list down while waiting, because
  /// rows below the screen are not built.
  Future<bool> findOnHome(WidgetTester t, Finder finder, {int seconds = 40}) async {
    for (var i = 0; i < seconds * 2; i++) {
      await t.pump(const Duration(milliseconds: 500));
      if (finder.evaluate().isNotEmpty) return true;
      final list = find.byType(Scrollable).first;
      if (list.evaluate().isNotEmpty) await t.drag(list, const Offset(0, -300), warnIfMissed: false);
    }
    return false;
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
    log('playing ${c.current!.href} from ${c.source.id}, duration ${c.player.state.duration}');
    await c.seekTo(c.player.state.duration - const Duration(seconds: 4));
    expect(await waitFor(t, find.textContaining('Next episode in'), seconds: 30), isTrue, reason: 'no countdown');
    log('countdown shown');
    expect(await until(t, () => c.current!.name.contains('S01E02') && c.player.state.playing, seconds: 30), isTrue);
    log('auto-played ${c.current!.name}');
    final ep1 = (await store.history()).firstWhere((h) => h.relPath.contains('S01E01'));
    expect(ep1.watched, isTrue, reason: 'finished episode must be marked watched');
    await back(t);
  });

  testWidgets('search across servers, filter by server, play from a second server', (t) async {
    await t.pumpWidget(DhakaFlixApp(state: app));
    for (final name in ['DHAKA-FLIX-14', 'DHAKA-FLIX-7', 'DHAKA-FLIX-12', 'DHAKA-FLIX-10']) {
      expect(await findOnHome(t, find.text(name)), isTrue, reason: 'home group $name');
    }
    for (final folder in ['English Movies', 'TV-WEB-Series', 'Documentary']) {
      await t.pumpWidget(DhakaFlixApp(state: app)); // Back to the top.
      expect(await findOnHome(t, find.text(folder)), isTrue, reason: 'root folder $folder');
    }
    log('home grouped by server');

    await t.enterText(find.byType(TextField), 'avatar');
    expect(
      await until(t, () => find.textContaining('waiting for').evaluate().isEmpty && find.textContaining(' results').evaluate().isNotEmpty, seconds: 60),
      isTrue,
    );
    // Each server answered with hits (counts on the filter chips), and rows carry a server label.
    for (final name in ['DHAKA-FLIX-14', 'DHAKA-FLIX-7', 'DHAKA-FLIX-12', 'DHAKA-FLIX-10']) {
      final chip = find.byWidgetPredicate((w) => w is ChoiceChip && (w.label as Text).data!.startsWith('$name ('));
      expect(chip, findsOneWidget, reason: 'chip count for $name');
      log('chip ${(t.widget<ChoiceChip>(chip).label as Text).data}');
    }
    expect(find.textContaining('DHAKA-FLIX-14 ·'), findsWidgets);
    log('all-servers results: ${t.widget<Text>(find.textContaining(' results')).data}');

    // Per-server filter.
    await t.tap(find.byWidgetPredicate((w) => w is ChoiceChip && (w.label as Text).data!.startsWith('DHAKA-FLIX-7')));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('DHAKA-FLIX-14 ·'), findsNothing);
    expect(find.textContaining('DHAKA-FLIX-7 ·'), findsWidgets);
    log('filter DHAKA-FLIX-7: ${t.widget<Text>(find.textContaining(' results')).data}');

    // Open the first DHAKA-FLIX-7 folder and play its first video.
    await t.tap(find.byIcon(Icons.folder_outlined).first);
    final video = find.descendant(of: find.byType(FolderPage), matching: find.byIcon(Icons.play_arrow));
    expect(await waitFor(t, video), isTrue);
    await t.pump(const Duration(seconds: 1));
    await t.tap(video.first);
    expect(await waitFor(t, find.byType(PlayerScreen)), isTrue);
    final c = player(t);
    expect(c.source.id, 'df7');
    expect(await until(t, () => c.player.state.playing && c.player.state.position > const Duration(seconds: 2)), isTrue);
    await c.seekTo(const Duration(minutes: 5));
    expect(await until(t, () => c.player.state.position > const Duration(minutes: 5, seconds: 1)), isTrue);
    await t.pump(const Duration(seconds: 6));
    log('playing from DHAKA-FLIX-7: ${c.current!.name}');
    await back(t);
    await back(t);
    final row = (await store.history()).firstWhere((h) => h.href == c.current!.href);
    expect(row.sourceId, 'df7');
    expect(row.position, greaterThan(const Duration(minutes: 5)));
    log('history row saved with source df7');

    await t.tap(find.byTooltip('Clear'));
    expect(await waitFor(t, find.text('Continue watching')), isTrue);
    expect(find.textContaining(c.current!.name.substring(0, 10)), findsWidgets);
    log('continue watching lists the DHAKA-FLIX-7 item');
  });

  testWidgets('one server unreachable: clear note, others keep working', (t) async {
    final original = app.sources;
    await app.updateSources(original.addCustom('http://127.0.0.1:9/DHAKA-FLIX-14/'));
    await t.pumpWidget(DhakaFlixApp(state: app));
    expect(await waitFor(t, find.text('Hindi Movies')), isTrue);
    expect(await findOnHome(t, find.text('http://127.0.0.1:9/DHAKA-FLIX-14/ is not reachable.')), isTrue);
    log('home: dead server note + other servers listed');
    await t.enterText(find.byType(TextField), 'godfather');
    expect(await waitFor(t, find.textContaining('did not answer (is not reachable)'), seconds: 60), isTrue);
    expect(await waitFor(t, find.textContaining('DHAKA-FLIX-14 ·'), seconds: 60), isTrue);
    log('search: dead server note + results from the others');
    await app.updateSources(original);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('settings: disable and enable a server', (t) async {
    await t.pumpWidget(DhakaFlixApp(state: app));
    expect(await findOnHome(t, find.text('DHAKA-FLIX-10')), isTrue);
    await t.tap(find.byTooltip('Settings'));
    await t.pump(const Duration(seconds: 1));
    final tile = find.widgetWithText(SwitchListTile, 'DHAKA-FLIX-10');
    await t.tap(tile);
    await t.pump(const Duration(milliseconds: 500));
    expect(app.sources.byId('df10')!.enabled, isFalse);
    expect(SourceList.load(await store.setting(Settings.sources)).byId('df10')!.enabled, isFalse, reason: 'saved');
    expect(find.byType(SettingsPage), findsOneWidget);
    await back(t);
    await t.pump(const Duration(seconds: 1));
    expect(await findOnHome(t, find.text('Documentary'), seconds: 8), isFalse, reason: 'DHAKA-FLIX-10 folders hidden');
    expect(find.text('DHAKA-FLIX-10'), findsNothing);
    log('disabled DHAKA-FLIX-10 hidden from home');
    await t.tap(find.byTooltip('Settings'));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.widgetWithText(SwitchListTile, 'DHAKA-FLIX-10'));
    await t.pump(const Duration(milliseconds: 500));
    await back(t);
    expect(await findOnHome(t, find.text('Documentary')), isTrue);
    log('re-enabled DHAKA-FLIX-10 back on home');
  });
}
