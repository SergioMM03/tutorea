import '../models/models.dart';

/// Perfiles de tutor.
abstract class TutorRepository {
  /// Tutores visibles para estudiantes: activos y con perfil completo.
  /// [universityId], [subjectId], [categoria], [modalidad] y [disponibleEn]
  /// (una sesión de [duracionMinutos] que empieza en esa fecha y hora) filtran
  /// opcionalmente.
  Future<List<TutorProfile>> getAvailable({
    String? universityId,
    String? subjectId,
    String? categoria,
    TutoringModality? modalidad,
    DateTime? disponibleEn,
    int duracionMinutos = 60,
  });

  Future<TutorProfile?> getById(String id);
  Future<TutorProfile?> getByUserId(String userId);

  /// Crea o actualiza el perfil (un perfil por usuario tutor) con sus materias
  /// y su disponibilidad. Lanza RepositoryException si los datos no son válidos
  /// (precio negativo, sin modalidad, horarios inválidos o que se cruzan).
  Future<TutorProfile> save(TutorProfile profile);
}
