import '../../domain/catalog_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

class LocalSubjectRepository implements SubjectRepository {
  final LocalDatabase _db;

  LocalSubjectRepository(this._db);

  @override
  Future<List<Subject>> getAll({String? universityId, String? careerId}) async =>
      CatalogRules.filterSubjects(
        _db.readList(LocalDatabase.subjects).map(Subject.fromJson),
        universityId: universityId,
        careerId: careerId,
      );

  /// Respeta el orden de [ids] e ignora ids desconocidos.
  @override
  Future<List<Subject>> getByIds(List<String> ids) async =>
      CatalogRules.subjectsByIds(await getAll(), ids);
}
