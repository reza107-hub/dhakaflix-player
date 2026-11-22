import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/source.dart';
import 'data/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundled font: show its licence on the app's licences page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Noto Sans'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  MediaKit.ensureInitialized();
  final store = await Store.open();
  final state = AppState(store, await store.setting(Settings.baseUrl) ?? defaultBaseUrl);
  runApp(DhakaFlixApp(state: state));
}
