/// Search across several DhakaFlix servers at once.
///
/// Concurrency: every server has its own [DhakaFlixClient] with its own limit
/// of 3 requests in flight. The limit exists to protect each server, so it is
/// per server, not shared. One search uses one slot on each enabled server.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'dhakaflix_client.dart';
import 'source.dart';

/// Most results kept per server. A short query can return 50,000+ names; we
/// keep the first [maxPerSource] useful ones so memory stays bounded.
const maxPerSource = 2000;

/// The answer (or failure) of one server.
class SourceResult {
  const SourceResult(this.source, {this.entries = const [], this.error, this.total = 0});
  final DhakaFlixSource source;

  /// Folders first, then files; at most [maxPerSource].
  final List<Entry> entries;

  /// Useful hits before the cap.
  final int total;

  /// Set when the server failed (unreachable, timeout, bad reply).
  final Object? error;

  bool get truncated => total > entries.length;
}

/// A running search over several servers. Results arrive on [results] one
/// server at a time, as each answers. [cancel] aborts every request.
class MultiSearch {
  MultiSearch(
    Map<DhakaFlixSource, DhakaFlixClient> clients,
    String query, {
    bool Function(Entry)? keep,
  }) {
    var pending = clients.length;
    if (pending == 0) {
      _out.close();
      return;
    }
    for (final MapEntry(key: source, value: client) in clients.entries) {
      final h = client.search(query);
      _handles.add(h);
      h.results
          .then((r) {
            final useful = r.where(keep ?? (_) => true).toList()
              ..sort((a, b) => a.isDir == b.isDir ? 0 : (a.isDir ? -1 : 1));
            return SourceResult(source, entries: useful.take(maxPerSource).toList(), total: useful.length);
          })
          .catchError((Object e) => SourceResult(source, error: e))
          .then((res) {
            if (_cancelled) return;
            if (res.error is http.RequestAbortedException) return;
            _out.add(res);
          })
          .whenComplete(() {
            if (--pending == 0 && !_out.isClosed) _out.close();
          });
    }
  }

  final _out = StreamController<SourceResult>();
  final _handles = <SearchHandle>[];
  bool _cancelled = false;

  Stream<SourceResult> get results => _out.stream;

  void cancel() {
    _cancelled = true;
    for (final h in _handles) {
      h.cancel();
    }
  }
}

/// Merges per-server answers for display: all folders (titles) first, then
/// all files; within each group servers appear in [order]. [only] keeps a
/// single server.
List<Entry> mergeResults(List<SourceResult> answers, List<DhakaFlixSource> order, {String? only}) {
  final byId = {for (final a in answers) a.source.id: a};
  final picked = [
    for (final s in order)
      if (only == null || s.id == only) ...?byId[s.id]?.entries,
  ];
  return [...picked.where((e) => e.isDir), ...picked.where((e) => !e.isDir)];
}
