import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/player/sidecar.dart';
import 'package:flutter_test/flutter_test.dart';

Entry f(String name) => Entry(href: '/D/f/${Uri.encodeComponent(name)}', isDir: false, size: 1);

List<String> names(List<Entry> l) => l.map((e) => e.name).toList();

void main() {
  test('single video: every srt/ass/vtt belongs to it; image subs and posters skipped', () {
    final video = f('Batman-The Dark Knight Returns, Part 2 (2013) 720p.mkv');
    final sibs = [
      video,
      f('Batman.The.Dark.Knight.Part.2.2013.720p.BRrip.x264.GAZ.YIFY.srt'),
      f('extra.ass'),
      f('movie.idx'),
      f('movie.sub'),
      f('a_AL_.jpg'),
    ];
    expect(names(sidecarsFor(video, sibs)), [
      'Batman.The.Dark.Knight.Part.2.2013.720p.BRrip.x264.GAZ.YIFY.srt',
      'extra.ass',
    ]);
  });

  test('episodes match by SxxEyy, ignoring other episodes', () {
    final e1 = f('Show S01E01 720p x265.mkv');
    final sibs = [
      e1,
      f('Show S01E02 720p x265.mkv'),
      f('show.s01e01.eng.srt'),
      f('show.s01e02.eng.srt'),
      f('Show S1E1.vtt'),
    ];
    expect(names(sidecarsFor(e1, sibs)), ['Show S1E1.vtt', 'show.s01e01.eng.srt']);
  });

  test('episode-only numbering (E02) and E2 vs E12 are distinct', () {
    final e2 = f('Orange.Marmalade.E02.KOR.720p.NF.WEB-DL.x264.ESub-Pahe.mkv');
    final sibs = [
      e2,
      f('Orange.Marmalade.E12.KOR.720p.mkv'),
      f('Orange.Marmalade.E02.srt'),
      f('Orange.Marmalade.E12.srt'),
    ];
    expect(names(sidecarsFor(e2, sibs)), ['Orange.Marmalade.E02.srt']);
  });

  test('folder with unrelated movies matches by title before the year', () {
    final a = f('8MM (1999) 1080p BluRay x265 HEVC ESub [Dual Audio][Hindi 5.1+English 5.1] -mkvC.mkv');
    final b = f('10 Things I Hate About You (1999) 1080p.mkv');
    final sibs = [a, b, f('8MM.1999.1080p.BluRay.x264.srt'), f('10.Things.I.Hate.About.You.1999.srt')];
    expect(names(sidecarsFor(a, sibs)), ['8MM.1999.1080p.BluRay.x264.srt']);
    expect(names(sidecarsFor(b, sibs)), ['10.Things.I.Hate.About.You.1999.srt']);
  });

  test('exact base-name prefix wins and comes first', () {
    final v = f('Movie A (2001).mkv');
    final sibs = [v, f('Other (2003).mkv'), f('Movie A (2001).srt'), f('Movie A 2001 eng.srt')];
    expect(names(sidecarsFor(v, sibs)), ['Movie A (2001).srt', 'Movie A 2001 eng.srt']);
  });

  test('episodeKey, titleOf and language', () {
    expect(episodeKey('18 Again S01E10  720p'), 'S1E10');
    expect(episodeKey('Show.E5.mkv'), 'E5');
    expect(episodeKey('Episode 07.mkv'), 'E7');
    expect(episodeKey('Pulp Fiction (1994) 1080p x265 HEVC.mkv'), isNull);
    expect(titleOf('Pulp.Fiction.1994.1080p.srt'), 'pulp fiction');
    expect(sidecarLanguage('Movie.2001.eng.srt'), 'English');
    expect(sidecarLanguage('Movie (2001) [Bangla].srt'), 'Bengali');
    expect(sidecarLanguage('Movie.srt'), isNull);
  });
}
