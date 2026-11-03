/// Qué autenticación usa la app (Fase 14.5).
///
///   flutter run --dart-define-from-file=env/supabase.dev.json --dart-define=TUTOREA_AUTH=supabase
///
/// Sin TUTOREA_AUTH, o con cualquier otro valor, se usa la autenticación local.
/// Con `supabase` solo se usa si Supabase quedó inicializado; si no, también local.
enum AuthMode {
  local,
  supabase;

  static const String variable = 'TUTOREA_AUTH';

  static AuthMode fromEnvironment() => parse(const String.fromEnvironment(variable));

  static AuthMode parse(String value) =>
      value.trim().toLowerCase() == 'supabase' ? AuthMode.supabase : AuthMode.local;
}
