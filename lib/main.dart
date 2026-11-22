import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'core/dhakaflix_client.dart';
import 'core/paths.dart';
import 'core/source.dart';
import 'data/store.dart';
import 'player/player_controller.dart';
import 'player/player_screen.dart';
import 'player/sidecar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = await Store.open();
  final source = DhakaFlixSource(await store.setting(Settings.baseUrl) ?? defaultBaseUrl);
  runApp(DhakaFlixApp(store: store, source: source));
}

class DhakaFlixApp extends StatelessWidget {
  const DhakaFlixApp({super.key, required this.store, required this.source});
  final Store store;
  final DhakaFlixSource source;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DhakaFlix Player',
    theme: ThemeData(colorSchemeSeed: Colors.red, brightness: Brightness.dark),
    home: FolderPage(store: store, source: source, client: DhakaFlixClient(source), href: source.rootHref),
  );
}

/// Phase 2 test harness: plain folder browser. Replaced by the real UI in Phase 3.
class FolderPage extends StatefulWidget {
  const FolderPage({super.key, required this.store, required this.source, required this.client, required this.href});
  final Store store;
  final DhakaFlixSource source;
  final DhakaFlixClient client;
  final String href;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  late Future<List<Entry>> _items = widget.client.list(widget.href);
  Future<List<HistoryItem>>? _continue;

  bool get _isRoot => widget.href == widget.source.rootHref;

  @override
  void initState() {
    super.initState();
    if (_isRoot) _continue = widget.store.continueWatching();
  }

  Future<void> _play(Entry e, List<Entry> siblings) async {
    final controller = PlayerController(source: widget.source, store: widget.store);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(controller: controller, entry: e, siblings: siblings),
      ),
    );
    if (_isRoot && mounted) setState(() => _continue = widget.store.continueWatching());
  }

  Future<void> _resume(HistoryItem h) async {
    final e = Entry(href: h.href, isDir: false, size: h.size);
    List<Entry> siblings = const [];
    try {
      siblings = await widget.client.list(parentOf(h.href));
    } catch (_) {}
    await _play(e, siblings);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_isRoot ? 'DhakaFlix Player' : nameOf(widget.href))),
    body: FutureBuilder<List<Entry>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${snap.error}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => _items = widget.client.list(widget.href)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!.where((e) => e.isDir || isVideo(e)).toList();
        return ListView(
          children: [
            if (_continue != null)
              FutureBuilder<List<HistoryItem>>(
                future: _continue,
                builder: (context, h) => Column(
                  children: [
                    for (final item in h.data ?? const <HistoryItem>[])
                      ListTile(
                        leading: const Icon(Icons.play_circle),
                        title: Text(nameOf(item.href), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: LinearProgressIndicator(
                          value: item.duration.inMilliseconds == 0
                              ? 0
                              : item.position.inMilliseconds / item.duration.inMilliseconds,
                        ),
                        onTap: () => _resume(item),
                      ),
                  ],
                ),
              ),
            for (final e in items)
              ListTile(
                leading: Icon(e.isDir ? Icons.folder : Icons.movie),
                title: Text(e.name),
                subtitle: e.isDir ? null : Text('${((e.size ?? 0) / (1 << 20)).toStringAsFixed(0)} MB'),
                onTap: () => e.isDir
                    ? Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FolderPage(
                            store: widget.store,
                            source: widget.source,
                            client: widget.client,
                            href: e.href,
                          ),
                        ),
                      )
                    : _play(e, snap.data!),
              ),
          ],
        );
      },
    ),
  );
}
