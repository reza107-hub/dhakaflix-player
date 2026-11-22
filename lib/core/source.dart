/// DhakaFlix sources (servers) and the "only talk to these servers" guard.
library;

import 'dart:convert';

import 'paths.dart';

/// The built-in servers, in display order. All enabled by default.
///
/// ADDING A HOST: Android blocks plain HTTP to any host that is not listed in
/// android/app/src/main/res/xml/network_security_config.xml. When you add a
/// server here, add its host there too, and to [knownHosts] below.
const defaultSources = [
  (id: 'df14', name: 'DHAKA-FLIX-14', url: 'http://172.16.50.14/DHAKA-FLIX-14/'),
  (id: 'df7', name: 'DHAKA-FLIX-7', url: 'http://172.16.50.7/DHAKA-FLIX-7/'),
  (id: 'df12', name: 'DHAKA-FLIX-12', url: 'http://172.16.50.12/DHAKA-FLIX-12/'),
  (id: 'df10', name: 'DHAKA-FLIX-10', url: 'http://172.16.50.10/DHAKA-FLIX-10/'),
];

/// The only server of v1.0.0. Its history rows migrate to source id `df14`.
const defaultBaseUrl = 'http://172.16.50.14/DHAKA-FLIX-14/';

/// Hosts allowed for cleartext HTTP on Android. Must match
/// android/app/src/main/res/xml/network_security_config.xml.
const knownHosts = {'172.16.50.14', '172.16.50.7', '172.16.50.12', '172.16.50.10'};

/// Keep in sync with `version:` in pubspec.yaml.
const appVersion = '1.1.0';
const userAgent = 'DhakaFlixPlayer/$appVersion';

/// Source id given to a custom address carried over from v1.0.0 settings.
const legacyCustomId = 'custom1';

class DhakaFlixSource {
  DhakaFlixSource(String baseUrl, {this.id = 'df14', String? name, this.enabled = true, this.builtIn = false})
    : base = parseBaseUrl(baseUrl),
      name = name ?? parseBaseUrl(baseUrl).toString();

  /// Stable id stored with history rows. Never changes for a server.
  final String id;
  final String name;
  final bool enabled;
  final bool builtIn;

  /// Normalised base, e.g. http://172.16.50.14/DHAKA-FLIX-14/
  final Uri base;

  /// Absolute href of the base folder, e.g. /DHAKA-FLIX-14/
  String get rootHref => base.path;

  DhakaFlixSource copyWith({bool? enabled}) =>
      DhakaFlixSource(base.toString(), id: id, name: name, enabled: enabled ?? this.enabled, builtIn: builtIn);

  /// Full URL for an h5ai href. Throws if it points outside this source.
  Uri urlFor(String href) {
    if (!isInside(href)) throw ArgumentError.value(href, 'href', 'outside the DhakaFlix source');
    // Keep the server's encoding as-is: build from the raw string, not Uri(path:).
    return Uri.parse('${base.scheme}://${base.authority}$href');
  }

  /// True if [href] is an absolute path inside the base folder, with no
  /// `.`/`..` segments (plain or percent-encoded) and no backslashes.
  bool isInside(String href) {
    if (!href.startsWith(rootHref) || href.contains('\\') || href.contains('?') || href.contains('#')) return false;
    for (final seg in href.substring(rootHref.length).split('/')) {
      final String d;
      try {
        d = Uri.decodeComponent(seg);
      } catch (_) {
        return false; // Broken percent-encoding or invalid UTF-8.
      }
      if (d == '.' || d == '..' || d.contains('/') || d.contains('\\')) return false;
    }
    return true;
  }

  /// Guard for any URL handed to the player or the HTTP client.
  bool allows(Uri url) =>
      url.scheme == base.scheme &&
      url.host == base.host &&
      url.port == base.port &&
      !url.hasQuery &&
      !url.hasFragment &&
      isInside(url.path);

  /// Relative, decoded path used as a storage key (with source id and size).
  String relativePath(String href) => decodeHref(href.substring(rootHref.length));

  Map<String, Object> toJson() => {'id': id, 'name': name, 'url': base.toString(), 'enabled': enabled};
}

/// All configured sources. Built-in servers always exist (they can only be
/// disabled); custom servers can be added and removed.
class SourceList {
  SourceList(List<DhakaFlixSource> sources) : all = List.unmodifiable(sources);

  final List<DhakaFlixSource> all;

  List<DhakaFlixSource> get enabled => all.where((s) => s.enabled).toList();

  DhakaFlixSource? byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// True only if one *enabled* source allows the whole URL (host and path
  /// of the same source: host A with source B's folder is refused).
  bool allows(Uri url) => enabled.any((s) => s.allows(url));

  /// Loads from the stored JSON. [legacyBaseUrl] is the v1.0.0 single-address
  /// setting: if it was a custom address it becomes a custom source.
  static SourceList load(String? json, {String? legacyBaseUrl}) {
    final saved = <String, Map<String, dynamic>>{};
    if (json != null) {
      try {
        for (final m in (jsonDecode(json) as List).cast<Map<String, dynamic>>()) {
          saved[m['id'] as String] = m;
        }
      } on Object {
        // Corrupt setting: fall back to defaults.
      }
    }
    final list = [
      for (final d in defaultSources)
        DhakaFlixSource(d.url, id: d.id, name: d.name, builtIn: true, enabled: saved[d.id]?['enabled'] as bool? ?? true),
    ];
    for (final m in saved.values) {
      if (list.any((s) => s.id == m['id'])) continue;
      try {
        list.add(
          DhakaFlixSource(m['url'] as String, id: m['id'] as String, name: m['name'] as String?, enabled: m['enabled'] as bool? ?? true),
        );
      } on Object {
        // Skip a broken custom entry.
      }
    }
    if (json == null && legacySourceId(legacyBaseUrl) == legacyCustomId) {
      list.add(DhakaFlixSource(legacyBaseUrl!, id: legacyCustomId));
    }
    return SourceList(list);
  }

  String toJson() => jsonEncode([for (final s in all) s.toJson()]);

  SourceList setEnabled(String id, bool enabled) =>
      SourceList([for (final s in all) s.id == id ? s.copyWith(enabled: enabled) : s]);

  /// Adds a custom server. Throws [FormatException] for a bad or duplicate address.
  SourceList addCustom(String url) {
    final base = parseBaseUrl(url);
    if (all.any((s) => s.base == base)) throw const FormatException('This server is already in the list.');
    var n = 1;
    while (all.any((s) => s.id == 'custom$n')) {
      n++;
    }
    return SourceList([...all, DhakaFlixSource(base.toString(), id: 'custom$n')]);
  }

  SourceList remove(String id) => SourceList([for (final s in all) if (s.id != id || s.builtIn) s]);
}

/// Source id for history rows written by v1.0.0, which had one address:
/// `df14` for the default (or unset), [legacyCustomId] for anything else.
String legacySourceId(String? legacyBaseUrl) {
  if (legacyBaseUrl == null) return 'df14';
  try {
    return parseBaseUrl(legacyBaseUrl) == parseBaseUrl(defaultBaseUrl) ? 'df14' : legacyCustomId;
  } on FormatException {
    return 'df14';
  }
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
