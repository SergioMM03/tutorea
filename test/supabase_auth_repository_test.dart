import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthApiException, AuthRetryableFetchException, AuthWeakPasswordException;
import 'package:tutorea/config/auth_mode.dart';
import 'package:tutorea/data/local/local_seed.dart';
import 'package:tutorea/data/supabase/auth_selection.dart';
import 'package:tutorea/data/supabase/remote_auth_gateway.dart';
import 'package:tutorea/data/supabase/remote_catalog.dart';
import 'package:tutorea/data/supabase/remote_catalog_repositories.dart';
import 'package:tutorea/data/supabase/supabase_auth_errors.dart';
import 'package:tutorea/data/supabase/supabase_auth_repository.dart';
import 'package:tutorea/data/supabase/supabase_bootstrap.dart';
import 'package:tutorea/domain/models/models.dart';
import 'package:tutorea/domain/repositories/repositories.dart';
import 'package:tutorea/state/session_store.dart';

// Todo es simulado: ninguna prueba usa la red ni el Supabase real.

const _esenUuid = '11111111-1111-4111-8111-111111111111';
String _careerUuid(String slug) => 'career-$slug';

const _esenRow = {
  'id': _esenUuid,
  'slug': 'esen',
  'name': 'Escuela Superior de Economía y Negocios (ESEN)',
  'short_name': 'ESEN',
  'country': 'El Salvador',
  'is_active': true,
};

