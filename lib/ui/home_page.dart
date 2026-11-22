import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/dhakaflix_client.dart';
import '../core/multi_search.dart';
import '../core/paths.dart';
import '../data/store.dart';
import '../player/sidecar.dart';
import 'common.dart';
import 'settings_page.dart';

const searchPageSize = 200;
const searchDebounce = Duration(milliseconds: 300);

/// Search box on top; below it either search results, or Continue watching
/// plus the top-level DhakaFlix folders.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _query = TextEditingController();
  Timer? _debounce;
  MultiSearch? _search;
  String _searched = '';

  /// Answers received so far for [_searched], one per server.
  List<SourceResult> _answers = const [];
  bool _searching = false;

  /// Server filter for search results; null = all servers.
  String? _only;
  int _shown = searchPageSize;

  final Map<String, Future<List<Entry>>> _roots = {};
  Future<List<HistoryItem>>? _continue;
  int _historyVersion = -1;
  int _sourcesVersion = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (_sourcesVersion != app.sourcesVersion) {
      _sourcesVersion = app.sourcesVersion;
      _roots.clear();
      for (final s in app.sources.enabled) {
        _roots[s.id] = app.client(s.id).list(s.rootHref);
      }
      if (_only != null && app.sources.byId(_only!)?.enabled != true) _only = null;
      if (_searched.isNotEmpty) {
        final q = _searched;
        _searched = '';
        // Re-run the search on the new server list after this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _runSearch(q);
        });
      }
    }
    if (_historyVersion != app.historyVersion) {
      _historyVersion = app.historyVersion;
      _continue = app.store.continueWatching();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => _runSearch(q.trim()));
    if (q.trim().isEmpty) _runSearch('');
  }

  Future<void> _runSearch(String q) async {
    if (q == _searched) return;
    _search?.cancel(); // Abort every in-flight request for the old query.
    _search = null;
    _searched = q;
    if (q.length < DhakaFlixClient.minQueryLength) {
      setState(() {
        _answers = const [];
        _searching = false;
      });
      return;
    }
    final app = AppScope.read(context);
    // Folders (titles) and videos only; drop posters and other files.
    final search = MultiSearch(app.enabledClients, q, keep: (e) => e.isDir || isVideo(e));
    _search = search;
    setState(() {
      _answers = const [];
      _shown = searchPageSize;
      _searching = true;
    });
    await for (final answer in search.results) {
      if (!mounted || search != _search) return;
      setState(() => _answers = [..._answers, answer]);
    }
    if (mounted && search == _search) setState(() => _searching = false);
  }

  void _retrySearch() {
    final q = _searched;
    _searched = '';
    _runSearch(q);
  }

  void _retryRoot(String sourceId) {
    final app = AppScope.read(context);
    final s = app.source(sourceId);
    if (s == null || !s.enabled) return;
    setState(() {
      _roots[sourceId] = app.client(sourceId).list(s.rootHref);
      _continue = app.store.continueWatching();
    });
  }

  @override
  Widget build(BuildContext context) {
    final searching = _searched.length >= DhakaFlixClient.minQueryLength;
    return Scaffold(
      appBar: AppBar(
        title: const Text('DhakaFlix Player'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Centered(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: TextField(
                controller: _query,
                onChanged: _onQueryChanged,
                onSubmitted: (q) => _runSearch(q.trim()),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search movies and series',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _query.clear();
                            _onQueryChanged('');
                          },
                        ),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Centered(child: searching ? _searchBody() : _homeBody()),
    );
  }

  Widget _searchBody() {
    final app = AppScope.of(context);
    final order = app.sources.enabled;
    if (order.isEmpty) return const _NoServers();
    final failed = _answers.where((a) => a.error != null).toList();
    // Every server failed: show the full-page error (usually "not on the ISP network").
    if (!_searching && failed.length == _answers.length && failed.isNotEmpty) {
      return ErrorView(error: failed.first.error!, onRetry: _retrySearch);
    }
    final r = mergeResults(_answers, order, only: _only);
    final visible = r.take(_shown).toList();
    final notes = [
      for (final a in failed)
        if (_only == null || _only == a.source.id) '${a.source.name} did not answer (${_failure(a.error!)}).',
      for (final a in _answers)
        if (a.truncated && (_only == null || _only == a.source.id))
          '${a.source.name}: showing the first ${a.entries.length} of ${a.total} matches. Type more words to narrow it down.',
    ];
    final waiting = _searching ? order.length - _answers.length : 0;
    return Column(
      children: [
        if (_searching) const LinearProgressIndicator(),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _chip('All servers', null),
              for (final s in order) _chip(s.name, s.id),
            ],
          ),
        ),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(child: Text(n, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              [
                '${r.length} results',
                if (r.length > visible.length) 'showing ${visible.length}',
                if (waiting > 0) 'waiting for $waiting ${waiting == 1 ? 'server' : 'servers'}',
              ].join(' · '),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        Expanded(
          child: r.isEmpty
              ? Center(child: Text(_searching ? 'Searching…' : 'No results for "$_searched".'))
              : ListView.builder(
                  itemCount: visible.length + (r.length > visible.length ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == visible.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton(
                          onPressed: () => setState(() => _shown += searchPageSize),
                          child: Text('Show ${(r.length - visible.length).clamp(0, searchPageSize)} more'),
                        ),
                      );
                    }
                    return EntryTile(entry: visible[i], showPath: true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, String? id) {
    final count = id == null ? null : _answers.where((a) => a.source.id == id).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(count == null || count.error != null ? label : '$label (${count.total})'),
        selected: _only == id,
        onSelected: (_) => setState(() {
          _only = id;
          _shown = searchPageSize;
        }),
      ),
    );
  }

  Widget _homeBody() {
    final app = AppScope.of(context);
    final enabled = app.sources.enabled;
    return ListView(
      children: [
        _ContinueWatching(future: _continue),
        if (enabled.isEmpty) const _NoServers(),
        for (final s in enabled) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(s.name, style: Theme.of(context).textTheme.titleMedium),
          ),
          FutureBuilder<List<Entry>>(
            future: _roots[s.id],
            builder: (context, root) {
              if (root.hasError) {
                return ListTile(
                  leading: Icon(root.error is DhakaFlixUnreachable ? Icons.wifi_off : Icons.error_outline),
                  title: Text('${s.name} ${_failure(root.error!)}.'),
                  trailing: TextButton(onPressed: () => _retryRoot(s.id), child: const Text('Retry')),
                );
              }
              if (!root.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return Column(children: [for (final e in root.data!.where((e) => e.isDir)) EntryTile(entry: e)]);
            },
          ),
        ],
      ],
    );
  }
}

/// Short reason for a failed server, e.g. "is not reachable".
String _failure(Object e) => e is DhakaFlixUnreachable ? 'is not reachable' : 'failed: $e';

class _NoServers extends StatelessWidget {
  const _NoServers();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(32),
    child: Center(child: Text('All servers are turned off. Turn one on in Settings.', textAlign: TextAlign.center)),
  );
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching({required this.future});
  final Future<List<HistoryItem>>? future;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<HistoryItem>>(
    future: future,
    builder: (context, snap) {
      final items = snap.data ?? const <HistoryItem>[];
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Continue watching', style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final h in items) _HistoryTile(item: h),
        ],
      );
    },
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item});
  final HistoryItem item;

  String _left(Duration d) {
    final m = d.inMinutes;
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min left' : '$m min left';
  }

  @override
  Widget build(BuildContext context) {
    final h = item;
    final app = AppScope.read(context);
    final progress = h.duration.inMilliseconds == 0 ? 0.0 : h.position.inMilliseconds / h.duration.inMilliseconds;
    return ListTile(
      leading: const Icon(Icons.play_circle_outline),
      title: Text(nameOf(h.href), maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(child: LinearProgressIndicator(value: progress.clamp(0, 1))),
            const SizedBox(width: 12),
            Text(_left(h.duration - h.position)),
          ],
        ),
      ),
      trailing: IconButton(
        tooltip: 'Remove from Continue watching',
        icon: const Icon(Icons.close),
        onPressed: () async {
          await app.store.removeHistory(h.sourceId, h.relPath, h.size);
          app.historyChanged();
        },
      ),
      onTap: () => openEntry(context, Entry(sourceId: h.sourceId, href: h.href, isDir: false, size: h.size)),
    );
  }
}
