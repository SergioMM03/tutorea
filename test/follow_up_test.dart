import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:tutorea/data/local/local_booking_repository.dart';
import 'package:tutorea/data/local/local_database.dart';
import 'package:tutorea/data/local/local_follow_up_repositories.dart';
import 'package:tutorea/data/local/local_notifications.dart';
import 'package:tutorea/data/local/local_tutor_repository.dart';
import 'package:tutorea/data/supabase/remote_follow_up_repositories.dart';
import 'package:tutorea/domain/follow_up_rules.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/domain/tutor_rules.dart';
import 'package:tutorea/state/booking_store.dart';
import 'package:tutorea/state/follow_up_stores.dart';
import 'package:tutorea/widgets/rating_label.dart';

// Fase 14.9: confirmaciones, incidencias, calificaciones y notificaciones.
// Modo local (mismas reglas que las migraciones 19–23) y repositorios remotos
// con un servidor simulado (errores TU0xx, privacidad, Realtime).

const _student = 'u-sergio';
const _tutorUser = 'u-valeria';
const _tutor = 'tp-valeria';
const _outsider = 'u-daniel';

/// Martes 10 de noviembre de 2026, 10:00–11:00 (Valeria atiende de 08 a 20).
final _start = DateTime(2026, 11, 10, 10);
final _end = DateTime(2026, 11, 10, 11);

Matcher _fails(String message) =>
    throwsA(isA<RepositoryException>().having((e) => e.message, 'message', message));

int _seq = 0;

class _Local {
  final LocalDatabase db;
  DateTime clock = DateTime(2026, 11, 2, 8);
  late final LocalTutorRepository tutors = LocalTutorRepository(db);
  late final LocalNotifications notifier = LocalNotifications(db, now: () => clock);
  late final LocalBookingRepository bookings =
      LocalBookingRepository(db, tutors, now: () => clock, notifications: notifier);
  late final LocalIncidentRepository incidents =
      LocalIncidentRepository(db, tutors, now: () => clock, notifications: notifier);
  late final LocalAdminIncidentRepository admin =
      LocalAdminIncidentRepository(db, tutors, now: () => clock, notifications: notifier);
  late final LocalReviewRepository reviews = LocalReviewRepository(db, tutors, now: () => clock);
  late final LocalNotificationRepository notifications = LocalNotificationRepository(db, now: () => clock);
  _Local(this.db);

  Future<Booking> accepted({DateTime? start}) async {
    final b = await bookings.create(Booking(
      id: 'bk-${_seq++}',
      studentId: _student,
      tutorId: _tutor,
      subjectId: 'est',
      fechaHora: start ?? _start,
      duracion: 60,
      precio: 0,
      modalidad: TutoringModality.presencial,
    ));
    return bookings.updateStatus(b.id, BookingStatus.aceptada, actorId: _tutorUser);
  }

  /// Reserva completada por las dos partes.
  Future<Booking> completed() async {
    final b = await accepted();
    clock = _end.add(const Duration(minutes: 5));
    await bookings.confirm(b.id, actorId: _student);
    return bookings.confirm(b.id, actorId: _tutorUser);
  }

  Future<List<AppNotification>> inbox(String user) => notifications.getMine(user);
}

