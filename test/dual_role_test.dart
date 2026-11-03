import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/main.dart';
import 'package:tutorea/routes/app_navigator.dart';
import 'package:tutorea/state/app_providers.dart';
import 'package:tutorea/state/booking_store.dart';
import 'package:tutorea/state/session_store.dart';
import 'package:tutorea/state/tutor_store.dart';

// Corrección de la Fase 14.7: una misma cuenta puede ser estudiante y tutor.
// Ofrecer tutorías = tener TutorProfile; el rol principal no cambia.

/// Próximo [weekday] (1 = lunes) a la hora indicada, siempre en el futuro.
DateTime _next(int weekday, int hour) {
  var day = DateTime.now().add(const Duration(days: 1));
  while (day.weekday != weekday) {
    day = day.add(const Duration(days: 1));
  }
  return DateTime(day.year, day.month, day.day, hour);
}

/// Pestaña de la barra inferior (el título de la pantalla puede repetir el texto).
Finder _navTab(String label) =>
    find.descendant(of: find.byType(BottomNavigationBar), matching: find.text(label));

/// Hace scroll en la lista de la pantalla hasta [target] (las listas se construyen
/// a medida que aparecen), lo deja completo en pantalla y lo toca.
Future<void> _tapInList(WidgetTester tester, Finder target) async {
  final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(target, 200, scrollable: list);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

TutorProfile _sergioTutor() => const TutorProfile(
      id: 'tp-sergio',
      userId: 'u-sergio',
      descripcion: 'Estudiante de segundo año; explico Estadística.',
      precioHora: 8,
      materias: ['est'],
      disponibilidad: [AvailabilitySlot(diaSemana: 2, horaInicio: 480, horaFin: 720)],
      ofrecePresencial: false,
    );

void main() {
  late LocalRepositories repos;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repos = await LocalRepositories.open();
  });

  Future<SessionStore> loginAs(String correo) async {
    final session = SessionStore(repos.auth, repos.universities);
    await session.loadUniversities();
    expect(await session.selectUniversity('esen'), isTrue);
    expect(await session.login(correo: correo, password: LocalSeed.demoPassword), isTrue);
    return session;
  }

  group('Doble rol (lógica)', () {
    test('un estudiante crea su perfil de tutor sin cambiar su rol principal', () async {
      final session = await loginAs('sergio@esen.edu.sv');
      expect(session.isStudent, isTrue);
      final tutors = TutorStore(repos.tutors, repos.subjects, repos.auth);

      await tutors.loadMyProfile('u-sergio');
      expect(tutors.myProfile, isNull);
      expect(await tutors.saveProfile(_sergioTutor()), isTrue);
      expect(tutors.myProfile?.userId, 'u-sergio');
      expect(session.isStudent, isTrue); // sigue siendo estudiante
      expect((await repos.auth.getUserById('u-sergio'))!.rol, UserRole.estudiante);
      expect((await repos.tutors.getByUserId('u-sergio'))?.id, 'tp-sergio');
    });

    test('administra sus materias y su disponibilidad', () async {
      await loginAs('sergio@esen.edu.sv');
      final tutors = TutorStore(repos.tutors, repos.subjects, repos.auth);
      await tutors.saveProfile(_sergioTutor());

      final updated = tutors.myProfile!.copyWith(
        materias: ['mic', 'mac'],
        disponibilidad: const [
          AvailabilitySlot(diaSemana: 1, horaInicio: 600, horaFin: 720),
          AvailabilitySlot(diaSemana: 4, horaInicio: 840, horaFin: 960),
        ],
      );
      expect(await tutors.saveProfile(updated), isTrue);
      final saved = (await repos.tutors.getByUserId('u-sergio'))!;
      expect(saved.materias, ['mic', 'mac']);
      expect(saved.disponibilidad.map((s) => s.diaSemana), [1, 4]);

      // Las mismas reglas que para cualquier tutor.
      final crossed = saved.copyWith(disponibilidad: const [
        AvailabilitySlot(diaSemana: 1, horaInicio: 600, horaFin: 720),
        AvailabilitySlot(diaSemana: 1, horaInicio: 660, horaFin: 780),
      ]);
      expect(await tutors.saveProfile(crossed), isFalse);
      expect(tutors.error, 'Hay horarios que se cruzan el mismo día.');
      expect((await repos.tutors.getByUserId('u-sergio'))!.disponibilidad, hasLength(2));
    });

    test('con perfil de tutor sigue solicitando tutorías a otros tutores', () async {
      await loginAs('sergio@esen.edu.sv');
      await TutorStore(repos.tutors, repos.subjects, repos.auth).saveProfile(_sergioTutor());
      final bookings = BookingStore(repos.bookings);

      final created = await bookings.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-valeria',
        subjectId: 'est',
        fechaHora: _next(DateTime.tuesday, 10),
        duracion: 60,
      );
      expect(created, isNotNull);
      expect(bookings.studentBookings.single.tutorId, 'tp-valeria');
    });

    test('una cuenta con rol principal tutor también solicita tutorías', () async {
      final session = await loginAs('valeria@esen.edu.sv');
      expect(session.isTutor, isTrue);
      final created = await BookingStore(repos.bookings).createRequest(
        studentId: 'u-valeria',
        tutorId: 'tp-daniel',
        subjectId: 'fin',
        fechaHora: _next(DateTime.monday, 10),
        duracion: 60,
      );
      expect(created, isNotNull);
    });

    test('otros lo encuentran, le solicitan tutorías y él las recibe como tutor', () async {
      await loginAs('sergio@esen.edu.sv');
      await TutorStore(repos.tutors, repos.subjects, repos.auth).saveProfile(_sergioTutor());

      final search = TutorStore(repos.tutors, repos.subjects, repos.auth);
      await search.loadForUniversity('esen');
      expect(search.availableTutors.map((t) => t.id), contains('tp-sergio'));

      final request = await BookingStore(repos.bookings).createRequest(
        studentId: 'u-valeria',
        tutorId: 'tp-sergio',
        subjectId: 'est',
        fechaHora: _next(DateTime.tuesday, 9),
        duracion: 60,
      );
      expect(request, isNotNull);

      final asTutor = BookingStore(repos.bookings);
      await asTutor.loadForTutor('tp-sergio');
      expect(asTutor.tutorRequests.single.studentId, 'u-valeria');
      expect(await asTutor.accept(request!.id), isTrue);
    });

    test('nadie se solicita una tutoría a su propio perfil', () async {
      await loginAs('sergio@esen.edu.sv');
      await TutorStore(repos.tutors, repos.subjects, repos.auth).saveProfile(_sergioTutor());
      final bookings = BookingStore(repos.bookings);

      final created = await bookings.createRequest(
        studentId: 'u-sergio',
        tutorId: 'tp-sergio',
        subjectId: 'est',
        fechaHora: _next(DateTime.tuesday, 10),
        duracion: 60,
      );
      expect(created, isNull);
      expect(bookings.error, selfBookingMessage);
      expect(await repos.bookings.getForTutor('tp-sergio'), isEmpty);
    });
  });

  group('Doble rol (pantallas)', () {
    testWidgets('el estudiante pasa a ofrecer tutorías y vuelve a buscar con la misma cuenta',
        (tester) async {
      await repos.universities.saveSelectedUniversityId('esen');
      await repos.auth.login(
          correo: 'sergio@esen.edu.sv', password: LocalSeed.demoPassword, universityId: 'esen');
      final session = await repos.auth.currentSession();
      await tester.pumpWidget(AppProviders.local(repos,
          child: TutoreaApp(initialRoute: AppNavigator.initialRouteFor(session))));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Sergio'), findsOneWidget);

      // Perfil (modo estudiante) → Ofrecer tutorías → Dashboard del tutor sin perfil.
      await tester.tap(_navTab('Perfil'));
      await tester.pumpAndSettle();
      await _tapInList(tester, find.byKey(const Key('to-tutor-space')));
      expect(find.text('Completa tu perfil de tutor'), findsOneWidget);

      // Mi perfil (modo tutor) → Buscar y solicitar tutorías → Inicio del estudiante.
      await tester.tap(_navTab('Mi perfil'));
      await tester.pumpAndSettle();
      await _tapInList(tester, find.byKey(const Key('to-student-space')));
      expect(find.text('Hola, Sergio'), findsOneWidget);
      expect(find.text('Tutores recomendados'), findsOneWidget);
    });

    testWidgets('un tutor con perfil ve el espacio de tutor y también puede ir a buscar tutorías',
        (tester) async {
      await repos.universities.saveSelectedUniversityId('esen');
      await repos.auth.login(
          correo: 'valeria@esen.edu.sv', password: LocalSeed.demoPassword, universityId: 'esen');
      final session = await repos.auth.currentSession();
      await tester.pumpWidget(AppProviders.local(repos,
          child: TutoreaApp(initialRoute: AppNavigator.initialRouteFor(session))));
      await tester.pumpAndSettle();
      expect(find.text('Completa tu perfil de tutor'), findsNothing); // ya tiene perfil

      await tester.tap(_navTab('Mi perfil'));
      await tester.pumpAndSettle();
      await _tapInList(tester, find.byKey(const Key('to-student-space')));
      expect(find.text('Tutores recomendados'), findsOneWidget);
    });
  });
}
