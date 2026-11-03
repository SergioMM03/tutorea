import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

import '../../domain/models/models.dart' show Career, Subject, University;
import 'supabase_bootstrap.dart';

/// Lectura de solo lectura del catálogo remoto (Fase 14.4, diagnóstico).
///
/// Tablas (migraciones 04 y 05):
///   universities (id uuid, slug, name, short_name, country, is_active)
///   careers      (id uuid, university_id uuid, slug, name)
///   subjects     (id uuid, university_id uuid, career_id uuid?, slug, name,
///                 category, academic_year?)
///
/// Las filas se traducen a los modelos actuales sin modificarlos: el id de
/// Flutter es el `slug` (decisión 17) y los uuid se guardan aparte para las
/// fases siguientes. Aquí no hay insert, update ni delete.

/// Filas tal como llegan de PostgREST.
class RemoteCatalogRows {
  final Map<String, dynamic> university;
  final List<Map<String, dynamic>> careers;
  final List<Map<String, dynamic>> subjects;

  const RemoteCatalogRows({
    required this.university,
    required this.careers,
    required this.subjects,
  });
}

/// Origen de las filas. En la app es Supabase; en las pruebas, datos simulados.
abstract class CatalogRowsSource {
  /// Filas de la universidad con ese slug, o null si no existe o no es visible.
  Future<RemoteCatalogRows?> fetch(String universitySlug);
}

/// Universidades visibles (Fase 14.6). RLS: anon y authenticated ven las
/// activas; un usuario también ve la suya aunque se desactive.
abstract class UniversityListSource {
  /// Filas de `universities` activas, ordenadas por nombre.
  Future<List<Map<String, dynamic>>> fetchActiveUniversities();

  /// slug de una universidad a partir de su uuid, o null si no es visible.
  Future<String?> universitySlugById(String universityUuid);
}

/// Consultas reales a Supabase (rol anon: RLS deja leer el catálogo de
/// universidades activas sin iniciar sesión).
class SupabaseCatalogSource implements CatalogRowsSource, UniversityListSource {
  final SupabaseClient _client;
  final Duration timeout;

  SupabaseCatalogSource(this._client, {this.timeout = const Duration(seconds: 10)});

  /// Usa el cliente global solo si [SupabaseBootstrap] confirmó la inicialización.
  factory SupabaseCatalogSource.fromInitializedClient() {
    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase no está inicializado; no se consulta nada.');
    }
    return SupabaseCatalogSource(Supabase.instance.client);
  }

  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async {
    final university = await _client
        .from('universities')
        .select('id, slug, name, short_name, country, is_active')
        .eq('slug', universitySlug)
        .maybeSingle()
        .timeout(timeout);
    if (university == null) return null;

    final universityUuid = university['id'];
    if (universityUuid is! String) {
      throw const CatalogMappingException('universities.id no es texto');
    }

    final careers = await _client
        .from('careers')
        .select('id, university_id, slug, name')
        .eq('university_id', universityUuid)
        .order('slug')
        .timeout(timeout);

    final subjects = await _client
        .from('subjects')
        .select('id, university_id, career_id, slug, name, category, academic_year')
        .eq('university_id', universityUuid)
        .order('slug')
        .timeout(timeout);

    return RemoteCatalogRows(university: university, careers: careers, subjects: subjects);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() => _client
      .from('universities')
      .select('id, slug, name, short_name, country, is_active')
      .eq('is_active', true)
      .order('name')
      .timeout(timeout);

  @override
  Future<String?> universitySlugById(String universityUuid) async {
    final row = await _client
        .from('universities')
        .select('slug')
        .eq('id', universityUuid)
        .maybeSingle()
        .timeout(timeout);
    final slug = row?['slug'];
    return slug is String ? slug : null;
  }
}

/// Una fila no tiene la forma que exige el esquema.
class CatalogMappingException implements Exception {
  final String message;
  const CatalogMappingException(this.message);

  @override
  String toString() => 'CatalogMappingException: $message';
}

/// Catálogo remoto ya traducido a los modelos de Flutter.
class RemoteCatalog {
  final University university;
  final String universityUuid;
  final String shortName; // universities.short_name (no existe en University)
  final List<Career> careers;
  final List<Subject> subjects;

  /// slug → uuid, para traducir ids en fases siguientes.
  final Map<String, String> careerUuidBySlug;
  final Map<String, String> subjectUuidBySlug;

  const RemoteCatalog({
    required this.university,
    required this.universityUuid,
    required this.shortName,
    required this.careers,
    required this.subjects,
    required this.careerUuidBySlug,
    required this.subjectUuidBySlug,
  });
}

/// Traduce filas remotas a University, Career y Subject.
class CatalogMapper {
  CatalogMapper._();

  /// Fila de `universities` → University (id = slug).
  static University university(Map<String, dynamic> u) => University(
        id: _text(u, 'slug', 'universities'),
        nombre: _text(u, 'name', 'universities'),
        pais: _text(u, 'country', 'universities'),
        activo: _bool(u, 'is_active', 'universities'),
      );

