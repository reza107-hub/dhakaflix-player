// Multi-server list, settings migration and the strict host/path guard.
import 'dart:convert';
import 'dart:io';

import 'package:dhakaflix_player/core/source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SourceList', () {
    test('defaults: the four servers, all enabled, DHAKA-FLIX-14 keeps id df14', () {
      final l = SourceList.load(null);
      expect(l.all.map((s) => s.base.toString()), [
        'http://172.16.50.14/DHAKA-FLIX-14/',
        'http://172.16.50.7/DHAKA-FLIX-7/',
        'http://172.16.50.12/DHAKA-FLIX-12/',
        'http://172.16.50.10/DHAKA-FLIX-10/',
      ]);
      expect(l.all.every((s) => s.enabled && s.builtIn), isTrue);
      expect(l.byId('df14')!.base.toString(), defaultBaseUrl);
    });

    test('v1.0.0 default or unset address: nothing extra', () {
      expect(SourceList.load(null, legacyBaseUrl: defaultBaseUrl).all.length, 4);
      expect(SourceList.load(null, legacyBaseUrl: 'http://172.16.50.14/DHAKA-FLIX-14').all.length, 4);
    });

    test('v1.0.0 custom address becomes an enabled custom source', () {
      final l = SourceList.load(null, legacyBaseUrl: 'http://10.0.0.5/MEDIA/');
      expect(l.all.length, 5);
      expect(l.byId(legacyCustomId)!.base.toString(), 'http://10.0.0.5/MEDIA/');
      expect(legacySourceId('http://10.0.0.5/MEDIA/'), legacyCustomId);
      expect(legacySourceId(null), 'df14');
    });

    test('enable/disable, add, remove and JSON round-trip', () {
      var l = SourceList.load(null).setEnabled('df12', false);
      l = l.addCustom('http://10.1.1.1/X');
      expect(() => l.addCustom('http://172.16.50.7/DHAKA-FLIX-7/'), throwsFormatException);
      expect(() => l.addCustom('not a url'), throwsFormatException);
      final back = SourceList.load(l.toJson());
      expect(back.byId('df12')!.enabled, isFalse);
      expect(back.byId('custom1')!.base.toString(), 'http://10.1.1.1/X/');
      expect(back.enabled.map((s) => s.id), ['df14', 'df7', 'df10', 'custom1']);
      expect(back.remove('custom1').byId('custom1'), isNull);
      expect(back.remove('df14').byId('df14'), isNotNull, reason: 'built-ins can only be disabled');
      // Stored settings cannot change a built-in server's address.
      final tampered = jsonEncode([
        {'id': 'df7', 'name': 'x', 'url': 'http://evil/', 'enabled': true},
      ]);
      expect(SourceList.load(tampered).byId('df7')!.base.host, '172.16.50.7');
      expect(SourceList.load('{broken').all.length, 4);
    });

    test('Android cleartext list matches the built-in hosts', () {
      final xml = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
      final hosts = RegExp(r'<domain[^>]*>([^<]+)</domain>').allMatches(xml).map((m) => m.group(1)!.trim()).toSet();
      expect(hosts, knownHosts);
      expect(defaultSources.map((d) => Uri.parse(d.url).host).toSet(), knownHosts);
      expect(xml, contains('<base-config cleartextTrafficPermitted="false" />'));
    });
  });

  group('host guard across servers', () {
    final l = SourceList.load(null);
    final df14 = l.byId('df14')!, df7 = l.byId('df7')!;

    test('each source allows only its own host + folder', () {
      expect(df7.allows(Uri.parse('http://172.16.50.7/DHAKA-FLIX-7/English%20Movies/a.mkv')), isTrue);
      // Host A with source B's path: rejected by A, B and the whole list.
      final mixed = Uri.parse('http://172.16.50.7/DHAKA-FLIX-14/a.mkv');
      expect(df7.allows(mixed), isFalse);
      expect(df14.allows(mixed), isFalse);
      expect(l.allows(mixed), isFalse);
      expect(l.allows(Uri.parse('http://172.16.50.14/DHAKA-FLIX-7/a.mkv')), isFalse);
      expect(l.allows(Uri.parse('http://172.16.50.12/DHAKA-FLIX-12/TV-WEB-Series/x.mkv')), isTrue);
      expect(l.allows(Uri.parse('http://172.16.50.99/DHAKA-FLIX-14/a.mkv')), isFalse);
    });

    test('disabled sources are not allowed', () {
      final off = l.setEnabled('df7', false);
      expect(off.allows(Uri.parse('http://172.16.50.7/DHAKA-FLIX-7/a.mkv')), isFalse);
      expect(off.allows(Uri.parse('http://172.16.50.14/DHAKA-FLIX-14/a.mkv')), isTrue);
    });

    test('path traversal, plain and percent-encoded', () {
      for (final bad in [
        '/DHAKA-FLIX-14/../etc/passwd',
        '/DHAKA-FLIX-14/a/..',
        '/DHAKA-FLIX-14/%2e%2e/DHAKA-FLIX-7/a.mkv',
        '/DHAKA-FLIX-14/%2E%2E/x',
        '/DHAKA-FLIX-14/.%2e/x',
        '/DHAKA-FLIX-14/./a.mkv',
        '/DHAKA-FLIX-14/a%2F..%2F..%2Fx',
        '/DHAKA-FLIX-14/a%5C..%5Cx',
        '/DHAKA-FLIX-14/a\\b',
        '/DHAKA-FLIX-14/%zz.mkv',
        '/DHAKA-FLIX-14/a.mkv?x=1',
        '/DHAKA-FLIX-140/a.mkv',
        '/DHAKA-FLIX-1/a.mkv',
      ]) {
        expect(df14.isInside(bad), isFalse, reason: bad);
      }
      expect(l.allows(Uri.parse('http://172.16.50.14/DHAKA-FLIX-14/a.mkv?x=1')), isFalse);
      expect(l.allows(Uri.parse('http://172.16.50.14/DHAKA-FLIX-14/a.mkv#f')), isFalse);
    });

    test('real encoded names are still allowed', () {
      for (final ok in [
        '/DHAKA-FLIX-14/Animation%20Movies/Nausica%C3%A4%20%5BX%5D.mkv',
        '/DHAKA-FLIX-14/KOREAN%20TV%20%26%20WEB%20Series/',
        '/DHAKA-FLIX-14/a/..b/c...mkv',
      ]) {
        expect(df14.isInside(ok), isTrue, reason: ok);
      }
      const unicode = '/DHAKA-FLIX-12/TV-WEB-Series/TV%20Series%20%E2%99%A6%20%20S%20%20%E2%80%94%20%20Z/';
      expect(l.byId('df12')!.isInside(unicode), isTrue);
      expect(l.byId('df12')!.relativePath(unicode), 'TV-WEB-Series/TV Series ♦  S  —  Z/');
    });
  });
}
