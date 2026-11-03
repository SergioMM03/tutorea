import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/supabase/remote_booking_repository.dart';
import 'package:tutorea/domain/follow_up_rules.dart';
import 'package:tutorea/data/supabase/remote_catalog.dart';
import 'package:tutorea/data/supabase/remote_catalog_repositories.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/state/booking_store.dart';
import 'package:tutorea/utils/tutorea_time.dart';

// Fase 14.8: reservas en Supabase. Ninguna prueba usa la red: _FakeServer imita
// la tabla bookings con su RLS y las funciones request/accept/reject/cancel
// (migraciones 17 y 18), con los mismos códigos de error.

const _esen = '11111111-1111-4111-8111-111111111111';
const _student = '00000000-0000-4000-8000-0000000000a1';
const _student2 = '00000000-0000-4000-8000-0000000000a2';
const _tutorUser = '00000000-0000-4000-8000-0000000000f1';
const _dualUser = '00000000-0000-4000-8000-0000000000d1'; // estudiante con perfil de tutor
const _tpTutor = '10000000-0000-4000-9000-000000000001';
const _tpDual = '10000000-0000-4000-9000-000000000002';

/// "Ahora" del servidor y de la app: lunes 2 de noviembre de 2026, 06:00 en El Salvador.
final _serverNow = DateTime.utc(2026, 11, 2, 12);
DateTime _appNow() => DateTime(2026, 11, 2, 6);

/// Lunes 9 de noviembre de 2026 a esa hora (El Salvador).
DateTime _monday(int hour, [int minute = 0]) => DateTime(2026, 11, 9, hour, minute);

