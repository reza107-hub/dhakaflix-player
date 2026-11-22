// Search across several servers: merging, labels, partial failure, cap, cancel.
import 'dart:convert';

import 'package:dhakaflix_player/core/dhakaflix_client.dart';
import 'package:dhakaflix_player/core/multi_search.dart';
import 'package:dhakaflix_player/core/source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final sources = SourceList.load(null);
  final df14 = sources.byId('df14')!, df7 = sources.byId('df7')!, df12 = sources.byId('df12')!;

  /// A client whose server answers with [hrefs] after [delay], or fails.
  DhakaFlixClient fake(DhakaFlixSource s, List<String> hrefs, {Duration delay = Duration.zero, Object? fail}) =>
      DhakaFlixClient(
        s,
        httpClient: MockClient((req) async {
          await Future.delayed(delay);
          if (fail != null) throw fail;
          return http.Response(
            jsonEncode({
              'search': [
                for (final h in hrefs) {'href': h, 'time': 1, 'size': h.endsWith('/') ? null : 10},
              ],
            }),
            200,
          );
        }),
      );

  test('results arrive per server as each answers, labelled with their server', () async {
    final s = MultiSearch({
      df14: fake(df14, ['/DHAKA-FLIX-14/Avatar.mkv'], delay: const Duration(milliseconds: 80)),
      df7: fake(df7, ['/DHAKA-FLIX-7/3D%20Movies/Avatar/']),
    }, 'avatar');
    final got = await s.results.toList();
    expect(got.map((r) => r.source.id), ['df7', 'df14'], reason: 'fastest server first');
    expect(got[0].entries.single.sourceId, 'df7');
    expect(got[1].entries.single.sourceId, 'df14');
    // Merge: folders first, then files; servers in configured order.
    final merged = mergeResults(got, sources.all);
    expect(merged.map((e) => e.href), ['/DHAKA-FLIX-7/3D%20Movies/Avatar/', '/DHAKA-FLIX-14/Avatar.mkv']);
    expect(mergeResults(got, sources.all, only: 'df14').map((e) => e.sourceId), ['df14']);
  });

  test('one server down: others still answer, failure is reported for that server', () async {
    final s = MultiSearch({
      df14: fake(df14, ['/DHAKA-FLIX-14/a.mkv']),
      df12: fake(df12, const [], fail: http.ClientException('Network is unreachable')),
    }, 'abc');
    final got = await s.results.toList();
    final bad = got.singleWhere((r) => r.source.id == 'df12');
    expect(bad.error, isA<DhakaFlixUnreachable>());
    expect(got.singleWhere((r) => r.source.id == 'df14').entries.length, 1);
    expect(mergeResults(got, sources.all).length, 1);
  });

  test('a server answering with another server\'s paths is dropped', () async {
    final s = MultiSearch({
      df7: fake(df7, ['/DHAKA-FLIX-14/x.mkv', '/DHAKA-FLIX-7/../DHAKA-FLIX-14/y.mkv', '/DHAKA-FLIX-7/ok.mkv']),
    }, 'abc');
    final got = await s.results.toList();
    expect(got.single.entries.map((e) => e.href), ['/DHAKA-FLIX-7/ok.mkv']);
  });

  test('memory cap per server, keep filter applies before the cap', () async {
    final many = [for (var i = 0; i < maxPerSource + 500; i++) '/DHAKA-FLIX-14/f$i.mkv', '/DHAKA-FLIX-14/poster.jpg'];
    final s = MultiSearch({df14: fake(df14, many)}, 'the', keep: (e) => !e.href.endsWith('.jpg'));
    final r = (await s.results.toList()).single;
    expect(r.entries.length, maxPerSource);
    expect(r.total, maxPerSource + 500);
    expect(r.truncated, isTrue);
  });

  test('cancel aborts every in-flight request and emits nothing', () async {
    var aborted = 0;
    DhakaFlixClient slow(DhakaFlixSource src) => DhakaFlixClient(
      src,
      httpClient: MockClient.streaming((req, _) async {
        final abortable = req as http.Abortable;
        await abortable.abortTrigger;
        aborted++;
        throw http.RequestAbortedException(req.url);
      }),
    );
    final s = MultiSearch({df14: slow(df14), df7: slow(df7), df12: slow(df12)}, 'abc');
    final done = s.results.toList();
    await Future.delayed(const Duration(milliseconds: 20));
    s.cancel();
    expect(await done.timeout(const Duration(seconds: 2)), isEmpty);
    expect(aborted, 3);
  });

  test('short query: no requests', () async {
    var calls = 0;
    final c = DhakaFlixClient(df14, httpClient: MockClient((_) async {
      calls++;
      return http.Response('{"search":[]}', 200);
    }));
    final got = await MultiSearch({df14: c}, 'ab').results.toList();
    expect(got.single.entries, isEmpty);
    expect(calls, 0);
  });
}