void main() {
  late _Local local;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    local = _Local(await LocalDatabase.open());
  });

  group('confirmaciones (modo local)', () {
    test('primera → pendiente_confirmacion, segunda → completada; se conservan', () async {
      final b = await local.accepted();
      local.clock = _end.add(const Duration(minutes: 1));

      final first = await local.bookings.confirm(b.id, actorId: _student);
      expect(first.estado, BookingStatus.pendienteConfirmacion);
      final second = await local.bookings.confirm(b.id, actorId: _tutorUser);
      expect(second.estado, BookingStatus.completada);

      final confirmations = await local.bookings.getConfirmations(b.id);
      expect(confirmations.map((c) => c.party), [BookingParty.estudiante, BookingParty.tutor]);
      expect(confirmations.map((c) => c.userId), [_student, _tutorUser]);
    });

    test('solo participantes, solo después del fin y una vez por parte', () async {
      final b = await local.accepted();
      await expectLater(local.bookings.confirm(b.id, actorId: _student), _fails(sessionNotFinishedMessage));
      local.clock = _end; // justo al terminar ya se puede
      await expectLater(local.bookings.confirm(b.id, actorId: _outsider), _fails(confirmNotFoundMessage));
      await expectLater(local.bookings.confirm(b.id), _fails(confirmNotFoundMessage));
      await local.bookings.confirm(b.id, actorId: _tutorUser);
      await expectLater(local.bookings.confirm(b.id, actorId: _tutorUser), _fails(alreadyConfirmedMessage));
    });

    test('una solicitud pendiente, rechazada o cancelada no se confirma', () async {
      final pending = await local.bookings.create(Booking(
        id: 'bk-p', studentId: _student, tutorId: _tutor, subjectId: 'est', fechaHora: _start,
        duracion: 60, precio: 0, modalidad: TutoringModality.presencial,
      ));
      local.clock = _end.add(const Duration(hours: 1));
      await expectLater(local.bookings.confirm(pending.id, actorId: _student), _fails(notConfirmableMessage));
    });

    test('no se completa por tiempo ni cambiando el estado directamente', () async {
      final b = await local.accepted();
      local.clock = _end.add(const Duration(days: 30));
      final reread = (await local.bookings.getForStudent(_student)).firstWhere((x) => x.id == b.id);
      expect(reread.estado, BookingStatus.aceptada);
      await expectLater(local.bookings.updateStatus(b.id, BookingStatus.completada, actorId: _tutorUser),
          _fails(notConfirmableMessage));
      await expectLater(local.bookings.updateStatus(b.id, BookingStatus.pendienteConfirmacion, actorId: _student),
          _fails(notConfirmableMessage));
    });

    test('BookingStore: botón de confirmar solo al terminar', () async {
      final b = await local.accepted();
      final store = BookingStore(local.bookings, now: () => local.clock);
      await store.loadForStudent(_student);
      expect(store.sessionEnded(store.studentBookingById(b.id)!), isFalse);
      local.clock = _end.add(const Duration(minutes: 1));
      expect(store.sessionEnded(store.studentBookingById(b.id)!), isTrue);
      expect(await store.confirm(b.id, actorId: _student), isTrue);
      expect(store.studentBookingById(b.id)!.estado, BookingStatus.pendienteConfirmacion);
      expect(store.hasConfirmed(b.id, BookingParty.estudiante), isTrue);
      expect(await store.confirm(b.id, actorId: _student), isFalse);
      expect(store.error, alreadyConfirmedMessage);
    });
  });

  group('incidencias (modo local)', () {
    test('las dos partes reportan; una abierta por persona; categoría y descripción válidas', () async {
      final b = await local.accepted();
      final i = await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.inasistencia, description: '  El tutor no llegó a la sesión. ',
          actorId: _student);
      expect(i.status, IncidentStatus.pendienteRevision);
      expect(i.reporterParty, BookingParty.estudiante);
      expect(i.description, 'El tutor no llegó a la sesión.');

      await expectLater(
          local.incidents.report(
              bookingId: b.id, category: IncidentCategory.otro, description: 'Otra vez lo mismo, sí.', actorId: _student),
          _fails(incidentAlreadyOpenMessage));
      await expectLater(
          local.incidents.report(bookingId: b.id, category: IncidentCategory.otro, description: 'corto', actorId: _tutorUser),
          _fails(invalidIncidentMessage));
      final byTutor = await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.conducta, description: 'El estudiante fue irrespetuoso.',
          actorId: _tutorUser);
      expect(byTutor.reporterParty, BookingParty.tutor);
      await expectLater(
          local.incidents.report(
              bookingId: b.id, category: IncidentCategory.otro, description: 'No participo en esta reserva.',
              actorId: _outsider),
          _fails(confirmNotFoundMessage));
      expect(await local.incidents.getForBooking(b.id), hasLength(2));
    });

    test('desde aceptada hasta 7 días después del fin; nunca en pendiente', () async {
      final pending = await local.bookings.create(Booking(
        id: 'bk-p', studentId: _student, tutorId: _tutor, subjectId: 'est', fechaHora: _start,
        duracion: 60, precio: 0, modalidad: TutoringModality.presencial,
      ));
      await expectLater(
          local.incidents.report(
              bookingId: pending.id, category: IncidentCategory.otro, description: 'Todavía no me responde.',
              actorId: _student),
          _fails(notReportableMessage));

      final b = await local.accepted(start: DateTime(2026, 11, 11, 10));
      local.clock = DateTime(2026, 11, 18, 11); // fin + 7 días: todavía se puede
      await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.calidad, description: 'La explicación fue confusa.',
          actorId: _student);
      local.clock = DateTime(2026, 11, 18, 11, 1);
      await expectLater(
          local.incidents.report(
              bookingId: b.id, category: IncidentCategory.calidad, description: 'Un reporte fuera de plazo.',
              actorId: _tutorUser),
          _fails(reportWindowClosedMessage));
    });

    test('una incidencia abierta impide completar; resuelta, quien falta confirma', () async {
      final b = await local.accepted();
      local.clock = _end.add(const Duration(minutes: 10));
      await local.bookings.confirm(b.id, actorId: _student);
      final i = await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.impuntualidad, description: 'Llegó 40 minutos tarde.',
          actorId: _tutorUser);
      await expectLater(local.bookings.confirm(b.id, actorId: _tutorUser),
          _fails(openIncidentBlocksCompletionMessage));
      expect((await local.bookings.getConfirmations(b.id)), hasLength(1)); // la primera se conserva

      await local.admin.startInvestigation(i.id, note: 'Hablar con ambos.', actorId: 'u-admin');
      await expectLater(local.bookings.confirm(b.id, actorId: _tutorUser),
          _fails(openIncidentBlocksCompletionMessage));
      final resolved = await local.admin.resolve(i.id, 'Se aclaró con ambas partes.', actorId: 'u-admin');
      expect(resolved.status, IncidentStatus.resuelta);
      // Resolver no cambia la reserva ni crea calificaciones.
      expect((await local.bookings.getForStudent(_student)).single.estado, BookingStatus.pendienteConfirmacion);
      expect(await local.reviews.getForTutor(_tutor), isEmpty);

      final done = await local.bookings.confirm(b.id, actorId: _tutorUser);
      expect(done.estado, BookingStatus.completada);
      expect(await local.bookings.getConfirmations(b.id), hasLength(2));
    });

    test('la primera confirmación sí se permite con una incidencia abierta', () async {
      final b = await local.accepted();
      await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.tecnico, description: 'El enlace no funcionaba.',
          actorId: _student);
      local.clock = _end.add(const Duration(minutes: 1));
      expect((await local.bookings.confirm(b.id, actorId: _tutorUser)).estado, BookingStatus.pendienteConfirmacion);
    });

    test('gestión administrativa: transiciones, resolución obligatoria, notas internas e historial', () async {
      final b = await local.accepted();
      final i = await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.conducta, description: 'Comentarios fuera de lugar.',
          actorId: _student);
      await expectLater(local.admin.resolve(i.id, 'ok', actorId: 'u-admin'), _fails(incidentNoteRequiredMessage));
      await local.admin.startInvestigation(i.id, note: 'Revisar mensajes.', actorId: 'u-admin');
      await expectLater(local.admin.startInvestigation(i.id, actorId: 'u-admin'), _fails(incidentTransitionMessage));
      await local.admin.addNote(i.id, 'Llamar al tutor el lunes.', actorId: 'u-admin');
      final dismissed = await local.admin.dismiss(i.id, 'No se encontraron pruebas.', actorId: 'u-admin');
      expect(dismissed.status, IncidentStatus.desestimada);
      expect(dismissed.resolutionNote, 'No se encontraron pruebas.');
      expect(dismissed.resolvedAt, isNotNull);
      await expectLater(local.admin.resolve(i.id, 'Cambio de opinión.', actorId: 'u-admin'),
          _fails(incidentTransitionMessage));

      final adminHistory = await local.admin.getEvents(i.id);
      expect(adminHistory.map((e) => e.event), [
        IncidentEventType.reportada,
        IncidentEventType.estado,
        IncidentEventType.nota,
        IncidentEventType.nota,
        IncidentEventType.estado,
      ]);
      // Las partes ven el historial sin las notas internas.
      final partyHistory = await local.incidents.getEvents(i.id);
      expect(partyHistory.any((e) => e.internal), isFalse);
      expect(partyHistory.map((e) => e.event),
          [IncidentEventType.reportada, IncidentEventType.estado, IncidentEventType.estado]);
      expect(await local.admin.listForUniversity(status: IncidentStatus.desestimada), hasLength(1));
      expect(await local.admin.listForUniversity(status: IncidentStatus.pendienteRevision), isEmpty);
    });
  });

  group('calificaciones (modo local)', () {
    test('solo el estudiante, solo completada, una vez, de 1 a 5', () async {
      final b = await local.accepted();
      local.clock = _end.add(const Duration(minutes: 5));
      await expectLater(local.reviews.submit(bookingId: b.id, rating: 5, actorId: _student),
          _fails(notCompletedReviewMessage));
      await local.bookings.confirm(b.id, actorId: _student);
      await local.bookings.confirm(b.id, actorId: _tutorUser);

      await expectLater(local.reviews.submit(bookingId: b.id, rating: 5, actorId: _tutorUser),
          _fails(tutorSelfReviewMessage));
      await expectLater(local.reviews.submit(bookingId: b.id, rating: 5, actorId: _outsider),
          _fails(confirmNotFoundMessage));
      await expectLater(local.reviews.submit(bookingId: b.id, rating: 0, actorId: _student),
          _fails(invalidRatingMessage));
      await expectLater(local.reviews.submit(bookingId: b.id, rating: 6, actorId: _student),
          _fails(invalidRatingMessage));
      await expectLater(
          local.reviews.submit(bookingId: b.id, rating: 4, comment: 'x' * 1001, actorId: _student),
          _fails(invalidRatingMessage));

      final r = await local.reviews.submit(bookingId: b.id, rating: 4, comment: ' Muy clara ', actorId: _student);
      expect(r.rating, 4);
      expect(r.comment, 'Muy clara');
      await expectLater(local.reviews.submit(bookingId: b.id, rating: 5, actorId: _student),
          _fails(alreadyReviewedMessage));
      expect((await local.reviews.getForBooking(b.id))!.rating, 4);
    });

    test('una incidencia abierta impide calificar', () async {
      final b = await local.completed();
      await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.calidad, description: 'No cubrió el tema pedido.',
          actorId: _student);
      await expectLater(local.reviews.submit(bookingId: b.id, rating: 2, actorId: _student),
          _fails(openIncidentBlocksReviewMessage));
    });

    test('promedio y total calculados a partir de las reseñas; «Nuevo» sin reseñas', () async {
      final before = (await local.tutors.getById(_tutor))!;
      expect(before.totalResenas, 0);
      expect(before.calificacion, isNull); // nunca 0.0
      expect(before.tieneCalificaciones, isFalse);

      final b1 = await local.completed();
      await local.reviews.submit(bookingId: b1.id, rating: 5, actorId: _student);
      local.clock = DateTime(2026, 11, 2, 8);
      final b2 = await local.accepted(start: DateTime(2026, 11, 12, 15));
      local.clock = DateTime(2026, 11, 12, 17);
      await local.bookings.confirm(b2.id, actorId: _student);
      await local.bookings.confirm(b2.id, actorId: _tutorUser);
      await local.reviews.submit(bookingId: b2.id, rating: 4, actorId: _student);

      final after = (await local.tutors.getById(_tutor))!;
      expect(after.totalResenas, 2);
      expect(after.calificacion, 4.5);
      // Guardar el perfil no cambia la calificación calculada.
      await local.tutors.save(after.copyWith(precioHora: 11, rating: 1, totalResenas: 99));
      final saved = (await local.tutors.getById(_tutor))!;
      expect(saved.calificacion, 4.5);
      expect(saved.totalResenas, 2);
    });

    test('las reseñas públicas no exponen al estudiante ni la reserva', () async {
      final b = await local.completed();
      await local.reviews.submit(bookingId: b.id, rating: 5, comment: 'Excelente', actorId: _student);
      final public = await local.reviews.getForTutor(_tutor);
      expect(public.single.comment, 'Excelente');
      expect(public.single.studentId, isNull);
      expect(public.single.bookingId, isNull);
    });

    test('ordenar tutores: sin reseñas no cuenta como 0 pero va después', () {
      TutorProfile p(String id, double rating, int count) => TutorProfile(
          id: id, userId: 'u-$id', descripcion: 'Perfil', precioHora: 10, materias: const ['est'],
          disponibilidad: const [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 600)],
          rating: rating, totalResenas: count);
      final sorted = TutorRules.visible([p('a', 4.9, 0), p('b', 4.2, 3), p('c', 5, 1)]);
      expect(sorted.map((t) => t.id), ['c', 'b', 'a']);
    });
  });

  group('notificaciones (modo local)', () {
    test('cada hecho avisa a quien corresponde, sin duplicados', () async {
      final b = await local.accepted();
      local.clock = _end.add(const Duration(minutes: 1));
      await local.bookings.confirm(b.id, actorId: _student);
      final i = await local.incidents.report(
          bookingId: b.id, category: IncidentCategory.otro, description: 'Faltó material prometido.',
          actorId: _student);
      await local.admin.dismiss(i.id, 'No aplica.', actorId: 'u-admin');
      await local.bookings.confirm(b.id, actorId: _tutorUser);

      final tutor = (await local.inbox(_tutorUser)).map((n) => n.type).toList();
      final student = (await local.inbox(_student)).map((n) => n.type).toList();
      expect(tutor.toSet(), {
        NotificationType.reservaSolicitada,
        NotificationType.confirmacionPendiente,
        NotificationType.incidenciaReportada,
        NotificationType.incidenciaActualizada,
        NotificationType.reservaCompletada,
      });
      expect(student.toSet(), {
        NotificationType.reservaAceptada,
        NotificationType.incidenciaActualizada,
        NotificationType.reservaCompletada,
      });
      // Una por hecho y persona.
      for (final list in [await local.inbox(_tutorUser), await local.inbox(_student)]) {
        expect(list.map((n) => n.eventKey).toSet(), hasLength(list.length));
      }
      // Volver a registrar el mismo hecho no duplica.
      await local.notifier.bookingEvent((await local.bookings.getForStudent(_student)).single, tutorUserId: _tutorUser);
      expect(await local.inbox(_student), hasLength(student.length));
      expect(await local.inbox(_outsider), isEmpty);
    });

    test('rechazo y cancelación avisan a la otra parte', () async {
      final a = await local.bookings.create(Booking(
        id: 'bk-a', studentId: _student, tutorId: _tutor, subjectId: 'est', fechaHora: _start,
        duracion: 60, precio: 0, modalidad: TutoringModality.presencial,
      ));
      await local.bookings.updateStatus(a.id, BookingStatus.rechazada, actorId: _tutorUser);
      final c = await local.accepted(start: DateTime(2026, 11, 13, 10));
      await local.bookings.updateStatus(c.id, BookingStatus.cancelada, motivo: 'Me enfermé', actorId: _tutorUser);
      final student = (await local.inbox(_student)).map((n) => n.type).toSet();
      expect(student, containsAll([NotificationType.reservaRechazada, NotificationType.reservaCancelada]));
      final tutor = (await local.inbox(_tutorUser)).map((n) => n.type).toList();
      expect(tutor, isNot(contains(NotificationType.reservaCancelada))); // quien canceló no se avisa
    });

    test('cada cuenta lee y marca solo las suyas', () async {
      await local.accepted();
      final mine = await local.inbox(_student);
      expect(mine.single.leida, isFalse);
      // Otra cuenta no puede marcarlas.
      expect(await local.notifications.markRead(_tutorUser, [mine.single.id]), 0);
      expect((await local.inbox(_student)).single.leida, isFalse);
      expect(await local.notifications.markRead(_student, [mine.single.id]), 1);
      expect((await local.inbox(_student)).single.leida, isTrue);
      expect(await local.notifications.markAllRead(_tutorUser), 1);
      expect(await local.notifications.markAllRead(_tutorUser), 0);
    });

    test('NotificationStore: contador de no leídas', () async {
      await local.accepted();
      final store = NotificationStore(local.notifications);
      await store.load(_tutorUser);
      expect(store.unreadCount, 1);
      await store.markAllRead();
      expect(store.unreadCount, 0);
      store.reset();
      expect(store.items, isEmpty);
      store.dispose();
    });
  });

  group('stores de incidencias y reseñas', () {
    test('IncidentStore y ReviewStore muestran el mensaje del repositorio', () async {
      final b = await local.completed();
      final incidents = IncidentStore(local.incidents);
      final reviews = ReviewStore(local.reviews);
      expect(await reviews.submit(bookingId: b.id, rating: 5, actorId: _tutorUser), isNull);
      expect(reviews.error, tutorSelfReviewMessage);
      expect(await reviews.submit(bookingId: b.id, rating: 5, actorId: _student), isNotNull);
      await reviews.loadForTutor(_tutor);
      expect(reviews.forTutor(_tutor).single.studentId, isNull);

      expect(await incidents.report(bookingId: b.id, category: IncidentCategory.otro, description: 'corto',
          actorId: _student), isNull);
      expect(incidents.error, invalidIncidentMessage);
      await incidents.report(
          bookingId: b.id, category: IncidentCategory.otro, description: 'Algo pasó después.', actorId: _student);
      expect(incidents.hasOpenBy(b.id, _student), isTrue);
      expect(incidents.hasOpenBy(b.id, _tutorUser), isFalse);
    });
  });

  group('repositorios remotos (servidor simulado)', () {
    late _FakeFollowUp server;
    setUp(() => server = _FakeFollowUp());

    test('códigos TU0xx → mensajes fijos', () {
      final cases = {
        'TU009': confirmNotFoundMessage,
        'TU030': notReportableMessage,
        'TU031': reportWindowClosedMessage,
        'TU032': incidentAlreadyOpenMessage,
        'TU033': invalidIncidentMessage,
        'TU034': incidentNotFoundMessage,
        'TU035': incidentTransitionMessage,
        'TU036': incidentNoteRequiredMessage,
        'TU040': onlyStudentReviewsMessage,
        'TU041': tutorSelfReviewMessage,
        'TU042': notCompletedReviewMessage,
        'TU043': openIncidentBlocksReviewMessage,
        'TU044': alreadyReviewedMessage,
        'TU045': invalidRatingMessage,
        '42501': followUpPermissionMessage,
      };
      cases.forEach((code, message) {
        expect(describeFollowUpError(PostgrestException(message: 'texto del servidor', code: code)).message,
            message);
      });
      expect(describeFollowUpError(TimeoutException('x')).message, followUpTimeoutMessage);
      expect(describeFollowUpError(Exception('red')).message, followUpConnectionMessage);
      expect(
          describeFollowUpError(PostgrestException(message: 'dup', code: '23505'),
                  duplicate: alreadyReviewedMessage)
              .message,
          alreadyReviewedMessage);
    });

    test('reportar: la app envía solo reserva, categoría y descripción', () async {
      final repo = RemoteIncidentRepository(server);
      final i = await repo.report(
          bookingId: _uuidBooking, category: IncidentCategory.tecnico, description: '  Se cayó la llamada. ',
          actorId: 'id-que-se-ignora');
      expect(server.lastReport, [_uuidBooking, 'tecnico', 'Se cayó la llamada.']);
      expect(i.status, IncidentStatus.pendienteRevision);
      expect(i.reportedBy, _uuidStudent); // auth.uid() del servidor
      server.error = 'TU031';
      await expectLater(
          repo.report(bookingId: _uuidBooking, category: IncidentCategory.otro, description: 'Fuera de plazo ya.'),
          _fails(reportWindowClosedMessage));
      // Validación previa: no llama al servidor con datos inválidos.
      server.error = null;
      final calls = server.calls;
      await expectLater(
          repo.report(bookingId: _uuidBooking, category: IncidentCategory.otro, description: 'corto'),
          _fails(invalidIncidentMessage));
      expect(server.calls, calls);
    });

    test('las partes no reciben notas internas', () async {
      final events = await RemoteIncidentRepository(server).getEvents(_uuidIncident);
      expect(events.any((e) => e.internal), isFalse);
      final adminEvents = await RemoteAdminIncidentRepository(server).getEvents(_uuidIncident);
      expect(adminEvents.where((e) => e.internal), hasLength(1));
    });

    test('administración: errores del servidor', () async {
      final admin = RemoteAdminIncidentRepository(server);
      server.error = 'TU034';
      await expectLater(admin.resolve(_uuidIncident, 'Resuelto ya.'), _fails(incidentNotFoundMessage));
      server.error = 'TU035';
      await expectLater(admin.dismiss(_uuidIncident, 'No procede.'), _fails(incidentTransitionMessage));
      server.error = null;
      final resolved = await admin.resolve(_uuidIncident, ' Resuelto con ambos. ');
      expect(server.lastAdmin, ['resolve', _uuidIncident, 'Resuelto con ambos.']);
      expect(resolved.status, IncidentStatus.resuelta);
    });

    test('reseñas: públicas sin estudiante; errores; promedio solo del servidor', () async {
      final repo = RemoteReviewRepository(server);
      final public = await repo.getForTutor(_uuidTutor);
      expect(public.single.studentId, isNull);
      expect(public.single.bookingId, isNull);
      final r = await repo.submit(bookingId: _uuidBooking, rating: 5, comment: '  ', actorId: 'ignorado');
      expect(server.lastReview, [_uuidBooking, 5, null]);
      expect(r.studentId, _uuidStudent);
      for (final code in ['TU040', 'TU041', 'TU042', 'TU043', 'TU044', 'TU045']) {
        server.error = code;
        await expectLater(repo.submit(bookingId: _uuidBooking, rating: 4), throwsA(isA<RepositoryException>()));
      }
      server.error = '23505';
      await expectLater(repo.submit(bookingId: _uuidBooking, rating: 4), _fails(alreadyReviewedMessage));
      server.error = null;
      await expectLater(repo.submit(bookingId: _uuidBooking, rating: 7), _fails(invalidRatingMessage));
    });

    test('notificaciones: consulta inicial, Realtime y marcar leídas con la función', () async {
      final repo = RemoteNotificationRepository(server);
      final store = NotificationStore(repo);
      await store.load(_uuidStudent);
      expect(store.unreadCount, 1);
      expect(store.items.single.type, NotificationType.reservaAceptada);

      server.addNotification(); // llega por Realtime
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(store.unreadCount, 2);

      await store.markRead(store.items.first.id);
      expect(server.lastMarked, [store.items.first.id]);
      await store.markAllRead();
      expect(server.lastMarked, isNull); // null = todas las propias
      expect(store.unreadCount, 0);
      expect(await repo.markRead(_uuidStudent, ['nt-local']), 0); // ids no uuid no viajan
      store.dispose();
    });
  });

  testWidgets('«Nuevo» en vez de 0.0 cuando no hay reseñas', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RatingLabel(rating: null, count: 0),
          RatingLabel(rating: 4.5, count: 2),
        ]),
      ),
    ));
    expect(find.text('Nuevo'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.text('4.5'), findsOneWidget);
    expect(find.text('(2)'), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// Servidor simulado (funciones y RLS de las migraciones 20, 22 y 23)
// ---------------------------------------------------------------------------

const _uuidStudent = '00000000-0000-4000-8000-0000000000a1';
const _uuidBooking = '20000000-0000-4000-9000-000000000001';
const _uuidIncident = '30000000-0000-4000-9000-000000000001';
const _uuidTutor = '10000000-0000-4000-9000-000000000001';
const _now = '2026-11-09T18:00:00Z';

class _FakeFollowUp implements FollowUpRowsSource {
  String? error;
  int calls = 0;
  List<Object?>? lastReport;
  List<Object?>? lastAdmin;
  List<Object?>? lastReview;
  List<String>? lastMarked = const ['sin llamar'];
  String incidentStatus = 'pendiente_revision';
  final StreamController<void> realtime = StreamController<void>.broadcast();
  final List<Map<String, dynamic>> notifications = [
    {
      'id': '40000000-0000-4000-9000-000000000001',
      'recipient_id': _uuidStudent,
      'type': 'reserva_aceptada',
      'booking_id': _uuidBooking,
      'incident_id': null,
      'event_key': 'booking:$_uuidBooking:aceptada',
      'read_at': null,
      'created_at': _now,
    },
  ];

  Future<void> _check() async {
    calls++;
    final code = error;
    if (code != null) throw PostgrestException(message: 'texto del servidor', code: code);
  }

  Map<String, dynamic> get _incident => {
        'id': _uuidIncident,
        'booking_id': _uuidBooking,
        'university_id': 'u',
        'reported_by': _uuidStudent,
        'reporter_party': 'estudiante',
        'category': 'tecnico',
        'description': 'Se cayó la llamada.',
        'status': incidentStatus,
        'resolution_note': incidentStatus == 'resuelta' ? 'Resuelto con ambos.' : null,
        'resolved_at': incidentStatus == 'resuelta' ? _now : null,
        'created_at': _now,
      };

  void addNotification() {
    notifications.insert(0, {
      ...notifications.last,
      'id': '40000000-0000-4000-9000-00000000000${notifications.length + 1}',
      'type': 'confirmacion_pendiente',
      'event_key': 'booking:$_uuidBooking:pendiente_confirmacion',
      'read_at': null,
    });
    realtime.add(null);
  }

  @override
  Future<String> reportIncident(String bookingId, String category, String description) async {
    await _check();
    lastReport = [bookingId, category, description];
    return _uuidIncident;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchIncidentsForBooking(String bookingId) async => [_incident];

  @override
  Future<List<Map<String, dynamic>>> fetchIncidents({String? status}) async => [_incident];

  @override
  Future<Map<String, dynamic>?> fetchIncident(String id) async => _incident;

  @override
  Future<List<Map<String, dynamic>>> fetchIncidentEvents(String incidentId) async => [
        {
          'id': 'e1', 'incident_id': incidentId, 'event': 'reportada', 'from_status': null, 'to_status': null,
          'note': null, 'internal': false, 'actor_id': _uuidStudent, 'created_at': _now,
        },
        // Para un administrador la RLS incluye la nota interna; la app la filtra
        // además en el repositorio de las partes.
        {
          'id': 'e2', 'incident_id': incidentId, 'event': 'nota', 'from_status': null, 'to_status': null,
          'note': 'interna', 'internal': true, 'actor_id': 'admin', 'created_at': _now,
        },
      ];

  @override
  Future<void> adminStartInvestigation(String incidentId, String? note) async {
    await _check();
    lastAdmin = ['start', incidentId, note];
    incidentStatus = 'en_investigacion';
  }

  @override
  Future<void> adminAddNote(String incidentId, String note) async {
    await _check();
    lastAdmin = ['note', incidentId, note];
  }

  @override
  Future<void> adminResolve(String incidentId, String resolution) async {
    await _check();
    lastAdmin = ['resolve', incidentId, resolution];
    incidentStatus = 'resuelta';
  }

  @override
  Future<void> adminDismiss(String incidentId, String resolution) async {
    await _check();
    lastAdmin = ['dismiss', incidentId, resolution];
    incidentStatus = 'desestimada';
  }

  static const Map<String, dynamic> _review = {
    'id': '50000000-0000-4000-9000-000000000001',
    'booking_id': _uuidBooking,
    'tutor_profile_id': _uuidTutor,
    'student_id': _uuidStudent,
    'rating': 5,
    'comment': null,
    'created_at': _now,
  };

  @override
  Future<String> submitReview(String bookingId, int rating, String? comment) async {
    await _check();
    lastReview = [bookingId, rating, comment];
    return _review['id'] as String;
  }

  /// Vista public_reviews: sin student_id ni booking_id.
  @override
  Future<List<Map<String, dynamic>>> fetchPublicReviews(String tutorProfileId) async => [
        {for (final e in _review.entries) if (e.key != 'student_id' && e.key != 'booking_id') e.key: e.value},
      ];

  @override
  Future<Map<String, dynamic>?> fetchReviewForBooking(String bookingId) async => {..._review};

  @override
  Future<Map<String, dynamic>?> fetchReview(String id) async => {..._review};

  @override
  Future<List<Map<String, dynamic>>> fetchNotifications() async => [for (final n in notifications) {...n}];

  @override
  Future<int> markNotificationsRead(List<String>? ids) async {
    lastMarked = ids;
    var count = 0;
    for (final n in notifications) {
      if (n['read_at'] == null && (ids == null || ids.contains(n['id']))) {
        n['read_at'] = _now;
        count++;
      }
    }
    return count;
  }

  @override
  Stream<void> notificationChanges() => realtime.stream;
}
