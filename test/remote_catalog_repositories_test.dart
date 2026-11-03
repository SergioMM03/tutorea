import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/supabase/remote_catalog.dart';
import 'package:tutorea/data/supabase/remote_catalog_repositories.dart';
import 'package:tutorea/domain/catalog_rules.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';

// Datos simulados: ninguna prueba usa la red.

const _esenUuid = '11111111-1111-4111-8111-111111111111';
const _otraUuid = '22222222-2222-4222-8222-222222222222';

Map<String, dynamic> _universityRow(String uuid, String slug, String name, {bool active = true}) => {
      'id': uuid,
      'slug': slug,
      'name': name,
      'short_name': slug.toUpperCase(),
      'country': 'El Salvador',
      'is_active': active,
    };

/// ESEN con el contenido del seed (filas en orden de slug, como las pide la
/// consulta real) y una segunda universidad con una carrera y una materia.
class _FakeSource implements CatalogRowsSource, UniversityListSource {
  final Map<String, int> fetchesBySlug = {};
  int listFetches = 0;
  Object? error;
  bool hang = false;

  RemoteCatalogRows _esen() {
    final subjects = [...LocalSeed.subjects]..sort((a, b) => a.id.compareTo(b.id));
    return RemoteCatalogRows(
      university: _universityRow(_esenUuid, 'esen', 'Escuela Superior de Economía y Negocios (ESEN)'),
      careers: [
        for (final c in LocalSeed.careers)
          {'id': 'c-${c.id}', 'university_id': _esenUuid, 'slug': c.id, 'name': c.nombre},
      ],
      subjects: [
        for (final s in subjects)
          {
            'id': 's-${s.id}',
            'university_id': _esenUuid,
            'career_id': s.careerId == null ? null : 'c-${s.careerId}',
            'slug': s.id,
            'name': s.nombre,
            'category': s.categoria,
            'academic_year': s.anioAcademico,
          },
      ],
    );
  }

  RemoteCatalogRows _otra() => RemoteCatalogRows(
        university: _universityRow(_otraUuid, 'otra-u', 'Otra Universidad'),
        careers: [
          {'id': 'c-otra-der', 'university_id': _otraUuid, 'slug': 'otra-der', 'name': 'Derecho'},
        ],
        subjects: [
          {
            'id': 's-otra-civ', 'university_id': _otraUuid, 'career_id': 'c-otra-der',
            'slug': 'civ', 'name': 'Civil', 'category': 'Derecho', 'academic_year': 1,
          },
        ],
      );

