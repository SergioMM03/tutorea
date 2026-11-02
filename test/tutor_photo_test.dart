import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorea/data/device/device_profile_photo_repository.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/main.dart';
import 'package:tutorea/state/app_providers.dart';
import 'package:tutorea/widgets/tutor_avatar.dart';

/// PNG válido de 1×1 píxel.
final List<int> _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

/// Selector falso: no abre la galería. "Elegir" crea una imagen en una
/// carpeta temporal y "guardar" la copia a otra carpeta (como la real).
/// Usa E/S síncrona para funcionar dentro de testWidgets.
class FakePhotoRepository implements ProfilePhotoRepository {
  final Directory gallery;
  final Directory appFolder;
  int _count = 0;
  bool cancelNext = false;

  FakePhotoRepository(Directory root)
      : gallery = Directory('${root.path}/gallery')..createSync(recursive: true),
        appFolder = Directory('${root.path}/profile_photos')..createSync(recursive: true);

  @override
  Future<String?> pickFromGallery() {
    if (cancelNext) {
      cancelNext = false;
      return Future.value(null);
    }
    final file = File('${gallery.path}/foto_${++_count}.png')..writeAsBytesSync(_pngBytes);
    return Future.value(file.path);
  }

  @override
  Future<String> saveCopy(String sourcePath, {required String ownerId}) {
    final target = '${appFolder.path}/${ownerId}_$_count.png';
    File(sourcePath).copySync(target);
    return Future.value(target);
  }

  @override
  Future<void> delete(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
    return Future.value();
  }
}

Future<void> _login(WidgetTester tester, String correo) async {
  await tester.pumpAndSettle();
  if (find.text('Selecciona tu universidad').evaluate().isNotEmpty) {
    await tester.tap(find.text('Escuela Superior de Economía y Negocios (ESEN)'));
    await tester.pump();
    final continuar = find.widgetWithText(ElevatedButton, 'Continuar');
    await tester.ensureVisible(continuar);
    await tester.tap(continuar);
    await tester.pumpAndSettle();
  }
  final welcomeLogin = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
  await tester.ensureVisible(welcomeLogin);
  await tester.tap(welcomeLogin);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Correo'), correo);
  await tester.enterText(find.widgetWithText(TextFormField, 'Contraseña'), 'tutorea123');
  final submit = find.widgetWithText(ElevatedButton, 'Iniciar sesión');
  await tester.ensureVisible(submit);
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Finder get _listScrollable =>
    find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

/// Mi perfil (tutor) → Editar perfil.
Future<void> _openEditProfile(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(BottomNavigationBar), matching: find.text('Mi perfil')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text('Editar perfil'), 200, scrollable: _listScrollable);
  await tester.tap(find.text('Editar perfil'));
  await tester.pumpAndSettle();
}

Future<void> _saveProfile(WidgetTester tester) async {
  await tester.tap(find.text('Guardar perfil'));
  await tester.pumpAndSettle();
  // Quita el aviso "Perfil guardado" para que no tape otros botones.
  tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
  await tester.pumpAndSettle();
}

