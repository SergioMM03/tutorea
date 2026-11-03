import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/supabase/remote_catalog.dart';
import 'package:tutorea/data/supabase/remote_catalog_repositories.dart';
import 'package:tutorea/data/supabase/remote_tutor_repository.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/domain/tutor_rules.dart';
import 'package:tutorea/state/tutor_store.dart';

// Datos simulados: ninguna prueba usa la red. _FakeServer imita lo que hacen la
// RLS, los triggers y las restricciones de las migraciones 12 a 16 (16: cualquier
// cuenta estudiante o tutor puede tener perfil de tutor; una administradora no).

const _esen = '11111111-1111-4111-8111-111111111111';
const _otra = '22222222-2222-4222-8222-222222222222';
const _tutor1 = '00000000-0000-4000-8000-000000000001';
const _tutor2 = '00000000-0000-4000-8000-000000000002';
const _student = '00000000-0000-4000-8000-000000000003';
const _tutorOtra = '00000000-0000-4000-8000-000000000004';
const _admin = '00000000-0000-4000-8000-000000000005';

String _subjectUuid(String slug) => 's-$slug';

class _FakeCatalog implements CatalogRowsSource, UniversityListSource {
  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async {
    if (universitySlug == 'otra-u') {
      return RemoteCatalogRows(
        university: _uni(_otra, 'otra-u'),
        careers: const [],
        subjects: [
          {'id': 's-civ', 'university_id': _otra, 'career_id': null, 'slug': 'civ',
           'name': 'Civil', 'category': 'Derecho', 'academic_year': 1},
        ],
      );
    }
    if (universitySlug != 'esen') return null;
    return RemoteCatalogRows(
      university: _uni(_esen, 'esen'),
      careers: [
        for (final c in LocalSeed.careers)
          {'id': 'c-${c.id}', 'university_id': _esen, 'slug': c.id, 'name': c.nombre},
      ],
      subjects: [
        for (final s in LocalSeed.subjects)
          {
            'id': _subjectUuid(s.id),
            'university_id': _esen,
            'career_id': s.careerId == null ? null : 'c-${s.careerId}',
            'slug': s.id,
            'name': s.nombre,
            'category': s.categoria,
            'academic_year': s.anioAcademico,
          },
      ],
    );
  }

  static Map<String, dynamic> _uni(String id, String slug) =>
      {'id': id, 'slug': slug, 'name': slug, 'short_name': slug, 'country': 'SV', 'is_active': true};

  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() async => [_uni(_esen, 'esen'), _uni(_otra, 'otra-u')];

  @override
  Future<String?> universitySlugById(String universityUuid) async =>
      {_esen: 'esen', _otra: 'otra-u'}[universityUuid];
}

class _FakeServer implements TutorRowsSource {
  /// Cuentas: id → (universidad, rol).
  final Map<String, (String, String)> accounts = {
    _tutor1: (_esen, 'tutor'),
    _tutor2: (_esen, 'tutor'),
    _student: (_esen, 'estudiante'),
    _tutorOtra: (_otra, 'tutor'),
    _admin: (_esen, 'administrador'),
  };
  final Map<String, Map<String, dynamic>> profiles = {}; // id → fila
  String? sessionUser = _tutor1;
  Object? error;
  bool hang = false;
  Map<String, Object>? lastSave;
  int _next = 1;

  PostgrestException _pg(String code) => PostgrestException(message: 'error $code', code: code);

  bool _visible(Map<String, dynamic> row) {
    final me = sessionUser;
    if (me == null) return false;
    return row['university_id'] == accounts[me]!.$1 && (row['is_active'] == true || row['user_id'] == me);
  }

  Future<void> _check() async {
    if (hang) await Completer<void>().future;
    if (error != null) throw error!;
  }

