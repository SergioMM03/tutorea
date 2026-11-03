import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, StorageException;
import 'package:tutorea/data/device/device_university_selection.dart';
import 'package:tutorea/data/local/local_database.dart';
import 'package:tutorea/data/local/local_repositories.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/supabase/remote_catalog.dart';
import 'package:tutorea/data/supabase/remote_catalog_repositories.dart';
import 'package:tutorea/data/supabase/remote_tutor_photo_storage.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/photo_rules.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/state/tutor_store.dart';
import 'package:tutorea/widgets/startup_error_app.dart';
import 'package:tutorea/widgets/tutor_avatar.dart';

// Fase 14.10: fotografías en Storage, filtros de búsqueda y Supabase como
// única fuente de datos. Ninguna prueba usa la red: los servidores son simulados.

const _esen = '11111111-1111-4111-8111-111111111111';
const _otra = '22222222-2222-4222-8222-222222222222';
const _tp = '10000000-0000-4000-9000-000000000001';
const _tpOtro = '10000000-0000-4000-9000-000000000002';

Matcher _fails(String message) =>
    throwsA(isA<RepositoryException>().having((e) => e.message, 'message', message));

class _FakeCatalog implements CatalogRowsSource, UniversityListSource {
  static Map<String, dynamic> _uni(String id, String slug) =>
      {'id': id, 'slug': slug, 'name': slug, 'short_name': slug, 'country': 'SV', 'is_active': true};

  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async {
    final id = {'esen': _esen, 'otra-u': _otra}[universitySlug];
    if (id == null) return null;
    return RemoteCatalogRows(university: _uni(id, universitySlug), careers: const [], subjects: const []);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() async => [_uni(_esen, 'esen'), _uni(_otra, 'otra-u')];

  @override
  Future<String?> universitySlugById(String universityUuid) async =>
      {_esen: 'esen', _otra: 'otra-u'}[universityUuid];
}

/// Imita el bucket privado tutor-photos, su RLS y set_tutor_photo (migración 24)
/// para la cuenta dueña del perfil [_tp] de ESEN.
class _FakeStorage implements PhotoStorageSource {
  final Map<String, (Uint8List, String)> objects = {};
  final Map<String, String?> photoOf = {_tp: null};
  String? failSetWith;
  bool failSigned = false;
  int signedCalls = 0;

  bool _mine(String path) => path.startsWith('$_esen/$_tp/');

  @override
  Future<void> upload(String path, Uint8List bytes, String contentType) async {
    if (!_mine(path)) throw StorageException('RLS', statusCode: '403');
    if (bytes.length > PhotoRules.maxBytes) throw StorageException('grande', statusCode: '413');
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(contentType)) {
      throw StorageException('tipo', statusCode: '415');
    }
    objects[path] = (bytes, contentType);
  }

  @override
  Future<void> remove(List<String> paths) async {
    for (final p in paths) {
      if (_mine(p)) objects.remove(p);
    }
  }

  @override
  Future<String?> setPhoto(String? path) async {
    if (failSetWith != null) throw PostgrestException(message: 'x', code: failSetWith);
    if (path != null && (!_mine(path) || !objects.containsKey(path))) {
      throw const PostgrestException(message: 'x', code: 'TU051');
    }
    final previous = photoOf[_tp];
    photoOf[_tp] = path;
    return previous;
  }

  @override
  Future<String> signedUrl(String path, Duration expiresIn) async {
    signedCalls++;
    if (failSigned) throw StorageException('no', statusCode: '400');
    return 'https://example.test/sign/$path?t=$signedCalls';
  }
}

TutorProfile _profile({String id = _tp, String? photo}) => TutorProfile(
      id: id,
      userId: 'u-$id',
      universityId: 'esen',
      descripcion: 'Perfil',
      precioHora: 10,
      materias: const ['est'],
      disponibilidad: const [AvailabilitySlot(diaSemana: 1, horaInicio: 480, horaFin: 600)],
      photoPath: photo,
    );

