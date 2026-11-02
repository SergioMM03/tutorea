import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/main.dart';
import 'package:tutorea/routes/routes.dart';
import 'package:tutorea/state/app_providers.dart';
import 'package:tutorea/state/session_store.dart';

const _esenName = 'Escuela Superior de Economía y Negocios (ESEN)';

final List<int> _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

/// Selector de fotos falso (no abre la galería; E/S síncrona para testWidgets).
class _FakePhotos implements ProfilePhotoRepository {
  final Directory root;
  int _n = 0;
  _FakePhotos(this.root);

  @override
  Future<String?> pickFromGallery() {
    final f = File('${root.path}/g_${++_n}.png')..writeAsBytesSync(_pngBytes);
    return Future.value(f.path);
  }

  @override
  Future<String> saveCopy(String sourcePath, {required String ownerId}) {
    final target = '${root.path}/${ownerId}_$_n.png';
    File(sourcePath).copySync(target);
    return Future.value(target);
  }

  @override
  Future<void> delete(String path) {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    return Future.value();
  }
}

/// Tamaño de pantalla lógico y tamaño de texto del sistema para la prueba.
void _setScreen(WidgetTester tester, Size logical, {double textScale = 1.0}) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = logical * 3.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _loginStudent(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text(_esenName));
  await tester.pump();
  Future<void> tapButton(String label) async {
    final b = find.widgetWithText(ElevatedButton, label);
    await tester.ensureVisible(b);
    await tester.pumpAndSettle();
    await tester.tap(b);
    await tester.pumpAndSettle();
  }

  await tapButton('Continuar');
  await tapButton('Iniciar sesión');
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), 'sergio@esen.edu.sv');
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'tutorea123');
  await tapButton('Iniciar sesión');
}

Future<void> _openStudentEdit(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar), matching: find.text('Perfil')));
  await tester.pumpAndSettle();
  // "Editar perfil" puede quedar fuera de la pantalla: scroll hasta construirlo.
  final edit = find.text('Editar perfil');
  await tester.scrollUntilVisible(edit, 200,
      scrollable: find
          .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
          .first);
  await tester.ensureVisible(edit);
  await tester.pumpAndSettle();
  await tester.tap(edit);
  await tester.pumpAndSettle();
}

Future<void> _chooseFromDropdown(WidgetTester tester, Key key, String option) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last); // la opción del menú abierto
  await tester.pumpAndSettle();
}

