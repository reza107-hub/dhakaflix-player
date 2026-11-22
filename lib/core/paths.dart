/// Helpers for DhakaFlix (h5ai) hrefs.
///
/// h5ai returns hrefs already percent-encoded (UTF-8). We keep them exactly as
/// received for requests and only decode for display, so nothing is ever
/// double-encoded.
library;

/// Decodes an href for display. Falls back to the raw text if it is malformed.
String decodeHref(String href) {
  try {
    return Uri.decodeComponent(href);
  } on ArgumentError {
    return href;
  }
}

/// The display name of an entry: the last path segment, decoded.
String nameOf(String href) {
  final trimmed = href.endsWith('/') ? href.substring(0, href.length - 1) : href;
  return decodeHref(trimmed.substring(trimmed.lastIndexOf('/') + 1));
}

/// The parent folder href (with trailing slash).
String parentOf(String href) {
  final trimmed = href.endsWith('/') ? href.substring(0, href.length - 1) : href;
  return trimmed.substring(0, trimmed.lastIndexOf('/') + 1);
}

/// Encodes one decoded path segment the way h5ai does (so `/` cannot leak in).
String encodeSegment(String segment) => Uri.encodeComponent(segment);

/// Escapes PCRE metacharacters. h5ai's search `pattern` is a regex; an
/// unbalanced `(` makes the server silently return no results.
String escapeRegex(String s) => s.replaceAllMapped(RegExp(r'[\\^$.|?*+()\[\]{}/#-]'), (m) => '\\${m[0]}');

/// Builds the search pattern from user input: each word is escaped, and words
/// may be joined by nothing, spaces, dots, underscores or dashes, so
/// "god father" finds "Godfather" and "angry men" finds "12.Angry.Men".
String searchPattern(String query) =>
    query.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map(escapeRegex).join(r'[\s._-]*');
