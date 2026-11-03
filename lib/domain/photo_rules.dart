/// Reglas de las fotografías de tutor (Fase 14.10). Las mismas que aplica el
/// servidor (bucket `tutor-photos`, migración 24): JPEG, PNG o WebP de hasta 2 MB.
class PhotoRules {
  PhotoRules._();

  static const int maxBytes = 2 * 1024 * 1024;
  static const Set<String> extensions = {'jpg', 'jpeg', 'png', 'webp'};

  static const String tooLargeMessage = 'La fotografía pesa más de 2 MB. Elige una más liviana.';
  static const String invalidTypeMessage = 'La fotografía debe ser JPEG, PNG o WebP.';

  /// Extensión en minúsculas (sin punto), o '' si no tiene.
  static String extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 || dot == name.length - 1 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Tipo MIME para subir el archivo, o null si no está permitido.
  static String? mimeOf(String path) => switch (extensionOf(path)) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };

  /// Primer problema del archivo, o null si se puede subir.
  static String? problem(String path, int bytes) {
    if (mimeOf(path) == null) return invalidTypeMessage;
    if (bytes <= 0 || bytes > maxBytes) return tooLargeMessage;
    return null;
  }

  static final RegExp _storagePath = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
      r'[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$');

  /// ¿Es la ruta de un objeto de Storage (<universidad>/<perfil>/<archivo>)?
  /// Si no, es un archivo del dispositivo (vista previa o modo de desarrollo).
  static bool isStoragePath(String? path) => path != null && _storagePath.hasMatch(path);
}