void main() {
  group('Perfil del estudiante (lógica)', () {
    late LocalRepositories repos;
    late SessionStore session;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repos = await LocalRepositories.open();
      session = SessionStore(repos.auth, repos.universities);
      await session.loadUniversities();
      await session.selectUniversity('esen');
      await session.login(correo: 'sergio@esen.edu.sv', password: LocalSeed.demoPassword);
    });

    test('guarda nombre, carrera y año; SessionStore se actualiza al instante', () async {
      final before = session.user!;
      final careers = await session.careersOfCurrentUser();
      expect(careers.every((c) => c.universityId == 'esen'), isTrue);

      expect(
          await session.updateProfile(
              nombre: '  Sergio Pérez ', careerId: LocalSeed.ingNegocios, anioAcademico: 3),
          isTrue);
      final after = session.user!;
      expect(after.nombre, 'Sergio Pérez');
      expect(after.careerId, LocalSeed.ingNegocios);
      expect(after.carrera, 'Ingeniería de Negocios');
      expect(after.anioAcademico, 3);
      // No cambian.
      expect(after.id, before.id);
      expect(after.correo, before.correo);
      expect(after.universityId, before.universityId);
      expect(after.rol, before.rol);
      expect(session.role, before.rol);
    });

    test('los cambios persisten al reiniciar la app', () async {
      await session.updateProfile(
          nombre: 'Sergio Pérez', careerId: LocalSeed.software, anioAcademico: 4);

      final prefs = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues(
          {for (final k in prefs.getKeys()) k: prefs.get(k)!});
      final reopened = await LocalRepositories.open();
      final restored = (await reopened.auth.currentSession()).usuario!;
      expect(restored.nombre, 'Sergio Pérez');
      expect(restored.careerId, LocalSeed.software);
      expect(restored.anioAcademico, 4);
      expect(restored.correo, 'sergio@esen.edu.sv');
    });

    test('no guarda datos inválidos', () async {
      final before = session.user!;
      expect(await session.updateProfile(nombre: ' ', careerId: LocalSeed.eyn, anioAcademico: 2),
          isFalse);
      expect(
          await session.updateProfile(nombre: 'Sergio', careerId: 'no-existe', anioAcademico: 2),
          isFalse);
      expect(await session.updateProfile(nombre: 'Sergio', careerId: LocalSeed.eyn, anioAcademico: 0),
          isFalse);
      expect(session.error, isNotNull);
      final stored = (await repos.auth.currentSession()).usuario!;
      expect(stored.nombre, before.nombre);
      expect(stored.anioAcademico, before.anioAcademico);
    });

    test('no afecta a los tutores ni a sus perfiles', () async {
      final profileBefore = (await repos.tutors.getById('tp-valeria'))!.toJson();
      final valeriaBefore = (await repos.auth.getUserById('u-valeria'))!.toJson();

      await session.updateProfile(nombre: 'Sergio Pérez', careerId: LocalSeed.eyn, anioAcademico: 5);

      expect((await repos.tutors.getById('tp-valeria'))!.toJson(), profileBefore);
      expect((await repos.auth.getUserById('u-valeria'))!.toJson(), valeriaBefore);
    });
  });

  group('Perfil del estudiante (pantalla)', () {
    testWidgets('abre la edición con datos precargados, guarda y se ve al instante',
        (tester) async {
      _setScreen(tester, const Size(412, 915)); // Samsung S24 Ultra (aprox.)
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
      await _loginStudent(tester);
      await _openStudentEdit(tester);

      // Precargados.
      expect(find.text('Editar perfil'), findsOneWidget); // título
      expect(find.widgetWithText(TextFormField, 'Sergio'), findsOneWidget);
      expect(find.text('Licenciatura en Economía y Negocios'), findsWidgets);
      expect(find.text('2.º año'), findsWidgets);
      // No editables.
      expect(find.text('sergio@esen.edu.sv'), findsOneWidget);
      expect(find.text(_esenName), findsOneWidget);

      // Cambiar nombre, carrera y año.
      await tester.enterText(find.widgetWithText(TextFormField, 'Sergio'), 'Sergio Pérez');
      await _chooseFromDropdown(tester, const Key('student-career'), 'Ingeniería de Negocios');
      await _chooseFromDropdown(tester, const Key('student-year'), '3.º año');
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // De vuelta en Perfil, con los datos nuevos.
      expect(find.text('Perfil actualizado'), findsOneWidget);
      expect(find.text('Sergio Pérez'), findsOneWidget);
      expect(find.text('Ingeniería de Negocios'), findsOneWidget);
      expect(find.text('3.º año'), findsOneWidget);
      expect(find.text('sergio@esen.edu.sv'), findsOneWidget);

      final stored = (await repos.auth.currentSession()).usuario!;
      expect(stored.nombre, 'Sergio Pérez');
      expect(stored.universityId, 'esen');
    });

    testWidgets('Cancelar regresa sin guardar', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
      await _loginStudent(tester);
      await _openStudentEdit(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Sergio'), 'Otro Nombre');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('Otro Nombre'), findsNothing);
      expect((await repos.auth.currentSession()).usuario!.nombre, 'Sergio');
    });

    testWidgets('el nombre vacío no se guarda', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      await tester.pumpWidget(AppProviders.local(repos, child: const TutoreaApp()));
      await _loginStudent(tester);
      await _openStudentEdit(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Sergio'), '');
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe tu nombre.'), findsOneWidget);
      expect((await repos.auth.currentSession()).usuario!.nombre, 'Sergio');
    });
  });

  group('Editar perfil del tutor: sección de fotografía', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('tutorea_layout'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> openTutorEdit(WidgetTester tester, LocalRepositories repos) async {
      await repos.auth.login(correo: 'valeria@esen.edu.sv', password: LocalSeed.demoPassword);
      await tester.pumpWidget(AppProviders.local(
        repos,
        photos: _FakePhotos(root),
        child: const TutoreaApp(initialRoute: AppRoutes.tutorMyProfile),
      ));
      await tester.pumpAndSettle();
      final scrollable =
          find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Editar perfil'), 200, scrollable: scrollable);
      // scrollUntilVisible se detiene cuando el botón ya existe, aunque quede
      // bajo la barra inferior: ensureVisible lo lleva a la zona visible.
      await tester.ensureVisible(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
    }

    for (final (label, size, scale) in [
      ('pantalla angosta (360 px)', const Size(360, 780), 1.0),
      ('S24 Ultra con texto grande', const Size(412, 915), 1.3),
    ]) {
      testWidgets('sin overflow en $label y el botón se puede usar', (tester) async {
        _setScreen(tester, size, textScale: scale);
        SharedPreferences.setMockInitialValues({});
        final repos = await LocalRepositories.open();
        await openTutorEdit(tester, repos);

        // Si hubiera un "RenderFlex overflowed", flutter_test hace fallar la
        // prueba y muestra qué widget y qué línea lo causan.
        expect(find.byKey(const Key('photo-section-stacked')), findsOneWidget);

        // El botón está visible, completo y responde.
        final pick = find.byKey(const Key('pick-photo'));
        final rect = tester.getRect(pick);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        await tester.tap(pick);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('avatar-photo')), findsOneWidget);
        expect(find.text('Cambiar fotografía'), findsOneWidget);

        // El formulario sigue funcionando: guardar conserva los datos.
        final before = (await repos.tutors.getById('tp-valeria'))!;
        await tester.tap(find.text('Guardar perfil'));
        await tester.pumpAndSettle();
        final after = (await repos.tutors.getById('tp-valeria'))!;
        expect(after.photoPath, isNotNull);
        expect(after.descripcion, before.descripcion);
        expect(after.disponibilidad, before.disponibilidad);
      });
    }

    testWidgets('en pantallas anchas el avatar y el botón van en una fila', (tester) async {
      _setScreen(tester, const Size(1280, 800));
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      await openTutorEdit(tester, repos);
      expect(find.byKey(const Key('photo-section-row')), findsOneWidget);
    });
  });
}
