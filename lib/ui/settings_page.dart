import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/source.dart';
import '../data/store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _seek = 10;
  bool _subsOn = false;
  bool _autoNext = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _load(AppScope.read(context).store);
  }

  Future<void> _load(Store store) async {
    final seek = int.tryParse(await store.setting(Settings.seekSeconds) ?? '') ?? 10;
    final subs = await store.setting(Settings.subtitlesOnByDefault) == 'true';
    final next = await store.setting(Settings.autoPlayNext) != 'false';
    if (mounted) {
      setState(() {
        _seek = seek;
        _subsOn = subs;
        _autoNext = next;
      });
    }
  }

  Future<void> _setEnabled(DhakaFlixSource s, bool on) async {
    final app = AppScope.read(context);
    await app.updateSources(app.sources.setEnabled(s.id, on));
  }

  Future<void> _remove(DhakaFlixSource s) async {
    final app = AppScope.read(context);
    await app.updateSources(app.sources.remove(s.id));
  }

  Future<void> _addServer() async {
    final app = AppScope.read(context);
    final added = await showDialog<SourceList>(
      context: context,
      builder: (_) => _AddServerDialog(sources: app.sources),
    );
    if (added == null || !mounted) return;
    await app.updateSources(added);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server added.')));
  }

  Future<void> _set(String key, String value) => AppScope.read(context).store.setSetting(key, value);

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear watch history?'),
        content: const Text('Removes all resume positions and Continue watching on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = AppScope.read(context);
    await app.store.clearHistory();
    app.historyChanged();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('History cleared.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Servers', style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final s in AppScope.of(context).sources.all)
              SwitchListTile(
                title: Text(s.name),
                subtitle: Text(
                  [s.base.toString(), if (_blockedOnAndroid(s.base)) _androidWarning].join('\n'),
                ),
                isThreeLine: _blockedOnAndroid(s.base),
                value: s.enabled,
                onChanged: (v) => _setEnabled(s, v),
                secondary: s.builtIn
                    ? const Icon(Icons.dns_outlined)
                    : IconButton(
                        tooltip: 'Remove server',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _remove(s),
                      ),
              ),
            ListTile(leading: const Icon(Icons.add), title: const Text('Add server'), onTap: _addServer),
            const Divider(),
            ListTile(
              title: const Text('Skip forward / back'),
              subtitle: Text('$_seek seconds (double-tap and arrow keys)'),
              trailing: DropdownButton<int>(
                value: _seek,
                items: [
                  for (final s in const [5, 10, 15, 30]) DropdownMenuItem(value: s, child: Text('$s s')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _seek = v);
                  _set(Settings.seekSeconds, '$v');
                },
              ),
            ),
            SwitchListTile(
              title: const Text('Subtitles on by default'),
              subtitle: const Text('Turns on the first text subtitle for new videos'),
              value: _subsOn,
              onChanged: (v) {
                setState(() => _subsOn = v);
                _set(Settings.subtitlesOnByDefault, '$v');
              },
            ),
            SwitchListTile(
              title: const Text('Auto-play next episode'),
              value: _autoNext,
              onChanged: (v) {
                setState(() => _autoNext = v);
                _set(Settings.autoPlayNext, '$v');
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear watch history'),
              onTap: _clearHistory,
            ),
            const AboutListTile(
              icon: Icon(Icons.info_outline),
              applicationName: 'DhakaFlix Player',
              applicationVersion: appVersion,
              aboutBoxChildren: [
                Text('Plays videos from a DhakaFlix server on your ISP network. Nothing is uploaded or shared.'),
                SizedBox(height: 8),
                Text('Free software under the GNU GPL v3. Video playback uses mpv and FFmpeg (LGPL).'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Android only allows plain HTTP to the hosts built into the app.
bool _blockedOnAndroid(Uri base) => Platform.isAndroid && base.scheme == 'http' && !knownHosts.contains(base.host);

const _androidWarning =
    'Android only allows plain HTTP to the built-in DhakaFlix hosts. This address will not load on Android.';

class _AddServerDialog extends StatefulWidget {
  const _AddServerDialog({required this.sources});
  final SourceList sources;
  @override
  State<_AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<_AddServerDialog> {
  final _url = TextEditingController();
  String? _error;
  String? _warning;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _check(String text) {
    try {
      setState(() => _warning = _blockedOnAndroid(parseBaseUrl(text)) ? _androidWarning : null);
    } on FormatException {
      setState(() => _warning = null);
    }
  }

  void _save() {
    try {
      Navigator.pop(context, widget.sources.addCustom(_url.text));
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add server'),
    content: TextField(
      controller: _url,
      autofocus: true,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onChanged: _check,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: 'Address',
        hintText: 'http://172.16.50.14/DHAKA-FLIX-14/',
        helperText: _warning,
        helperMaxLines: 4,
        errorText: _error,
        errorMaxLines: 3,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _save, child: const Text('Add')),
    ],
  );
}
