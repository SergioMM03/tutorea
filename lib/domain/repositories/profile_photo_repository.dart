/// Fotografías de perfil guardadas en el dispositivo.
/// Hoy: DeviceProfilePhotoRepository (galería + carpeta de la app).
/// Con backend se reemplazaría por una implementación que suba la imagen.
abstract class ProfilePhotoRepository {
  /// Abre la galería. Devuelve la ruta TEMPORAL de la imagen elegida,
  /// o null si el usuario canceló.
  Future<String?> pickFromGallery();

  /// Copia la imagen a la carpeta permanente de la app y devuelve la ruta
  /// de la copia (es la que se guarda en TutorProfile.photoPath).
  Future<String> saveCopy(String sourcePath, {required String ownerId});

  /// Borra una fotografía guardada por la app. No falla si ya no existe.
  Future<void> delete(String path);
}