  Future<void> _check() async {
    if (hang) await Completer<void>().future;
    if (error != null) throw error!;
  }

  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async {
    await _check();
    fetchesBySlug.update(universitySlug, (n) => n + 1, ifAbsent: () => 1);
    return switch (universitySlug) {
      'esen' => _esen(),
      'otra-u' => _otra(),
      _ => null,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() async {
    await _check();
    listFetches++;
    return [
      _universityRow(_esenUuid, 'esen', 'Escuela Superior de Economía y Negocios (ESEN)'),
      _universityRow(_otraUuid, 'otra-u', 'Otra Universidad'),
    ];
  }

  @override
  Future<String?> universitySlugById(String universityUuid) async {
    await _check();
    return {_esenUuid: 'esen', _otraUuid: 'otra-u'}[universityUuid];
  }
}

/// La universidad elegida sigue siendo del dispositivo.
class _DeviceSelection implements UniversityRepository {
  String? selected;
  @override
  Future<String?> getSelectedUniversityId() async => selected;
  @override
  Future<void> saveSelectedUniversityId(String universityId) async => selected = universityId;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('no debe usarse');
}

void main() {
  late _FakeSource source;
  late RemoteCatalogCache cache;
  late RemoteUniversityRepository universities;
  late RemoteSubjectRepository subjects;
  late _DeviceSelection device;

  setUp(() {
    source = _FakeSource();
    cache = RemoteCatalogCache(catalog: source, universities: source, timeout: const Duration(seconds: 1));
    device = _DeviceSelection();
    universities = RemoteUniversityRepository(cache, deviceSelection: device);
    subjects = RemoteSubjectRepository(cache);
  });

  group('universidades y carreras', () {
    test('universidades activas con id = slug', () async {
      final active = await universities.getActive();
      expect(active.map((u) => u.id), ['esen', 'otra-u']);
      expect(active.first.nombre, 'Escuela Superior de Economía y Negocios (ESEN)');
      expect(active.every((u) => u.activo), isTrue);
    });

    test('getById', () async {
      expect((await universities.getById('esen'))?.pais, 'El Salvador');
      expect(await universities.getById('no-existe'), isNull);
    });

    test('carreras de una universidad, ordenadas por nombre como en local', () async {
      final careers = await universities.getCareers('esen');
      expect(careers.map((c) => c.id), [
        LocalSeed.ingNegocios, // Ingeniería de Negocios
        LocalSeed.software, // Ingeniería de Software y Negocios Digitales
        LocalSeed.juridicas, // Licenciatura en Ciencias Jurídicas
        LocalSeed.eyn, // Licenciatura en Economía y Negocios
      ]);
      expect(careers.every((c) => c.universityId == 'esen'), isTrue);
      expect(await universities.getCareers('no-existe'), isEmpty);
    });

    test('mismo resultado que las reglas locales', () async {
      expect((await universities.getCareers('esen')).map((c) => c.id),
          CatalogRules.careersOf(LocalSeed.careers, 'esen').map((c) => c.id));
    });

    test('getCareerById busca en todas las universidades activas', () async {
      expect((await universities.getCareerById('otra-der'))?.universityId, 'otra-u');
      expect((await universities.getCareerById(LocalSeed.eyn))?.universityId, 'esen');
      expect(await universities.getCareerById('no-existe'), isNull);
    });

    test('la universidad elegida se guarda en el dispositivo', () async {
      await universities.saveSelectedUniversityId('esen');
      expect(device.selected, 'esen');
      expect(await universities.getSelectedUniversityId(), 'esen');
      expect(source.listFetches, 0); // no consulta Supabase para esto
    });

    test('cada universidad se consulta una sola vez', () async {
      await universities.getActive();
      await universities.getActive();
      await universities.getCareers('esen');
      await subjects.getAll(universityId: 'esen');
      await universities.getCareerById(LocalSeed.eyn);
      expect(source.listFetches, 1);
      expect(source.fetchesBySlug['esen'], 1);
    });
  });

  group('materias', () {
    test('de una universidad, en el mismo orden que el repositorio local', () async {
      final remote = await subjects.getAll(universityId: 'esen');
      expect(remote.map((s) => s.id), LocalSeed.subjects.map((s) => s.id));
      final categories = remote.map((s) => s.categoria).toSet().toList();
      expect(categories, ['Matemáticas', 'Economía', 'Negocios', 'Tecnología']);
    });

    test('filtro por carrera: esa carrera más las comunes', () async {
      final remote = await subjects.getAll(universityId: 'esen', careerId: LocalSeed.software);
      final local = CatalogRules.filterSubjects(LocalSeed.subjects,
          universityId: 'esen', careerId: LocalSeed.software);
      expect(remote.map((s) => s.id), local.map((s) => s.id));
      expect(remote.every((s) => s.careerId == null || s.careerId == LocalSeed.software), isTrue);
    });

    test('mapeo uuid → slug de universidad y carrera', () async {
      final bdd = (await subjects.getByIds(['bdd'])).single;
      expect(bdd.universityId, 'esen');
      expect(bdd.careerId, LocalSeed.software);
      expect(bdd.anioAcademico, 2);
      final catalog = await cache.bySlug('esen');
      expect(catalog!.subjectUuidBySlug['bdd'], 's-bdd');
      expect(catalog.careerUuidBySlug[LocalSeed.software], 'c-${LocalSeed.software}');
      expect((await cache.byUuid(_esenUuid))?.university.id, 'esen');
    });

    test('sin universidad: todas las activas; getByIds respeta el orden e ignora desconocidos', () async {
      final all = await subjects.getAll();
      expect(all.map((s) => s.id), [...LocalSeed.subjects.map((s) => s.id), 'civ']);
      final some = await subjects.getByIds(['bdd', 'no-existe', 'mat', 'civ']);
      expect(some.map((s) => s.id), ['bdd', 'mat', 'civ']);
    });

    test('materias nuevas (no están en LocalSeed) van al final por nombre', () {
      final ordered = RemoteSubjectRepository.orderLikeLocal([
        const Subject(id: 'zzz', nombre: 'Zoología', categoria: 'X'),
        const Subject(id: 'aaa', nombre: 'Arte', categoria: 'X'),
        LocalSeed.subjects[1],
        LocalSeed.subjects[0],
      ]);
      expect(ordered.map((s) => s.id), [LocalSeed.subjects[0].id, LocalSeed.subjects[1].id, 'aaa', 'zzz']);
    });

    test('universidad inexistente: lista vacía', () async {
      expect(await subjects.getAll(universityId: 'no-existe'), isEmpty);
    });
  });

  group('errores', () {
    test('sin conexión: RepositoryException con mensaje claro', () async {
      source.error = Exception('SocketException: Failed host lookup');
      await expectLater(universities.getActive(),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', catalogConnectionMessage)));
      await expectLater(subjects.getAll(universityId: 'esen'), throwsA(isA<RepositoryException>()));
    });

    test('tiempo agotado', () async {
      source.hang = true;
      cache = RemoteCatalogCache(catalog: source, universities: source, timeout: const Duration(milliseconds: 50));
      await expectLater(RemoteUniversityRepository(cache, deviceSelection: device).getActive(),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', catalogTimeoutMessage)));
    });

    test('datos con forma inesperada', () async {
      final broken = _BrokenSource();
      cache = RemoteCatalogCache(catalog: broken, universities: broken);
      await expectLater(RemoteUniversityRepository(cache, deviceSelection: device).getActive(),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', catalogFormatMessage)));
    });

    test('tras un error se puede reintentar', () async {
      source.error = Exception('sin red');
      await expectLater(universities.getActive(), throwsA(isA<RepositoryException>()));
      source.error = null;
      expect(await universities.getActive(), hasLength(2));
    });
  });
}

class _BrokenSource implements CatalogRowsSource, UniversityListSource {
  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async => null;
  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() async => [
        {'id': 'x', 'slug': 'x', 'name': 'X', 'country': 'SV', 'is_active': 'sí'},
      ];
  @override
  Future<String?> universitySlugById(String universityUuid) async => null;
}
