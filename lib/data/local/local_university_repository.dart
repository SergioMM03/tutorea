import '../../domain/catalog_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

class LocalUniversityRepository implements UniversityRepository {
  final LocalDatabase _db;

  LocalUniversityRepository(this._db);

  List<University> _all() =>
      _db.readList(LocalDatabase.universities).map(University.fromJson).toList();

  List<Career> _careers() =>
      _db.readList(LocalDatabase.careers).map(Career.fromJson).toList();

  @override
  Future<List<University>> getActive() async => CatalogRules.active(_all());

  @override
  Future<University?> getById(String id) async {
    for (final u in _all()) {
      if (u.id == id) return u;
    }
    return null;
  }

  @override
  Future<List<Career>> getCareers(String universityId) async =>
      CatalogRules.careersOf(_careers(), universityId);

  @override
  Future<String?> getSelectedUniversityId() async =>
      _db.readString(LocalDatabase.selectedUniversity);

  @override
  Future<void> saveSelectedUniversityId(String universityId) =>
      _db.writeString(LocalDatabase.selectedUniversity, universityId);

  @override
  Future<Career?> getCareerById(String id) async {
    for (final c in _careers()) {
      if (c.id == id) return c;
    }
    return null;
  }
}