class _FakeCatalog implements CatalogRowsSource, UniversityListSource {
  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async {
    if (universitySlug != 'esen') return null;
    return RemoteCatalogRows(
      university: _uni,
      careers: [
        for (final c in LocalSeed.careers)
          {'id': 'c-${c.id}', 'university_id': _esen, 'slug': c.id, 'name': c.nombre},
      ],
      subjects: [
        for (final s in LocalSeed.subjects)
          {
            'id': 's-${s.id}',
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

  static const Map<String, dynamic> _uni = {
    'id': _esen, 'slug': 'esen', 'name': 'ESEN', 'short_name': 'ESEN', 'country': 'SV', 'is_active': true,
  };

  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() async => [_uni];

  @override
  Future<String?> universitySlugById(String universityUuid) async => universityUuid == _esen ? 'esen' : null;
}

/// Perfiles de tutor visibles (lo que devolvería RemoteTutorRepository).
class _Tutors implements TutorRepository {
  final Map<String, TutorProfile> profiles = {
    _tpTutor: const TutorProfile(
      id: _tpTutor,
      userId: _tutorUser,
      descripcion: 'Tutor',
      precioHora: 10,
      materias: ['est', 'mat'],
      disponibilidad: [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 720)],
      ofreceVirtual: false,
    ),
    _tpDual: const TutorProfile(
      id: _tpDual,
      userId: _dualUser,
      descripcion: 'Doble',
      precioHora: 8,
      materias: ['mat'],
      disponibilidad: [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 720)],
      ofrecePresencial: false,
    ),
  };

  @override
  Future<TutorProfile?> getById(String id) async => profiles[id];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Imita bookings + RLS + funciones de la migración 18.
class _FakeServer implements BookingRowsSource {
  final _Tutors tutors;
  _FakeServer(this.tutors);

  String? sessionUser = _student;
  Object? error;
  bool hang = false;
  Map<String, Object?>? lastRequest;
  final Map<String, Map<String, dynamic>> rows = {};
  final StreamController<void> events = StreamController<void>.broadcast();
  int _next = 1;

  PostgrestException _pg(String code) => PostgrestException(message: 'error $code', code: code);

  Future<void> _check() async {
    if (hang) await Completer<void>().future;
    if (error != null) throw error!;
  }

  String? _tutorUserOf(String tutorProfileId) => tutors.profiles[tutorProfileId]?.userId;

  bool _visible(Map<String, dynamic> row) =>
      row['student_id'] == sessionUser || _tutorUserOf(row['tutor_profile_id'] as String) == sessionUser;

  static bool _blocking(Object? status) =>
      status == 'aceptada' || status == 'pendiente_confirmacion' || status == 'completada';

  bool _overlaps(String field, String value, DateTime start, DateTime end, String? except) =>
      rows.values.any((r) =>
          r['id'] != except &&
          r[field] == value &&
          _blocking(r['status']) &&
          DateTime.parse(r['starts_at'] as String).isBefore(end) &&
          start.isBefore(DateTime.parse(r['ends_at'] as String)));

  @override
  Future<List<Map<String, dynamic>>> fetchForStudent(String studentId) async {
    await _check();
    return [for (final r in rows.values) if (_visible(r) && r['student_id'] == studentId) {...r}]
      ..sort((a, b) => (b['starts_at'] as String).compareTo(a['starts_at'] as String));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchForTutor(String tutorProfileId) async {
    await _check();
    return [for (final r in rows.values) if (_visible(r) && r['tutor_profile_id'] == tutorProfileId) {...r}];
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async {
    await _check();
    final row = rows[id];
    return row != null && _visible(row) ? {...row} : null;
  }

  @override
  Future<String> request({
    required String tutorProfileId,
    required String subjectId,
    required String modality,
    required String startsAtUtc,
    required int durationMinutes,
    String? topic,
    String? location,
  }) async {
    await _check();
    lastRequest = {
      'tutor': tutorProfileId, 'subject': subjectId, 'modality': modality,
      'starts': startsAtUtc, 'duration': durationMinutes, 'topic': topic, 'location': location,
    };
    final me = sessionUser;
    if (me == null) throw _pg('42501');
    if (![60, 90, 120].contains(durationMinutes)) throw _pg('TU005');
    final start = DateTime.parse(startsAtUtc);
    if (!start.isAfter(_serverNow)) throw _pg('TU006');
    final tutor = tutors.profiles[tutorProfileId];
    if (tutor == null || !tutor.activo) throw _pg('TU001');
    if (tutor.userId == me) throw _pg('TU002');
    if (!tutor.materias.map((s) => 's-$s').contains(subjectId)) throw _pg('TU003');
    final mod = TutoringModality.values.byName(modality);
    if (!tutor.ofrece(mod)) throw _pg('TU004');
    // Disponibilidad en hora de El Salvador (como tutorea_time_zone()).
    if (!tutor.disponibleEn(TutoreaTime.fromUtc(start), durationMinutes)) throw _pg('TU007');
    final end = start.add(Duration(minutes: durationMinutes));
    if (_overlaps('tutor_profile_id', tutorProfileId, start, end, null)) throw _pg('TU008');
    if (_overlaps('student_id', me, start, end, null)) throw _pg('TU014');
    if (rows.values.any((r) =>
        r['student_id'] == me && r['tutor_profile_id'] == tutorProfileId &&
        r['starts_at'] == start.toIso8601String() &&
        (r['status'] == 'pendiente' || r['status'] == 'aceptada'))) {
      throw _pg('23505');
    }
    final id = '20000000-0000-4000-9000-${(_next++).toString().padLeft(12, '0')}';
    rows[id] = {
      'id': id,
      'university_id': _esen, // del perfil, no de la app
      'student_id': me, // auth.uid(), no de la app
      'tutor_profile_id': tutorProfileId,
      'subject_id': subjectId,
      'modality': modality,
      'topic': topic?.trim().isEmpty ?? true ? null : topic!.trim(),
      'location': location,
      'starts_at': start.toIso8601String(),
      'ends_at': end.toIso8601String(),
      'duration_minutes': durationMinutes,
      'agreed_price': tutor.precioHora * durationMinutes / 60, // precio acordado
      'status': 'pendiente',
      'responded_at': null,
      'cancelled_by': null,
      'cancelled_at': null,
      'cancellation_reason': null,
    };
    return id;
  }

  Map<String, dynamic> _ownAsTutor(String id) {
    final row = rows[id];
    if (row == null || _tutorUserOf(row['tutor_profile_id'] as String) != sessionUser) throw _pg('TU009');
    return row;
  }

  @override
  Future<void> accept(String bookingId) async {
    await _check();
    final row = _ownAsTutor(bookingId);
    if (row['status'] != 'pendiente') throw _pg('TU010');
    final start = DateTime.parse(row['starts_at'] as String);
    final end = DateTime.parse(row['ends_at'] as String);
    // accept_booking vuelve a validar con la disponibilidad ACTUAL del tutor.
    final tutor = tutors.profiles[row['tutor_profile_id']]!;
    if (!tutor.activo) throw _pg('TU001');
    if (!tutor.disponibleEn(TutoreaTime.fromUtc(start), row['duration_minutes'] as int)) throw _pg('TU015');
    if (_overlaps('tutor_profile_id', row['tutor_profile_id'] as String, start, end, bookingId)) {
      throw _pg('TU008');
    }
    if (_overlaps('student_id', row['student_id'] as String, start, end, bookingId)) throw _pg('TU014');
    row['status'] = 'aceptada';
    row['responded_at'] = _serverNow.toIso8601String();
  }

  @override
  Future<void> reject(String bookingId) async {
    await _check();
    final row = _ownAsTutor(bookingId);
    if (row['status'] != 'pendiente') throw _pg('TU010');
    row['status'] = 'rechazada';
    row['responded_at'] = _serverNow.toIso8601String();
  }

  @override
  Future<void> cancel(String bookingId, String? reason) async {
    await _check();
    final row = rows[bookingId];
    if (row == null || !_visible(row)) throw _pg('TU009');
    final isStudent = row['student_id'] == sessionUser;
    final text = reason?.trim() ?? '';
    if (row['status'] == 'pendiente') {
      if (!isStudent) throw _pg('TU013');
    } else if (row['status'] == 'aceptada') {
      if (text.length < 3) throw _pg('TU011');
    } else {
      throw _pg('TU010');
    }
    row['status'] = 'cancelada';
    row['cancelled_by'] = sessionUser;
    row['cancelled_at'] = _serverNow.toIso8601String();
    row['cancellation_reason'] = text.isEmpty ? null : text;
  }

  // ------------------------------------------ Fase 14.9 (migración 21)

  /// Reloj del servidor para confirm_booking (now() en PostgreSQL).
  DateTime now = _serverNow;

  /// Reservas con una incidencia abierta (booking_has_open_incident).
  final Set<String> openIncidents = {};

  /// booking_confirmations: (booking, party, user, confirmed_at).
  final List<Map<String, dynamic>> confirmations = [];

  @override
  Future<String> confirm(String bookingId) async {
    await _check();
    final row = rows[bookingId];
    final me = sessionUser;
    if (row == null || me == null || !_visible(row)) throw _pg('TU009');
    final party = row['student_id'] == me ? 'estudiante' : 'tutor';
    if (row['status'] != 'aceptada' && row['status'] != 'pendiente_confirmacion') throw _pg('TU023');
    if (now.isBefore(DateTime.parse(row['ends_at'] as String))) throw _pg('TU020');
    final mine = confirmations.where((c) => c['booking_id'] == bookingId);
    if (mine.any((c) => c['party'] == party)) throw _pg('TU021');
    final other = mine.any((c) => c['party'] != party);
    if (other && openIncidents.contains(bookingId)) throw _pg('TU022');
    final status = other ? 'completada' : 'pendiente_confirmacion';
    confirmations.add({
      'booking_id': bookingId,
      'party': party,
      'user_id': me,
      'confirmed_at': now.toIso8601String(),
    });
    row['status'] = status;
    return status;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchConfirmations(String bookingId) async {
    await _check();
    final row = rows[bookingId];
    if (row == null || !_visible(row)) return [];
    return [for (final c in confirmations) if (c['booking_id'] == bookingId) {...c}];
  }

  @override
  Stream<void> changes() => events.stream;
}

Booking _draft({
  String studentId = _student,
  String tutorId = _tpTutor,
  String subjectId = 'est',
  DateTime? fechaHora,
  int duracion = 60,
  TutoringModality? modalidad = TutoringModality.presencial,
  String? ubicacion,
}) =>
    Booking(
      id: 'bk-local-id-que-se-ignora',
      studentId: studentId,
      tutorId: tutorId,
      subjectId: subjectId,
      tema: ' Distribuciones ',
      fechaHora: fechaHora ?? _monday(10),
      duracion: duracion,
      precio: 999, // la app no fija el precio
      modalidad: modalidad,
      ubicacion: ubicacion,
    );

/// Deja correr los futuros pendientes (eventos de Realtime simulados).
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Tutors tutors;
  late _FakeServer server;
  late RemoteCatalogCache cache;
  late RemoteBookingRepository repo;

  RemoteBookingRepository build({Duration timeout = const Duration(seconds: 2)}) =>
      RemoteBookingRepository(server, cache, tutors, timeout: timeout);

  setUp(() {
    tutors = _Tutors();
    server = _FakeServer(tutors);
    cache = RemoteCatalogCache(catalog: _FakeCatalog(), universities: _FakeCatalog());
    repo = build();
  });

  group('solicitar', () {
    test('crea la reserva en Supabase; el servidor fija estudiante, universidad y precio', () async {
      final saved = await repo.create(_draft(studentId: _student, duracion: 90, ubicacion: 'Biblioteca'));
      expect(saved.id, isNot('bk-local-id-que-se-ignora'));
      expect(saved.studentId, _student);
      expect(saved.estado, BookingStatus.pendiente);
      expect(saved.precio, 15); // 10/h × 1,5 h, no el 999 de la app
      expect(saved.subjectId, 'est');
      expect(saved.modalidad, TutoringModality.presencial);
      expect(saved.ubicacion, 'Biblioteca');
      expect(saved.tema, 'Distribuciones');
      // Conversión de zona horaria: 10:00 en El Salvador = 16:00 UTC.
      expect(server.lastRequest!['starts'], '2026-11-09T16:00:00.000Z');
      expect(server.lastRequest!['subject'], 's-est');
      expect(saved.fechaHora, _monday(10));
    });

    test('las reglas del servidor llegan como mensajes claros', () async {
      Future<void> expectMessage(Booking draft, String message) => expectLater(
          repo.create(draft), throwsA(isA<RepositoryException>().having((e) => e.message, 'message', message)));

      await expectMessage(_draft(fechaHora: DateTime(2026, 11, 1, 10)), pastDateMessage);
      await expectMessage(_draft(fechaHora: _monday(7)), outsideAvailabilityMessage);
      await expectMessage(_draft(fechaHora: _monday(11), duracion: 90), outsideAvailabilityMessage);
      await expectMessage(_draft(modalidad: TutoringModality.virtual), modalityNotOfferedMessage);
      await expectMessage(_draft(subjectId: 'pro'), subjectNotOfferedMessage);
      await expectMessage(_draft(modalidad: null), chooseModalityMessage);
      await expectMessage(_draft(duracion: 45), invalidDurationMessage);
      await expectMessage(_draft(tutorId: 'tp-valeria'), tutorUnavailableMessage); // id local
      await repo.create(_draft());
      await expectMessage(_draft(), duplicateRequestMessage);
    });

    test('nadie se solicita una tutoría a sí mismo (doble rol)', () async {
      server.sessionUser = _dualUser;
      await expectLater(
          repo.create(_draft(studentId: _dualUser, tutorId: _tpDual, subjectId: 'mat',
              modalidad: TutoringModality.virtual)),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', selfBookingMessage)));
      expect(server.rows, isEmpty);
    });

    test('tutor inactivo', () async {
      tutors.profiles[_tpTutor] = tutors.profiles[_tpTutor]!.copyWith(activo: false);
      await expectLater(repo.create(_draft()),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', tutorUnavailableMessage)));
    });
  });

  group('consultar (doble rol)', () {
    test('una cuenta doble ve por separado lo que envió y lo que recibió', () async {
      server.sessionUser = _dualUser;
      await repo.create(_draft(studentId: _dualUser, subjectId: 'mat')); // pide a Tutor
      server.sessionUser = _student;
      await repo.create(_draft(tutorId: _tpDual, subjectId: 'mat', modalidad: TutoringModality.virtual));

      server.sessionUser = _dualUser;
      final sent = await repo.getForStudent(_dualUser);
      final received = await repo.getForTutor(_tpDual);
      expect(sent.single.tutorId, _tpTutor);
      expect(received.single.studentId, _student);

      // Otra cuenta no ve reservas ajenas (RLS).
      server.sessionUser = _student2;
      expect(await repo.getForStudent(_dualUser), isEmpty);
      expect(await repo.getForTutor(_tpDual), isEmpty);
    });

    test('ids locales antiguos no se consultan en Supabase', () async {
      expect(await repo.getForStudent('u-sergio'), isEmpty);
      expect(await repo.getForTutor('tp-valeria'), isEmpty);
    });

    test('una fila mal formada no impide mostrar las demás', () async {
      await repo.create(_draft());
      server.rows['20000000-0000-4000-9000-000000000099'] = {
        ...server.rows.values.first,
        'id': '20000000-0000-4000-9000-000000000099',
        'status': 'inventado',
      };
      expect(await repo.getForStudent(_student), hasLength(1));
    });
  });

  group('aceptar, rechazar y cancelar con BookingStore', () {
    late BookingStore studentStore;
    late BookingStore tutorStore;
    late Booking first;
    late Booking second;

    setUp(() async {
      studentStore = BookingStore(repo, now: _appNow);
      first = (await studentStore.createRequest(
        studentId: _student, tutorId: _tpTutor, subjectId: 'est',
        fechaHora: _monday(10), duracion: 60, modalidad: TutoringModality.presencial,
      ))!;
      server.sessionUser = _student2;
      second = await repo.create(_draft(studentId: _student2)); // mismo horario: pendientes coexisten
      server.sessionUser = _tutorUser;
      tutorStore = BookingStore(repo, now: _appNow);
      await tutorStore.loadForTutor(_tpTutor);
    });

    tearDown(() {
      studentStore.dispose();
      tutorStore.dispose();
    });

    test('el tutor ve las solicitudes recibidas, acepta una y la otra choca', () async {
      expect(tutorStore.tutorRequests, hasLength(2));
      expect(await tutorStore.accept(first.id), isTrue);
      expect(tutorStore.tutorRequests.firstWhere((b) => b.id == first.id).estado, BookingStatus.aceptada);
      expect(await tutorStore.accept(second.id), isFalse);
      expect(tutorStore.error, tutorBusyMessage);
      expect(await tutorStore.reject(second.id), isTrue);
      expect(await tutorStore.accept(second.id), isFalse); // rechazada es final
      expect(tutorStore.error, statusChangedMessage);
    });

    test('al aceptar se valida la disponibilidad actual del tutor', () async {
      // Otra cuenta pide 90 min el lunes 10:00 (cabe en 08–12).
      server.sessionUser = _dualUser;
      final long = await repo.create(
          _draft(studentId: _dualUser, fechaHora: _monday(10), duracion: 90, subjectId: 'mat'));
      server.sessionUser = _tutorUser;
      await tutorStore.loadForTutor(_tpTutor);
      final original = tutors.profiles[_tpTutor]!;

      // Acortó el bloque a 08–11: la de 90 min (10:00–11:30) ya no cabe; la de 60 sí.
      tutors.profiles[_tpTutor] = original.copyWith(
          disponibilidad: const [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 660)]);
      expect(await tutorStore.accept(long.id), isFalse);
      expect(tutorStore.error, availabilityChangedMessage);
      expect(await tutorStore.accept(first.id), isTrue); // la disponibilidad sigue vigente

      // Movió el lunes a la tarde: tampoco se acepta la del mismo horario.
      tutors.profiles[_tpTutor] = original.copyWith(
          disponibilidad: const [AvailabilitySlot(diaSemana: 1, horaInicio: 840, horaFin: 960)]);
      expect(await tutorStore.accept(second.id), isFalse);
      expect(tutorStore.error, availabilityChangedMessage);

      // Borró el lunes.
      tutors.profiles[_tpTutor] = original.copyWith(disponibilidad: const [
        AvailabilitySlot(diaSemana: 2, horaInicio: 480, horaFin: 720),
      ]);
      expect(await tutorStore.accept(long.id), isFalse);
      expect(tutorStore.error, availabilityChangedMessage);
      expect(tutorStore.tutorRequests.firstWhere((b) => b.id == long.id).estado, BookingStatus.pendiente);
    });

    test('el estudiante no puede aceptar', () async {
      server.sessionUser = _student;
      expect(await studentStore.accept(first.id), isFalse);
      expect(studentStore.error, notFoundMessage);
    });

    test('cancelar: pendiente solo quien la envió; aceptada ambos, con motivo', () async {
      // El tutor no cancela una pendiente: la rechaza.
      expect(await tutorStore.cancel(first.id, motivo: 'x x x'), isFalse);
      expect(await tutorStore.accept(first.id), isTrue);
      // Aceptada: sin motivo no se cancela (lo valida la app y el servidor).
      expect(await tutorStore.cancel(first.id), isFalse);
      expect(tutorStore.error, cancelReasonRequiredMessage);
      expect(await tutorStore.cancel(first.id, motivo: 'Me enfermé'), isTrue);
      final cancelled = tutorStore.tutorRequests.firstWhere((b) => b.id == first.id);
      expect(cancelled.estado, BookingStatus.cancelada);
      expect(cancelled.canceladaPor, _tutorUser);
      expect(cancelled.motivoCancelacion, 'Me enfermé');

      // El estudiante cancela su pendiente sin motivo.
      server.sessionUser = _student2;
      final store2 = BookingStore(repo, now: _appNow);
      await store2.loadForStudent(_student2);
      expect(await store2.cancel(second.id), isTrue);
      expect(store2.studentBookings.single.estado, BookingStatus.cancelada);
      store2.dispose();
    });

    test('una aceptada que ya empezó no se cancela', () async {
      await tutorStore.accept(first.id);
      final lateStore = BookingStore(repo, now: () => DateTime(2026, 11, 9, 10, 5));
      await lateStore.loadForTutor(_tpTutor);
      expect(await lateStore.cancel(first.id, motivo: 'Tarde'), isFalse);
      expect(lateStore.error, contains('ya empezó'));
      lateStore.dispose();
    });

    test('Realtime: el estudiante se entera cuando el tutor acepta', () async {
      server.sessionUser = _student;
      await studentStore.loadForStudent(_student);
      server.sessionUser = _tutorUser;
      await server.accept(first.id); // en el teléfono del tutor
      server.sessionUser = _student;
      server.events.add(null); // Supabase Realtime avisa al teléfono del estudiante
      await _settle();
      expect(studentStore.studentBookings.single.estado, BookingStatus.aceptada);
      expect(studentStore.notice, 'El tutor aceptó tu solicitud.');
    });

    test('Realtime: el tutor se entera de una solicitud nueva y de una cancelación', () async {
      server.sessionUser = _student;
      await server.request(
          tutorProfileId: _tpTutor, subjectId: 's-mat', modality: 'presencial',
          startsAtUtc: TutoreaTime.toUtc(_monday(11)).toIso8601String(), durationMinutes: 60);
      server.sessionUser = _tutorUser;
      server.events.add(null);
      await _settle();
      expect(tutorStore.tutorRequests, hasLength(3));
      expect(tutorStore.notice, 'Recibiste una nueva solicitud de tutoría.');

      server.sessionUser = _student2;
      await server.cancel(second.id, null);
      server.sessionUser = _tutorUser;
      server.events.add(null);
      await _settle();
      expect(tutorStore.notice, 'El estudiante canceló una reserva.');
    });
  });

  group('errores y almacenamiento', () {
    test('sin conexión y tiempo agotado', () async {
      server.error = Exception('Failed host lookup');
      await expectLater(repo.getForStudent(_student),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', bookingConnectionMessage)));
      server.error = null;
      server.hang = true;
      repo = build(timeout: const Duration(milliseconds: 50));
      await expectLater(repo.getForStudent(_student),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', bookingTimeoutMessage)));
    });

    test('códigos de PostgreSQL → mensajes fijos', () {
      String m(String code) => describeBookingError(PostgrestException(message: 'detalle interno', code: code)).message;
      expect(m('23P01'), slotTakenMessage);
      expect(m('TU014'), studentBusyMessage);
      expect(m('TU012'), alreadyStartedMessage);
      expect(m('TU013'), tutorCannotCancelPendingMessage);
      expect(m('TU015'), availabilityChangedMessage);
      expect(m('42501'), bookingPermissionMessage);
      expect(m('XX000'), actionFailedMessage);
    });

    test('en modo Supabase las reservas no se guardan en el dispositivo', () async {
      SharedPreferences.setMockInitialValues({});
      final store = BookingStore(repo, now: _appNow);
      await store.createRequest(
          studentId: _student, tutorId: _tpTutor, subjectId: 'est',
          fechaHora: _monday(10), duracion: 60, modalidad: TutoringModality.presencial);
      await store.loadForStudent(_student);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
      expect(server.rows, hasLength(1));
      store.dispose();
    });
  });

  group('hora de El Salvador', () {
    test('ida y vuelta UTC ↔ El Salvador', () {
      final wall = DateTime(2026, 11, 9, 23, 30);
      final utc = TutoreaTime.toUtc(wall);
      expect(utc, DateTime.utc(2026, 11, 10, 5, 30));
      expect(TutoreaTime.fromUtc(utc), wall);
      expect(TutoreaTime.fromUtc(DateTime.parse('2026-11-09T16:00:00+00:00')), DateTime(2026, 11, 9, 10));
    });
  });

  group('confirmar la sesión (Fase 14.9)', () {
    Future<Booking> accepted() async {
      final b = await repo.create(_draft());
      server.sessionUser = _tutorUser;
      await repo.updateStatus(b.id, BookingStatus.aceptada);
      return b;
    }

    test('la primera confirmación deja pendiente_confirmacion y la segunda completa', () async {
      final b = await accepted();
      server.now = DateTime.utc(2026, 11, 9, 17, 30); // fin: 11:00 SV = 17:00 UTC
      server.sessionUser = _student;
      final first = await repo.confirm(b.id, actorId: 'ignorado');
      expect(first.estado, BookingStatus.pendienteConfirmacion);
      final c1 = await repo.getConfirmations(b.id);
      expect(c1.single.party, BookingParty.estudiante);
      expect(c1.single.userId, _student); // auth.uid(), no el actorId de la app

      server.sessionUser = _tutorUser;
      final second = await repo.confirm(b.id);
      expect(second.estado, BookingStatus.completada);
      expect((await repo.getConfirmations(b.id)).map((c) => c.party).toSet(),
          {BookingParty.estudiante, BookingParty.tutor});
    });

    test('antes del fin, dos veces, ajena o con incidencia abierta: mensajes fijos', () async {
      final b = await accepted();
      server.sessionUser = _student;
      await expectLater(repo.confirm(b.id),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'm', sessionNotFinishedMessage)));
      server.now = DateTime.utc(2026, 11, 9, 18);
      await repo.confirm(b.id);
      await expectLater(repo.confirm(b.id),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'm', alreadyConfirmedMessage)));
      server.sessionUser = _student2;
      await expectLater(repo.confirm(b.id),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'm', notFoundMessage)));
      server.openIncidents.add(b.id);
      server.sessionUser = _tutorUser;
      await expectLater(repo.confirm(b.id),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'm', openIncidentBlocksCompletionMessage)));
      expect(server.rows[b.id]!['status'], 'pendiente_confirmacion');
      // Resuelta la incidencia, quien faltaba confirma y se completa.
      server.openIncidents.clear();
      expect((await repo.confirm(b.id)).estado, BookingStatus.completada);
    });

    test('una solicitud pendiente no se confirma (TU023)', () async {
      final b = await repo.create(_draft());
      server.now = DateTime.utc(2026, 11, 10);
      await expectLater(repo.confirm(b.id),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'm', notConfirmableMessage)));
    });

    test('BookingStore.confirm actualiza la lista y las confirmaciones', () async {
      final b = await accepted();
      server.now = DateTime.utc(2026, 11, 9, 17, 30);
      server.sessionUser = _student;
      final store = BookingStore(repo, now: () => DateTime(2026, 11, 9, 11, 30));
      await store.loadForStudent(_student);
      expect(store.sessionEnded(store.studentBookingById(b.id)!), isTrue);
      expect(await store.confirm(b.id), isTrue);
      expect(store.studentBookingById(b.id)!.estado, BookingStatus.pendienteConfirmacion);
      expect(store.hasConfirmed(b.id, BookingParty.estudiante), isTrue);
      expect(store.hasConfirmed(b.id, BookingParty.tutor), isFalse);
      store.dispose();
    });
  });
}
