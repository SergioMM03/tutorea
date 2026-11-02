import '../models/models.dart';

/// Perfiles de tutor.
abstract class TutorRepository {
  /// Tutores visibles para estudiantes: activos y con perfil completo.
  /// [universityId], [subjectId] o [categoria] filtran opcionalmente.
  Future<List<TutorProfile>> getAvailable({
    String? universityId,
    String? subjectId,
    String? categoria,
  });

  Future<TutorProfile?> getById(String id);
  Future<TutorProfile?> getByUserId(String userId);

  /// Crea o actualiza el perfil (un perfil por usuario tutor).
  Future<TutorProfile> save(TutorProfile profile);
}
