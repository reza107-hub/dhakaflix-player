/// Finds sidecar subtitle files for a video in the same folder.
///
/// DhakaFlix sidecar names rarely match the video exactly, for example
/// `Batman.The.Dark.Knight.Part.2.2013.720p.BRrip.x264.GAZ.YIFY.srt` next to a
/// differently named video. Matching rules (first that applies):
///  1. Only one video in the folder: every subtitle file belongs to it.
///  2. Video has an episode tag (S01E02 / E02): subtitles with the same tag.
///  3. Otherwise: subtitles whose title (words before the year/quality tags)
///     equals the video's title, or that start with the full video base name.
/// Image formats (.sub/.idx) are skipped in v1.
library;

import '../core/dhakaflix_client.dart';
import '../core/natural_sort.dart';

const subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt'};
const videoExtensions = {'mkv', 'mp4', 'avi', 'm4v', 'webm', 'flv', 'wmv', 'ts', 'mov'};

String extensionOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

bool isVideo(Entry e) => !e.isDir && videoExtensions.contains(extensionOf(e.name));
bool isSubtitle(Entry e) => !e.isDir && subtitleExtensions.contains(extensionOf(e.name));

String _base(String name) {
  final i = name.lastIndexOf('.');
  return (i < 0 ? name : name.substring(0, i)).toLowerCase();
}

String _normalise(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

final _seasonEpisode = RegExp(r's(\d{1,2})[ ._-]*e(\d{1,3})', caseSensitive: false);
final _episodeOnly = RegExp(r'(?:^|[^a-z0-9])e(?:p(?:isode)?)?[ ._-]*(\d{1,3})(?![0-9])', caseSensitive: false);

/// "S1E2" style key, or "E2" if only an episode number exists, else null.
String? episodeKey(String name) {
  final se = _seasonEpisode.firstMatch(name);
  if (se != null) return 'S${int.parse(se[1]!)}E${int.parse(se[2]!)}';
  final e = _episodeOnly.firstMatch(name);
  return e == null ? null : 'E${int.parse(e[1]!)}';
}

final _titleStop = RegExp(r'\b(19\d\d|20\d\d|\d{3,4}p|s\d{1,2}e\d{1,3})\b');

/// Words before the year / resolution / episode tag, normalised.
String titleOf(String name) {
  final n = _normalise(_base(name));
  final m = _titleStop.firstMatch(n);
  return (m == null ? n : n.substring(0, m.start)).trim();
}

/// Sidecar subtitles for [video] among its folder [siblings], best first.
List<Entry> sidecarsFor(Entry video, List<Entry> siblings) {
  final subs = siblings.where(isSubtitle).toList();
  if (subs.isEmpty) return const [];
  final videos = siblings.where(isVideo).toList();
  List<Entry> picked;
  if (videos.length <= 1) {
    picked = subs;
  } else {
    final ep = episodeKey(video.name);
    if (ep != null) {
      picked = subs.where((s) => episodeKey(s.name) == ep).toList();
    } else {
      final base = _base(video.name);
      final title = titleOf(video.name);
      picked = subs
          .where((s) => _base(s.name).startsWith(base) || (title.isNotEmpty && titleOf(s.name) == title))
          .toList();
    }
  }
  final base = _base(video.name);
  // Exact base-name matches first, then natural order.
  return picked..sort((a, b) {
    final ea = _base(a.name).startsWith(base) ? 0 : 1;
    final eb = _base(b.name).startsWith(base) ? 0 : 1;
    return ea != eb ? ea - eb : naturalCompare(a.name, b.name);
  });
}

/// Best-effort language label from a sidecar name, e.g. "Movie.eng.srt".
String? sidecarLanguage(String name) {
  final parts = _base(name).split(RegExp(r'[ ._\-\[\]()]+'));
  if (parts.length < 2) return null;
  const known = {
    'en': 'English',
    'eng': 'English',
    'english': 'English',
    'hi': 'Hindi',
    'hin': 'Hindi',
    'hindi': 'Hindi',
    'bn': 'Bengali',
    'ben': 'Bengali',
    'bangla': 'Bengali',
    'bengali': 'Bengali',
    'ko': 'Korean',
    'kor': 'Korean',
    'korean': 'Korean',
    'ar': 'Arabic',
    'ara': 'Arabic',
    'arabic': 'Arabic',
    'es': 'Spanish',
    'spa': 'Spanish',
    'spanish': 'Spanish',
    'fr': 'French',
    'fre': 'French',
    'fra': 'French',
    'french': 'French',
  };
  for (final p in parts.reversed.take(3)) {
    final l = known[p];
    if (l != null) return l;
  }
  return null;
}
