import 'package:dhakaflix_player/data/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Store store;
  setUp(() async => store = await Store.open(inMemory: true));
  tearDown(() => store.close());

  Future<void> save(
    String path,
    int posMin, {
    int durMin = 100,
    int size = 1,
    int at = 0,
    String? audio,
    String? sub,
  }) => store.saveProgress(
    sourceId: 'df14',
    relPath: path,
    size: size,
    href: '/DHAKA-FLIX-14/$path',
    position: Duration(minutes: posMin),
    duration: Duration(minutes: durMin),
    audioTrack: audio,
    subtitleTrack: sub,
    now: DateTime.fromMillisecondsSinceEpoch(at),
  );

  test('saves and reads back progress keyed by path + size', () async {
    await save('Movies/A (2000)/a.mkv', 10, audio: 'hin', sub: 'eng:1');
    await save('Movies/A (2000)/a.mkv', 20, size: 2); // Same path, different file size.
    final a = await store.progress('df14', 'Movies/A (2000)/a.mkv', 1);
    expect(a!.position, const Duration(minutes: 10));
    expect(a.audioTrack, 'hin');
    expect(a.subtitleTrack, 'eng:1');
    expect((await store.progress('df14', 'Movies/A (2000)/a.mkv', 2))!.position, const Duration(minutes: 20));
    expect(await store.progress('df14', 'missing', 1), isNull);
  });

  test('update keeps earlier track choices unless replaced', () async {
    await save('a', 1, audio: 'kor', sub: 'off');
    await save('a', 2);
    expect((await store.progress('df14', 'a', 1))!.audioTrack, 'kor');
    await save('a', 3, audio: 'hin');
    final r = (await store.progress('df14', 'a', 1))!;
    expect(r.audioTrack, 'hin');
    expect(r.subtitleTrack, 'off');
    expect(r.position, const Duration(minutes: 3));
  });

  test('watched at 95%, and continue watching is most recent first without watched items', () async {
    await save('old', 10, at: 1000);
    await save('new', 10, at: 3000);
    await save('done', 95, at: 2000);
    await save('almost', 94, at: 1500);
    expect((await store.progress('df14', 'done', 1))!.watched, isTrue);
    expect((await store.progress('df14', 'almost', 1))!.watched, isFalse);
    expect((await store.continueWatching()).map((h) => h.relPath), ['new', 'almost', 'old']);
    expect((await store.history()).map((h) => h.relPath), ['new', 'done', 'almost', 'old']);
  });

  test('rewatching a finished item puts it back in continue watching', () async {
    await save('m', 99, at: 1);
    await save('m', 5, at: 2);
    expect((await store.continueWatching()).map((h) => h.relPath), ['m']);
  });

  test('remove one item and clear all', () async {
    await save('a', 1);
    await save('b', 1);
    await store.removeHistory('df14', 'a', 1);
    expect((await store.history()).map((h) => h.relPath), ['b']);
    await store.clearHistory();
    expect(await store.history(), isEmpty);
  });

  test('settings', () async {
    expect(await store.setting(Settings.baseUrl), isNull);
    await store.setSetting(Settings.baseUrl, 'http://x/');
    await store.setSetting(Settings.baseUrl, 'http://y/');
    expect(await store.setting(Settings.baseUrl), 'http://y/');
  });
}
