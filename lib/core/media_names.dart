/// Name parsing for the versions menu and auto-play next episode.
library;

import '../player/sidecar.dart';
import 'dhakaflix_client.dart';
import 'natural_sort.dart';

final _resolution = RegExp(r'(?:^|[^0-9])(\d{3,4})p(?![a-z0-9])', caseSensitive: false);
final _uhd = RegExp(r'\b(4k|uhd)\b', caseSensitive: false);
final _year = RegExp(r'(?:^|[^0-9])((?:19|20)\d\d)(?![0-9])');

/// Vertical resolution from the name (720, 1080, 2160), or null.
int? resolutionOf(String name) {
  final m = _resolution.firstMatch(name);
  if (m != null) return int.parse(m[1]!);
  return _uhd.hasMatch(name) ? 2160 : null;
}

String resolutionLabel(int r) => r == 2160 ? '2160p (4K)' : '${r}p';

/// Identity of "the same title or episode" across versions.
String? _identity(String name) {
  final ep = episodeKey(name);
  if (ep != null) return 'ep:$ep';
  final title = titleOf(name);
  if (title.isEmpty) return null;
  final year = _year.firstMatch(name)?[1];
  return 'title:$title:${year ?? ''}';
}

/// Other resolution versions of [video] in the same folder, including itself,
/// highest resolution first. Empty when there is nothing to switch to.
List<Entry> versionsOf(Entry video, List<Entry> siblings) {
  final id = _identity(video.name);
  if (id == null || resolutionOf(video.name) == null) return const [];
  final byRes = <int, Entry>{};
  for (final e in siblings.where(isVideo)) {
    final r = resolutionOf(e.name);
    if (r == null || _identity(e.name) != id) continue;
    // One entry per resolution; keep the current file for its own resolution.
    if (e.href == video.href || !byRes.containsKey(r)) byRes[r] = e;
  }
  if (byRes.length < 2) return const [];
  final keys = byRes.keys.toList()..sort((a, b) => b - a);
  return [for (final k in keys) byRes[k]!];
}

/// The next episode after [video] in its folder, preferring the same
/// resolution when several versions exist. Null if none or not an episode.
Entry? nextEpisode(Entry video, List<Entry> siblings) {
  final key = episodeKey(video.name);
  if (key == null) return null;
  final res = resolutionOf(video.name);
  final videos = siblings.where(isVideo).toList()..sort((a, b) => naturalCompare(a.name, b.name));
  final num = _episodeNumber(key);
  Entry? best;
  (int, int)? bestNum;
  for (final e in videos) {
    final k = episodeKey(e.name);
    if (k == null) continue;
    final n = _episodeNumber(k);
    if (_compare(n, num) <= 0) continue;
    if (bestNum == null || _compare(n, bestNum) < 0) {
      best = e;
      bestNum = n;
    } else if (_compare(n, bestNum) == 0 && res != null && resolutionOf(e.name) == res) {
      best = e; // Same episode, matching resolution wins.
    }
  }
  return best;
}

/// (season, episode); season 0 when unknown.
(int, int) _episodeNumber(String key) {
  final m = RegExp(r'^(?:S(\d+))?E(\d+)$').firstMatch(key)!;
  return (int.parse(m[1] ?? '0'), int.parse(m[2]!));
}

int _compare((int, int) a, (int, int) b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2;

/// "1.4 GB" / "350 MB".
String formatSize(int? bytes) {
  if (bytes == null) return '';
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / (1024 * 1024)).round()} MB';
}
