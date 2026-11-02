import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

class LocalSubjectRepository implements SubjectRepository {
  final LocalDatabase _db;

  LocalSubjectRepository(this._db);

  @override
  Future<List<Subject>> getAll({String? universityId, String? careerId}) async =>
      _db
          .readList(LocalDatabase.subjects)
          .map(Subject.fromJson)
          .where((s) => universityId == null || s.universityId == universityId)
          .where((s) => careerId == null || s.esDeCarrera(careerId))
          .toList();

  /// Respeta el orden de [ids] e ignora ids desconocidos.
  @override
  Future<List<Subject>> getByIds(List<String> ids) async {
    final byId = {for (final s in await getAll()) s.id: s};
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }
}
