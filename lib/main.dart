import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/source.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final store = await Store.open();
  final state = AppState(store, await store.setting(Settings.baseUrl) ?? defaultBaseUrl);
  runApp(DhakaFlixApp(state: state));
}
