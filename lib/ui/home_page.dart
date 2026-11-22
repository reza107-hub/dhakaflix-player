import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../app.dart';
import '../core/dhakaflix_client.dart';
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
  SearchHandle? _search;
  String _searched = '';
  List<Entry>? _results;
  Object? _searchError;
  bool _searching = false;
  int _shown = searchPageSize;

  Future<List<Entry>>? _root;
  Future<List<HistoryItem>>? _continue;
  int _historyVersion = -1;
  String? _rootFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    // Compare the full address: another server can have the same folder path.
    final base = app.source.base.toString();
    if (_rootFor != base || _root == null) {
      _rootFor = base;
      _root = app.client.list(app.source.rootHref);
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
    _search?.cancel(); // Abort the in-flight request for the old query.
    _searched = q;
    if (q.length < DhakaFlixClient.minQueryLength) {
      setState(() {
        _results = null;
        _searchError = null;
        _searching = false;
      });
      return;
    }
    final handle = AppScope.read(context).client.search(q);
    _search = handle;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final r = await handle.results;
      if (!mounted || handle != _search) return;
      // Folders first (titles), then videos; drop posters and other files.
      final useful = r.where((e) => e.isDir || isVideo(e)).toList()
        ..sort((a, b) => a.isDir == b.isDir ? 0 : (a.isDir ? -1 : 1));
      setState(() {
        _results = useful;
        _shown = searchPageSize;
        _searching = false;
      });
    } on http.RequestAbortedException {
      // Superseded by a newer query.
    } catch (e) {
      if (!mounted || handle != _search) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  void _retryHome() {
    final app = AppScope.read(context);
    setState(() {
      _root = app.client.list(app.source.rootHref);
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
    if (_searching && _results == null) return const Center(child: CircularProgressIndicator());
    if (_searchError != null) {
      return ErrorView(
        error: _searchError!,
        onRetry: () {
          final q = _searched;
          _searched = '';
          _runSearch(q);
        },
      );
    }
    final r = _results ?? const <Entry>[];
    if (r.isEmpty) return Center(child: Text(_searching ? 'Searching…' : 'No results for "$_searched".'));
    final visible = r.take(_shown).toList();
    return Column(
      children: [
        if (_searching) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${r.length} results${r.length > visible.length ? ' · showing ${visible.length}' : ''}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
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

  Widget _homeBody() => FutureBuilder<List<Entry>>(
    future: _root,
    builder: (context, root) => ListView(
      children: [
        _ContinueWatching(future: _continue),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Browse', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (root.hasError)
          ErrorView(error: root.error!, onRetry: _retryHome)
        else if (!root.hasData)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final e in root.data!.where((e) => e.isDir)) EntryTile(entry: e),
      ],
    ),
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
          await app.store.removeHistory(h.relPath, h.size);
          app.historyChanged();
        },
      ),
      onTap: () {
        if (!app.source.isInside(h.href)) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('This item is from a different DhakaFlix address.')));
          return;
        }
        openEntry(context, Entry(href: h.href, isDir: false, size: h.size));
      },
    );
  }
}
