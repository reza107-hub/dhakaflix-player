import 'dart:convert';

import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/core/natural_sort.dart';
import 'package:dhakaflix_player/core/paths.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('paths', () {
    // Real hrefs from the server.
    const nausicaa =
        '/DHAKA-FLIX-14/Animation%20Movies/%282000%29%20%26%20Before/'
        'Nausica%C3%A4%20of%20the%20Valley%20of%20the%20Wind%20%281984%29%20720p/';
    const episode =
        '/DHAKA-FLIX-14/KOREAN%20TV%20%26%20WEB%20Series/18%20Again%20%28TV%20Series%202020%29%20720p%20'
        '%5BDual%20Audio%5D/Season%201/18%20Again%20S01E01%20%20720p%20AMZN%20WEBRip%20x265%20HEVC%20ESub%20'
        '%5BDual%20Audio%5D%5BHindi%202.0%2BKorean%202.0%5D%20-MsMod.mkv';

    test('decodes unicode, &, (), [] and +', () {
      expect(nameOf(nausicaa), 'Nausicaä of the Valley of the Wind (1984) 720p');
      expect(
        nameOf(episode),
        '18 Again S01E01  720p AMZN WEBRip x265 HEVC ESub [Dual Audio][Hindi 2.0+Korean 2.0] -MsMod.mkv',
      );
      expect(decodeHref(parentOf(nausicaa)), '/DHAKA-FLIX-14/Animation Movies/(2000) & Before/');
    });

    test('encode/decode round-trips and encodes reserved characters', () {
      const name = 'Tom & Jerry [Dual Audio] (2021) 100% ä/b';
      final enc = encodeSegment(name);
      expect(enc.contains('/'), isFalse);
      expect(enc.contains('&'), isFalse);
      expect(decodeHref(enc), name);
    });

    test('malformed escapes do not throw', () {
      expect(decodeHref('/a/100%/'), '/a/100%/');
    });

    test('regex escaping neutralises metacharacters', () {
      expect(escapeRegex('angry (men'), r'angry \(men');
      expect(escapeRegex(r'a.b*c+d?[e]{f}|g^h$i\j/k'), r'a\.b\*c\+d\?\[e\]\{f\}\|g\^h\$i\\j\/k');
      // The escaped text must match itself literally.
      for (final s in ['angry (men', 'x[1]', 'a+b', r'c$d']) {
        expect(RegExp(escapeRegex(s)).hasMatch('..$s..'), isTrue, reason: s);
      }
    });

    test('search pattern joins words across spaces, dots, dashes', () {
      final re = RegExp(searchPattern('  angry   men '), caseSensitive: false);
      expect(re.hasMatch('12.Angry.Men.1957'), isTrue);
      expect(re.hasMatch('12 Angry Men (1957)'), isTrue);
      expect(RegExp(searchPattern('god father'), caseSensitive: false).hasMatch('The Godfather'), isTrue);
    });
  });

  group('natural sort', () {
    test('episode 2 before episode 10', () {
      final l = ['Show E10.mkv', 'Show E2.mkv', 'Show E1.mkv', 'Show E02 extra.mkv'];
      l.sort(naturalCompare);
      expect(l, ['Show E1.mkv', 'Show E02 extra.mkv', 'Show E2.mkv', 'Show E10.mkv']);
    });

    test('seasons, case-insensitive, leading zeros, huge numbers', () {
      final l = [
        'season 10',
        'Season 9',
        'Season 1',
        'S01E09',
        'S01E10',
        'S02E01',
        'x99999999999999999999',
        'x100000000000000000000',
      ];
      l.sort(naturalCompare);
      expect(l, [
        'S01E09',
        'S01E10',
        'S02E01',
        'Season 1',
        'Season 9',
        'season 10',
        'x99999999999999999999',
        'x100000000000000000000',
      ]);
    });

    test('is a consistent total order', () {
      expect(naturalCompare('a', 'a'), 0);
      expect(naturalCompare('A', 'a'), isNot(0)); // Stable tie-break.
      expect(naturalCompare('a2', 'a10').sign, -naturalCompare('a10', 'a2').sign);
    });
  });

  group('source guard', () {
    final src = DhakaFlixSource('http://172.16.50.14/DHAKA-FLIX-14');

    test('normalises base url', () {
      expect(src.base.toString(), 'http://172.16.50.14/DHAKA-FLIX-14/');
      expect(src.rootHref, '/DHAKA-FLIX-14/');
      expect(() => DhakaFlixSource('172.16.50.14'), throwsFormatException);
      expect(() => DhakaFlixSource('ftp://172.16.50.14/'), throwsFormatException);
    });

    test('allows only the configured host and folder', () {
      expect(src.allows(Uri.parse('http://172.16.50.14/DHAKA-FLIX-14/a%20b/c.mkv')), isTrue);
      expect(src.allows(Uri.parse('http://172.16.50.15/DHAKA-FLIX-14/c.mkv')), isFalse);
      expect(src.allows(Uri.parse('https://172.16.50.14/DHAKA-FLIX-14/c.mkv')), isFalse);
      expect(src.allows(Uri.parse('http://172.16.50.14:8080/DHAKA-FLIX-14/c.mkv')), isFalse);
      expect(src.allows(Uri.parse('http://172.16.50.14/DHAKA-FLIX-7/c.mkv')), isFalse);
      expect(src.isInside('/DHAKA-FLIX-14/../etc/'), isFalse);
      expect(() => src.urlFor('/other/'), throwsArgumentError);
    });

    test('urlFor keeps server encoding untouched', () {
      const href = '/DHAKA-FLIX-14/%282000%29%20%26%20Before/Nausica%C3%A4%20%5BX%5D.mkv';
      expect(src.urlFor(href).toString(), 'http://172.16.50.14$href');
    });

    test('relative path key is decoded', () {
      expect(src.relativePath('/DHAKA-FLIX-14/Hindi%20Movies/%282002%29/a.mkv'), 'Hindi Movies/(2002)/a.mkv');
    });
  });

  group('client (mocked server)', () {
    final src = DhakaFlixSource(defaultBaseUrl);
    const folder = '/DHAKA-FLIX-14/Show/Season%201/';

    test('list keeps direct children, sorts folders first then naturally, sends h5ai request', () async {
      late http.Request seen;
      final mock = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'items': [
              {'href': '/', 'time': 1, 'size': null},
              {'href': '/DHAKA-FLIX-14/', 'time': 1, 'size': null},
              {'href': '/DHAKA-FLIX-14/Show/', 'time': 1, 'size': null},
              {'href': folder, 'time': 1, 'size': null},
              {'href': '${folder}E10.mkv', 'time': 1700000000000, 'size': 10},
              {'href': '${folder}E2.mkv', 'time': 1, 'size': 20},
              {'href': '${folder}Extras/', 'time': 1, 'size': null},
            ],
          }),
          200,
        );
      });
      final c = DhakaFlixClient(src, httpClient: mock);
      final l = await c.list(folder);
      expect(l.map((e) => e.name), ['Extras', 'E2.mkv', 'E10.mkv']);
      expect(l[2].size, 10);
      expect(l[2].modified, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://172.16.50.14$folder?');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
      expect(seen.headers['User-Agent'], userAgent);
      expect(jsonDecode(seen.body), {
        'action': 'get',
        'items': {'href': folder, 'what': 1},
      });
    });

    test('search sends escaped pattern, ignores short queries, drops out-of-source hits', () async {
      var calls = 0;
      late Map body;
      final mock = MockClient((req) async {
        calls++;
        body = jsonDecode(req.body) as Map;
        return http.Response(
          jsonEncode({
            'search': [
              {'href': '/DHAKA-FLIX-14/A%20(Men)/', 'time': 1, 'size': null},
              {'href': '/ELSEWHERE/x.mkv', 'time': 1, 'size': 5},
            ],
          }),
          200,
        );
      });
      final c = DhakaFlixClient(src, httpClient: mock);
      expect(await c.search('ab').results, isEmpty);
      expect(calls, 0);
      final r = await c.search('angry (men').results;
      expect(r.map((e) => e.href), ['/DHAKA-FLIX-14/A%20(Men)/']);
      expect(body['search'], {'href': '/DHAKA-FLIX-14/', 'pattern': r'angry[\s._-]*\(men', 'ignorecase': true});
    });

    test('network failure becomes DhakaFlixUnreachable after one retry for listings', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        throw http.ClientException('Network is unreachable');
      });
      final c = DhakaFlixClient(src, httpClient: mock);
      await expectLater(c.list(folder), throwsA(isA<DhakaFlixUnreachable>()));
      expect(calls, 2);
      expect(unreachableMessage, 'DhakaFlix is not reachable. Connect to the ISP network.');
    });

    test('non-200 is a DhakaFlixError', () async {
      final c = DhakaFlixClient(src, httpClient: MockClient((_) async => http.Response('nope', 500)));
      await expectLater(c.list(folder), throwsA(isA<DhakaFlixError>()));
    });

    test('never more than maxConcurrent requests in flight', () async {
      var inFlight = 0, peak = 0;
      final mock = MockClient((req) async {
        inFlight++;
        peak = inFlight > peak ? inFlight : peak;
        await Future.delayed(const Duration(milliseconds: 20));
        inFlight--;
        return http.Response('{"items":[]}', 200);
      });
      final c = DhakaFlixClient(src, httpClient: mock, maxConcurrent: 2);
      await Future.wait(List.generate(8, (_) => c.list(folder)));
      expect(peak, 2);
    });
  });
}
