import '../models/models.dart';

/// Catálogo de materias.
abstract class SubjectRepository {
  /// Materias del catálogo. Filtros opcionales:
  /// [universityId] (solo esa universidad) y [careerId] (esa carrera + comunes).
  Future<List<Subject>> getAll({String? universityId, String? careerId});
  Future<List<Subject>> getByIds(List<String> ids);
}
