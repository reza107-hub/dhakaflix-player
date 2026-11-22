/// The configured DhakaFlix source and the "only talk to this server" guard.
library;

import 'paths.dart';

const defaultBaseUrl = 'http://172.16.50.14/DHAKA-FLIX-14/';

/// Hosts allowed for cleartext HTTP. Must match
/// android/app/src/main/res/xml/network_security_config.xml, because Android
/// blocks cleartext to any host not listed there.
const knownHosts = {'172.16.50.14'};

/// Keep in sync with `version:` in pubspec.yaml.
const appVersion = '1.0.0';
const userAgent = 'DhakaFlixPlayer/$appVersion';

class DhakaFlixSource {
  DhakaFlixSource(String baseUrl) : base = parseBaseUrl(baseUrl);

  /// Normalised base, e.g. http://172.16.50.14/DHAKA-FLIX-14/
  final Uri base;

  /// Absolute href of the base folder, e.g. /DHAKA-FLIX-14/
  String get rootHref => base.path;

  /// Full URL for an h5ai href. Throws if it points outside this source.
  Uri urlFor(String href) {
    if (!isInside(href)) throw ArgumentError.value(href, 'href', 'outside the DhakaFlix source');
    // Keep the server's encoding as-is: build from the raw string, not Uri(path:).
    return Uri.parse('${base.scheme}://${base.authority}$href');
  }

  /// True if [href] is an absolute path inside the base folder.
  bool isInside(String href) =>
      href.startsWith(rootHref) && !href.contains('/../') && !href.contains('/./') && !href.contains('\\');

  /// Guard for any URL handed to the player or the HTTP client.
  bool allows(Uri url) =>
      url.scheme == base.scheme && url.host == base.host && url.port == base.port && isInside(url.path);

  /// Relative, decoded path used as a stable storage key (with the file size).
  String relativePath(String href) => decodeHref(href.substring(rootHref.length));
}

/// Validates and normalises a user-entered base URL. Throws [FormatException].
Uri parseBaseUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    throw const FormatException('Enter a full address such as http://172.16.50.14/DHAKA-FLIX-14/');
  }
  final path = uri.path.isEmpty ? '/' : (uri.path.endsWith('/') ? uri.path : '${uri.path}/');
  return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path);
}
