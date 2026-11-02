import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_booking_repository.dart';
import 'package:tutorea/data/local/local_database.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/local/local_tutor_repository.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/state/booking_store.dart';
import 'package:tutorea/state/session_store.dart';
import 'package:tutorea/state/tutor_store.dart';

/// Próximo [weekday] (1 = lunes) a la hora indicada, siempre en el futuro.
DateTime nextWeekday(int weekday, int hour) {
  var day = DateTime.now().add(const Duration(days: 1));
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day, hour);
}

/// Simula cerrar y volver a abrir la app: se crean repositorios nuevos
/// sobre los mismos datos guardados en shared_preferences.
Future<LocalRepositories> restartApp() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = <String, Object>{
    for (final key in prefs.getKeys()) key: prefs.get(key)!,
  };
  SharedPreferences.setMockInitialValues(saved);
  return LocalRepositories.open();
}

void main() {
  late LocalRepositories repos;
  late BookingStore student;
  late Booking forValeria1;
  late Booking forValeria2;
  late Booking forDaniel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repos = await LocalRepositories.open();
    student = BookingStore(repos.bookings);

    // Sergio envía 2 solicitudes a Valeria y 1 a Daniel.
    forValeria1 = (await student.createRequest(
      studentId: 'u-sergio',
      tutorId: 'tp-valeria',
      subjectId: 'est',
      tema: 'Distribuciones',
      fechaHora: nextWeekday(DateTime.tuesday, 10),
      duracion: 60,
    ))!;
    forValeria2 = (await student.createRequest(
      studentId: 'u-sergio',
      tutorId: 'tp-valeria',
      subjectId: 'mat',
      fechaHora: nextWeekday(DateTime.tuesday, 14),
      duracion: 90,
    ))!;
    forDaniel = (await student.createRequest(
      studentId: 'u-sergio',
      tutorId: 'tp-daniel',
      subjectId: 'fin',
      fechaHora: nextWeekday(DateTime.monday, 10),
      duracion: 60,
    ))!;
  });

  test('1. Un tutor inicia sesión con rol tutor y se carga su perfil', () async {
    final session = SessionStore(repos.auth, repos.universities);
    final tutors = TutorStore(repos.tutors, repos.subjects, repos.auth);

    // Desde la Fase 13.6 se inicia sesión con una universidad elegida.
    await session.loadUniversities();
    expect(await session.selectUniversity('esen'), isTrue);
    expect(
        await session.login(correo: 'valeria@esen.edu.sv', password: LocalSeed.demoPassword),
        isTrue);
    expect(session.isTutor, isTrue);

    await tutors.loadMyProfile(session.user!.id);
    expect(tutors.myProfile?.id, 'tp-valeria');

    await session.loadUsers([session.user!.id]);
    expect(session.universityName(session.user!.universityId), contains('ESEN'));
  });

  test('2. El tutor solo ve las solicitudes dirigidas a su cuenta', () async {
    final valeria = BookingStore(repos.bookings);
    await valeria.loadForTutor('tp-valeria');
    expect(valeria.tutorRequests.map((b) => b.id),
        unorderedEquals([forValeria1.id, forValeria2.id]));
    expect(valeria.tutorRequests.any((b) => b.id == forDaniel.id), isFalse);

    final daniel = BookingStore(repos.bookings);
    await daniel.loadForTutor('tp-daniel');
    expect(daniel.tutorRequests.single.id, forDaniel.id);
  });

  test('3. Consulta pendientes y resuelve nombres sin mostrar ids', () async {
    final valeria = BookingStore(repos.bookings);
    await valeria.loadForTutor('tp-valeria');
    expect(valeria.pendingCount, 2);

    final session = SessionStore(repos.auth, repos.universities);
    await session.loadUsers(valeria.tutorRequests.map((b) => b.studentId));
    final studentUser = session.userById('u-sergio');
    expect(studentUser?.nombre, 'Sergio');
    expect(studentUser?.carrera, isNotEmpty);
    expect(session.universityName(studentUser!.universityId), contains('ESEN'));
  });

  test('4 y 5. Acepta una solicitud y rechaza otra', () async {
    final valeria = BookingStore(repos.bookings);
    await valeria.loadForTutor('tp-valeria');

    expect(await valeria.accept(forValeria1.id), isTrue);
    expect(await valeria.reject(forValeria2.id), isTrue);

    expect(valeria.tutorRequestsWith(BookingStatus.aceptada).single.id, forValeria1.id);
    expect(valeria.tutorRequestsWith(BookingStatus.rechazada).single.id, forValeria2.id);
    expect(valeria.pendingCount, 0);
  });

  test('6. No puede modificar solicitudes que ya no están pendientes', () async {
    final valeria = BookingStore(repos.bookings);
    await valeria.loadForTutor('tp-valeria');
    await valeria.accept(forValeria1.id);
    await valeria.reject(forValeria2.id);

    expect(await valeria.reject(forValeria1.id), isFalse); // ya aceptada
    expect(valeria.error, isNotNull);
    expect(await valeria.accept(forValeria2.id), isFalse); // ya rechazada
    expect(valeria.error, isNotNull);

    // Cancelada por el estudiante: el tutor ya no puede aceptarla.
    final daniel = BookingStore(repos.bookings);
    expect(await student.cancel(forDaniel.id), isTrue);
    await daniel.loadForTutor('tp-daniel');
    expect(await daniel.accept(forDaniel.id), isFalse);

    // Los estados no cambiaron.
    await valeria.loadForTutor('tp-valeria');
    expect(valeria.tutorRequestsWith(BookingStatus.aceptada).single.id, forValeria1.id);
    expect(valeria.tutorRequestsWith(BookingStatus.rechazada).single.id, forValeria2.id);
  });

  test('7. El estudiante ve el estado actualizado en sus reservas', () async {
    final valeria = BookingStore(repos.bookings);
    await valeria.loadForTutor('tp-valeria');
    await valeria.accept(forValeria1.id);
    await valeria.reject(forValeria2.id);

    await student.loadForStudent('u-sergio');
    Booking find(String id) => student.studentBookings.firstWhere((b) => b.id == id);
    expect(find(forValeria1.id).estado, BookingStatus.aceptada);
    expect(find(forValeria2.id).estado, BookingStatus.rechazada);
    expect(student.studentUpcoming.map((b) => b.id), contains(forValeria1.id));
    expect(student.studentHistory.map((b) => b.id), contains(forValeria2.id));
  });

  test('8. Los cambios persisten después de reiniciar la app', () async {
    final valeria = BookingStore(repos.bookings);
    await valeria.loadForTutor('tp-valeria');
    await valeria.accept(forValeria1.id);
    await valeria.reject(forValeria2.id);

    final reopened = await restartApp();
    final afterRestart = BookingStore(reopened.bookings);
    await afterRestart.loadForTutor('tp-valeria');
    expect(afterRestart.tutorRequestsWith(BookingStatus.aceptada).single.id, forValeria1.id);
    expect(afterRestart.tutorRequestsWith(BookingStatus.rechazada).single.id, forValeria2.id);

    final studentAfter = BookingStore(reopened.bookings);
    await studentAfter.loadForStudent('u-sergio');
    expect(studentAfter.studentBookings.length, 3);
  });

  test('No se puede aceptar una solicitud cuya fecha y hora ya pasaron', () async {
    final db = await LocalDatabase.open();
    final tutorsRepo = LocalTutorRepository(db);
    final start = nextWeekday(DateTime.thursday, 10);

    // Se creó cuando aún era futura...
    final before = LocalBookingRepository(db, tutorsRepo,
        now: () => start.subtract(const Duration(days: 1)));
    final created = await before.create(Booking(
      id: 'bk-pasada',
      studentId: 'u-sergio',
      tutorId: 'tp-valeria',
      subjectId: 'mic',
      fechaHora: start,
      duracion: 60,
      precio: 0,
    ));

    // ...y el tutor intenta aceptarla cuando ya pasó.
    final after = LocalBookingRepository(db, tutorsRepo,
        now: () => start.add(const Duration(hours: 1)));
    final valeria = BookingStore(after);
    await valeria.loadForTutor('tp-valeria');
    expect(await valeria.accept(created.id), isFalse);
    expect(valeria.error, contains('ya pasaron'));
    expect(valeria.tutorRequests.firstWhere((b) => b.id == created.id).estado,
        BookingStatus.pendiente);

    // Las demás reglas no cambian: rechazarla sí está permitido.
    expect(await valeria.reject(created.id), isTrue);
  });

  test('Rechazadas y canceladas se distinguen', () async {
    final valeria = BookingStore(repos.bookings);
    expect(await student.cancel(forValeria1.id), isTrue); // la cancela el estudiante
    await valeria.loadForTutor('tp-valeria');
    expect(await valeria.reject(forValeria2.id), isTrue); // la rechaza el tutor

    expect(valeria.tutorRequestsWith(BookingStatus.cancelada).single.id, forValeria1.id);
    expect(valeria.tutorRequestsWith(BookingStatus.rechazada).single.id, forValeria2.id);
    expect(BookingStatus.cancelada.label, 'Cancelada');
    expect(BookingStatus.rechazada.label, 'Rechazada');
  });

}
