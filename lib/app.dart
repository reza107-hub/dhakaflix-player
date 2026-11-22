import 'package:flutter/material.dart';

import 'core/dhakaflix_client.dart';
import 'core/source.dart';
import 'data/store.dart';
import 'ui/home_page.dart';

/// App-wide state: storage, the configured source and its client.
class AppState extends ChangeNotifier {
  AppState(this.store, String baseUrl) {
    _setSource(baseUrl);
  }

  final Store store;
  late DhakaFlixSource source;
  late DhakaFlixClient client;

  void _setSource(String baseUrl) {
    source = DhakaFlixSource(baseUrl);
    client = DhakaFlixClient(source);
  }

  /// Validates, stores and switches to a new base URL. Throws [FormatException].
  Future<void> setBaseUrl(String input) async {
    final normalised = parseBaseUrl(input).toString();
    client.close();
    _setSource(normalised);
    await store.setSetting(Settings.baseUrl, normalised);
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
