import 'package:flutter/material.dart';

import '../app.dart';
import '../core/dhakaflix_client.dart';
import '../core/paths.dart';
import '../player/sidecar.dart';
import 'common.dart';

/// One DhakaFlix folder: subfolders, then videos in natural order.
class FolderPage extends StatefulWidget {
  const FolderPage({super.key, required this.href});
  final String href;

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  Future<List<Entry>>? _items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= _load();
  }

  Future<List<Entry>> _load() => AppScope.read(context).client.list(widget.href);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(nameOf(widget.href), maxLines: 2, overflow: TextOverflow.ellipsis)),
    body: FutureBuilder<List<Entry>>(
      future: _items,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: () => setState(() => _items = _load()));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final shown = all.where((e) => e.isDir || isVideo(e)).toList();
        if (shown.isEmpty) return const Center(child: Text('No videos in this folder.'));
        return RefreshIndicator(
          onRefresh: () async {
            final f = _load();
            setState(() => _items = f);
            await f;
          },
          child: Centered(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (_, i) => EntryTile(entry: shown[i], siblings: all),
            ),
          ),
        );
      },
    ),
  );
}
