import '../models/models.dart';

/// URLs para mostrar fotografías guardadas en Storage (archivos privados:
/// URLs firmadas que vencen).
abstract class PhotoUrlResolver {
  /// URL ya obtenida y vigente, o null.
  String? cachedUrl(String path);

  /// Obtiene (o reutiliza) una URL firmada. null si no se puede.
  Future<String?> signedUrl(String path);
}

/// Fotografías de tutores en Supabase Storage (Fase 14.10, migración 24).
/// El servidor exige que la cuenta con sesión sea la dueña del perfil.
abstract class TutorPhotoStorage implements PhotoUrlResolver {
  /// Problema del archivo local (tipo o tamaño), o null si se puede subir.
  Future<String?> validate(String localPath);

  /// Sube el archivo local [localPath] a la carpeta del perfil, lo fija como su
  /// fotografía y borra la anterior. Devuelve la ruta nueva.
  Future<String> upload(TutorProfile profile, String localPath);

  /// Quita la fotografía del perfil y borra el archivo.
  Future<void> remove(TutorProfile profile);
}
