import 'dart:convert';

/// Resultado de validar la configuración de Supabase.
enum SupabaseConfigStatus {
  /// URL https y publishable key (o anon key antigua) válidas.
  valid,

  /// Falta la URL, la clave o ambas: la app muestra un error al arrancar (Fase 14.10).
  missing,

  /// La URL no es https o no tiene dominio.
  invalidUrl,

  /// Clave secreta (sb_secret_...) o JWT de service_role: nunca en Flutter.
  forbiddenKey,

  /// La clave no tiene un formato reconocido.
  invalidKey,
}

/// Configuración de Supabase que llega al compilar con `--dart-define` o
/// `--dart-define-from-file` (ver README):
///
///   SUPABASE_URL              https://<project-ref>.supabase.co
///   SUPABASE_PUBLISHABLE_KEY  sb_publishable_...
///
/// Solo se acepta la clave pública. Las claves secretas (`sb_secret_...`) y la
/// `service_role` se rechazan siempre: esas claves saltan RLS y solo pueden
/// vivir en los scripts del equipo, nunca dentro de la app.
class SupabaseConfig {
  static const String urlVariable = 'SUPABASE_URL';
  static const String keyVariable = 'SUPABASE_PUBLISHABLE_KEY';

  static const String _publishablePrefix = 'sb_publishable_';
  static const String _secretPrefix = 'sb_secret_';

  final String url;
  final String publishableKey;
  final SupabaseConfigStatus status;

  const SupabaseConfig._(this.url, this.publishableKey, this.status);

  /// Lee los valores definidos al compilar. Sin `--dart-define` quedan vacíos.
  factory SupabaseConfig.fromEnvironment() => SupabaseConfig.parse(
        url: const String.fromEnvironment(urlVariable),
        publishableKey: const String.fromEnvironment(keyVariable),
      );

  /// Valida una URL y una clave. Nunca lanza excepciones.
  factory SupabaseConfig.parse({required String url, required String publishableKey}) {
    final cleanUrl = url.trim();
    final cleanKey = publishableKey.trim();

    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      return const SupabaseConfig._('', '', SupabaseConfigStatus.missing);
    }
    // La clave se revisa primero: una clave prohibida se rechaza aunque la URL
    // también esté mal, para que el mensaje lo diga claramente.
    final keyStatus = _checkKey(cleanKey);
    if (keyStatus != SupabaseConfigStatus.valid) {
      return SupabaseConfig._('', '', keyStatus);
    }
    if (!_isValidUrl(cleanUrl)) {
      return const SupabaseConfig._('', '', SupabaseConfigStatus.invalidUrl);
    }
    return SupabaseConfig._(cleanUrl, cleanKey, SupabaseConfigStatus.valid);
  }

  bool get isValid => status == SupabaseConfigStatus.valid;

  /// Mensaje para la consola. Nunca incluye la clave.
  String get description => switch (status) {
        SupabaseConfigStatus.valid => 'Configuración de Supabase válida ($url).',
        SupabaseConfigStatus.missing =>
          'Supabase no configurado: faltan $urlVariable o $keyVariable.',
        SupabaseConfigStatus.invalidUrl =>
          '$urlVariable no es una URL https válida.',
        SupabaseConfigStatus.forbiddenKey =>
          'RECHAZADA: $keyVariable es una clave secreta o service_role. '
              'Nunca se usa en Flutter; usa la publishable key.',
        SupabaseConfigStatus.invalidKey =>
          '$keyVariable no tiene el formato de una publishable key.',
      };

  @override
  String toString() => 'SupabaseConfig(${status.name})'; // sin la clave

  static bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
  }

  static SupabaseConfigStatus _checkKey(String key) {
    if (key.startsWith(_secretPrefix)) return SupabaseConfigStatus.forbiddenKey;
    if (key.startsWith(_publishablePrefix)) {
      return key.length > _publishablePrefix.length
          ? SupabaseConfigStatus.valid
          : SupabaseConfigStatus.invalidKey;
    }
    // Claves antiguas (JWT): solo se acepta la de rol anon.
    final role = _jwtRole(key);
    if (role == null) return SupabaseConfigStatus.invalidKey;
    if (role == 'anon') return SupabaseConfigStatus.valid;
    if (role == 'service_role') return SupabaseConfigStatus.forbiddenKey;
    return SupabaseConfigStatus.invalidKey;
  }

  /// Rol del payload de un JWT, o null si no es un JWT legible.
  static String? _jwtRole(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) return null;
      final role = data['role'];
      return role is String ? role : null;
    } on FormatException {
      return null;
    }
  }
}
