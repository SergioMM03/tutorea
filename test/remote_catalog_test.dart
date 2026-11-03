import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/supabase/remote_catalog.dart';
import 'package:tutorea/data/supabase/supabase_bootstrap.dart';
import 'package:tutorea/diagnostics/catalog_diagnostic.dart';

/// Todo con datos simulados: ninguna prueba usa la red.

const _uniUuid = '11111111-1111-1111-1111-111111111111';
String _careerUuid(String slug) => 'c-$slug';
String _subjectUuid(String slug) => 's-$slug';

/// Filas como las devolvería PostgREST para el seed de ESEN (supabase/seed.sql),
/// construidas desde LocalSeed para que ambas fuentes partan de los mismos datos.
RemoteCatalogRows _seedRows() => RemoteCatalogRows(
      university: {
        'id': _uniUuid,
        'slug': 'esen',
        'name': 'Escuela Superior de Economía y Negocios (ESEN)',
        'short_name': 'ESEN',
        'country': 'El Salvador',
        'is_active': true,
      },
      careers: [
        for (final c in LocalSeed.careers)
          {'id': _careerUuid(c.id), 'university_id': _uniUuid, 'slug': c.id, 'name': c.nombre},
      ],
      subjects: [
        for (final s in LocalSeed.subjects)
          {
            'id': _subjectUuid(s.id),
            'university_id': _uniUuid,
            'career_id': s.careerId == null ? null : _careerUuid(s.careerId!),
            'slug': s.id,
            'name': s.nombre,
            'category': s.categoria,
            'academic_year': s.anioAcademico,
          },
      ],
    );

CatalogComparison _compare(RemoteCatalog remote) => CatalogComparison.compare(
      localUniversity: LocalSeed.universities.single,
      localCareers: LocalSeed.careers,
      localSubjects: LocalSeed.subjects,
      remote: remote,
    );

class _FakeSource implements CatalogRowsSource {
  final Future<RemoteCatalogRows?> Function() onFetch;
  String? askedSlug;
  _FakeSource(this.onFetch);

  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) {
    askedSlug = universitySlug;
    return onFetch();
  }
}

