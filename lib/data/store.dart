/// Local-only storage: watch history, resume positions and settings.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/source.dart';

/// Watched once playback reaches this fraction of the duration.
const watchedThreshold = 0.95;

class HistoryItem {
  const HistoryItem({
    required this.sourceId,
    required this.relPath,
    required this.size,
    required this.href,
    required this.position,
    required this.duration,
    required this.lastWatched,
    required this.watched,
    this.audioTrack,
    this.subtitleTrack,
  });

  /// Server the file is on (see `DhakaFlixSource.id`). Part of the key.
  final String sourceId;

  /// Decoded path relative to the source base; with [sourceId] and [size] it
  /// forms the key.
  final String relPath;
  final int size;

  /// Encoded href, kept so the file can be reopened without searching.
  final String href;
  final Duration position;
  final Duration duration;
  final DateTime lastWatched;
  final bool watched;
  final String? audioTrack;
  final String? subtitleTrack;

  static HistoryItem _fromRow(Map<String, Object?> r) => HistoryItem(
    sourceId: r['source_id']! as String,
    relPath: r['rel_path']! as String,
    size: r['size']! as int,
    href: r['href']! as String,
    position: Duration(milliseconds: r['position_ms']! as int),
    duration: Duration(milliseconds: r['duration_ms']! as int),
    lastWatched: DateTime.fromMillisecondsSinceEpoch(r['last_watched']! as int),
    watched: r['watched'] == 1,
    audioTrack: r['audio_track'] as String?,
    subtitleTrack: r['subtitle_track'] as String?,
  );
}

class Store {
  Store._(this._db);
  final Database _db;

  /// Opens the database in the app support folder, or in memory for tests.
  /// [fileName] lets tests use their own file instead of the user's history;
  /// [directory] (tests only) replaces the app support folder.
  static Future<Store> open({bool inMemory = false, String fileName = 'dhakaflix.db', String? directory}) async {
    sqfliteFfiInit();
    final path = inMemory
        ? inMemoryDatabasePath
        : p.join(directory ?? (await getApplicationSupportDirectory()).path, fileName);
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await _createHistory(db);
          await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        },
        onUpgrade: (db, from, _) async {
          if (from < 2) await _migrateToV2(db);
        },
      ),
    );
    return Store._(db);
  }

  static Future<void> _createHistory(Database db) async {
    await db.execute('''
      CREATE TABLE history(
        source_id TEXT NOT NULL,
        rel_path TEXT NOT NULL,
        size INTEGER NOT NULL,
        href TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        last_watched INTEGER NOT NULL,
        watched INTEGER NOT NULL DEFAULT 0,
        audio_track TEXT,
        subtitle_track TEXT,
        PRIMARY KEY (source_id, rel_path, size)
      )''');
    await db.execute('CREATE INDEX history_recent ON history(last_watched DESC)');
  }

  /// v1 -> v2: the history key gains the source id. v1 had one server, so
  /// every row gets the id of that server (the stored address, or DHAKA-FLIX-14).
  /// Runs in one transaction: either every row moves or nothing changes.
  static Future<void> _migrateToV2(Database db) async {
    final legacy = await db.query('settings', where: 'key = ?', whereArgs: [Settings.baseUrl]);
    final id = legacySourceId(legacy.isEmpty ? null : legacy.first['value'] as String);
    await db.execute('ALTER TABLE history RENAME TO history_v1');
    await db.execute('DROP INDEX IF EXISTS history_recent');
    await _createHistory(db);
    await db.execute(
      '''
      INSERT INTO history(source_id, rel_path, size, href, position_ms, duration_ms, last_watched, watched, audio_track, subtitle_track)
      SELECT ?, rel_path, size, href, position_ms, duration_ms, last_watched, watched, audio_track, subtitle_track FROM history_v1''',
      [id],
    );
    await db.execute('DROP TABLE history_v1');
  }

  Future<void> close() => _db.close();

  // ---- History ----

  /// Saves progress. Marks watched at >= 95%. Keeps earlier track choices
  /// unless new ones are given.
  Future<void> saveProgress({
    required String sourceId,
    required String relPath,
    required int size,
    required String href,
    required Duration position,
    required Duration duration,
    String? audioTrack,
    String? subtitleTrack,
    DateTime? now,
  }) async {
    final watched = duration > Duration.zero && position.inMilliseconds >= duration.inMilliseconds * watchedThreshold;
    await _db.rawInsert(
      '''
      INSERT INTO history(source_id, rel_path, size, href, position_ms, duration_ms, last_watched, watched, audio_track, subtitle_track)
      VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_id, rel_path, size) DO UPDATE SET
        href = excluded.href,
        position_ms = excluded.position_ms,
        duration_ms = excluded.duration_ms,
        last_watched = excluded.last_watched,
        watched = excluded.watched,
        audio_track = COALESCE(excluded.audio_track, history.audio_track),
        subtitle_track = COALESCE(excluded.subtitle_track, history.subtitle_track)
    ''',
      [
        sourceId,
        relPath,
        size,
        href,
        position.inMilliseconds,
        duration.inMilliseconds,
        (now ?? DateTime.now()).millisecondsSinceEpoch,
        watched ? 1 : 0,
        audioTrack,
        subtitleTrack,
      ],
    );
  }

  Future<HistoryItem?> progress(String sourceId, String relPath, int size) async {
    final rows = await _db.query(
      'history',
      where: 'source_id = ? AND rel_path = ? AND size = ?',
      whereArgs: [sourceId, relPath, size],
    );
    return rows.isEmpty ? null : HistoryItem._fromRow(rows.first);
  }

  /// Unfinished items, most recent first.
  Future<List<HistoryItem>> continueWatching({int limit = 50}) async {
    final rows = await _db.query(
      'history',
      where: 'watched = 0 AND position_ms > 0',
      orderBy: 'last_watched DESC',
      limit: limit,
    );
    return rows.map(HistoryItem._fromRow).toList();
  }

  /// All items, most recent first.
  Future<List<HistoryItem>> history({int limit = 200}) async {
    final rows = await _db.query('history', orderBy: 'last_watched DESC', limit: limit);
    return rows.map(HistoryItem._fromRow).toList();
  }

  Future<void> removeHistory(String sourceId, String relPath, int size) => _db.delete(
    'history',
    where: 'source_id = ? AND rel_path = ? AND size = ?',
    whereArgs: [sourceId, relPath, size],
  );

  Future<void> clearHistory() => _db.delete('history');

  // ---- Settings ----

  Future<String?> setting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) =>
      _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}

/// Setting keys used by the app.
abstract final class Settings {
  /// v1.0.0 single server address. Only read to migrate; see [sources].
  static const baseUrl = 'base_url';

  /// JSON list of servers (`SourceList.toJson`).
  static const sources = 'sources';
  static const preferredAudioLanguage = 'audio_language';
  static const subtitlesOnByDefault = 'subtitles_on';
  static const seekSeconds = 'seek_seconds';
  static const autoPlayNext = 'auto_play_next';
}
