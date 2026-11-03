import '../../domain/models/models.dart';
import '../../domain/tutor_rules.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

class LocalTutorRepository implements TutorRepository {
  final LocalDatabase _db;

  LocalTutorRepository(this._db);

  List<TutorProfile> _profiles() =>
      _db.readList(LocalDatabase.tutorProfiles).map(TutorProfile.fromJson).toList();

  @override
  Future<List<TutorProfile>> getAvailable({
    String? universityId,
    String? subjectId,
    String? categoria,
    TutoringModality? modalidad,
    DateTime? disponibleEn,
    int duracionMinutos = 60,
  }) async {
    // Ids de las materias de esa categoría (si se filtra por categoría).
    final Set<String>? categoryIds = categoria == null
        ? null
        : _db
            .readList(LocalDatabase.subjects)
            .map(Subject.fromJson)
            .where((s) => s.categoria == categoria)
            .map((s) => s.id)
            .toSet();

    return TutorRules.visible(
      _profiles(),
      universityId: universityId,
      subjectId: subjectId,
      categorySubjectIds: categoryIds,
      modalidad: modalidad,
      disponibleEn: disponibleEn,
      duracionMinutos: duracionMinutos,
    );
  }

  @override
  Future<TutorProfile?> getById(String id) async {
    for (final p in _profiles()) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<TutorProfile?> getByUserId(String userId) async {
    for (final p in _profiles()) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  @override
  Future<TutorProfile> save(TutorProfile profile) async {
    TutorRules.validateForSave(profile);
    final profiles = _profiles();
    final other = profiles.where((p) => p.userId == profile.userId && p.id != profile.id);
    if (other.isNotEmpty) {
      throw const RepositoryException('Este usuario ya tiene un perfil de tutor.');
    }
    final index = profiles.indexWhere((p) => p.id == profile.id);
    // La calificación no la decide quien guarda el perfil: se conserva la
    // calculada a partir de las reseñas (igual que en el servidor). Un perfil
    // nuevo empieza sin reseñas.
    final stored = index >= 0 ? profiles[index] : null;
    final saved = profile.copyWith(
      rating: stored?.rating ?? 0,
      totalResenas: stored?.totalResenas ?? 0,
    );
    if (index >= 0) {
      profiles[index] = saved;
    } else {
      profiles.add(saved);
    }
    await _db.writeList(
        LocalDatabase.tutorProfiles, profiles.map((p) => p.toJson()).toList());
    return saved;
  }
}
