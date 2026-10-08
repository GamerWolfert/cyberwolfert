import 'package:flutter_test/flutter_test.dart';
import 'package:cyberwolfert_browser/services/url_utils.dart';

void main() {
  group('UrlUtils.asUrl — alles wat een adres is wordt een URL', () {
    test('gewone domeinen', () {
      expect(UrlUtils.asUrl('google.com'), 'google.com');
      expect(UrlUtils.asUrl('voorbeeld.nl'), 'voorbeeld.nl');
      expect(UrlUtils.asUrl('www.a.nl'), 'www.a.nl');
      expect(UrlUtils.asUrl('sub.domein.co.uk/pad?x=1&y=2'),
          'sub.domein.co.uk/pad?x=1&y=2');
      expect(UrlUtils.asUrl('  google.com  '), 'google.com');
    });

    test('bestaande schemes blijven intact', () {
      expect(UrlUtils.asUrl('https://a.nl/x'), 'https://a.nl/x');
      expect(UrlUtils.asUrl('http://a.nl'), 'http://a.nl');
      expect(UrlUtils.asUrl('about:blank'), 'about:blank');
      expect(UrlUtils.asUrl('ftp://bestand.nl/x.zip'), 'ftp://bestand.nl/x.zip');
    });

    test("localhost, IP's en poorten (kameras/backends)", () {
      expect(UrlUtils.asUrl('localhost:8080/status'), 'localhost:8080/status');
      expect(UrlUtils.asUrl('192.168.1.42:43711/'), '192.168.1.42:43711/');
      expect(UrlUtils.asUrl('10.0.0.5'), '10.0.0.5');
      expect(UrlUtils.asUrl('127.0.0.1'), '127.0.0.1');
    });

    test('zoekopdrachten blijven zoekopdrachten', () {
      expect(UrlUtils.asUrl('hoe maak ik een website'), isNull);
      expect(UrlUtils.asUrl('hallo'), isNull);
      expect(UrlUtils.asUrl(''), isNull);
      expect(UrlUtils.asUrl('   '), isNull);
    });

    test('adres met spaties wordt toch een adres', () {
      expect(UrlUtils.asUrl('youtube.com/watch?v=abc meer woorden'),
          'youtube.com/watch?v=abcmeerwoorden');
      expect(UrlUtils.asUrl('google.com zoeken'), isNull);
    });
  });

  group('UrlUtils.normScheme', () {
    test('https als het ontbreekt', () {
      expect(UrlUtils.normScheme('google.com'), 'https://google.com');
      expect(UrlUtils.normScheme('//cdn.a.nl/x'), 'https://cdn.a.nl/x');
    });

    test('http voor lokale adressen (geen certificaat)', () {
      expect(UrlUtils.normScheme('localhost:8080'), 'http://localhost:8080');
      expect(UrlUtils.normScheme('192.168.1.42:43711/'),
          'http://192.168.1.42:43711/');
      expect(UrlUtils.normScheme('127.0.0.1/x'), 'http://127.0.0.1/x');
    });

    test('bestaande schemes nooit dubbeld', () {
      expect(UrlUtils.normScheme('https://a.nl'), 'https://a.nl');
      expect(UrlUtils.normScheme('http://a.nl'), 'http://a.nl');
      expect(UrlUtils.normScheme('https://localhost:9/x'),
          'https://localhost:9/x');
    });
  });
}
