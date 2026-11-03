import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/state/booking_store.dart';

// Fase 14.8 en modo local: mismas reglas de estados, modalidad, duración y
// cancelación que el servidor (el modo local sigue funcionando sin Supabase).

DateTime _next(int weekday, int hour) {
  var day = DateTime.now().add(const Duration(days: 1));
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day, hour);
}

void main() {
  late LocalRepositories repos;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repos = await LocalRepositories.open();
  });

  group('estados', () {
    test('transiciones permitidas y finales', () {
      expect(BookingStatus.pendiente.puedeCambiarA(BookingStatus.cancelada), isTrue);
      expect(BookingStatus.aceptada.puedeCambiarA(BookingStatus.cancelada), isTrue);
      expect(BookingStatus.aceptada.puedeCambiarA(BookingStatus.pendienteConfirmacion), isTrue);
      expect(BookingStatus.pendienteConfirmacion.puedeCambiarA(BookingStatus.completada), isTrue);
      expect(BookingStatus.rechazada.puedeCambiarA(BookingStatus.aceptada), isFalse);
      expect(BookingStatus.cancelada.puedeCambiarA(BookingStatus.aceptada), isFalse);
      expect(BookingStatus.completada.puedeCambiarA(BookingStatus.cancelada), isFalse);
      for (final s in [BookingStatus.rechazada, BookingStatus.cancelada, BookingStatus.completada]) {
        expect(s.esFinal, isTrue);
      }
    });

    test('nombres de la base de datos', () {
      expect(BookingStatus.pendienteConfirmacion.dbValue, 'pendiente_confirmacion');
      expect(BookingStatus.fromJson('pendiente_confirmacion'), BookingStatus.pendienteConfirmacion);
      expect(BookingStatus.fromJson('pendienteConfirmacion'), BookingStatus.pendienteConfirmacion);
      expect(() => BookingStatus.fromJson('inventado'), throwsFormatException);
    });

    test('reservas locales guardadas antes de 14.8 se siguen leyendo', () {
      final old = Booking.fromJson({
        'id': 'bk-1', 'studentId': 'u-sergio', 'tutorId': 'tp-valeria', 'subjectId': 'est',
        'tema': null, 'fechaHora': '2026-11-10T10:00:00.000', 'duracion': 60, 'precio': 10.0,
        'estado': 'aceptada',
      });
      expect(old.modalidad, isNull);
      expect(old.motivoCancelacion, isNull);
      final copy = Booking.fromJson(old.copyWith(
        estado: BookingStatus.cancelada, canceladaPor: 'u-sergio', motivoCancelacion: 'Examen',
      ).toJson());
      expect(copy.estado, BookingStatus.cancelada);
      expect(copy.motivoCancelacion, 'Examen');
    });
  });

  group('solicitar (local)', () {
    Booking draft({int duracion = 60, TutoringModality? modalidad = TutoringModality.presencial}) => Booking(
          id: 'bk-x',
          studentId: 'u-sergio',
          tutorId: 'tp-valeria',
          subjectId: 'est',
          fechaHora: _next(DateTime.tuesday, 10),
          duracion: duracion,
          precio: 0,
          modalidad: modalidad,
          ubicacion: '  Biblioteca  ',
        );

    test('guarda modalidad y lugar; solo 60, 90 o 120 minutos', () async {
      final saved = await repos.bookings.create(draft());
      expect(saved.modalidad, TutoringModality.presencial);
      expect(saved.ubicacion, 'Biblioteca');
      await expectLater(repos.bookings.create(draft(duracion: 45)), throwsA(isA<RepositoryException>()));
    });

    test('no acepta una modalidad que el tutor no ofrece', () async {
      final valeria = (await repos.tutors.getById('tp-valeria'))!;
      await repos.tutors.save(valeria.copyWith(ofreceVirtual: false));
      await expectLater(
          repos.bookings.create(draft(modalidad: TutoringModality.virtual)),
          throwsA(isA<RepositoryException>()
              .having((e) => e.message, 'message', 'El tutor no ofrece esa modalidad.')));
    });
  });

  group('aceptar (local): misma regla de disponibilidad que el servidor', () {
    late BookingStore student;
    late BookingStore tutor;
    late TutorProfile original;

    setUp(() async {
      student = BookingStore(repos.bookings);
      tutor = BookingStore(repos.bookings);
      original = (await repos.tutors.getById('tp-valeria'))!;
    });

    Future<Booking> request(int hour, int minutes, {String subject = 'est'}) async => (await student.createRequest(
          studentId: 'u-sergio',
          tutorId: 'tp-valeria',
          subjectId: subject,
          fechaHora: _next(DateTime.tuesday, hour),
          duracion: minutes,
          modalidad: TutoringModality.presencial,
        ))!;

    Future<void> setTuesday(List<AvailabilitySlot> slots) async {
      await repos.tutors.save(original.copyWith(disponibilidad: [
        for (final s in original.disponibilidad)
          if (s.diaSemana != DateTime.tuesday) s,
        ...slots,
      ]));
      await tutor.loadForTutor('tp-valeria');
    }

    test('acepta si sigue dentro; no si el tutor acortó, movió o borró el horario', () async {
      final ok = await request(9, 60);
      final long = await request(11, 120); // 11:00–13:00
      final moved = await request(16, 60, subject: 'mat');
      final removed = await request(18, 60, subject: 'mic');

      // Martes ahora: 08–12 y 14–17 (antes 08–20).
      await setTuesday(const [
        AvailabilitySlot(diaSemana: DateTime.tuesday, horaInicio: 480, horaFin: 720),
        AvailabilitySlot(diaSemana: DateTime.tuesday, horaInicio: 840, horaFin: 1020),
      ]);
      expect(await tutor.accept(ok.id), isTrue);
      expect(await tutor.accept(long.id), isFalse); // la duración ya no cabe
      expect(tutor.error, availabilityChangedMessage);
      expect(await tutor.accept(removed.id), isFalse); // 18:00 ya no existe
      expect(tutor.error, availabilityChangedMessage);

      // Mueve la tarde a 13–15: la de 16:00 queda fuera.
      await setTuesday(const [
        AvailabilitySlot(diaSemana: DateTime.tuesday, horaInicio: 480, horaFin: 720),
        AvailabilitySlot(diaSemana: DateTime.tuesday, horaInicio: 780, horaFin: 900),
      ]);
      expect(await tutor.accept(moved.id), isFalse);
      expect(tutor.error, availabilityChangedMessage);
      expect((await repos.bookings.getForTutor('tp-valeria')).where((b) => b.estado == BookingStatus.pendiente),
          hasLength(3));
    });
  });

  group('cancelar (local)', () {
    late BookingStore student;
    late BookingStore tutor;
    late Booking accepted;

    setUp(() async {
      student = BookingStore(repos.bookings);
      accepted = (await student.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-valeria',
        subjectId: 'est',
        fechaHora: _next(DateTime.tuesday, 10),
        duracion: 60,
        modalidad: TutoringModality.virtual,
        ubicacion: 'https://meet.example/abc',
      ))!;
      tutor = BookingStore(repos.bookings);
      await tutor.loadForTutor('tp-valeria');
      expect(await tutor.accept(accepted.id), isTrue);
      await student.loadForStudent('u-sergio');
    });

    test('el tutor cancela una aceptada con motivo', () async {
      expect(await tutor.cancel(accepted.id, actorId: 'u-valeria'), isFalse);
      expect(tutor.error, cancelReasonRequiredMessage);
      expect(await tutor.cancel(accepted.id, motivo: 'Se me cruzó un examen', actorId: 'u-valeria'), isTrue);
      final saved = (await repos.bookings.getForStudent('u-sergio')).single;
      expect(saved.estado, BookingStatus.cancelada);
      expect(saved.canceladaPor, 'u-valeria');
      expect(saved.motivoCancelacion, 'Se me cruzó un examen');
      expect(saved.canceladaEn, isNotNull);
    });

    test('el estudiante cancela una aceptada con motivo', () async {
      expect(await student.cancel(accepted.id, motivo: 'Ya entendí el tema'), isTrue);
      final saved = student.studentBookingById(accepted.id)!;
      expect(saved.canceladaPor, 'u-sergio');
      expect(student.studentHistory.map((b) => b.id), contains(accepted.id));
    });

    test('el tutor no cancela una pendiente (la rechaza)', () async {
      final pending = (await student.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-valeria',
        subjectId: 'mat',
        fechaHora: _next(DateTime.wednesday, 10),
        duracion: 60,
        modalidad: TutoringModality.presencial,
      ))!;
      await tutor.loadForTutor('tp-valeria');
      expect(await tutor.cancel(pending.id, motivo: 'No puedo'), isFalse);
      expect(await tutor.reject(pending.id), isTrue);
    });

    test('una aceptada que ya empezó no se cancela', () async {
      final late0 = BookingStore(repos.bookings, now: () => accepted.fechaHora.add(const Duration(minutes: 5)));
      await late0.loadForStudent('u-sergio');
      expect(await late0.cancel(accepted.id, motivo: 'Tarde'), isFalse);
      expect(late0.error, contains('ya empezó'));
    });
  });
}
