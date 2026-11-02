import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_database.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/main.dart';
import 'package:tutorea/routes/app_navigator.dart';
import 'package:tutorea/routes/routes.dart';
import 'package:tutorea/state/app_providers.dart';
import 'package:tutorea/state/session_store.dart';

const _esenName = 'Escuela Superior de Economía y Negocios (ESEN)';

/// Solo para pruebas: otra universidad activa y una inactiva, además de ESEN.
/// (La app real solo trae ESEN; no se agregan universidades ficticias al seed.)
const _testUniversity = University(id: 'uprueba', nombre: 'Universidad de Prueba (UP)', pais: 'El Salvador');
const _inactiveUniversity =
    University(id: 'uinactiva', nombre: 'Universidad Inactiva', pais: 'El Salvador', activo: false);
const _testCareer = Career(id: 'up-sistemas', universityId: 'uprueba', nombre: 'Sistemas');

Future<LocalRepositories> _openWith(List<University> universities) async {
  SharedPreferences.setMockInitialValues({});
  final repos = await LocalRepositories.open();
  final db = await LocalDatabase.open(); // misma base (ya cargada)
  await db.writeList(LocalDatabase.universities, [for (final u in universities) u.toJson()]);
  await db.writeList(LocalDatabase.careers, [
    for (final c in [...LocalSeed.careers, _testCareer]) c.toJson(),
  ]);
  return repos;
}

final _allUniversities = [...LocalSeed.universities, _testUniversity, _inactiveUniversity];

/// Cuenta de la Universidad de Prueba (sin sesión iniciada).
Future<void> _createTestUniversityAccount(LocalRepositories repos) async {
  await repos.auth.register(
    nombre: 'Ana Prueba',
    correo: 'ana@up.edu.sv',
    password: 'tutorea123',
    universityId: 'uprueba',
    careerId: 'up-sistemas',
    carrera: 'Sistemas',
    anioAcademico: 1,
    rol: UserRole.estudiante,
  );
  await repos.auth.logout();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find.widgetWithText(ElevatedButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _chooseUniversity(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump();
  await _tapButton(tester, 'Continuar');
}

Future<void> _fillLogin(WidgetTester tester, String correo) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), correo);
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'tutorea123');
  await _tapButton(tester, 'Iniciar sesión');
}

