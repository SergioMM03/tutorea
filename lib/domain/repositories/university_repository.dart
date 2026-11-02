import '../models/models.dart';

/// Universidades y carreras.
abstract class UniversityRepository {
  /// Universidades donde ya se puede usar Tutorea (activo = true).
  Future<List<University>> getActive();

  Future<University?> getById(String id);

  /// Carreras de una universidad, ordenadas por nombre.
  Future<List<Career>> getCareers(String universityId);

  Future<Career?> getCareerById(String id);

  /// Universidad elegida en la pantalla inicial (antes de iniciar sesión).
  /// Es solo contexto del dispositivo: no cambia la universidad de ninguna cuenta.
  Future<String?> getSelectedUniversityId();

  Future<void> saveSelectedUniversityId(String universityId);
}
