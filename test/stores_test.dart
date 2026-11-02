import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/state/booking_store.dart';
import 'package:tutorea/state/session_store.dart';
import 'package:tutorea/state/tutor_store.dart';

void main() {
  late LocalRepositories repos;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repos = await LocalRepositories.open();
  });

  test('SessionStore: login inválido, login válido, rol y logout', () async {
    final session = SessionStore(repos.auth);
    await session.load();
    expect(session.isLoggedIn, isFalse);

    expect(await session.login(correo: 'sergio@esen.edu.sv', password: 'mala'), isFalse);
    expect(session.error, isNotNull);

    expect(
        await session.login(correo: 'sergio@esen.edu.sv', password: LocalSeed.demoPassword),
        isTrue);
    expect(session.isStudent, isTrue);
    expect(session.user?.nombre, 'Sergio');

    await session.logout();
    expect(session.isLoggedIn, isFalse);
  });

  test('TutorStore: lista, filtros y nombres resueltos', () async {
    final tutors = TutorStore(repos.tutors, repos.subjects, repos.auth);
    await tutors.loadAvailable();
    expect(tutors.availableTutors.length, 5);
    expect(tutors.availableTutors.first.nombre, isNotEmpty);
    expect(tutors.categories, contains('Economía'));

    await tutors.filterBySubject('est');
    expect(tutors.availableTutors.single.nombre, 'Valeria Gómez');
    expect(tutors.availableTutors.single.subjects.first.nombre, 'Estadística');

    await tutors.filterByCategory(null);
    expect(tutors.availableTutors.length, 5);
  });

  test('BookingStore: el estudiante solicita y el tutor acepta', () async {
    final student = BookingStore(repos.bookings);
    final tutor = BookingStore(repos.bookings);

    // Un martes futuro a las 10:00 (Valeria atiende de lunes a sábado).
    var day = DateTime.now().add(const Duration(days: 1));
    while (day.weekday != DateTime.tuesday) {
      day = day.add(const Duration(days: 1));
    }
    final when = DateTime(day.year, day.month, day.day, 10);

    final created = await student.createRequest(
      studentId: 'u-sergio',
      tutorId: 'tp-valeria',
      subjectId: 'est',
      fechaHora: when,
      duracion: 90,
    );
    expect(created, isNotNull);
    expect(created!.precio, 15);
    expect(student.studentUpcoming.length, 1);

    await tutor.loadForTutor('tp-valeria');
    expect(tutor.pendingCount, 1);
    expect(await tutor.accept(created.id), isTrue);
    expect(tutor.tutorRequestsWith(BookingStatus.aceptada).length, 1);

    await student.loadForStudent('u-sergio');
    expect(student.studentBookings.single.estado, BookingStatus.aceptada);

    // No se puede cancelar una solicitud ya aceptada.
    expect(await student.cancel(created.id), isFalse);
    expect(student.error, isNotNull);
  });
}
