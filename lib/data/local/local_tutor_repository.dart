import '../../domain/models/models.dart';
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

    return _profiles().where((p) {
      if (!p.activo || !p.completo) return false;
      if (universityId != null && p.universityId != universityId) return false;
      if (subjectId != null && !p.ensenaMateria(subjectId)) return false;
      if (categoryIds != null && !p.materias.any(categoryIds.contains)) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
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
    if (profile.precioHora < 0) {
      throw const RepositoryException('El precio no puede ser negativo.');
    }
    final profiles = _profiles();
    final other = profiles.where((p) => p.userId == profile.userId && p.id != profile.id);
    if (other.isNotEmpty) {
      throw const RepositoryException('Este usuario ya tiene un perfil de tutor.');
    }
    final index = profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _db.writeList(
        LocalDatabase.tutorProfiles, profiles.map((p) => p.toJson()).toList());
    return profile;
  }
}