  static RemoteCatalog map(RemoteCatalogRows rows) {
    final u = rows.university;
    final universityUuid = _text(u, 'id', 'universities');
    final university = CatalogMapper.university(u);
    final universitySlug = university.id;

    final careerSlugByUuid = <String, String>{};
    final careerUuidBySlug = <String, String>{};
    final careers = <Career>[];
    for (final row in rows.careers) {
      final uuid = _text(row, 'id', 'careers');
      final slug = _text(row, 'slug', 'careers');
      _sameUniversity(row, universityUuid, 'careers', slug);
      careerSlugByUuid[uuid] = slug;
      careerUuidBySlug[slug] = uuid;
      careers.add(Career(
        id: slug,
        universityId: universitySlug,
        nombre: _text(row, 'name', 'careers'),
      ));
    }

    final subjectUuidBySlug = <String, String>{};
    final subjects = <Subject>[];
    for (final row in rows.subjects) {
      final slug = _text(row, 'slug', 'subjects');
      _sameUniversity(row, universityUuid, 'subjects', slug);
      final careerUuid = _optionalText(row, 'career_id', 'subjects');
      String? careerSlug;
      if (careerUuid != null) {
        careerSlug = careerSlugByUuid[careerUuid];
        if (careerSlug == null) {
          throw CatalogMappingException(
              'subjects.$slug apunta a una carrera que no está en la lista');
        }
      }
      subjectUuidBySlug[slug] = _text(row, 'id', 'subjects');
      subjects.add(Subject(
        id: slug,
        nombre: _text(row, 'name', 'subjects'),
        categoria: _text(row, 'category', 'subjects'),
        universityId: universitySlug,
        careerId: careerSlug,
        anioAcademico: _optionalInt(row, 'academic_year', 'subjects'),
      ));
    }

    return RemoteCatalog(
      university: university,
      universityUuid: universityUuid,
      shortName: _text(u, 'short_name', 'universities'),
      careers: careers,
      subjects: subjects,
      careerUuidBySlug: careerUuidBySlug,
      subjectUuidBySlug: subjectUuidBySlug,
    );
  }

  static void _sameUniversity(
      Map<String, dynamic> row, String universityUuid, String table, String slug) {
    if (_text(row, 'university_id', table) != universityUuid) {
      throw CatalogMappingException('$table.$slug pertenece a otra universidad');
    }
  }

  static String _text(Map<String, dynamic> row, String key, String table) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw CatalogMappingException('$table.$key falta o no es texto');
  }

  static String? _optionalText(Map<String, dynamic> row, String key, String table) {
    final value = row[key];
    if (value == null) return null;
    if (value is String && value.trim().isNotEmpty) return value;
    throw CatalogMappingException('$table.$key no es texto');
  }

  static int? _optionalInt(Map<String, dynamic> row, String key, String table) {
    final value = row[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    throw CatalogMappingException('$table.$key no es un entero');
  }

  static bool _bool(Map<String, dynamic> row, String key, String table) {
    final value = row[key];
    if (value is bool) return value;
    throw CatalogMappingException('$table.$key no es booleano');
  }
}

/// Resultado de comparar el catálogo local con el remoto.
class CatalogComparison {
  final int localCareers;
  final int remoteCareers;
  final int localSubjects;
  final int remoteSubjects;
  final List<String> differences;

  const CatalogComparison({
    required this.localCareers,
    required this.remoteCareers,
    required this.localSubjects,
    required this.remoteSubjects,
    required this.differences,
  });

  bool get matches => differences.isEmpty;

  /// Compara por id (= slug) y campo a campo.
  factory CatalogComparison.compare({
    required University localUniversity,
    required List<Career> localCareers,
    required List<Subject> localSubjects,
    required RemoteCatalog remote,
  }) {
    final diffs = <String>[];
    void field(String what, Object? local, Object? remoteValue) {
      if (local != remoteValue) diffs.add('$what: local "$local" ≠ remoto "$remoteValue"');
    }

    final ru = remote.university;
    field('universidad.id', localUniversity.id, ru.id);
    field('universidad.nombre', localUniversity.nombre, ru.nombre);
    field('universidad.pais', localUniversity.pais, ru.pais);
    field('universidad.activo', localUniversity.activo, ru.activo);

    final localC = {for (final c in localCareers) c.id: c};
    final remoteC = {for (final c in remote.careers) c.id: c};
    for (final id in localC.keys.where((k) => !remoteC.containsKey(k))) {
      diffs.add('carrera $id: solo existe en local');
    }
    for (final id in remoteC.keys.where((k) => !localC.containsKey(k))) {
      diffs.add('carrera $id: solo existe en remoto');
    }
    for (final id in localC.keys.where(remoteC.containsKey)) {
      field('carrera $id.nombre', localC[id]!.nombre, remoteC[id]!.nombre);
      field('carrera $id.universityId', localC[id]!.universityId, remoteC[id]!.universityId);
    }

    final localS = {for (final s in localSubjects) s.id: s};
    final remoteS = {for (final s in remote.subjects) s.id: s};
    for (final id in localS.keys.where((k) => !remoteS.containsKey(k))) {
      diffs.add('materia $id: solo existe en local');
    }
    for (final id in remoteS.keys.where((k) => !localS.containsKey(k))) {
      diffs.add('materia $id: solo existe en remoto');
    }
    for (final id in localS.keys.where(remoteS.containsKey)) {
      final l = localS[id]!;
      final r = remoteS[id]!;
      field('materia $id.nombre', l.nombre, r.nombre);
      field('materia $id.categoria', l.categoria, r.categoria);
      field('materia $id.careerId', l.careerId, r.careerId);
      field('materia $id.anioAcademico', l.anioAcademico, r.anioAcademico);
      field('materia $id.universityId', l.universityId, r.universityId);
    }

    return CatalogComparison(
      localCareers: localCareers.length,
      remoteCareers: remote.careers.length,
      localSubjects: localSubjects.length,
      remoteSubjects: remote.subjects.length,
      differences: diffs,
    );
  }
}
