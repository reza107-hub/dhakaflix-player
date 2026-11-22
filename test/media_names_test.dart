import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/core/media_names.dart';
import 'package:flutter_test/flutter_test.dart';

Entry f(String name, [int size = 1]) => Entry(href: '/D/x/${Uri.encodeComponent(name)}', isDir: false, size: size);
List<String> names(Iterable<Entry> l) => l.map((e) => e.name).toList();

void main() {
  test('resolution parsing', () {
    expect(resolutionOf('Movie (2001) 1080p BluRay x265.mkv'), 1080);
    expect(resolutionOf('Show S01E01  720p AMZN.mkv'), 720);
    expect(resolutionOf('Movie.2160p.UHD.mkv'), 2160);
    expect(resolutionOf('Movie 4K HDR.mkv'), 2160);
    expect(resolutionOf('Movie (2001).mkv'), isNull);
    expect(resolutionOf('x264 AAC.mkv'), isNull); // "264" without p is not a resolution.
  });

  test('versions: same movie in 720p and 1080p, unrelated movie ignored', () {
    final a720 = f('Inception (2010) 720p BluRay.mkv');
    final a1080 = f('Inception.2010.1080p.BluRay.x265.mkv');
    final other = f('Interstellar (2014) 1080p.mkv');
    final sibs = [a720, a1080, other, f('a_AL_.jpg')];
    expect(names(versionsOf(a720, sibs)), [a1080.name, a720.name]);
    expect(versionsOf(other, sibs), isEmpty);
  });

  test('versions: episodes match by SxxEyy only', () {
    final e1a = f('Show S01E01 720p.mkv');
    final e1b = f('Show S01E01 1080p.mkv');
    final e2 = f('Show S01E02 1080p.mkv');
    expect(names(versionsOf(e1a, [e1a, e1b, e2])), [e1b.name, e1a.name]);
    expect(versionsOf(e2, [e1a, e1b, e2]), isEmpty);
  });

  test('versions hidden when only one resolution or no resolution tag', () {
    final a = f('Movie (2001) 1080p.mkv');
    final b = f('Movie (2001) 1080p Extended.mkv');
    expect(versionsOf(a, [a, b]), isEmpty);
    final c = f('Movie (2001).mkv');
    expect(versionsOf(c, [c, a]), isEmpty);
  });

  test('next episode: natural order, skips non-episodes, prefers same resolution', () {
    final eps = [
      for (final n in [1, 2, 10, 3]) f('Show S01E${n.toString().padLeft(2, '0')} 720p.mkv'),
      f('Show S01E02 1080p.mkv'),
      f('Show Special.mkv'),
    ];
    expect(nextEpisode(eps[0], eps)!.name, 'Show S01E02 720p.mkv');
    expect(nextEpisode(eps[1], eps)!.name, 'Show S01E03 720p.mkv');
    expect(nextEpisode(eps[3], eps)!.name, 'Show S01E10 720p.mkv');
    expect(nextEpisode(eps[2], eps), isNull); // Last episode.
    expect(nextEpisode(f('Movie (2001).mkv'), eps), isNull);
  });

  test('next episode with E-only numbering and across seasons in one folder', () {
    final a = [f('Orange.Marmalade.E09.mkv'), f('Orange.Marmalade.E10.mkv'), f('Orange.Marmalade.E11.mkv')];
    expect(nextEpisode(a[0], a)!.name, 'Orange.Marmalade.E10.mkv');
    final b = [f('X S01E12.mkv'), f('X S02E01.mkv')];
    expect(nextEpisode(b[0], b)!.name, 'X S02E01.mkv');
  });

  test('formatSize', () {
    expect(formatSize(2676718 * 1024), '2.6 GB');
    expect(formatSize(404455447), '386 MB');
    expect(formatSize(null), '');
  });
}
