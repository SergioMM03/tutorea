import 'package:flutter_test/flutter_test.dart';
import 'package:tutorea/config/supabase_config.dart';
import 'package:tutorea/data/supabase/supabase_bootstrap.dart';

/// Las pruebas nunca llaman al Supabase real: usan un inicializador falso.
void main() {
  late int calls;

  setUp(() {
    SupabaseBootstrap.resetForTesting();
    calls = 0;
  });

  Future<void> fakeOk(SupabaseConfig _) async {
    calls++;
  }

  final valid = SupabaseConfig.parse(
      url: 'https://abcdefgh.supabase.co', publishableKey: 'sb_publishable_abc123');

  test('sin configuración no inicializa y sigue en modo local', () async {
    final ok = await SupabaseBootstrap.initializeIfConfigured(
      config: SupabaseConfig.parse(url: '', publishableKey: ''),
      initializer: fakeOk,
    );
    expect(ok, isFalse);
    expect(calls, 0);
    expect(SupabaseBootstrap.isReady, isFalse);
  });

  test('por defecto (sin --dart-define) no inicializa', () async {
    expect(await SupabaseBootstrap.initializeIfConfigured(initializer: fakeOk), isFalse);
    expect(calls, 0);
  });

  test('con una clave prohibida no inicializa', () async {
    final ok = await SupabaseBootstrap.initializeIfConfigured(
      config: SupabaseConfig.parse(
          url: 'https://abcdefgh.supabase.co', publishableKey: 'sb_secret_abc123'),
      initializer: fakeOk,
    );
    expect(ok, isFalse);
    expect(calls, 0);
  });

  test('con configuración válida inicializa una sola vez', () async {
    expect(await SupabaseBootstrap.initializeIfConfigured(config: valid, initializer: fakeOk), isTrue);
    expect(await SupabaseBootstrap.initializeIfConfigured(config: valid, initializer: fakeOk), isTrue);
    expect(calls, 1);
    expect(SupabaseBootstrap.isReady, isTrue);
  });

  test('si la inicialización falla no lanza y sigue en modo local', () async {
    final ok = await SupabaseBootstrap.initializeIfConfigured(
      config: valid,
      initializer: (_) async => throw Exception('sin red'),
    );
    expect(ok, isFalse);
    expect(SupabaseBootstrap.isReady, isFalse);
  });

  test('si tarda demasiado no bloquea el arranque', () async {
    final ok = await SupabaseBootstrap.initializeIfConfigured(
      config: valid,
      initializer: (_) => Future<void>.delayed(const Duration(seconds: 1)),
      timeout: const Duration(milliseconds: 50),
    );
    expect(ok, isFalse);
    expect(SupabaseBootstrap.isReady, isFalse);
  });
}
