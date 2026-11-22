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
  late final TextEditingController _url;
  String? _urlError;
  String? _urlWarning;
  int _seek = 10;
  bool _subsOn = false;
  bool _autoNext = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final app = AppScope.read(context);
    _url = TextEditingController(text: app.source.base.toString());
    _load(app.store);
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

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    final app = AppScope.read(context);
    try {
      final uri = parseBaseUrl(_url.text);
      await app.setBaseUrl(_url.text);
      setState(() {
        _urlError = null;
        // Android blocks plain HTTP to hosts not built into the app.
        _urlWarning = Platform.isAndroid && uri.scheme == 'http' && !knownHosts.contains(uri.host)
            ? 'This app version only allows plain HTTP to ${knownHosts.join(', ')}. '
                  'Other addresses will not load on Android.'
            : null;
        _url.text = app.source.base.toString();
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Address saved.')));
    } on FormatException catch (e) {
      setState(() => _urlError = e.message);
    }
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onSubmitted: (_) => _saveUrl(),
                decoration: InputDecoration(
                  labelText: 'DhakaFlix address',
                  helperText: _urlWarning ?? 'Default: $defaultBaseUrl',
                  helperMaxLines: 3,
                  errorText: _urlError,
                  suffixIcon: IconButton(tooltip: 'Save', icon: const Icon(Icons.check), onPressed: _saveUrl),
                ),
              ),
            ),
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
              applicationVersion: '0.1.0',
              aboutBoxChildren: [
                Text('Plays videos from a DhakaFlix server on your ISP network. Nothing is uploaded or shared.'),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