void main() {
  group('reglas de fotografías', () {
    test('JPEG, PNG y WebP de hasta 2 MB', () {
      expect(PhotoRules.problem('/a/foto.JPG', 1000), isNull);
      expect(PhotoRules.problem('/a/foto.png', PhotoRules.maxBytes), isNull);
      expect(PhotoRules.problem('/a/foto.webp', 10), isNull);
      expect(PhotoRules.problem('/a/foto.gif', 10), PhotoRules.invalidTypeMessage);
      expect(PhotoRules.problem('/a/foto', 10), PhotoRules.invalidTypeMessage);
      expect(PhotoRules.problem('/a/foto.jpg', PhotoRules.maxBytes + 1), PhotoRules.tooLargeMessage);
      expect(PhotoRules.problem('/a/foto.jpg', 0), PhotoRules.tooLargeMessage);
    });

    test('distingue rutas de Storage de archivos del dispositivo', () {
      expect(PhotoRules.isStoragePath('$_esen/$_tp/1700.jpg'), isTrue);
      expect(PhotoRules.isStoragePath('/data/user/0/app/profile_photos/x.jpg'), isFalse);
      expect(PhotoRules.isStoragePath('$_esen/$_tp/../x.jpg'), isFalse);
      expect(PhotoRules.isStoragePath(null), isFalse);
    });
  });

  group('fotografías en Storage', () {
    late _FakeStorage server;
    late RemoteTutorPhotoStorage storage;
    final files = <String, Uint8List>{};
    var clock = DateTime(2026, 11, 3, 10);

    setUp(() {
      server = _FakeStorage();
      files
        ..clear()
        ..['/tmp/ok.jpg'] = Uint8List(5000)
        ..['/tmp/otra.png'] = Uint8List(8000)
        ..['/tmp/grande.jpg'] = Uint8List(PhotoRules.maxBytes + 1)
        ..['/tmp/anim.gif'] = Uint8List(100);
      storage = RemoteTutorPhotoStorage(
        server,
        RemoteCatalogCache(catalog: _FakeCatalog(), universities: _FakeCatalog()),
        readFile: (p) async => files[p] ?? (throw StateError('no existe')),
        now: () => clock = clock.add(const Duration(seconds: 1)),
      );
    });

    test('sube, reemplaza (borra la anterior) y elimina sin dejar huérfanos', () async {
      final first = await storage.upload(_profile(), '/tmp/ok.jpg');
      expect(first, matches(RegExp('^$_esen/$_tp/\\d+\\.jpg\$')));
      expect(PhotoRules.isStoragePath(first), isTrue);
      expect(server.objects[first]!.$2, 'image/jpeg');
      expect(server.photoOf[_tp], first);

      final second = await storage.upload(_profile(photo: first), '/tmp/otra.png');
      expect(server.objects[second]!.$2, 'image/png');
      expect(server.photoOf[_tp], second);
      expect(server.objects.keys, [second]); // la anterior se borró

      await storage.remove(_profile(photo: second));
      expect(server.photoOf[_tp], isNull);
      expect(server.objects, isEmpty);
    });

    test('rechaza archivos inválidos antes de subirlos', () async {
      await expectLater(storage.upload(_profile(), '/tmp/grande.jpg'), _fails(PhotoRules.tooLargeMessage));
      await expectLater(storage.upload(_profile(), '/tmp/anim.gif'), _fails(PhotoRules.invalidTypeMessage));
      expect(server.objects, isEmpty);
      expect(await storage.validate('/tmp/grande.jpg'), PhotoRules.tooLargeMessage);
      expect(await storage.validate('/tmp/anim.gif'), PhotoRules.invalidTypeMessage);
      expect(await storage.validate('/tmp/ok.jpg'), isNull);
      expect(await storage.validate('/tmp/no-existe.jpg'), photoInvalidMessage);
    });

    test('no sube a la carpeta de otro tutor (RLS) y no deja archivos si fijarla falla', () async {
      await expectLater(storage.upload(_profile(id: _tpOtro), '/tmp/ok.jpg'), _fails(photoFailedMessage));
      expect(server.objects, isEmpty);
      server.failSetWith = 'TU051';
      await expectLater(storage.upload(_profile(), '/tmp/ok.jpg'), _fails(photoInvalidMessage));
      expect(server.objects, isEmpty); // lo subido se borró
      server.failSetWith = 'TU050';
      await expectLater(storage.remove(_profile()), _fails(photoNoProfileMessage));
    });

    test('URLs firmadas: se reutilizan mientras están vigentes; sin URL, null', () async {
      final path = await storage.upload(_profile(), '/tmp/ok.jpg');
      final url = await storage.signedUrl(path);
      expect(url, startsWith('https://example.test/sign/$_esen/'));
      expect(await storage.signedUrl(path), url);
      expect(storage.cachedUrl(path), url);
      expect(server.signedCalls, 1);
      clock = clock.add(const Duration(hours: 1)); // vencida
      expect(storage.cachedUrl(path), isNull);
      server.failSigned = true;
      expect(await storage.signedUrl(path), isNull);
    });

    test('los datos viven en el servidor: otra instancia (app reabierta) ve la misma foto', () async {
      SharedPreferences.setMockInitialValues({});
      final path = await storage.upload(_profile(), '/tmp/ok.jpg');
      final reopened = RemoteTutorPhotoStorage(
          server, RemoteCatalogCache(catalog: _FakeCatalog(), universities: _FakeCatalog()));
      expect(await reopened.signedUrl(path), isNotNull);
      expect(server.photoOf[_tp], path);
      // Nada de negocio quedó en el dispositivo.
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  });

  group('TutorStore con Storage', () {
    late LocalRepositories repos;
    late _StoreStorage storage;
    late _Photos photos;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repos = await LocalRepositories.open();
      storage = _StoreStorage(repos.tutors);
      photos = _Photos();
    });

    TutorStore store() => TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities, photos, storage);

    test('guardar con foto nueva la sube, borra la copia local y recarga el perfil', () async {
      final s = store();
      await s.loadMyProfile('u-valeria');
      final local = await s.pickProfilePhoto('u-valeria');
      expect(local, '/copias/foto.jpg');
      expect(await s.saveProfile(s.myProfile!.copyWith(photoPath: local)), isTrue);
      expect(storage.uploaded, ['/copias/foto.jpg']);
      expect(photos.deleted, ['/copias/foto.jpg']);
      expect(s.myProfile!.photoPath, storage.lastPath);

      // Guardar sin cambiar la foto no vuelve a subirla.
      expect(await s.saveProfile(s.myProfile!.copyWith(precioHora: 12)), isTrue);
      expect(storage.uploaded, hasLength(1));

      // Quitarla.
      expect(await s.saveProfile(s.myProfile!.copyWith(removePhoto: true)), isTrue);
      expect(storage.removed, 1);
      expect(s.myProfile!.photoPath, isNull);
    });

    test('un archivo inválido se rechaza al elegirlo', () async {
      storage.problem = PhotoRules.tooLargeMessage;
      final s = store();
      expect(await s.pickProfilePhoto('u-valeria'), isNull);
      expect(s.error, PhotoRules.tooLargeMessage);
    });

    test('si la subida falla, el perfil se guarda y se informa', () async {
      storage.failUpload = true;
      final s = store();
      await s.loadMyProfile('u-valeria');
      expect(await s.saveProfile(s.myProfile!.copyWith(photoPath: '/copias/foto.jpg', precioHora: 14)), isFalse);
      expect(s.error, contains('Tu perfil se guardó, pero la fotografía no'));
      expect((await repos.tutors.getById('tp-valeria'))!.precioHora, 14);
    });
  });

  group('búsqueda y filtros', () {
    late LocalRepositories repos;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repos = await LocalRepositories.open();
      // Calificaciones calculadas (como las deja el servidor a partir de reseñas).
      final db = await LocalDatabase.open();
      final profiles = db.readList(LocalDatabase.tutorProfiles);
      for (final p in profiles) {
        if (p['id'] == 'tp-valeria') {
          p['rating'] = 4.8;
          p['ratingCount'] = 5;
        } else if (p['id'] == 'tp-daniel') {
          p['rating'] = 4.2;
          p['ratingCount'] = 3;
        } else {
          p['rating'] = 0;
          p['ratingCount'] = 0;
        }
      }
      await db.writeList(LocalDatabase.tutorProfiles, profiles);
    });

    test('calificación mínima: «Nuevo» no cumple ningún mínimo', () async {
      final s = TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities);
      await s.loadForUniversity('esen');
      final all = s.availableTutors.length;
      await s.filterByMinRating(4);
      expect(s.availableTutors.map((t) => t.id).toSet(), {'tp-valeria', 'tp-daniel'});
      await s.filterByMinRating(4.5);
      expect(s.availableTutors.map((t) => t.id), ['tp-valeria']);
      expect(s.hasSearchOrFilters, isTrue);
      await s.clearSearch();
      expect(s.availableTutors, hasLength(all));
      expect(s.minRatingFilter, isNull);
    });

    test('combina materia, modalidad, disponibilidad, calificación y texto', () async {
      final valeria = (await repos.tutors.getById('tp-valeria'))!;
      await repos.tutors.save(valeria.copyWith(ofreceVirtual: false));
      final s = TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities);
      await s.loadForUniversity('esen');
      await s.filterBySubject('est');
      expect(s.availableTutors.map((t) => t.id), contains('tp-valeria'));
      await s.filterByModality(TutoringModality.virtual);
      expect(s.availableTutors.map((t) => t.id), isNot(contains('tp-valeria')));
      await s.filterByModality(TutoringModality.presencial);
      await s.filterByMinRating(4.5);
      expect(s.availableTutors.map((t) => t.id), ['tp-valeria']);
      // Domingo: Valeria no atiende.
      var sunday = DateTime.now().add(const Duration(days: 1));
      while (sunday.weekday != DateTime.sunday) {
        sunday = sunday.add(const Duration(days: 1));
      }
      await s.filterByAvailability(DateTime(sunday.year, sunday.month, sunday.day, 10));
      expect(s.availableTutors, isEmpty);
      await s.filterByAvailability(null);
      s.search('valeria');
      expect(s.searchResults.single.id, 'tp-valeria');
      s.search('daniel');
      expect(s.searchResults, isEmpty);
    });

    test('no se ofrece el propio perfil de tutor ni perfiles inactivos', () async {
      final s = TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities);
      await s.loadForUniversity('esen', viewerId: 'u-valeria');
      expect(s.availableTutors.map((t) => t.id), isNot(contains('tp-valeria')));
      final daniel = (await repos.tutors.getById('tp-daniel'))!;
      await repos.tutors.save(daniel.copyWith(activo: false));
      await s.loadAvailable();
      expect(s.availableTutors.map((t) => t.id), isNot(contains('tp-daniel')));
      s.reset();
      await s.loadForUniversity('esen');
      expect(s.availableTutors.map((t) => t.id), contains('tp-valeria')); // otra cuenta sí lo ve
    });

    test('aislamiento entre universidades', () async {
      final s = TutorStore(repos.tutors, repos.subjects, repos.auth, repos.universities);
      await s.loadForUniversity('otra-u');
      expect(s.availableTutors, isEmpty);
      await s.loadForUniversity('esen');
      expect(s.availableTutors, isNotEmpty);
      expect(s.availableTutors.every((t) => t.profile.universityId == 'esen'), isTrue);
    });
  });

  group('producción sin datos locales', () {
    test('la universidad elegida es lo único que guarda el dispositivo', () async {
      SharedPreferences.setMockInitialValues({});
      final selection = DeviceUniversitySelection();
      expect(await selection.getSelectedUniversityId(), isNull);
      await selection.saveSelectedUniversityId('esen');
      expect(await DeviceUniversitySelection().getSelectedUniversityId(), 'esen'); // al reabrir
      final keys = (await SharedPreferences.getInstance()).getKeys();
      expect(keys, {DeviceUniversitySelection.key});
      expect(keys.any((k) => k == LocalDatabase.tutorProfiles || k == LocalDatabase.bookings), isFalse);
      expect(() => selection.getActive(), throwsUnsupportedError); // no es un catálogo local
    });

    testWidgets('sin Supabase: mensaje comprensible y Reintentar', (tester) async {
      var retries = 0;
      await tester.pumpWidget(StartupErrorApp(
        message: 'No se pudo conectar con el servidor de Tutorea.',
        onRetry: () async => retries++,
      ));
      expect(find.text('Sin conexión con Tutorea'), findsOneWidget);
      expect(find.text('No se pudo conectar con el servidor de Tutorea.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pumpAndSettle();
      expect(retries, 1);
      // No muestra tutores ni datos de demostración.
      expect(find.text(LocalSeed.tutorProfiles.first.descripcion), findsNothing);
    });

    testWidgets('avatar con ruta de Storage: pide la URL firmada; sin URL, iniciales', (tester) async {
      final resolver = _Resolver();
      await tester.pumpWidget(MaterialApp(
        home: Provider<PhotoUrlResolver?>.value(
          value: resolver,
          child: const Scaffold(body: TutorAvatar(name: 'Valeria Gómez', photoPath: '$_esen/$_tp/1.jpg')),
        ),
      ));
      await tester.pumpAndSettle();
      expect(resolver.asked, ['$_esen/$_tp/1.jpg']);
      expect(find.text('VG'), findsOneWidget);

      // Sin resolver (modo de desarrollo): iniciales, sin errores.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: TutorAvatar(name: 'Valeria Gómez', photoPath: '$_esen/$_tp/1.jpg')),
      ));
      expect(find.text('VG'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Resolver implements PhotoUrlResolver {
  final List<String> asked = [];
  @override
  String? cachedUrl(String path) => null;
  @override
  Future<String?> signedUrl(String path) async {
    asked.add(path);
    return null;
  }
}

/// Selector de galería simulado.
class _Photos implements ProfilePhotoRepository {
  final List<String> deleted = [];
  @override
  Future<String?> pickFromGallery() async => '/tmp/galeria.jpg';
  @override
  Future<String> saveCopy(String sourcePath, {required String ownerId}) async => '/copias/foto.jpg';
  @override
  Future<void> delete(String path) async => deleted.add(path);
}

/// Storage simulado para TutorStore: "el servidor" deja la ruta en el perfil.
class _StoreStorage implements TutorPhotoStorage {
  final TutorRepository tutors;
  _StoreStorage(this.tutors);
  final List<String> uploaded = [];
  int removed = 0;
  String? lastPath;
  String? problem;
  bool failUpload = false;

  @override
  Future<String?> validate(String localPath) async => problem;

  @override
  Future<String> upload(TutorProfile profile, String localPath) async {
    if (failUpload) throw const RepositoryException(photoConnectionMessage);
    uploaded.add(localPath);
    lastPath = '$_esen/$_tp/${uploaded.length}.jpg';
    final current = (await tutors.getById(profile.id))!;
    await tutors.save(current.copyWith(photoPath: lastPath));
    return lastPath!;
  }

  @override
  Future<void> remove(TutorProfile profile) async {
    removed++;
    final current = (await tutors.getById(profile.id))!;
    await tutors.save(current.copyWith(removePhoto: true));
  }

  @override
  String? cachedUrl(String path) => null;
  @override
  Future<String?> signedUrl(String path) async => null;
}
