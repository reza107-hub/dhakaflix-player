// Live, read-only tests against the real DhakaFlix server.
// Run with: flutter test --tags live   (needs the ISP network)
@Tags(['live'])
library;

import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final src = DhakaFlixSource(defaultBaseUrl);
  late DhakaFlixClient client;
  setUp(() => client = DhakaFlixClient(src));
  tearDown(() => client.close());

  test('root lists the known categories', () async {
    final names = (await client.list(src.rootHref)).map((e) => e.name).toList();
    expect(names, containsAll(['Hindi Movies', 'IMDb Top-250 Movies', 'KOREAN TV & WEB Series']));
  });

  test('series season lists episodes in natural order with sizes', () async {
    final series = (await client.list('${src.rootHref}KOREAN%20TV%20%26%20WEB%20Series/'))
        .firstWhere((e) => e.name.startsWith('18 Again'));
    final season = (await client.list(series.href)).firstWhere((e) => e.isDir);
    final eps = (await client.list(season.href)).where((e) => e.name.endsWith('.mkv')).toList();
    expect(eps.length, greaterThanOrEqualTo(10));
    final numbers = eps.map((e) => int.parse(RegExp(r'E(\d+)').firstMatch(e.name)!.group(1)!)).toList();
    expect(numbers, List.generate(numbers.length, (i) => i + 1));
    expect(eps.every((e) => (e.size ?? 0) > 100 * 1024 * 1024), isTrue);
  });

  test('unicode folder round-trips: search href -> list -> file Range GET', () async {
    final hit = (await client.search('Nausica').results).firstWhere((e) => e.isDir && e.name.contains('ä'));
    expect(hit.name, startsWith('Nausicaä of the Valley of the Wind'));
    final files = await client.list(hit.href);
    final video = files.firstWhere((e) => !e.isDir && RegExp(r'\.(mkv|mp4|avi)$').hasMatch(e.name));
    final url = src.urlFor(video.href);
    expect(src.allows(url), isTrue);
    final res = await http.get(url, headers: {'Range': 'bytes=0-1023', 'User-Agent': userAgent});
    expect(res.statusCode, 206);
    expect(res.bodyBytes.length, 1024);
  });

  test('search: case-insensitive, regex chars are safe, multi-word', () async {
    expect((await client.search('GODFATHER').results), isNotEmpty);
    // Unescaped, "(" is an invalid regex and the server silently returns nothing.
    final paren = await client.search('angry men (1957').results;
    expect(paren.any((e) => e.name.contains('12 Angry Men (1957)')), isTrue);
    final words = await client.search('12 angry men').results;
    expect(words.any((e) => e.name.contains('12 Angry Men')), isTrue);
    final scoped = await client.search('again', scopeHref: '${src.rootHref}KOREAN%20TV%20%26%20WEB%20Series/').results;
    expect(scoped.every((e) => e.href.startsWith('${src.rootHref}KOREAN%20TV%20%26%20WEB%20Series/')), isTrue);
    expect(scoped, isNotEmpty);
  });

  test('search can be cancelled', () async {
    final h = client.search('the'); // Large result set.
    h.cancel();
    await expectLater(h.results, throwsA(isA<http.RequestAbortedException>()));
  });

  test('unreachable server gives the friendly error', () async {
    final dead = DhakaFlixClient(DhakaFlixSource('http://127.0.0.1:9/DHAKA-FLIX-14/'));
    await expectLater(dead.list('/DHAKA-FLIX-14/'), throwsA(isA<DhakaFlixUnreachable>()));
    dead.close();
  });
}
