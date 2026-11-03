import 'dart:async';

import '../data/local/local_seed.dart';
import '../data/supabase/remote_catalog.dart';
import '../domain/models/models.dart' show University, kDefaultUniversityId;

/// Diagnóstico de la Fase 14.4: lee el catálogo remoto y lo compara con el
/// catálogo local de LocalSeed (no abre ni modifica los datos del dispositivo).
///
/// Solo imprime datos de catálogo (slugs, nombres, cantidades): nada de
/// usuarios, correos ni claves.
class CatalogDiagnostic {
  static const String tag = '[Diagnóstico catálogo]';

  final CatalogRowsSource source;
  final void Function(String line) log;

  CatalogDiagnostic({required this.source, required this.log});

  /// Devuelve true solo si la consulta funcionó y los catálogos coinciden.
  Future<bool> run({String universitySlug = kDefaultUniversityId}) async {
    _log('Consultando universidad "$universitySlug" en Supabase (solo lectura)...');
    RemoteCatalogRows? rows;
    try {
      rows = await source.fetch(universitySlug);
    } on TimeoutException {
      _log('RESULTADO: ERROR — Supabase no respondió a tiempo.');
      return false;
    } catch (error) {
      _log('RESULTADO: ERROR — la consulta falló: $error');
      return false;
    }
    if (rows == null) {
      _log('RESULTADO: ERROR — "$universitySlug" no existe o no está activa en Supabase '
          '(¿se desplegó con --include-seed?).');
      return false;
    }

    RemoteCatalog remote;
    try {
      remote = CatalogMapper.map(rows);
    } on CatalogMappingException catch (error) {
      _log('RESULTADO: ERROR — los datos no tienen la forma esperada: ${error.message}');
      return false;
    }

    _log('Remoto: ${remote.university.nombre} (${remote.shortName}), '
        '${remote.careers.length} carreras, ${remote.subjects.length} materias.');
    _log('Carreras remotas: ${remote.careers.map((c) => c.id).join(', ')}');
    _log('Materias remotas: ${remote.subjects.map((s) => s.id).join(', ')}');

    final localUniversity = LocalSeed.universities.firstWhere(
      (u) => u.id == universitySlug,
      orElse: () => University(id: universitySlug, nombre: '(no existe en local)', pais: ''),
    );
    final comparison = CatalogComparison.compare(
      localUniversity: localUniversity,
      localCareers: LocalSeed.careers.where((c) => c.universityId == universitySlug).toList(),
      localSubjects: LocalSeed.subjects.where((s) => s.universityId == universitySlug).toList(),
      remote: remote,
    );
    _log('Local: ${comparison.localCareers} carreras, ${comparison.localSubjects} materias.');

    if (comparison.matches) {
      _log('RESULTADO: OK — el catálogo remoto coincide con el local '
          '(1 universidad, ${comparison.remoteCareers} carreras, ${comparison.remoteSubjects} materias).');
      return true;
    }
    _log('RESULTADO: DIFERENCIAS (${comparison.differences.length}):');
    for (final d in comparison.differences) {
      _log('  - $d');
    }
    return false;
  }

  void _log(String line) => log('$tag $line');
}
