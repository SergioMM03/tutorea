import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';

/// Universidad elegida en la pantalla inicial: preferencia del dispositivo,
/// no un dato de negocio (las universidades vienen de Supabase). Usa la misma
/// clave que el modo local para conservar la elección.
///
/// Solo implementa la selección; el catálogo lo da RemoteUniversityRepository.
class DeviceUniversitySelection implements UniversityRepository {
  static const String key = 'tutorea.selectedUniversity';

  @override
  Future<String?> getSelectedUniversityId() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> saveSelectedUniversityId(String universityId) async {
    await (await SharedPreferences.getInstance()).setString(key, universityId);
  }

  static Never _unsupported() =>
      throw UnsupportedError('DeviceUniversitySelection solo guarda la universidad elegida.');

  @override
  Future<List<University>> getActive() => _unsupported();

  @override
  Future<University?> getById(String id) => _unsupported();

  @override
  Future<List<Career>> getCareers(String universityId) => _unsupported();

  @override
  Future<Career?> getCareerById(String id) => _unsupported();
}