void main() {
  group('Iniciales', () {
    test('2. se generan correctamente', () {
      expect(TutorAvatar.initialsOf('Valeria Díaz'), 'VD');
      expect(TutorAvatar.initialsOf('valeria gómez'), 'VG');
      expect(TutorAvatar.initialsOf('Sofía'), 'SO');
      expect(TutorAvatar.initialsOf('  Ana   María López '), 'AM');
      expect(TutorAvatar.initialsOf('Á'), 'Á');
      expect(TutorAvatar.initialsOf(''), '?');
    });
  });

  group('TutorProfile.photoPath', () {
    test('9. perfiles antiguos sin photoPath siguen funcionando', () {
      final old = TutorProfile.fromJson({
        'id': 'tp-viejo',
        'userId': 'u-viejo',
        'descripcion': 'Perfil guardado antes de las fotografías',
        'precioHora': 9,
        'materias': ['est'],
        'disponibilidad': [
          {'diaSemana': 1, 'horaInicio': 480, 'horaFin': 720}
        ],
        'rating': 4.5,
      });
      expect(old.photoPath, isNull);
      expect(old.completo, isTrue);
      final again = TutorProfile.fromJson(old.toJson());
      expect(again.photoPath, isNull);
      expect(again.descripcion, old.descripcion);
    });

    test('10. cambiar o quitar la foto no altera los demás datos', () {
      const base = TutorProfile(
        id: 'tp-x',
        userId: 'u-x',
        descripcion: 'Descripción',
        precioHora: 12,
        materias: ['est', 'mat'],
        disponibilidad: [AvailabilitySlot(diaSemana: 2, horaInicio: 600, horaFin: 900)],
        rating: 4.8,
      );
      final withPhoto = base.copyWith(photoPath: '/app/profile_photos/a.png');
      final without = withPhoto.copyWith(removePhoto: true);
      expect(withPhoto.photoPath, '/app/profile_photos/a.png');
      expect(withPhoto.copyWith(descripcion: 'Otra').photoPath, '/app/profile_photos/a.png');
      expect(without.photoPath, isNull);
      for (final p in [withPhoto, without]) {
        expect(p.descripcion, base.descripcion);
        expect(p.precioHora, base.precioHora);
        expect(p.materias, base.materias);
        expect(p.disponibilidad, base.disponibilidad);
        expect(p.rating, base.rating);
      }
    });
  });

  group('DeviceProfilePhotoRepository (sin abrir la galería)', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('tutorea_photos'));
    tearDown(() => root.deleteSync(recursive: true));

    test('copia la imagen temporal a la carpeta permanente y la borra', () async {
      final repo = DeviceProfilePhotoRepository(baseDirectory: () async => root);
      final temp = File('${root.path}/temporal.JPG')..writeAsBytesSync(_pngBytes);

      final saved = await repo.saveCopy(temp.path, ownerId: 'tp-valeria');
      expect(saved, contains(DeviceProfilePhotoRepository.folderName));
      expect(saved.endsWith('.jpg'), isTrue);
      expect(File(saved).existsSync(), isTrue);

      temp.deleteSync(); // el sistema puede borrar el temporal…
      expect(File(saved).existsSync(), isTrue); // …la copia sigue

      await repo.delete(saved);
      expect(File(saved).existsSync(), isFalse);
      await repo.delete(saved); // borrar otra vez no falla
    });
  });

  group('Avatar', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('tutorea_avatar'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<void> pumpAvatar(WidgetTester tester, String? path) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(body: TutorAvatar(name: 'Valeria Gómez', photoPath: path)),
        ));

    testWidgets('3. sin fotografía muestra iniciales, sin errores', (tester) async {
      await pumpAvatar(tester, null);
      expect(find.text('VG'), findsOneWidget);
      expect(find.byKey(const Key('avatar-photo')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. con fotografía muestra la imagen', (tester) async {
      final file = File('${root.path}/foto.png')..writeAsBytesSync(_pngBytes);
      await pumpAvatar(tester, file.path);
      expect(find.byKey(const Key('avatar-photo')), findsOneWidget);
      expect(find.text('VG'), findsNothing);
    });

    testWidgets('5. si la imagen ya no existe muestra las iniciales', (tester) async {
      await pumpAvatar(tester, '${root.path}/no_existe.png');
      expect(find.text('VG'), findsOneWidget);
      expect(find.byKey(const Key('avatar-photo')), findsNothing);
    });
  });

  group('Fotografía del tutor en la app', () {
    late Directory root;
    late FakePhotoRepository photos;

    setUp(() {
      root = Directory.systemTemp.createTempSync('tutorea_flow');
      photos = FakePhotoRepository(root);
    });
    tearDown(() => root.deleteSync(recursive: true));

    testWidgets('1. los tutores seed aparecen con iniciales', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      await tester.pumpWidget(AppProviders.local(repos, photos: photos, child: const TutoreaApp()));
      await _login(tester, 'sergio@esen.edu.sv');

      expect(find.text('Valeria Gómez'), findsOneWidget);
      expect(find.text('VG'), findsOneWidget);
      expect(find.byKey(const Key('avatar-photo')), findsNothing);
    });

    testWidgets('6-8 y 10. elegir, conservar al reiniciar, reemplazar y eliminar',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      final before = (await repos.tutors.getById('tp-valeria'))!;
      await tester.pumpWidget(AppProviders.local(repos, photos: photos, child: const TutoreaApp()));
      await _login(tester, 'valeria@esen.edu.sv');

      // Elegir (con vista previa) y guardar.
      await _openEditProfile(tester);
      expect(find.text('Fotografía de perfil'), findsOneWidget);
      expect(find.text('Seleccionar fotografía'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-photo')), findsOneWidget); // vista previa
      expect(find.text('Cambiar fotografía'), findsOneWidget);
      await _saveProfile(tester);

      final first = (await repos.tutors.getById('tp-valeria'))!;
      expect(first.photoPath, startsWith(photos.appFolder.path)); // copia, no el temporal
      expect(File(first.photoPath!).existsSync(), isTrue);
      // 10. Lo demás no cambió.
      expect(first.descripcion, before.descripcion);
      expect(first.precioHora, before.precioHora);
      expect(first.materias, before.materias);
      expect(first.disponibilidad, before.disponibilidad);
      // Mi perfil (el avatar está arriba; la lista quedó desplazada hacia abajo).
      await tester.scrollUntilVisible(find.byKey(const Key('avatar-photo')), -200,
          scrollable: _listScrollable);
      expect(find.byKey(const Key('avatar-photo')), findsOneWidget);

      // 7. Reemplazar: la foto anterior se borra.
      await tester.scrollUntilVisible(find.text('Editar perfil'), 200, scrollable: _listScrollable);
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pick-photo')));
      await tester.pumpAndSettle();
      await _saveProfile(tester);
      final second = (await repos.tutors.getById('tp-valeria'))!;
      expect(second.photoPath, isNot(first.photoPath));
      expect(File(second.photoPath!).existsSync(), isTrue);
      expect(File(first.photoPath!).existsSync(), isFalse);

      // 6. "Reiniciar": nuevos repositorios sobre los datos guardados.
      final prefs = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues(
          {for (final k in prefs.getKeys()) k: prefs.get(k)!});
      final reopened = await LocalRepositories.open();
      expect((await reopened.tutors.getById('tp-valeria'))!.photoPath, second.photoPath);

      // 8. Eliminar: vuelve a las iniciales y se borra el archivo.
      await tester.scrollUntilVisible(find.text('Editar perfil'), 200, scrollable: _listScrollable);
      await tester.tap(find.text('Editar perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('remove-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-photo')), findsNothing);
      expect(find.text('VG'), findsOneWidget);
      await _saveProfile(tester);
      final third = (await repos.tutors.getById('tp-valeria'))!;
      expect(third.photoPath, isNull);
      expect(File(second.photoPath!).existsSync(), isFalse);
      expect(third.descripcion, before.descripcion);
      expect(third.disponibilidad, before.disponibilidad);
    });

    testWidgets('6. el estudiante ve la fotografía del tutor al reabrir la app', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      final photo = File('${photos.appFolder.path}/tp-valeria_1.png')..writeAsBytesSync(_pngBytes);
      final profile = (await repos.tutors.getById('tp-valeria'))!;
      await repos.tutors.save(profile.copyWith(photoPath: photo.path));

      final prefs = await SharedPreferences.getInstance();
      SharedPreferences.setMockInitialValues(
          {for (final k in prefs.getKeys()) k: prefs.get(k)!});
      final reopened = await LocalRepositories.open();
      await tester.pumpWidget(
          AppProviders.local(reopened, photos: photos, child: const TutoreaApp()));
      await _login(tester, 'sergio@esen.edu.sv');

      // Tarjeta de Valeria en Inicio con su foto; los demás con iniciales.
      expect(find.byKey(const Key('avatar-photo')), findsOneWidget);
      expect(find.text('VG'), findsNothing);

      // Mismo avatar en su perfil público.
      await tester.tap(find.text('Valeria Gómez'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-photo')), findsOneWidget);
    });

    testWidgets('cancelar la galería no cambia nada', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final repos = await LocalRepositories.open();
      await tester.pumpWidget(AppProviders.local(repos, photos: photos, child: const TutoreaApp()));
      await _login(tester, 'valeria@esen.edu.sv');
      await _openEditProfile(tester);

      photos.cancelNext = true;
      await tester.tap(find.byKey(const Key('pick-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('avatar-photo')), findsNothing);
      expect(find.text('Seleccionar fotografía'), findsOneWidget);
    });
  });
}
