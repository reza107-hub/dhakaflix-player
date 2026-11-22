import 'package:flutter/material.dart';

import 'core/dhakaflix_client.dart';
import 'core/source.dart';
import 'data/store.dart';
import 'ui/home_page.dart';

/// App-wide state: storage, the configured servers and one client per server.
class AppState extends ChangeNotifier {
  AppState(this.store, SourceList sources) {
    _setSources(sources);
  }

  /// Loads the server list, migrating the v1.0.0 single-address setting.
  static Future<AppState> load(Store store) async => AppState(
    store,
    SourceList.load(await store.setting(Settings.sources), legacyBaseUrl: await store.setting(Settings.baseUrl)),
  );

  final Store store;
  late SourceList sources;
  final Map<String, DhakaFlixClient> _clients = {};

  /// Bumped when the server list changes so pages can reload.
  int sourcesVersion = 0;

  void _setSources(SourceList list) {
    for (final c in _clients.values) {
      c.close();
    }
    _clients.clear();
    sources = list;
    for (final s in list.all) {
      _clients[s.id] = DhakaFlixClient(s);
    }
  }

  /// Source by id, or null if it was removed.
  DhakaFlixSource? source(String id) => sources.byId(id);

  /// Client for an *enabled* source. Throws if the source is gone or disabled,
  /// so nothing is ever requested from a server the user turned off.
  DhakaFlixClient client(String sourceId) {
    final s = sources.byId(sourceId);
    if (s == null || !s.enabled) throw DhakaFlixError('This server is turned off or removed. See Settings.');
    return _clients[sourceId]!;
  }

  /// Clients of the enabled sources, in display order.
  Map<DhakaFlixSource, DhakaFlixClient> get enabledClients => {for (final s in sources.enabled) s: _clients[s.id]!};

  Future<void> updateSources(SourceList list) async {
    _setSources(list);
    await store.setSetting(Settings.sources, list.toJson());
    sourcesVersion++;
    notifyListeners();
  }

  /// Bumped when history changes so lists can refresh.
  int historyVersion = 0;
  void historyChanged() {
    historyVersion++;
    notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Read without subscribing to changes (for callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class DhakaFlixApp extends StatelessWidget {
  const DhakaFlixApp({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => AppScope(
    state: state,
    child: MaterialApp(
      title: 'DhakaFlix Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFE50914),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const HomePage(),
    ),
  );
}
