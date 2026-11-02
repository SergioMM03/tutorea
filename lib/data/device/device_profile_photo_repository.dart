import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/profile_photo_repository.dart';

/// Fotografía de perfil desde la galería del dispositivo.
///
/// image_picker devuelve un archivo TEMPORAL (el sistema puede borrarlo).
/// Por eso se copia a `<documentos de la app>/profile_photos/` y se guarda
/// la ruta de esa copia. Nunca se guarda la imagen en shared_preferences.
class DeviceProfilePhotoRepository implements ProfilePhotoRepository {
  static const String folderName = 'profile_photos';

  final ImagePicker _picker;
  final Future<Directory> Function() _baseDirectory;

  DeviceProfilePhotoRepository({
    ImagePicker? picker,
    Future<Directory> Function()? baseDirectory, // inyectable en pruebas
  })  : _picker = picker ?? ImagePicker(),
        _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  @override
  Future<String?> pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024, // suficiente para un avatar; ahorra espacio
      maxHeight: 1024,
      imageQuality: 85,
    );
    return file?.path;
  }

  @override
  Future<String> saveCopy(String sourcePath, {required String ownerId}) async {
    final base = await _baseDirectory();
    final folder = Directory('${base.path}${Platform.pathSeparator}$folderName');
    if (!await folder.exists()) await folder.create(recursive: true);

    final safeOwner = ownerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    // Nombre nuevo en cada cambio: así una foto reemplazada no queda en caché.
    final name = '${safeOwner}_${DateTime.now().millisecondsSinceEpoch}${_extensionOf(sourcePath)}';
    final copy = await File(sourcePath).copy('${folder.path}${Platform.pathSeparator}$name');
    return copy.path;
  }

  @override
  Future<void> delete(String path) async {
    // Solo borra fotos que la app guardó en su carpeta.
    if (!path.contains(folderName)) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '.jpg';
    return name.substring(dot).toLowerCase();
  }
}
