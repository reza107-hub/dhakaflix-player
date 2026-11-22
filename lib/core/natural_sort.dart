/// Natural ("human") ordering: "E2" sorts before "E10", case-insensitive.
library;

final _chunk = RegExp(r'\d+|\D+');

int naturalCompare(String a, String b) {
  final ca = _chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final cb = _chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    final x = ca[i], y = cb[i];
    final xd = _isDigit(x), yd = _isDigit(y);
    int c;
    if (xd && yd) {
      // Compare numerically without overflow: strip leading zeros, then length, then digits.
      final xs = x.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final ys = y.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      c = xs.length != ys.length ? xs.length - ys.length : xs.compareTo(ys);
    } else {
      c = x.compareTo(y);
    }
    if (c != 0) return c;
  }
  if (ca.length != cb.length) return ca.length - cb.length;
  return a.compareTo(b); // Stable tie-break on the original text.
}

bool _isDigit(String s) {
  final c = s.codeUnitAt(0);
  return c >= 0x30 && c <= 0x39;
}
