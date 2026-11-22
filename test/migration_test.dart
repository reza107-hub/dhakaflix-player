// v1 (single server) -> v2 (source id in the history key) database migration.
import 'dart:io';

import 'package:dhakaflix_player/data/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The exact v1.0.0 schema (copied from the released Store._create).
Future<void> createV1(String path, {String? baseUrl, required List<List<Object?>> rows}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE history(
            rel_path TEXT NOT NULL, size INTEGER NOT NULL, href TEXT NOT NULL,
            position_ms INTEGER NOT NULL, duration_ms INTEGER NOT NULL, last_watched INTEGER NOT NULL,
            watched INTEGER NOT NULL DEFAULT 0, audio_track TEXT, subtitle_track TEXT,
            PRIMARY KEY (rel_path, size)
          )''');
        await db.execute('CREATE INDEX history_recent ON history(last_watched DESC)');
        await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      },
    ),
  );
  for (final r in rows) {
    await db.rawInsert('INSERT INTO history VALUES(?,?,?,?,?,?,?,?,?)', r);
  }
  await db.insert('settings', {'key': 'audio_language', 'value': 'hin'});
  await db.insert('settings', {'key': 'seek_seconds', 'value': '15'});
  if (baseUrl != null) await db.insert('settings', {'key': 'base_url', 'value': baseUrl});
  await db.close();
}

/// Realistic v1 rows: unicode, brackets, ampersands, same path with two
/// sizes, watched and unfinished items, track choices.
List<List<Object?>> realisticRows() {
  const names = [
    ('KOREAN TV & WEB Series/18 Again (TV Series 2020) 1080p/Season 1', '18.Again.S01E%02d.1080p.mkv'),
    ('Animation Movies/(2000) & Before/Nausicaä of the Valley of the Wind (1984) [Dual Audio]', 'Nausicaä %02d.mkv'),
    ('Hindi Movies/(2002)/Devdas (2002) 1080p [Hindi+Eng]', 'Devdas.Part.%02d.mkv'),
  ];
  final rows = <List<Object?>>[];
  var t = 1700000000000;
  for (final (folder, pattern) in names) {
    for (var i = 1; i <= 12; i++) {
      final name = pattern.replaceFirst('%02d', i.toString().padLeft(2, '0'));
      final rel = '$folder/$name';
      final href = '/DHAKA-FLIX-14/${rel.split('/').map(Uri.encodeComponent).join('/')}';
      rows.add([rel, 1000000000 + i, href, i * 60000, 2700000, t += 1000, i % 4 == 0 ? 1 : 0, i.isEven ? 'kor' : null, i % 3 == 0 ? 'eng:2' : null]);
    }
  }
  // Same path, different size (re-uploaded file): both must survive.
  rows.add([rows.first[0], 42, rows.first[2], 5000, 6000000, t += 1000, 0, null, null]);
  return rows;
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('dfp_mig_'));
  tearDown(() => dir.delete(recursive: true));

  Future<List<Map<String, Object?>>> rawRows(String path) async {
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    final r = await db.query('history', orderBy: 'rel_path, size');
    await db.close();
    return r;
  }

  test('every v1 row moves to source df14 with all fields unchanged', () async {
    final path = '${dir.path}/dhakaflix.db';
    final rows = realisticRows();
    await createV1(path, rows: rows);
    final before = await rawRows(path);

    final store = await Store.open(directory: dir.path);
    final after = await rawRows(path);
    expect(after.length, rows.length);
    for (var i = 0; i < before.length; i++) {
      expect(after[i], {'source_id': 'df14', ...before[i]});
    }
    // Resume lookups with the new key return the old positions.
    for (final r in rows) {
      final h = (await store.progress('df14', r[0]! as String, r[1]! as int))!;
      expect(h.position.inMilliseconds, r[3]);
      expect(h.audioTrack, r[7]);
      expect(h.subtitleTrack, r[8]);
    }
    expect((await store.continueWatching()).length, rows.where((r) => r[6] == 0).length);
    expect(await store.setting(Settings.preferredAudioLanguage), 'hin');
    expect(await store.setting(Settings.seekSeconds), '15');
    await store.close();

    // Opening again does not migrate twice.
    final again = await Store.open(directory: dir.path);
    expect((await again.history(limit: 1000)).length, rows.length);
    await again.close();
  });

  test('v1 with the default address stored also maps to df14', () async {
    final path = '${dir.path}/dhakaflix.db';
    await createV1(path, baseUrl: 'http://172.16.50.14/DHAKA-FLIX-14', rows: realisticRows().take(3).toList());
    final store = await Store.open(directory: dir.path);
    expect((await store.history()).map((h) => h.sourceId).toSet(), {'df14'});
    await store.close();
  });

  test('v1 with a custom address maps to the legacy custom source', () async {
    final path = '${dir.path}/dhakaflix.db';
    await createV1(path, baseUrl: 'http://10.0.0.5/MEDIA/', rows: realisticRows().take(3).toList());
    final store = await Store.open(directory: dir.path);
    expect((await store.history()).map((h) => h.sourceId).toSet(), {'custom1'});
    await store.close();
  });

  test('same path on two servers no longer collides', () async {
    final store = await Store.open(directory: dir.path);
    Future<void> save(String id, int min) => store.saveProgress(
      sourceId: id,
      relPath: 'Movies/A.mkv',
      size: 7,
      href: '/X/Movies/A.mkv',
      position: Duration(minutes: min),
      duration: const Duration(minutes: 100),
    );
    await save('df14', 10);
    await save('df7', 30);
    expect((await store.progress('df14', 'Movies/A.mkv', 7))!.position, const Duration(minutes: 10));
    expect((await store.progress('df7', 'Movies/A.mkv', 7))!.position, const Duration(minutes: 30));
    await store.removeHistory('df7', 'Movies/A.mkv', 7);
    expect(await store.progress('df14', 'Movies/A.mkv', 7), isNotNull);
    await store.close();
  });
}
