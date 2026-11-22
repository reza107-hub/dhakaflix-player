/// Read-only client for a DhakaFlix (h5ai 0.29) server.
///
/// Wire format (captured from the h5ai web UI):
///   `POST {folder href}?`   Content-Type: application/json;charset=UTF-8
///   list:   `{"action":"get","items":{"href":FOLDER,"what":1}}`
///           -> {"items":[{href,time,size,managed,fetched}, ...]}
///              (also contains every ancestor folder; we keep direct children)
///   search: `{"action":"get","search":{"href":SCOPE,"pattern":REGEX,"ignorecase":true}}`
///           -> {"search":[{href,time,size}, ...]}  (no paging, no server limit)
/// `size == null` means folder. `time` is epoch milliseconds.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'natural_sort.dart';
import 'paths.dart';
import 'source.dart';

const unreachableMessage = 'DhakaFlix is not reachable. Connect to the ISP network.';

class DhakaFlixUnreachable implements Exception {
  const DhakaFlixUnreachable([this.cause]);
  final Object? cause;
  @override
  String toString() => unreachableMessage;
}

class DhakaFlixError implements Exception {
  const DhakaFlixError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Entry {
  const Entry({required this.href, required this.isDir, this.size, this.modified});

  /// Percent-encoded absolute href exactly as the server sent it.
  final String href;
  final bool isDir;
  final int? size;
  final DateTime? modified;

  String get name => nameOf(href);
  String get folderPath => decodeHref(parentOf(href));

  static Entry fromJson(Map<String, dynamic> j) {
    final href = j['href'] as String;
    final size = j['size'];
    final time = j['time'];
    return Entry(
      href: href,
      isDir: href.endsWith('/'),
      size: size is num ? size.toInt() : null,
      modified: time is num ? DateTime.fromMillisecondsSinceEpoch(time.toInt()) : null,
    );
  }
}

/// A running search. Call [cancel] when the query changes.
class SearchHandle {
  SearchHandle._(this.results, this._abort);
  final Future<List<Entry>> results;
  final Completer<void> _abort;
  void cancel() {
    if (!_abort.isCompleted) _abort.complete();
  }
}

class DhakaFlixClient {
  DhakaFlixClient(this.source, {http.Client? httpClient, this.maxConcurrent = 3})
      : _http = httpClient ?? http.Client();

  final DhakaFlixSource source;
  final http.Client _http;
  final int maxConcurrent;

  static const minQueryLength = 3;
  static const listTimeout = Duration(seconds: 15);
  static const searchTimeout = Duration(seconds: 60);

  int _active = 0;
  final _waiting = <Completer<void>>[];

  /// Direct children of [folderHref], folders first, each group in natural order.
  Future<List<Entry>> list(String folderHref) async {
    if (!folderHref.endsWith('/')) throw ArgumentError.value(folderHref, 'folderHref', 'must end with /');
    final body = {
      'action': 'get',
      'items': {'href': folderHref, 'what': 1},
    };
    final json = await _post(folderHref, body, listTimeout, retries: 1);
    final items = (json['items'] as List? ?? const []).cast<Map<String, dynamic>>();
    final children = items
        .map(Entry.fromJson)
        .where((e) => e.href != folderHref && parentOf(e.href) == folderHref)
        .toList();
    return sortEntries(children);
  }

  /// Searches names under [scopeHref] (default: the whole source).
  /// Returns an empty list for queries shorter than [minQueryLength].
  SearchHandle search(String query, {String? scopeHref}) {
    final abort = Completer<void>();
    Future<List<Entry>> run() async {
      if (query.trim().length < minQueryLength) return const [];
      final scope = scopeHref ?? source.rootHref;
      final body = {
        'action': 'get',
        'search': {'href': scope, 'pattern': searchPattern(query), 'ignorecase': true},
      };
      final json = await _post(scope, body, searchTimeout, abort: abort.future);
      final items = (json['search'] as List? ?? const []).cast<Map<String, dynamic>>();
      return items.map(Entry.fromJson).where((e) => source.isInside(e.href)).toList();
    }

    return SearchHandle._(run(), abort);
  }

  void close() => _http.close();

  Future<Map<String, dynamic>> _post(
    String folderHref,
    Map<String, dynamic> body,
    Duration timeout, {
    int retries = 0,
    Future<void>? abort,
  }) async {
    final url = Uri.parse('${source.urlFor(folderHref)}?');
    for (var attempt = 0;; attempt++) {
      await _acquire();
      try {
        final req = http.AbortableRequest('POST', url, abortTrigger: abort)
          ..headers['Content-Type'] = 'application/json;charset=UTF-8'
          ..headers['User-Agent'] = userAgent
          ..body = jsonEncode(body);
        final res = await http.Response.fromStream(await _http.send(req)).timeout(timeout);
        if (res.statusCode != 200) throw DhakaFlixError('DhakaFlix returned HTTP ${res.statusCode}.');
        // Large searches can be >10 MB; decode off the UI isolate.
        final bytes = res.bodyBytes;
        final decoded = bytes.length > 256 * 1024
            ? await Isolate.run(() => jsonDecode(utf8.decode(bytes)))
            : jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw const DhakaFlixError('Unexpected reply from DhakaFlix.');
        return decoded;
      } on http.RequestAbortedException {
        rethrow;
      } on FormatException {
        throw const DhakaFlixError('Unexpected reply from DhakaFlix.');
      } on Object catch (e) {
        final network = e is SocketException || e is TimeoutException || e is http.ClientException;
        if (!network) rethrow;
        if (attempt >= retries) throw DhakaFlixUnreachable(e);
        await Future.delayed(const Duration(milliseconds: 500));
      } finally {
        _release();
      }
    }
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future; // Slot is handed over by _release.
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _active--;
    }
  }
}

/// Folders first, then files; each in natural order by name.
List<Entry> sortEntries(List<Entry> entries) => entries
  ..sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    return naturalCompare(a.name, b.name);
  });
