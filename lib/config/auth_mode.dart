import 'package:flutter/foundation.dart';

/// Origen de los datos de la app (Fase 14.10).
///
/// Producción: SIEMPRE Supabase (Auth + datos de negocio). No hay respaldo
/// local: si Supabase no está configurado o no responde, la app muestra un
/// error con "Reintentar" (StartupErrorApp).
///
/// Solo una compilación de DESARROLLO (debug o profile, nunca release) puede
/// pedir los datos locales de demostración, y solo de forma explícita:
///
///   flutter run --dart-define=TUTOREA_AUTH=local
///
/// Cualquier otro valor, o ninguno, es Supabase:
///
///   flutter run --dart-define-from-file=env/supabase.dev.json
enum AuthMode {
  local,
  supabase;

  static const String variable = 'TUTOREA_AUTH';

  static AuthMode fromEnvironment() =>
      resolve(const String.fromEnvironment(variable), releaseMode: kReleaseMode);

  /// En release nunca es local, aunque se pida.
  static AuthMode resolve(String value, {required bool releaseMode}) =>
      !releaseMode && value.trim().toLowerCase() == 'local' ? AuthMode.local : AuthMode.supabase;
}