  Map<String, dynamic> _copy(Map<String, dynamic> row) => {
        ...row,
        'tutor_subjects': [for (final s in row['tutor_subjects'] as List) Map.of(s as Map)],
        'availability_slots': [for (final s in row['availability_slots'] as List) Map.of(s as Map)],
      };

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles({String? universityUuid}) async {
    await _check();
    return [
      for (final row in profiles.values)
        if (_visible(row) && (universityUuid == null || row['university_id'] == universityUuid)) _copy(row),
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileById(String id) async {
    await _check();
    final row = profiles[id];
    return row != null && _visible(row) ? _copy(row) : null;
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileByUserId(String userId) async {
    await _check();
    for (final row in profiles.values) {
      if (row['user_id'] == userId && _visible(row)) return _copy(row);
    }
    return null;
  }

  @override
  Future<String> saveOwnProfile({
    required String description,
    required double hourlyRate,
    required bool offersInPerson,
    required bool offersVirtual,
    required bool isActive,
    required List<String> subjectUuids,
    required List<Map<String, int>> slots,
  }) async {
    await _check();
    lastSave = {'subjects': subjectUuids, 'slots': slots};
    final me = sessionUser;
    // prepare_tutor_profile (migración 16): con sesión y sin rol administrador.
    if (me == null || accounts[me]!.$2 == 'administrador') throw _pg('42501');
    if (hourlyRate < 0 || (!offersInPerson && !offersVirtual)) throw _pg('23514');
    final university = accounts[me]!.$1;
    final prefix = university == _esen ? 's-' : 's-civ';
    for (final s in subjectUuids) {
      final valid = university == _esen ? s.startsWith(prefix) && s != 's-civ' : s == 's-civ';
      if (!valid) throw _pg('23503'); // FK compuesta: materia de otra universidad
    }
    for (var i = 0; i < slots.length; i++) {
      for (var j = i + 1; j < slots.length; j++) {
        final a = slots[i], b = slots[j];
        if (a['weekday'] == b['weekday'] &&
            a['start_minute']! < b['end_minute']! &&
            b['start_minute']! < a['end_minute']!) {
          throw _pg('23P01'); // exclusión gist
        }
      }
    }
    final existing = profiles.values.where((r) => r['user_id'] == me).firstOrNull;
    final id = existing?['id'] as String? ?? '00000000-0000-4000-9000-${(_next++).toString().padLeft(12, '0')}';
    profiles[id] = {
      'id': id,
      'user_id': me, // del servidor (auth.uid()), no del cliente
      'university_id': university, // de su perfil, no del cliente
      'description': description,
      'hourly_rate': hourlyRate,
      'offers_in_person': offersInPerson,
      'offers_virtual': offersVirtual,
      'is_active': isActive,
      'rating_avg': existing?['rating_avg'],
      'rating_count': existing?['rating_count'] ?? 0,
      'tutor_subjects': [for (final s in subjectUuids.toSet()) {'subject_id': s}],
      'availability_slots': [for (final s in slots) {...s}],
    };
    return id;
  }
}

class _Users implements AuthRepository {
  @override
  Future<AppUser?> getUserById(String id) async => AppUser(
        id: id, nombre: 'Tutor $id', correo: '', password: '', carrera: 'x',
        anioAcademico: 3, rol: UserRole.tutor, fechaCreacion: DateTime(2026));
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

TutorProfile _draft({
  String id = 'tp-local-id-que-se-ignora',
  String userId = 'otro-usuario-que-se-ignora',
  String universityId = 'esen',
  List<String> materias = const ['est', 'mat'],
  List<AvailabilitySlot> slots = const [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 720)],
  double precio = 10,
  bool presencial = true,
  bool virtual = false,
  bool activo = true,
}) =>
    TutorProfile(
      id: id,
      userId: userId,
      universityId: universityId,
      descripcion: '  Clases de estadística ',
      precioHora: precio,
      materias: materias,
      disponibilidad: slots,
      activo: activo,
      ofrecePresencial: presencial,
      ofreceVirtual: virtual,
      photoPath: '/data/foto-local.jpg',
    );

void main() {
  late _FakeServer server;
  late RemoteCatalogCache cache;
  late RemoteTutorRepository repo;

  RemoteTutorRepository build({Duration timeout = const Duration(seconds: 2)}) =>
      RemoteTutorRepository(server, cache, timeout: timeout);

  setUp(() {
    server = _FakeServer();
    cache = RemoteCatalogCache(catalog: _FakeCatalog(), universities: _FakeCatalog());
    repo = build();
  });

  group('crear y actualizar perfil', () {
    test('crea el perfil del usuario con sesión; el servidor fija dueño y universidad', () async {
      final saved = await repo.save(_draft());
      expect(saved.id, isNot('tp-local-id-que-se-ignora'));
      expect(saved.userId, _tutor1);
      expect(saved.universityId, 'esen');
      expect(saved.descripcion, 'Clases de estadística');
      expect(saved.materias.toSet(), {'est', 'mat'});
      expect(server.lastSave!['subjects'], containsAll(['s-est', 's-mat']));
      expect(saved.ofrecePresencial, isTrue);
      expect(saved.ofreceVirtual, isFalse);
      expect(saved.rating, 0); // sin reseñas
      expect(saved.photoPath, isNull); // la foto aún no se sube
    });

    test('actualiza el mismo perfil (uno por tutor)', () async {
      final first = await repo.save(_draft());
      final second = await repo.save(first.copyWith(
        descripcion: 'Nueva', precioHora: 12.5, materias: ['bdd'], activo: false, ofreceVirtual: true,
        disponibilidad: const [AvailabilitySlot(diaSemana: 3, horaInicio: 840, horaFin: 960)]));
      expect(second.id, first.id);
      expect(server.profiles, hasLength(1));
      expect(second.precioHora, 12.5);
      expect(second.materias, ['bdd']);
      expect(second.activo, isFalse);
      expect(second.ofreceVirtual, isTrue);
      expect(second.disponibilidad.single.diaSemana, 3);
    });

    test('consultar: por usuario y por id', () async {
      final saved = await repo.save(_draft());
      expect((await repo.getByUserId(_tutor1))?.id, saved.id);
      expect((await repo.getById(saved.id))?.userId, _tutor1);
      expect(await repo.getByUserId(_tutor2), isNull);
      expect(await repo.getById('tp-valeria'), isNull); // ids locales no existen en Supabase
    });
  });

  group('materias y horarios', () {
    test('horarios ordenados y materias traducidas a slug', () async {
      final saved = await repo.save(_draft(slots: const [
        AvailabilitySlot(diaSemana: 5, horaInicio: 600, horaFin: 660),
        AvailabilitySlot(diaSemana: 1, horaInicio: 900, horaFin: 960),
        AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 540),
      ]));
      expect(saved.disponibilidad.map((s) => (s.diaSemana, s.horaInicio)), [(1, 480), (1, 900), (5, 600)]);
      // equals: dos Map con el mismo contenido no son == en Dart.
      expect(server.lastSave!['slots'], contains(equals({'weekday': 5, 'start_minute': 600, 'end_minute': 660})));
    });

    test('horarios que se cruzan: se rechazan antes de llamar al servidor', () async {
      await expectLater(
        repo.save(_draft(slots: const [
          AvailabilitySlot(diaSemana: 2, horaInicio: 480, horaFin: 600),
          AvailabilitySlot(diaSemana: 2, horaInicio: 540, horaFin: 660),
        ])),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('se cruzan'))),
      );
      expect(server.lastSave, isNull);
    });

    test('sin modalidad o precio negativo: se rechaza', () async {
      await expectLater(repo.save(_draft(presencial: false, virtual: false)), throwsA(isA<RepositoryException>()));
      await expectLater(repo.save(_draft(precio: -1)), throwsA(isA<RepositoryException>()));
      expect(server.lastSave, isNull);
    });

    test('materia que no es de su universidad', () async {
      await expectLater(repo.save(_draft(materias: ['no-existe'])),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', foreignSubjectMessage)));
    });

    test('la base es la autoridad: restricciones de PostgreSQL traducidas', () {
      expect(describeTutorError(const PostgrestException(message: 'x', code: '23P01')).message, overlapMessage);
      expect(describeTutorError(const PostgrestException(message: 'x', code: '23514')).message, invalidDataMessage);
      expect(describeTutorError(const PostgrestException(message: 'x', code: '23503')).message, foreignSubjectMessage);
      expect(describeTutorError(const PostgrestException(message: 'x', code: '42501')).message, permissionMessage);
      expect(describeTutorError(const PostgrestException(message: 'detalle interno', code: 'XX000')).message,
          saveFailedMessage);
    });
  });

  group('permisos', () {
    test('un estudiante crea su perfil de tutor y administra materias y horarios', () async {
      server.sessionUser = _student;
      final saved = await repo.save(_draft());
      expect(saved.userId, _student);
      expect(saved.universityId, 'esen');
      final updated = await repo.save(saved.copyWith(
        materias: ['bdd'],
        disponibilidad: const [AvailabilitySlot(diaSemana: 5, horaInicio: 600, horaFin: 720)],
      ));
      expect(updated.id, saved.id);
      expect(updated.materias, ['bdd']);
      expect(updated.disponibilidad.single.diaSemana, 5);
      expect((await repo.getByUserId(_student))!.id, saved.id);
      expect(server.profiles, hasLength(1));
    });

    test('un estudiante con perfil de tutor sigue viendo a los demás tutores', () async {
      await repo.save(_draft()); // tutor 1
      server.sessionUser = _student;
      await repo.save(_draft(materias: ['bdd']));
      final all = await repo.getAvailable(universityId: 'esen');
      expect(all.map((p) => p.userId).toSet(), {_tutor1, _student});
    });

    test('una cuenta administradora no ofrece tutorías', () async {
      server.sessionUser = _admin;
      await expectLater(repo.save(_draft()),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', permissionMessage)));
      expect(server.profiles, isEmpty);
    });

    test('el perfil siempre es el del usuario con sesión, aunque la app envíe otro userId', () async {
      await repo.save(_draft(userId: _tutor2));
      expect(server.profiles.values.single['user_id'], _tutor1);
      server.sessionUser = _tutor2;
      final other = await repo.save(_draft());
      expect(other.userId, _tutor2);
      expect(server.profiles, hasLength(2));
    });

    test('un tutor de otra universidad no ve los perfiles de ESEN', () async {
      await repo.save(_draft());
      server.sessionUser = _tutorOtra;
      expect(await repo.getAvailable(), isEmpty);
    });
  });

  group('búsqueda', () {
    setUp(() async {
      await repo.save(_draft(materias: ['est'], presencial: true, virtual: false)); // tutor 1
      server.sessionUser = _tutor2;
      await repo.save(_draft(
        materias: ['bdd'],
        presencial: false,
        virtual: true,
        slots: const [AvailabilitySlot(diaSemana: 3, horaInicio: 840, horaFin: 1020)],
      ));
      server.sessionUser = _student;
    });

    test('tutores activos de la misma universidad', () async {
      final all = await repo.getAvailable(universityId: 'esen');
      expect(all.map((p) => p.userId).toSet(), {_tutor1, _tutor2});
    });

    test('filtros por materia, categoría, modalidad y disponibilidad', () async {
      expect((await repo.getAvailable(universityId: 'esen', subjectId: 'est')).single.userId, _tutor1);
      expect((await repo.getAvailable(universityId: 'esen', categoria: 'Tecnología')).single.userId, _tutor2);
      expect((await repo.getAvailable(universityId: 'esen', modalidad: TutoringModality.virtual)).single.userId,
          _tutor2);
      // Miércoles 4 de noviembre de 2026, 15:00 (dentro del bloque del tutor 2).
      final miercoles = DateTime(2026, 11, 4, 15);
      expect((await repo.getAvailable(universityId: 'esen', disponibleEn: miercoles, duracionMinutos: 90))
          .single
          .userId, _tutor2);
      expect(await repo.getAvailable(universityId: 'esen', disponibleEn: DateTime(2026, 11, 4, 17), duracionMinutos: 90),
          isEmpty);
    });

    test('inactivos o incompletos no aparecen', () async {
      server.sessionUser = _tutor1;
      final mine = (await repo.getByUserId(_tutor1))!;
      await repo.save(mine.copyWith(activo: false));
      server.sessionUser = _student;
      expect((await repo.getAvailable(universityId: 'esen')).single.userId, _tutor2);
      server.profiles.values.firstWhere((r) => r['user_id'] == _tutor2)['tutor_subjects'] = <Object>[];
      expect(await repo.getAvailable(universityId: 'esen'), isEmpty); // sin materias = incompleto
    });

    test('TutorStore usa el repositorio remoto con los mismos filtros', () async {
      final store = TutorStore(repo, RemoteSubjectRepository(cache), _Users());
      await store.loadForUniversity('esen');
      expect(store.availableTutors, hasLength(2));
      await store.filterByModality(TutoringModality.presencial);
      expect(store.availableTutors.single.profile.userId, _tutor1);
      expect(store.hasSearchOrFilters, isTrue);
      await store.clearSearch();
      expect(store.availableTutors, hasLength(2));
      store.dispose();
    });
  });

  group('errores', () {
    test('sin conexión', () async {
      server.error = Exception('Failed host lookup');
      await expectLater(repo.getAvailable(universityId: 'esen'),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', catalogConnectionMessage)));
      await expectLater(repo.getByUserId(_tutor1), throwsA(isA<RepositoryException>()));
      expect(await repo.getById(_tutor1), isNull); // getById no lanza
    });

    test('tiempo agotado al guardar', () async {
      server.hang = true;
      repo = build(timeout: const Duration(milliseconds: 50));
      await expectLater(repo.save(_draft()),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', catalogTimeoutMessage)));
    });

    test('una fila mal formada no impide mostrar las demás', () async {
      await repo.save(_draft());
      server.profiles['00000000-0000-4000-9000-000000000099'] = {
        'id': '00000000-0000-4000-9000-000000000099', 'user_id': _tutor2, 'university_id': _esen,
        'hourly_rate': 'diez', 'is_active': true, 'tutor_subjects': <Object>[], 'availability_slots': <Object>[],
      };
      expect(await repo.getAvailable(universityId: 'esen'), hasLength(1));
    });
  });

  group('reglas compartidas con el modo local', () {
    test('validateForSave y slotsProblem', () {
      expect(TutorRules.slotsProblem(const [
        AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 600),
        AvailabilitySlot(diaSemana: 1, horaInicio: 600, horaFin: 660), // contiguo: válido
      ]), isNull);
      expect(TutorRules.slotsProblem(const [
        AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 600),
        AvailabilitySlot(diaSemana: 1, horaInicio: 599, horaFin: 660),
      ]), isNotNull);
      expect(() => TutorRules.validateForSave(_draft(presencial: false)), throwsA(isA<RepositoryException>()));
    });

    test('perfiles locales guardados antes de las modalidades ofrecen ambas', () {
      final old = TutorProfile.fromJson({
        'id': 'tp-x', 'userId': 'u-x', 'descripcion': 'd', 'precioHora': 5,
        'materias': ['est'], 'disponibilidad': <Object>[],
      });
      expect(old.ofrecePresencial && old.ofreceVirtual, isTrue);
      final roundTrip = TutorProfile.fromJson(old.copyWith(ofreceVirtual: false).toJson());
      expect(roundTrip.ofreceVirtual, isFalse);
      expect(roundTrip.ofrece(TutoringModality.presencial), isTrue);
    });
  });
}
