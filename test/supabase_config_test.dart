import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tutorea/config/supabase_config.dart';

/// JWT de prueba (firma falsa): solo importa el payload.
String _jwt(Map<String, dynamic> payload) {
  String part(Object value) => base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.firma';
}

const _url = 'https://abcdefgh.supabase.co';
const _publishable = 'sb_publishable_abc123';

SupabaseConfig _parse({String url = _url, String key = _publishable}) =>
    SupabaseConfig.parse(url: url, publishableKey: key);

void main() {
  group('SupabaseConfig', () {
    test('sin --dart-define queda sin configurar (modo local)', () {
      final config = SupabaseConfig.fromEnvironment();
      expect(config.status, SupabaseConfigStatus.missing);
      expect(config.isValid, isFalse);
    });

    test('falta la URL o la clave', () {
      expect(_parse(url: '').status, SupabaseConfigStatus.missing);
      expect(_parse(key: '').status, SupabaseConfigStatus.missing);
      expect(_parse(url: '   ', key: '  ').status, SupabaseConfigStatus.missing);
    });

    test('acepta https y publishable key, sin espacios sobrantes', () {
      final config = _parse(url: '  $_url  ', key: ' $_publishable ');
      expect(config.isValid, isTrue);
      expect(config.url, _url);
      expect(config.publishableKey, _publishable);
    });

    test('acepta la anon key antigua (JWT con rol anon)', () {
      expect(_parse(key: _jwt({'role': 'anon', 'ref': 'abcdefgh'})).isValid, isTrue);
    });

    test('rechaza claves secretas sb_secret_', () {
      final config = _parse(key: 'sb_secret_abc123');
      expect(config.status, SupabaseConfigStatus.forbiddenKey);
      expect(config.isValid, isFalse);
      expect(config.publishableKey, isEmpty);
    });

    test('rechaza la service_role (JWT)', () {
      final config = _parse(key: _jwt({'role': 'service_role', 'ref': 'abcdefgh'}));
      expect(config.status, SupabaseConfigStatus.forbiddenKey);
      expect(config.publishableKey, isEmpty);
    });

    test('rechaza la clave prohibida aunque la URL también esté mal', () {
      expect(_parse(url: 'http://x', key: 'sb_secret_abc').status, SupabaseConfigStatus.forbiddenKey);
    });

    test('rechaza URLs que no son https', () {
      expect(_parse(url: 'http://abcdefgh.supabase.co').status, SupabaseConfigStatus.invalidUrl);
      expect(_parse(url: 'abcdefgh.supabase.co').status, SupabaseConfigStatus.invalidUrl);
      expect(_parse(url: 'https://').status, SupabaseConfigStatus.invalidUrl);
      expect(_parse(url: 'https://user:pass@abcdefgh.supabase.co').status, SupabaseConfigStatus.invalidUrl);
    });

    test('rechaza claves con formato desconocido', () {
      expect(_parse(key: 'cualquier-cosa').status, SupabaseConfigStatus.invalidKey);
      expect(_parse(key: 'sb_publishable_').status, SupabaseConfigStatus.invalidKey);
      expect(_parse(key: 'a.b.c').status, SupabaseConfigStatus.invalidKey);
      expect(_parse(key: _jwt({'role': 'authenticated'})).status, SupabaseConfigStatus.invalidKey);
      expect(_parse(key: _jwt({'sub': 'sin-rol'})).status, SupabaseConfigStatus.invalidKey);
    });

    test('los mensajes nunca muestran la clave', () {
      const secret = 'sb_secret_no_debe_aparecer';
      final rejected = _parse(key: secret);
      expect(rejected.description, isNot(contains(secret)));
      expect(rejected.toString(), isNot(contains(secret)));
      expect(rejected.description, contains('RECHAZADA'));

      final valid = _parse();
      expect(valid.description, isNot(contains(_publishable)));
      expect(valid.toString(), isNot(contains(_publishable)));
    });
  });
}