void main() {
  group('SessionStore: universidades', () {
    test('1-2. solo universidades activas', () async {
      final repos = await _openWith(_allUniversities);
      final session = SessionStore(repos.auth, repos.universities);
      await session.loadUniversities();
      final names = session.activeUniversities.map((u) => u.nombre).toList();
      expect(names, containsAll([_esenName, 'Universidad de Prueba (UP)']));
      expect(names, isNot(contains('Universidad Inactiva')));
      expect(await session.selectUniversity('uinactiva'), isFalse);
    });

    test('3. elegir ESEN se guarda y carga sus carreras', () async {
      final repos = await _openWith(_allUniversities);
      final session = SessionStore(repos.auth, repos.universities);
      await session.loadUniversities();
      expect(session.selectedUniversity, isNull);

      expect(await session.selectUniversity('esen'), isTrue);
      expect(session.selectedUniversity?.id, 'esen');
      expect(session.selectedUniversityCareers, isNotEmpty);
      expect(session.selectedUniversityCareers.every((c) => c.universityId == 'esen'), isTrue);

      // Otro SessionStore (como al reabrir la app) recupera la selección.
      final reopened = SessionStore(repos.auth, repos.universities);
      await reopened.loadUniversities();
      expect(reopened.selectedUniversity?.id, 'esen');
    });

    test('5. no se crea una cuenta sin universidad válida', () async {
      final repos = await _openWith(_allUniversities);
      final session = SessionStore(repos.auth, repos.universities);
      await session.loadUniversities();

      Future<bool> register(
              {String? universityId,
              String careerId = LocalSeed.software,
              String correo = 'x@esen.edu.sv'}) =>
          session.register(
            nombre: 'Nueva Cuenta',
            correo: correo,
            password: 'tutorea123',
            universityId: universityId,
            careerId: careerId,
            carrera: 'Carrera',
            anioAcademico: 1,
            rol: UserRole.estudiante,
          );

      expect(await register(), isFalse); // sin universidad elegida
      expect(session.error, contains('universidad'));
      expect(await register(universityId: 'uinactiva'), isFalse); // inactiva
      expect(await register(universityId: 'no-existe'), isFalse);

      await session.selectUniversity('esen');
      expect(await register(careerId: 'up-sistemas'), isFalse); // carrera de otra universidad
      expect(session.error, contains('carrera'));

      expect(await register(careerId: LocalSeed.software), isTrue);
      expect(session.user?.universityId, 'esen');
      expect(session.user?.careerId, LocalSeed.software);
    });

    test('6. no inicia sesión desde una universidad distinta a la de la cuenta', () async {
      final repos = await _openWith(_allUniversities);
      await _createTestUniversityAccount(repos);
      final session = SessionStore(repos.auth, repos.universities);
      await session.loadUniversities();

      // Sin universidad elegida.
      expect(await session.login(correo: 'ana@up.edu.sv', password: 'tutorea123'), isFalse);

      // ESEN elegida, cuenta de la Universidad de Prueba.
      await session.selectUniversity('esen');
      expect(await session.login(correo: 'ana@up.edu.sv', password: 'tutorea123'), isFalse);
      expect(session.universityMismatch, isTrue);
      expect(session.error, contains('otra universidad'));
      expect(session.isLoggedIn, isFalse);
      expect((await repos.auth.currentSession()).iniciada, isFalse); // no quedó sesión

      // La cuenta conserva su universidad.
      final users = await repos.auth.login(correo: 'ana@up.edu.sv', password: 'tutorea123');
      expect(users.universityId, 'uprueba');
      await repos.auth.logout();

      // Con su universidad sí entra; las cuentas de ESEN siguen funcionando.
      await session.selectUniversity('uprueba');
      expect(await session.login(correo: 'ana@up.edu.sv', password: 'tutorea123'), isTrue);
      await session.logout();
      await session.selectUniversity('esen');
      expect(
          await session.login(correo: 'sergio@esen.edu.sv', password: LocalSeed.demoPassword),
          isTrue);
    });
  });

  group('Pantalla inicial', () {
    testWidgets('1-4. muestra activas, elige ESEN y la conserva en Login y Registro',
        (tester) async {
      final repos = await _openWith(_allUniversities);
      await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
      await tester.pumpAndSettle();

      expect(find.text('Selecciona tu universidad'), findsOneWidget);
      expect(find.text(_esenName), findsOneWidget);
      expect(find.text('Universidad de Prueba (UP)'), findsOneWidget);
      expect(find.text('Universidad Inactiva'), findsNothing);

      // Sin elegir, "Continuar" está deshabilitado.
      final continuar = find.widgetWithText(ElevatedButton, 'Continuar');
      expect(tester.widget<ElevatedButton>(continuar).onPressed, isNull);

      await _chooseUniversity(tester, _esenName);
      expect(find.text('ESEN'), findsOneWidget); // Bienvenida con la universidad elegida

      // Login.
      await _tapButton(tester, 'Iniciar sesión');
      expect(find.text(_esenName), findsOneWidget);
      expect(find.text('Entra con tu cuenta de ESEN.'), findsOneWidget);

      // Login → Registro: misma universidad y solo sus carreras.
      final toRegister = find.text('¿No tienes cuenta? Crear cuenta');
      await tester.ensureVisible(toRegister);
      await tester.tap(toRegister);
      await tester.pumpAndSettle();
      expect(find.text(_esenName), findsOneWidget);
      final careerField = find.widgetWithText(DropdownButtonFormField<Career>, 'Carrera');
      await tester.ensureVisible(careerField);
      await tester.tap(careerField);
      await tester.pumpAndSettle();
      expect(find.text('Licenciatura en Economía y Negocios').last, findsOneWidget);
      expect(find.text('Sistemas'), findsNothing); // carrera de otra universidad
      await tester.tap(find.text('Licenciatura en Economía y Negocios').last);
      await tester.pumpAndSettle();

      // Registro → Login: la selección sigue.
      final toLogin = find.text('¿Ya tienes cuenta? Iniciar sesión');
      await tester.ensureVisible(toLogin);
      await tester.tap(toLogin);
      await tester.pumpAndSettle();
      expect(find.text(_esenName), findsOneWidget);
    });

    testWidgets('5. registro sin universidad: aviso y botón deshabilitado', (tester) async {
      final repos = await _openWith(_allUniversities);
      await tester.pumpWidget(AppProviders.local(
        repos,
        child: const TutoreaApp(initialRoute: AppRoutes.register),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Elige tu universidad para poder crear tu cuenta.'), findsOneWidget);
      final crear = find.widgetWithText(ElevatedButton, 'Crear cuenta');
      await tester.ensureVisible(crear);
      expect(tester.widget<ElevatedButton>(crear).onPressed, isNull);
    });

    testWidgets('6. cuenta de otra universidad: mensaje y volver a seleccionar', (tester) async {
      final repos = await _openWith(_allUniversities);
      await _createTestUniversityAccount(repos);
      await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
      await tester.pumpAndSettle();

      await _chooseUniversity(tester, _esenName);
      await _tapButton(tester, 'Iniciar sesión'); // Bienvenida → Login
      await _fillLogin(tester, 'ana@up.edu.sv');

      expect(find.textContaining('pertenece a otra universidad'), findsOneWidget);
      expect(find.text('Hola, Ana'), findsNothing);

      final volver = find.widgetWithText(OutlinedButton, 'Volver a seleccionar universidad');
      await tester.ensureVisible(volver);
      await tester.tap(volver);
      await tester.pumpAndSettle();
      expect(find.text('Selecciona tu universidad'), findsOneWidget);
    });

    testWidgets('7 y 9. con sesión abre su módulo; al cerrar sesión vuelve a la selección',
        (tester) async {
      final repos = await _openWith(_allUniversities);
      await repos.auth.login(correo: 'sergio@esen.edu.sv', password: LocalSeed.demoPassword);
      final route = AppNavigator.initialRouteFor(await repos.auth.currentSession());
      expect(route, AppRoutes.home);

      await tester.pumpWidget(AppProviders.local(repos, child: TutoreaApp(initialRoute: route)));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Sergio'), findsOneWidget);
      expect(find.text('Selecciona tu universidad'), findsNothing);

      // Perfil → Cerrar sesión → selección de universidad.
      await tester.tap(find.descendant(
          of: find.byType(BottomNavigationBar), matching: find.text('Perfil')));
      await tester.pumpAndSettle();
      // "Cerrar sesión" está al final de la lista: hacer scroll hasta construirlo.
      final logout = find.text('Cerrar sesión');
      await tester.scrollUntilVisible(logout, 200,
          scrollable: find
              .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      await tester.tap(logout);
      await tester.pumpAndSettle();
      expect(find.text('Selecciona tu universidad'), findsOneWidget);
      expect(AppNavigator.initialRouteFor(await repos.auth.currentSession()),
          AppRoutes.universitySelection);

      // Un tutor con sesión abre su Dashboard.
      await repos.auth.login(correo: 'valeria@esen.edu.sv', password: LocalSeed.demoPassword);
      expect(AppNavigator.initialRouteFor(await repos.auth.currentSession()),
          AppRoutes.tutorDashboard);
    });

    testWidgets('8. sin universidades activas muestra un estado vacío', (tester) async {
      final repos = await _openWith([_inactiveUniversity]);
      await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
      await tester.pumpAndSettle();

      expect(find.text('Por ahora no hay universidades disponibles.'), findsOneWidget);
      expect(find.text('Continuar'), findsNothing);
    });
  });
}