/// Catálogo remoto con el mismo contenido que el seed (supabase/seed.sql).
class _FakeCatalog implements CatalogRowsSource, UniversityListSource {
  int fetches = 0;
  @override
  Future<RemoteCatalogRows?> fetch(String universitySlug) async {
    fetches++;
    if (universitySlug != 'esen') return null;
    return RemoteCatalogRows(
      university: Map.of(_esenRow),
      careers: [
        for (final c in LocalSeed.careers)
          {'id': _careerUuid(c.id), 'university_id': _esenUuid, 'slug': c.id, 'name': c.nombre},
      ],
      subjects: const [],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchActiveUniversities() async => [Map.of(_esenRow)];

  @override
  Future<String?> universitySlugById(String universityUuid) async =>
      universityUuid == _esenUuid ? 'esen' : null;
}

/// `profiles` y `public_profiles` simulados. [update] imita RLS: solo la fila
/// del usuario con sesión, solo las columnas permitidas, y career_name lo copia
/// "la base" desde la carrera (trigger sync_profile_career).
class _FakeProfiles implements RemoteProfileSource {
  final Map<String, Map<String, dynamic>> rows = {};
  Object? error;
  String? sessionUserId;
  Map<String, Object?>? lastUpdate;

  @override
  Future<Map<String, dynamic>?> ownProfile(String userId) async {
    if (error != null) throw error!;
    return rows[userId];
  }

  @override
  Future<Map<String, dynamic>?> publicProfile(String userId) async {
    if (error != null) throw error!;
    final row = rows[userId];
    if (row == null) return null;
    // La vista no tiene correo, career_id ni fechas.
    return {
      for (final key in ['id', 'university_id', 'full_name', 'career_name', 'academic_year', 'role'])
        key: row[key],
    };
  }

  @override
  Future<Map<String, dynamic>?> updateOwnProfile({
    required String userId,
    required String fullName,
    required String careerUuid,
    required int academicYear,
  }) async {
    if (error != null) throw error!;
    lastUpdate = {
      'id': userId,
      'full_name': fullName,
      'career_id': careerUuid,
      'academic_year': academicYear,
    };
    final row = rows[userId];
    if (row == null || userId != sessionUserId) return null; // RLS: 0 filas
    final career = LocalSeed.careers.where((c) => _careerUuid(c.id) == careerUuid).firstOrNull;
    if (career == null) throw Exception('FK');
    row
      ..['full_name'] = fullName
      ..['career_id'] = careerUuid
      ..['career_name'] = career.nombre
      ..['academic_year'] = academicYear;
    return Map.of(row);
  }
}

/// Supabase Auth simulado. Al registrar imita handle_new_user: crea el perfil
/// desde la metadata y solo acepta el rol tutor (cualquier otro → estudiante).
class _FakeGateway implements RemoteAuthGateway {
  final _FakeProfiles profiles;
  _FakeGateway(this.profiles);

  final Map<String, (String, RemoteAuthUser)> accounts = {};
  final StreamController<RemoteAuthEvent> controller = StreamController.broadcast();
  Object? signUpError;
  Object? signInError;
  Object? signOutError;
  bool confirmationRequired = false;
  bool hang = false;
  Map<String, Object>? lastSignUpData;
  String? lastEmail;
  int signOutCalls = 0;
  int refreshCalls = 0;
  int _next = 1;

  String _newId() => '00000000-0000-4000-8000-${(_next++).toString().padLeft(12, '0')}';

  RemoteAuthUser? _current;
  RemoteAuthUser? get current => _current;
  set current(RemoteAuthUser? user) {
    _current = user;
    profiles.sessionUserId = user?.id;
  }

  @override
  RemoteAuthUser? get currentUser => current;

  @override
  Future<void> refreshIfExpired() async => refreshCalls++;

  @override
  Future<RemoteSignUpResult> signUp({
    required String email,
    required String password,
    required Map<String, Object> data,
  }) async {
    lastEmail = email;
    lastSignUpData = data;
    if (hang) await Completer<void>().future;
    if (signUpError != null) throw signUpError!;
    final user = RemoteAuthUser(id: _newId(), email: email);
    accounts[email] = (password, user);
    final career = LocalSeed.careers.firstWhere((c) => _careerUuid(c.id) == data['career_id']);
    profiles.rows[user.id] = {
      'id': user.id,
      'university_id': data['university_id'],
      'role': data['role'] == 'tutor' ? 'tutor' : 'estudiante',
      'full_name': data['full_name'],
      'career_id': data['career_id'],
      'career_name': career.nombre,
      'academic_year': data['academic_year'],
      'created_at': '2026-11-02T18:00:00Z',
    };
    if (!confirmationRequired) {
      current = user;
      controller.add(RemoteAuthEvent.signedIn);
    }
    return RemoteSignUpResult(user: user, hasSession: !confirmationRequired);
  }

  @override
  Future<RemoteAuthUser> signIn({required String email, required String password}) async {
    lastEmail = email;
    if (hang) await Completer<void>().future;
    if (signInError != null) throw signInError!;
    final account = accounts[email];
    if (account == null || account.$1 != password) {
      throw const AuthApiException('Invalid login credentials',
          statusCode: '400', code: 'invalid_credentials');
    }
    current = account.$2;
    controller.add(RemoteAuthEvent.signedIn);
    return account.$2;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    current = null; // igual que supabase_flutter: borra la sesión local primero
    controller.add(RemoteAuthEvent.signedOut);
    if (signOutError != null) throw signOutError!;
  }

  @override
  Stream<RemoteAuthEvent> get events => controller.stream;
}

/// Cuentas locales del seed (para los tutores que siguen siendo locales).
class _LegacyUsers implements AuthRepository {
  @override
  Future<AppUser?> getUserById(String id) async => id == 'u-valeria'
      ? AppUser(
          id: 'u-valeria',
          nombre: 'Valeria',
          correo: 'valeria@esen.edu.sv',
          password: '',
          carrera: 'Economía',
          anioAcademico: 4,
          rol: UserRole.tutor,
          fechaCreacion: DateTime(2026, 10, 1),
        )
      : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoUniversities implements UniversityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoSubjects implements SubjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoTutors implements TutorRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoBookings implements BookingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoIncidents implements IncidentRepository, AdminIncidentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoReviews implements ReviewRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _NoNotifications implements NotificationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeProfiles profiles;
  late _FakeGateway gateway;
  late _FakeCatalog catalog;
  late SupabaseAuthRepository repo;

  SupabaseAuthRepository build({Duration timeout = const Duration(seconds: 2)}) =>
      SupabaseAuthRepository(
        gateway: gateway,
        profiles: profiles,
        catalog: RemoteCatalogCache(catalog: catalog, universities: catalog, timeout: timeout),
        legacyUsers: _LegacyUsers(),
        timeout: timeout,
        startupTimeout: timeout,
      );

  setUp(() {
    profiles = _FakeProfiles();
    gateway = _FakeGateway(profiles);
    catalog = _FakeCatalog();
    repo = build();
  });

  Future<AppUser> registerAna({UserRole rol = UserRole.estudiante, String password = 'clave123'}) =>
      repo.register(
        nombre: '  Ana López ',
        correo: ' ANA@esen.edu.sv ',
        password: password,
        universityId: 'esen',
        careerId: LocalSeed.software,
        carrera: 'Texto de la UI',
        anioAcademico: 2,
        rol: rol,
      );

  group('registro', () {
    test('crea la cuenta con metadata en uuid y devuelve el perfil de la base', () async {
      final user = await registerAna(rol: UserRole.tutor);

      expect(gateway.lastEmail, 'ana@esen.edu.sv');
      expect(gateway.lastSignUpData, {
        'university_id': _esenUuid,
        'career_id': _careerUuid(LocalSeed.software),
        'full_name': 'Ana López',
        'academic_year': 2,
        'role': 'tutor',
      });
      expect(user.id, gateway.current!.id);
      expect(user.correo, 'ana@esen.edu.sv');
      expect(user.password, isEmpty);
      expect(user.universityId, 'esen');
      expect(user.careerId, LocalSeed.software);
      expect(user.carrera, 'Ingeniería de Software y Negocios Digitales'); // de la base, no de la UI
      expect(user.rol, UserRole.tutor);
    });

    test('la app solo puede enviar estudiante o tutor como rol', () async {
      await registerAna();
      expect(gateway.lastSignUpData!['role'], 'estudiante');
      expect(UserRole.values.map((r) => r.name), ['estudiante', 'tutor']);
    });

    test('valida los datos antes de llamar a Supabase', () async {
      Future<void> attempt({String nombre = 'Ana', String correo = 'ana@esen.edu.sv',
              String password = 'clave123', String careerId = LocalSeed.eyn, int anio = 1}) =>
          repo.register(nombre: nombre, correo: correo, password: password,
              careerId: careerId, carrera: 'x', anioAcademico: anio, rol: UserRole.estudiante);

      for (final call in [
        () => attempt(nombre: ' '),
        () => attempt(correo: 'sin-arroba'),
        () => attempt(password: '123'),
        () => attempt(anio: 0),
        () => attempt(anio: 11),
        () => attempt(careerId: 'no-existe'),
      ]) {
        await expectLater(call(), throwsA(isA<RepositoryException>()));
      }
      expect(gateway.lastSignUpData, isNull);
    });

    test('universidad que no existe en Supabase', () async {
      await expectLater(
        repo.register(nombre: 'Ana', correo: 'a@b.co', password: 'clave123',
            universityId: 'otra-u', careerId: LocalSeed.eyn, carrera: 'x',
            anioAcademico: 1, rol: UserRole.estudiante),
        throwsA(isA<RepositoryException>()
            .having((e) => e.message, 'message', 'Esa universidad no está disponible.')),
      );
    });

    test('errores de Supabase con mensajes claros', () async {
      final cases = <Object, String>{
        const AuthApiException('User already registered', statusCode: '422', code: 'user_already_exists'):
            emailInUseMessage,
        AuthWeakPasswordException(message: 'weak', statusCode: '422', reasons: const ['length']):
            weakPasswordMessage,
        const AuthApiException('Database error saving new user', statusCode: '500', code: 'unexpected_failure'):
            registrationDataMessage,
        AuthRetryableFetchException(message: 'SocketException'): connectionMessage,
      };
      for (final entry in cases.entries) {
        gateway.signUpError = entry.key;
        await expectLater(registerAna(),
            throwsA(isA<RepositoryException>().having((e) => e.message, 'message', entry.value)));
      }
    });

    test('si el proyecto exige confirmar el correo lo explica', () async {
      gateway.confirmationRequired = true;
      await expectLater(registerAna(),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('confirmar'))));
    });

    test('tiempo de espera agotado', () async {
      repo = build(timeout: const Duration(milliseconds: 50));
      gateway.hang = true;
      await expectLater(registerAna(),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', timeoutMessage)));
    });
  });

  group('inicio y cierre de sesión', () {
    setUp(() async {
      await registerAna();
      await repo.logout();
    });

    test('inicio de sesión exitoso', () async {
      final user = await repo.login(correo: 'Ana@ESEN.edu.sv', password: 'clave123', universityId: 'esen');
      expect(user.nombre, 'Ana López');
      expect(user.universityId, 'esen');
      expect(gateway.current, isNotNull);
    });

    test('credenciales incorrectas', () async {
      await expectLater(repo.login(correo: 'ana@esen.edu.sv', password: 'mala'),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', invalidCredentialsMessage)));
      expect(gateway.current, isNull);
    });

    test('cuenta de otra universidad: no deja la sesión iniciada', () async {
      await expectLater(
          repo.login(correo: 'ana@esen.edu.sv', password: 'clave123', universityId: 'otra-u'),
          throwsA(isA<UniversityMismatchException>()));
      expect(gateway.current, isNull);
    });

    test('una cuenta administradora no entra a la app', () async {
      final id = gateway.accounts['ana@esen.edu.sv']!.$2.id;
      profiles.rows[id]!['role'] = 'administrador';
      await expectLater(repo.login(correo: 'ana@esen.edu.sv', password: 'clave123'),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('administrador'))));
      expect(gateway.current, isNull);
    });

    test('sin conexión o sin respuesta', () async {
      gateway.signInError = AuthRetryableFetchException(message: 'Failed host lookup');
      await expectLater(repo.login(correo: 'ana@esen.edu.sv', password: 'clave123'),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', connectionMessage)));

      gateway.signInError = null;
      gateway.hang = true;
      repo = build(timeout: const Duration(milliseconds: 50));
      await expectLater(repo.login(correo: 'ana@esen.edu.sv', password: 'clave123'),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', timeoutMessage)));
    });

    test('cerrar sesión, también sin red, nunca lanza', () async {
      await repo.login(correo: 'ana@esen.edu.sv', password: 'clave123');
      gateway.signOutError = AuthRetryableFetchException();
      await repo.logout();
      expect(gateway.current, isNull);
      expect(gateway.signOutCalls, greaterThanOrEqualTo(2));
    });
  });

  group('sesión persistida', () {
    test('sin sesión guardada', () async {
      expect((await repo.currentSession()).iniciada, isFalse);
    });

    test('recupera la sesión guardada con el perfil de la base', () async {
      final ana = await registerAna();
      final restored = build(); // como al reabrir la app
      final session = await restored.currentSession();
      expect(session.usuario?.id, ana.id);
      expect(session.rol, UserRole.estudiante);
      expect(gateway.refreshCalls, 1);
    });

    test('sin red al arrancar: sesión vacía, sin borrar la sesión guardada', () async {
      await registerAna();
      profiles.error = AuthRetryableFetchException();
      expect((await build().currentSession()).iniciada, isFalse);
      expect(gateway.current, isNotNull);
      expect(gateway.signOutCalls, 0);
    });

    test('avisa cuando la sesión remota termina', () async {
      final events = <Session>[];
      final sub = repo.sessionChanges.listen(events.add);
      gateway.controller.add(RemoteAuthEvent.signedIn);
      gateway.controller.add(RemoteAuthEvent.other);
      gateway.controller.add(RemoteAuthEvent.signedOut);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.iniciada, isFalse);
      await sub.cancel();
    });

    test('SessionStore recupera la sesión y reacciona al cierre remoto', () async {
      await registerAna();
      final store = SessionStore(build());
      await store.load();
      expect(store.isLoggedIn, isTrue);

      gateway.current = null;
      gateway.controller.add(RemoteAuthEvent.signedOut); // p. ej. token revocado
      await Future<void>.delayed(Duration.zero);
      expect(store.isLoggedIn, isFalse);
      store.dispose();
    });

    test('SessionStore: registro, inicio y cierre con Supabase', () async {
      final store = SessionStore(repo);
      expect(await store.register(nombre: 'Luis', correo: 'luis@esen.edu.sv', password: 'clave123',
          careerId: LocalSeed.eyn, carrera: 'x', anioAcademico: 1, rol: UserRole.tutor), isTrue);
      expect(store.isTutor, isTrue);
      await store.logout();
      expect(store.isLoggedIn, isFalse);
      expect(await store.login(correo: 'luis@esen.edu.sv', password: 'mala'), isFalse);
      expect(store.error, invalidCredentialsMessage);
      expect(await store.login(correo: 'luis@esen.edu.sv', password: 'clave123'), isTrue);
      store.dispose();
    });
  });

  group('otras cuentas y perfil', () {
    test('cuentas del seed local por id de texto; remotas sin correo', () async {
      final ana = await registerAna(rol: UserRole.tutor);
      await repo.logout();
      await repo.register(nombre: 'Beto', correo: 'beto@esen.edu.sv', password: 'clave123',
          careerId: LocalSeed.eyn, carrera: 'x', anioAcademico: 3, rol: UserRole.estudiante);

      expect((await repo.getUserById('u-valeria'))?.nombre, 'Valeria');
      final other = await repo.getUserById(ana.id);
      expect(other?.nombre, 'Ana López');
      expect(other?.correo, isEmpty);
      expect(other?.rol, UserRole.tutor);
      expect(await repo.getUserById('00000000-0000-4000-8000-999999999999'), isNull);

      profiles.rows[ana.id]!['role'] = 'administrador';
      expect(await repo.getUserById(ana.id), isNull);
      profiles.error = Exception('sin red');
      expect(await repo.getUserById(ana.id), isNull);
    });


    test('el catálogo remoto se consulta una sola vez', () async {
      await registerAna();
      await repo.logout();
      await repo.login(correo: 'ana@esen.edu.sv', password: 'clave123', universityId: 'esen');
      expect(catalog.fetches, 1);
    });
  });

  group('actualización del perfil (Fase 14.6)', () {
    Future<AppUser> update(AppUser user,
            {String nombre = ' Ana María ', String careerId = LocalSeed.eyn, int anio = 3}) =>
        repo.updateProfile(
            userId: user.id, nombre: nombre, careerId: careerId, carrera: 'texto ignorado', anioAcademico: anio);

    test('actualiza nombre, carrera y año del usuario con sesión', () async {
      final ana = await registerAna();
      final updated = await update(ana);

      expect(updated.id, ana.id);
      expect(updated.nombre, 'Ana María');
      expect(updated.careerId, LocalSeed.eyn);
      expect(updated.carrera, 'Licenciatura en Economía y Negocios'); // copiado por la base
      expect(updated.anioAcademico, 3);
      expect(updated.rol, ana.rol);
      expect(updated.universityId, 'esen');
      expect(updated.password, isEmpty);
      // Solo se envían columnas editables, con la carrera en uuid.
      expect(profiles.lastUpdate, {
        'id': ana.id,
        'full_name': 'Ana María',
        'career_id': _careerUuid(LocalSeed.eyn),
        'academic_year': 3,
      });
      // Queda guardado en "la base": al recuperar la sesión se ve el cambio.
      expect((await build().currentSession()).usuario?.nombre, 'Ana María');
    });

    test('nunca modifica el perfil de otro usuario', () async {
      final ana = await registerAna();
      await repo.logout();
      await repo.register(nombre: 'Beto', correo: 'beto@esen.edu.sv', password: 'clave123',
          careerId: LocalSeed.eyn, carrera: 'x', anioAcademico: 1, rol: UserRole.estudiante);

      await expectLater(update(ana),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('propio perfil'))));
      expect(profiles.lastUpdate, isNull);
      expect(profiles.rows[ana.id]!['full_name'], 'Ana López');
    });

    test('si RLS no deja actualizar, informa el error', () async {
      final ana = await registerAna();
      profiles.sessionUserId = 'otro'; // la base no reconoce la sesión
      await expectLater(update(ana), throwsA(isA<RepositoryException>()));
    });

    test('sin sesión no se puede editar', () async {
      final ana = await registerAna();
      await repo.logout();
      await expectLater(update(ana),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('Inicia sesión'))));
    });

    test('valida nombre, año y carrera de su universidad', () async {
      final ana = await registerAna();
      for (final call in [
        () => update(ana, nombre: ' '),
        () => update(ana, anio: 0),
        () => update(ana, anio: 11),
        () => update(ana, careerId: 'carrera-de-otra-u'),
      ]) {
        await expectLater(call(), throwsA(isA<RepositoryException>()));
      }
      expect(profiles.lastUpdate, isNull);
    });

    test('el rol y la universidad no se pueden cambiar desde la app', () async {
      final ana = await registerAna(rol: UserRole.tutor);
      final updated = await update(ana);
      expect(updated.rol, UserRole.tutor);
      expect(profiles.lastUpdate!.keys, isNot(contains('role')));
      expect(profiles.lastUpdate!.keys, isNot(contains('university_id')));
    });

    test('errores de conexión al guardar', () async {
      final ana = await registerAna();
      profiles.error = AuthRetryableFetchException();
      await expectLater(update(ana),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', connectionMessage)));
    });

    test('SessionStore.updateProfile con Supabase', () async {
      final store = SessionStore(repo);
      await store.register(nombre: 'Luis', correo: 'luis@esen.edu.sv', password: 'clave123',
          careerId: LocalSeed.eyn, carrera: 'x', anioAcademico: 1, rol: UserRole.estudiante);
      expect(await store.updateProfile(nombre: 'Luis Pérez', careerId: LocalSeed.software, anioAcademico: 2),
          isTrue);
      expect(store.user?.nombre, 'Luis Pérez');
      expect(store.user?.careerId, LocalSeed.software);
      store.dispose();
    });
  });

  group('mensajes de error', () {
    test('nunca copian el texto del servidor', () {
      const leaky = AuthApiException('password=secreto123 token=abc', statusCode: '400', code: 'algo_raro');
      final message = describeSupabaseAuthError(leaky).message;
      expect(message, genericAuthMessage);
      expect(message, isNot(contains('secreto123')));
    });

    test('límite de intentos, correo inválido y tiempo agotado', () {
      expect(describeSupabaseAuthError(const AuthApiException('x', statusCode: '429')).message, rateLimitMessage);
      expect(describeSupabaseAuthError(const AuthApiException('x', code: 'email_address_invalid')).message,
          invalidEmailMessage);
      expect(describeSupabaseAuthError(TimeoutException('x')).message, timeoutMessage);
      expect(describeSupabaseAuthError(Exception('red')).message, connectionMessage);
    });
  });

  group('selección del modo', () {
    final legacy = _LegacyUsers();
    AppDataSources sources({required bool remote}) => AppDataSources(
          auth: remote ? build() : legacy,
          universities: _NoUniversities(),
          subjects: _NoSubjects(),
          tutors: _NoTutors(),
          bookings: _NoBookings(),
          incidents: _NoIncidents(),
          adminIncidents: _NoIncidents(),
          reviews: _NoReviews(),
          notifications: _NoNotifications(),
          remote: remote,
        );

    test('local por defecto y si Supabase no está inicializado', () {
      expect(AuthMode.parse(''), AuthMode.local);
      expect(AuthMode.parse(' Supabase '), AuthMode.supabase);
      expect(AuthMode.fromEnvironment(), AuthMode.local);
      final local = sources(remote: false);
      AppDataSources remote() => throw StateError('no debe crearse');
      expect(selectDataSources(mode: AuthMode.local, supabaseReady: true, local: local, remote: remote, log: (_) {}),
          same(local));
      expect(selectDataSources(mode: AuthMode.supabase, supabaseReady: false, local: local, remote: remote, log: (_) {}),
          same(local));
    });

    test('si no se pueden crear los repositorios remotos, sigue en local', () {
      final local = sources(remote: false);
      expect(
        selectDataSources(mode: AuthMode.supabase, supabaseReady: true, local: local,
            remote: () => throw StateError('x'), log: (_) {}),
        same(local),
      );
      final remote = sources(remote: true);
      expect(selectDataSources(mode: AuthMode.supabase, supabaseReady: true, local: local,
          remote: () => remote, log: (_) {}), same(remote));
    });

    test('Supabase no inicializado: no se crean los repositorios remotos', () {
      SupabaseBootstrap.resetForTesting();
      expect(() => SupabaseAuthRepository.fromInitializedClient(), throwsStateError);
    });
  });
}
