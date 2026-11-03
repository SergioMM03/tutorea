import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

/// Función que inicializa el cliente; las pruebas pasan una falsa.
typedef SupabaseInitializer = Future<void> Function(SupabaseConfig config);

/// Inicializa Supabase solo si hay una configuración válida (Fase 14.3).
///
/// - Sin configuración, con una clave prohibida o si la inicialización falla,
///   no lanza excepciones: devuelve false. Desde la Fase 14.10 la app muestra
///   entonces un error con "Reintentar" (no hay respaldo local en producción).
/// - Supabase guarda su sesión con una clave propia (sb-<project-ref>-auth-token).
class SupabaseBootstrap {
  SupabaseBootstrap._();

  /// Tiempo máximo que el arranque espera a Supabase.
  static const Duration defaultTimeout = Duration(seconds: 5);

  static bool _ready = false;

  /// true si Supabase quedó inicializado en esta ejecución.
  static bool get isReady => _ready;

  static Future<bool> initializeIfConfigured({
    SupabaseConfig? config,
    SupabaseInitializer? initializer,
    Duration timeout = defaultTimeout,
  }) async {
    if (_ready) return true;

    final effective = config ?? SupabaseConfig.fromEnvironment();
    if (!effective.isValid) {
      debugPrint('[Supabase] ${effective.description}');
      return false;
    }

    try {
      await (initializer ?? _initializeClient)(effective).timeout(timeout);
      _ready = true;
      debugPrint('[Supabase] Inicializado (${effective.url}).');
      return true;
    } on TimeoutException {
      debugPrint('[Supabase] La inicialización tardó más de ${timeout.inSeconds} s.');
      return false;
    } catch (error) {
      debugPrint('[Supabase] No se pudo inicializar ($error).');
      return false;
    }
  }

  static Future<void> _initializeClient(SupabaseConfig config) async {
    await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      // Sin OAuth ni enlaces de confirmación (confirmación de correo desactivada):
      // no se escuchan enlaces profundos.
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    );
  }

  /// Solo para pruebas: vuelve al estado inicial.
  @visibleForTesting
  static void resetForTesting() => _ready = false;
}
