/// Modo de datos de la app (Fases 14.5 a 14.8).
///
///   flutter run --dart-define-from-file=env/supabase.dev.json --dart-define=TUTOREA_AUTH=supabase
///
/// Con `supabase` (y Supabase inicializado): cuentas, perfiles, catálogo
/// (universidades, carreras, materias), tutores y disponibilidad vienen de
/// Supabase, y también las reservas (Fase 14.8). Sin TUTOREA_AUTH, con otro
/// valor o sin Supabase: todo local.
enum AuthMode {
  local,
  supabase;

  static const String variable = 'TUTOREA_AUTH';

  static AuthMode fromEnvironment() => parse(const String.fromEnvironment(variable));

  static AuthMode parse(String value) =>
      value.trim().toLowerCase() == 'supabase' ? AuthMode.supabase : AuthMode.local;
}
