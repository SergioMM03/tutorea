import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/state/booking_store.dart';
import 'package:tutorea/state/tutor_store.dart';

/// Próximo [weekday] (1 = lunes) a la hora indicada, siempre en el futuro.
DateTime nextWeekday(int weekday, int hour) {
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

  TutorStore newTutorStore() =>
      TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities);

  List<String> names(List<TutorSummary> tutors) => [for (final t in tutors) t.nombre];

  group('Búsqueda', () {
    test('por nombre (sin distinguir mayúsculas ni tildes)', () async {
      final store = newTutorStore();
      await store.loadForUniversity('esen');
      expect(store.searchResults.length, 5);

      store.search('vale');
      expect(names(store.searchResults), ['Valeria Gómez']);
      store.search('GOMEZ');
      expect(names(store.searchResults), ['Valeria Gómez']);
      store.search('andrés');
      expect(names(store.searchResults), ['Andrés Martínez']);
    });

    test('por materia que imparte el tutor', () async {
      final store = newTutorStore();
      await store.loadForUniversity('esen');

      store.search('finanzas');
      expect(names(store.searchResults), ['Daniel Rivas']);
      store.search('estadistica'); // sin tilde
      expect(names(store.searchResults), ['Valeria Gómez']);
      store.search('program');
      expect(names(store.searchResults), ['Sofía Hernández']);
    });

    test('combina texto, categoría y carrera; limpiar quita todo', () async {
      final store = newTutorStore();
      await store.loadForUniversity('esen');

      await store.filterByCategory('Matemáticas'); // Valeria y Andrés
      expect(names(store.searchResults)..sort(), ['Andrés Martínez', 'Valeria Gómez']);

      store.search('andres');
      expect(names(store.searchResults), ['Andrés Martínez']);

      store.search('');
      store.filterByCareer(LocalSeed.eyn); // de esos, solo Valeria da materias de EyN
      expect(names(store.searchResults), ['Valeria Gómez']);

      store.search('andres'); // Andrés no da materias de EyN
      expect(store.searchResults, isEmpty);
      expect(store.hasSearchOrFilters, isTrue);

      await store.clearSearch();
      expect(store.hasSearchOrFilters, isFalse);
      expect(store.searchResults.length, 5);
    });

    test('solo carreras con materias propias se ofrecen como filtro', () async {
      final store = newTutorStore();
      await store.loadForUniversity('esen');
      final ids = store.careers.map((c) => c.id).toList();
      expect(ids, containsAll([LocalSeed.eyn, LocalSeed.ingNegocios, LocalSeed.software]));
      expect(ids, isNot(contains(LocalSeed.juridicas))); // sin materias propias
    });

    test('no muestra tutores de otras universidades', () async {
      // Un tutor de otra universidad que también imparte Estadística.
      final other = await repos.auth.register(
        nombre: 'Tutor Externo',
        correo: 'externo@otra.edu',
        password: 'tutorea123',
        universityId: 'otra-u',
        careerId: 'otra-u-eco',
        carrera: 'Economía',
        anioAcademico: 3,
        rol: UserRole.tutor,
      );
      await repos.tutors.save(TutorProfile(
        id: 'tp-externo',
        userId: other.id,
        universityId: 'otra-u',
        descripcion: 'Tutor de otra universidad.',
        precioHora: 8,
        materias: const ['est'],
        disponibilidad: const [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 720)],
      ));

      final store = newTutorStore();
      await store.loadForUniversity('esen');
      expect(names(store.searchResults), isNot(contains('Tutor Externo')));
      store.search('externo');
      expect(store.searchResults, isEmpty);
      store.search('estadística');
      expect(names(store.searchResults), ['Valeria Gómez']);

      await store.loadForUniversity('otra-u');
      expect(names(store.availableTutors), ['Tutor Externo']);
    });
  });

  group('Cancelación', () {
    late BookingStore student;
    late Booking pending;
    late Booking accepted;

    setUp(() async {
      student = BookingStore(repos.bookings);
      pending = (await student.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-valeria',
        subjectId: 'est',
        fechaHora: nextWeekday(DateTime.tuesday, 10),
        duracion: 60,
      ))!;
      accepted = (await student.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-daniel',
        subjectId: 'fin',
        fechaHora: nextWeekday(DateTime.monday, 10),
        duracion: 60,
      ))!;
      await repos.bookings.updateStatus(accepted.id, BookingStatus.aceptada);
      await student.loadForStudent('u-sergio');
    });

    test('cancela una solicitud pendiente y actualiza las listas', () async {
      expect(await student.cancel(pending.id), isTrue);
      expect(student.studentBookingById(pending.id)?.estado, BookingStatus.cancelada);
      expect(student.studentUpcoming.map((b) => b.id), isNot(contains(pending.id)));
      expect(student.studentHistory.map((b) => b.id), contains(pending.id));
    });

    test('no permite cancelar estados no autorizados', () async {
      // Aceptada: el modelo no permite cambiarla.
      expect(await student.cancel(accepted.id), isFalse);
      expect(student.error, contains('aceptada'));
      expect(student.studentBookingById(accepted.id)?.estado, BookingStatus.aceptada);

      // Ya cancelada: no se cancela dos veces.
      expect(await student.cancel(pending.id), isTrue);
      expect(await student.cancel(pending.id), isFalse);
      expect(student.error, isNotNull);

      // Rechazada.
      final other = (await student.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-valeria',
        subjectId: 'mat',
        fechaHora: nextWeekday(DateTime.tuesday, 14),
        duracion: 60,
      ))!;
      await repos.bookings.updateStatus(other.id, BookingStatus.rechazada);
      await student.loadForStudent('u-sergio');
      expect(await student.cancel(other.id), isFalse);

      // El repositorio también lo bloquea (no basta con ocultar el botón).
      await expectLater(repos.bookings.updateStatus(accepted.id, BookingStatus.cancelada),
          throwsA(isA<RepositoryException>()));
    });

    test('no cancela solicitudes que no son del estudiante', () async {
      final otherStudent = BookingStore(repos.bookings);
      await otherStudent.loadForStudent('u-otro');
      expect(await otherStudent.cancel(pending.id), isFalse);
      expect(otherStudent.error, isNotNull);
    });

    test('la cancelación persiste después de reiniciar', () async {
      expect(await student.cancel(pending.id), isTrue);

      final prefs = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues(
          {for (final k in prefs.getKeys()) k: prefs.get(k)!});
      final reopened = await LocalRepositories.open();

      final afterRestart = BookingStore(reopened.bookings);
      await afterRestart.loadForStudent('u-sergio');
      expect(afterRestart.studentBookingById(pending.id)?.estado, BookingStatus.cancelada);
      expect(afterRestart.studentBookingById(accepted.id)?.estado, BookingStatus.aceptada);
    });
  });
}
