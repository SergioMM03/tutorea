import 'models/models.dart';

/// Reglas de consulta del catálogo que comparten los repositorios locales y
/// los remotos (Fase 14.6), para que ambos modos devuelvan lo mismo.
class CatalogRules {
  CatalogRules._();

  /// Universidades donde ya se puede usar Tutorea, en el orden recibido.
  static List<University> active(Iterable<University> universities) =>
      universities.where((u) => u.activo).toList();

  /// Carreras de una universidad, ordenadas por nombre.
  static List<Career> careersOf(Iterable<Career> careers, String universityId) =>
      careers.where((c) => c.universityId == universityId).toList()
        ..sort((a, b) => a.nombre.compareTo(b.nombre));

  /// Materias filtradas por universidad y por carrera (esa carrera + comunes),
  /// en el orden recibido.
  static List<Subject> filterSubjects(
    Iterable<Subject> subjects, {
    String? universityId,
    String? careerId,
  }) =>
      subjects
          .where((s) => universityId == null || s.universityId == universityId)
          .where((s) => careerId == null || s.esDeCarrera(careerId))
          .toList();

  /// Respeta el orden de [ids] e ignora ids desconocidos.
  static List<Subject> subjectsByIds(Iterable<Subject> subjects, List<String> ids) {
    final byId = {for (final s in subjects) s.id: s};
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }
}