void main() {
  group('CatalogMapper', () {
    test('traduce uuid a los ids de Flutter (slug)', () {
      final remote = CatalogMapper.map(_seedRows());

      expect(remote.university.id, 'esen');
      expect(remote.university.activo, isTrue);
      expect(remote.universityUuid, _uniUuid);
      expect(remote.shortName, 'ESEN');
      expect(remote.careers.map((c) => c.id),
          ['esen-eyn', 'esen-ing-negocios', 'esen-juridicas', 'esen-software']);
      expect(remote.careers.every((c) => c.universityId == 'esen'), isTrue);
      expect(remote.subjects, hasLength(13));

      final bdd = remote.subjects.singleWhere((s) => s.id == 'bdd');
      expect(bdd.careerId, LocalSeed.software);
      expect(bdd.universityId, 'esen');
      expect(bdd.anioAcademico, 2);
      expect(remote.subjects.singleWhere((s) => s.id == 'mat').careerId, isNull);

      expect(remote.careerUuidBySlug['esen-software'], 'c-esen-software');
      expect(remote.subjectUuidBySlug['bdd'], 's-bdd');
    });

    test('acepta academic_year nulo y numérico entero', () {
      final rows = _seedRows();
      rows.subjects[0]['academic_year'] = null;
      rows.subjects[1]['academic_year'] = 2.0;
      final remote = CatalogMapper.map(rows);
      expect(remote.subjects[0].anioAcademico, isNull);
      expect(remote.subjects[1].anioAcademico, 2);
    });

    test('rechaza una materia con una carrera desconocida', () {
      final rows = _seedRows();
      rows.subjects.last['career_id'] = 'c-no-existe';
      expect(() => CatalogMapper.map(rows), throwsA(isA<CatalogMappingException>()));
    });

    test('rechaza filas de otra universidad', () {
      final rows = _seedRows();
      rows.careers.first['university_id'] = 'otra';
      expect(() => CatalogMapper.map(rows), throwsA(isA<CatalogMappingException>()));
    });

    test('rechaza campos faltantes o con tipo incorrecto', () {
      final sinNombre = _seedRows()..subjects.first.remove('name');
      final activoTexto = _seedRows()..university['is_active'] = 'true';
      final anioTexto = _seedRows()..subjects.first['academic_year'] = 'uno';
      final anioDecimal = _seedRows()..subjects.first['academic_year'] = 1.5;
      for (final rows in [sinNombre, activoTexto, anioTexto, anioDecimal]) {
        expect(() => CatalogMapper.map(rows), throwsA(isA<CatalogMappingException>()));
      }
    });
  });

  group('CatalogComparison', () {
    test('el seed remoto coincide con LocalSeed', () {
      final comparison = _compare(CatalogMapper.map(_seedRows()));
      expect(comparison.differences, isEmpty);
      expect(comparison.matches, isTrue);
      expect(comparison.remoteCareers, 4);
      expect(comparison.remoteSubjects, 13);
    });

    test('detecta faltantes, sobrantes y campos distintos', () {
      final rows = _seedRows();
      rows.subjects.removeWhere((s) => s['slug'] == 'alg');
      rows.subjects.add({
        'id': 's-nueva', 'university_id': _uniUuid, 'career_id': null,
        'slug': 'nueva', 'name': 'Nueva', 'category': 'Otra', 'academic_year': 1,
      });
      rows.careers.firstWhere((c) => c['slug'] == 'esen-eyn')['name'] = 'Economía';
      rows.subjects.firstWhere((s) => s['slug'] == 'bdd')['academic_year'] = 3;

      final comparison = _compare(CatalogMapper.map(rows));
      expect(comparison.matches, isFalse);
      expect(comparison.differences, containsAll([
        'materia alg: solo existe en local',
        'materia nueva: solo existe en remoto',
        'carrera esen-eyn.nombre: local "Licenciatura en Economía y Negocios" ≠ remoto "Economía"',
        'materia bdd.anioAcademico: local "2" ≠ remoto "3"',
      ]));
    });
  });

  group('CatalogDiagnostic', () {
    Future<(bool, List<String>)> run(_FakeSource source) async {
      final lines = <String>[];
      final ok = await CatalogDiagnostic(source: source, log: lines.add).run();
      return (ok, lines);
    }

    test('consulta exitosa: imprime cantidades y RESULTADO: OK', () async {
      final source = _FakeSource(() async => _seedRows());
      final (ok, lines) = await run(source);
      expect(ok, isTrue);
      expect(source.askedSlug, 'esen');
      expect(lines.every((l) => l.startsWith(CatalogDiagnostic.tag)), isTrue);
      expect(lines.last, contains('RESULTADO: OK'));
      expect(lines.last, contains('4 carreras, 13 materias'));
    });

    test('universidad inexistente', () async {
      final (ok, lines) = await run(_FakeSource(() async => null));
      expect(ok, isFalse);
      expect(lines.last, contains('RESULTADO: ERROR'));
    });

    test('error de red o tiempo agotado no lanza', () async {
      final (failOk, failLines) = await run(_FakeSource(() async => throw Exception('sin red')));
      expect(failOk, isFalse);
      expect(failLines.last, contains('RESULTADO: ERROR'));

      final (timeOk, timeLines) = await run(_FakeSource(() async => throw TimeoutException('lento')));
      expect(timeOk, isFalse);
      expect(timeLines.last, contains('no respondió a tiempo'));
    });

    test('datos con forma inesperada', () async {
      final (ok, lines) = await run(_FakeSource(() async => _seedRows()..university.remove('slug')));
      expect(ok, isFalse);
      expect(lines.last, contains('forma esperada'));
    });

    test('catálogos distintos: RESULTADO: DIFERENCIAS', () async {
      final rows = _seedRows()..subjects.removeLast();
      final (ok, lines) = await run(_FakeSource(() async => rows));
      expect(ok, isFalse);
      expect(lines.any((l) => l.contains('RESULTADO: DIFERENCIAS (1)')), isTrue);
    });
  });

  test('sin Supabase inicializado no se crea el cliente remoto', () {
    SupabaseBootstrap.resetForTesting();
    expect(SupabaseCatalogSource.fromInitializedClient, throwsStateError);
  });
}
