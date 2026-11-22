import 'package:flutter/material.dart';

import '../app.dart';
import '../core/dhakaflix_client.dart';
import '../core/media_names.dart';
import '../core/paths.dart';
import '../player/player_controller.dart';
import '../player/player_screen.dart';
import '../player/sidecar.dart';
import 'folder_page.dart';

/// Keeps content readable on wide desktop windows.
class Centered extends StatelessWidget {
  const Centered({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960), child: child),
  );
}

/// Friendly error with retry. Network failures show the ISP-network hint.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(error is DhakaFlixUnreachable ? Icons.wifi_off : Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            error is DhakaFlixUnreachable || error is DhakaFlixError ? '$error' : 'Something went wrong.\n$error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ),
    ),
  );
}

/// Opens a folder or plays a video. Loads the folder listing for videos when
/// [siblings] is not known (needed for subtitles, versions and next episode).
Future<void> openEntry(BuildContext context, Entry e, {List<Entry>? siblings}) async {
  final app = AppScope.read(context);
  final source = app.source(e.sourceId);
  if (source == null || !source.enabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This server is turned off or removed. Turn it on in Settings.')),
    );
    return;
  }
  if (e.isDir) {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => FolderPage(sourceId: e.sourceId, href: e.href)));
    return;
  }
  var sibs = siblings;
  if (sibs == null) {
    try {
      sibs = await app.client(e.sourceId).list(parentOf(e.href));
    } catch (_) {
      sibs = const []; // Still playable; just no sidecars/versions/next.
    }
  }
  if (!context.mounted) return;
  final controller = PlayerController(source: source, store: app.store);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(controller: controller, entry: e, siblings: sibs!),
    ),
  );
  app.historyChanged();
}

/// One row for a folder or a video file.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, this.siblings, this.showPath = false});
  final Entry entry;
  final List<Entry>? siblings;
  final bool showPath;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final app = AppScope.of(context);
    final details = [
      if (!e.isDir) formatSize(e.size),
      if (!e.isDir && resolutionOf(e.name) != null) resolutionLabel(resolutionOf(e.name)!),
      if (!e.isDir) extensionOf(e.name).toUpperCase(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final source = app.source(e.sourceId);
    final path = !showPath || source == null
        ? ''
        : '${source.name} · ${decodeHref(parentOf(e.href)).replaceFirst(decodeHref(source.rootHref), '')}';
    return ListTile(
      leading: Icon(e.isDir ? Icons.folder_outlined : Icons.movie_outlined),
      title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: (details.isEmpty && path.isEmpty)
          ? null
          : Text([if (path.isNotEmpty) path, if (details.isNotEmpty) details].join('\n'), maxLines: 3),
      isThreeLine: showPath && details.isNotEmpty && path.isNotEmpty,
      trailing: e.isDir ? const Icon(Icons.chevron_right) : const Icon(Icons.play_arrow),
      onTap: () => openEntry(context, e, siblings: siblings),
    );
  }
}
