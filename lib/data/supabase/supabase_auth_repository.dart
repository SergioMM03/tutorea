import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'remote_auth_gateway.dart';
import 'remote_catalog.dart';
import 'remote_catalog_repositories.dart';
import 'supabase_auth_errors.dart';

/// AuthRepository con Supabase Auth (Fase 14.5) y perfiles en `profiles` (Fase 14.6).
///
/// Cómo encaja con el esquema (migraciones 06 y 08):
/// - El registro llama a `auth.signUp` con metadata: university_id, career_id
///   (uuid), full_name, academic_year y role. El trigger `handle_new_user` crea la
///   fila de `profiles` en la misma transacción; si un dato no es válido, el
///   registro completo falla. Flutter nunca inserta en `profiles`.
/// - El rol: la app solo envía 'estudiante' o 'tutor' (UserRole no tiene otro
///   valor) y el trigger convierte cualquier otro valor en 'estudiante'. El rol
///   que usa la app siempre se lee de `profiles`, nunca de la metadata.
/// - Los ids de Flutter (slug) se traducen a uuid con el catálogo remoto
///   (decisión 17), compartido con los repositorios de catálogo.
/// - [updateProfile] solo cambia nombre, carrera y año del usuario con sesión;
///   RLS, los permisos de columna y el trigger de guarda lo garantizan también
///   en la base.
///
/// Transición: el resto de la app (tutores, reservas, catálogo) sigue siendo
/// local. Para que los tutores del seed local sigan mostrando su nombre,
/// [getUserById] consulta [legacyUsers] cuando el id no es un uuid.
class SupabaseAuthRepository implements AuthRepository, AuthSessionChanges {
  final RemoteAuthGateway _gateway;
  final RemoteProfileSource _profiles;
  final RemoteCatalogCache _catalog;
  final AuthRepository? _legacyUsers;
  final Duration _timeout;
  final Duration _startupTimeout;

  SupabaseAuthRepository({
    required RemoteAuthGateway gateway,
    required RemoteProfileSource profiles,
    required RemoteCatalogCache catalog,
    AuthRepository? legacyUsers,
    Duration timeout = const Duration(seconds: 15),
    Duration startupTimeout = const Duration(seconds: 5),
  })  : _gateway = gateway,
        _profiles = profiles,
        _catalog = catalog,
        _legacyUsers = legacyUsers,
        _timeout = timeout,
        _startupTimeout = startupTimeout;

  /// Con el cliente global. Lanza StateError si Supabase no está inicializado.
  factory SupabaseAuthRepository.fromInitializedClient({
    AuthRepository? legacyUsers,
    RemoteCatalogCache? catalog,
  }) {
    final client = initializedSupabaseClient();
    final source = SupabaseCatalogSource(client);
    return SupabaseAuthRepository(
      gateway: SupabaseAuthGateway(client.auth),
      profiles: SupabaseProfileSource(client),
      catalog: catalog ?? RemoteCatalogCache(catalog: source, universities: source),
      legacyUsers: legacyUsers,
    );
  }

  static final RegExp _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  static String _normalize(String correo) => correo.trim().toLowerCase();

  // ---------------------------------------------------------------- registro

  @override
  Future<AppUser> register({
    required String nombre,
    required String correo,
    required String password,
    String universityId = kDefaultUniversityId,
    required String careerId,
    required String carrera,
    required int anioAcademico,
    required UserRole rol,
  }) async {
    final email = _normalize(correo);
    // Mismas reglas que LocalAuthRepository y handle_new_user, antes de llamar
    // al servidor (Supabase Auth no devuelve el motivo exacto del trigger).
    final name = _validName(nombre);
    if (!email.contains('@') || !email.contains('.')) {
      throw const RepositoryException(invalidEmailMessage);
    }
    if (password.length < 6) {
      throw const RepositoryException('La contraseña debe tener al menos 6 caracteres.');
    }
    _validYear(anioAcademico);

    final catalog = await _guard(() => _catalogFor(universityId));
    final careerUuid = _careerUuid(catalog, careerId);

    final result = await _guard(() => _gateway.signUp(
          email: email,
          password: password,
          data: {
            'university_id': catalog.universityUuid,
            'career_id': careerUuid,
            'full_name': name,
            'academic_year': anioAcademico,
            'role': rol.name, // solo 'estudiante' o 'tutor'
          },
        ));

    if (!result.hasSession) {
      throw const RepositoryException(
          'La cuenta se creó, pero el proyecto pide confirmar el correo. '
          'En el MVP la confirmación debe estar desactivada.');
    }
    try {
      return await _guard(() => _ownUser(result.user));
    } catch (_) {
      await _signOutQuietly();
      throw const RepositoryException(
          'La cuenta se creó, pero no se pudo leer tu perfil. Inicia sesión de nuevo.');
    }
  }

  // ---------------------------------------------------------------- sesión

  @override
  Future<AppUser> login({
    required String correo,
    required String password,
    String? universityId,
  }) async {
    final remoteUser = await _guard(
        () => _gateway.signIn(email: _normalize(correo), password: password));
    final AppUser user;
    try {
      user = await _guard(() => _ownUser(remoteUser));
    } catch (_) {
      await _signOutQuietly(); // no se deja una sesión sin perfil utilizable
      rethrow;
    }
    if (universityId != null && user.universityId != universityId) {
      await _signOutQuietly();
      throw const UniversityMismatchException();
    }
    return user;
  }

  /// Nunca lanza: Supabase borra la sesión local antes de avisar al servidor,
  /// así que aunque falle la red la sesión queda cerrada en el dispositivo.
  @override
  Future<void> logout() => _signOutQuietly();

  /// Sesión persistida por supabase_flutter. Sin red o si el perfil no se puede
  /// leer, devuelve una sesión vacía sin borrar la sesión guardada, y no espera
  /// más de [_startupTimeout] (la app no depende de Internet para arrancar).
  @override
  Future<Session> currentSession() async {
    final remoteUser = _gateway.currentUser;
    if (remoteUser == null) return const Session.empty();
    try {
      await _gateway.refreshIfExpired().timeout(_startupTimeout);
      final user = await _ownUser(remoteUser).timeout(_startupTimeout);
      return Session.forUser(user);
    } catch (_) {
      return const Session.empty();
    }
  }

  @override
  Stream<Session> get sessionChanges => _gateway.events
      .where((event) => event == RemoteAuthEvent.signedOut)
      .map<Session>((_) => const Session.empty())
      .handleError((Object _) {}); // un error del stream no debe romper la app

  // ---------------------------------------------------------------- perfiles

  /// Actualiza nombre, carrera y año del usuario CON SESIÓN. Nunca otro perfil:
  /// [userId] debe ser el de la sesión (y RLS lo exige también). La carrera debe
  /// ser de la universidad de la cuenta; [carrera] (texto) se ignora porque la
  /// base copia el nombre desde la carrera elegida.
  @override
  Future<AppUser> updateProfile({
    required String userId,
    required String nombre,
    required String careerId,
    required String carrera,
    required int anioAcademico,
  }) async {
    final current = _gateway.currentUser;
    if (current == null) {
      throw const RepositoryException('Inicia sesión para editar tu perfil.');
    }
    if (current.id != userId) {
      throw const RepositoryException('Solo puedes editar tu propio perfil.');
    }
    final name = _validName(nombre);
    _validYear(anioAcademico);

    final own = await _guard(() => _profiles.ownProfile(current.id));
    if (own == null) throw const RepositoryException(profileReadMessage);
    final catalog = await _guard(() => _catalogForUuid(_text(own, 'university_id')));
    final careerUuid = _careerUuid(catalog, careerId);

    final updated = await _guard(() => _profiles.updateOwnProfile(
          userId: current.id,
          fullName: name,
          careerUuid: careerUuid,
          academicYear: anioAcademico,
        ));
    if (updated == null) {
      throw const RepositoryException('No se pudo guardar tu perfil. Intenta de nuevo.');
    }
    return _guard(() => _userFromRow(current, updated));
  }

  /// Cuenta por id. Ids que no son uuid (cuentas del seed local) se buscan en
  /// [legacyUsers]. Otras cuentas remotas se leen de `public_profiles`, sin correo.
  /// Nunca lanza: si no se puede leer, devuelve null.
  @override
  Future<AppUser?> getUserById(String id) async {
    if (!_uuid.hasMatch(id)) {
      final legacy = _legacyUsers;
      return legacy == null ? null : await legacy.getUserById(id);
    }
    try {
      final current = _gateway.currentUser;
      if (current != null && current.id == id) return await _ownUser(current).timeout(_timeout);
      final row = await _profiles.publicProfile(id).timeout(_timeout);
      if (row == null) return null;
      final role = _role(row['role']);
      if (role == null) return null; // administradores no se muestran como usuarios
      final catalog = await _catalogForUuid(_text(row, 'university_id'));
      return AppUser(
        id: _text(row, 'id'),
        nombre: _text(row, 'full_name'),
        correo: '', // public_profiles no expone correos
        password: '',
        universityId: catalog.university.id,
        careerId: null, // public_profiles no expone career_id
        carrera: _text(row, 'career_name'),
        anioAcademico: _int(row, 'academic_year'),
        rol: role,
        fechaCreacion: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- interno

  /// Perfil propio → AppUser (sin contraseña).
  Future<AppUser> _ownUser(RemoteAuthUser remoteUser) async {
    final row = await _profiles.ownProfile(remoteUser.id);
    if (row == null) {
      throw const RepositoryException('Tu cuenta no tiene perfil. Contacta al equipo de Tutorea.');
    }
    return _userFromRow(remoteUser, row);
  }

  /// Fila de `profiles` → AppUser. El rol siempre sale de la base.
  Future<AppUser> _userFromRow(RemoteAuthUser remoteUser, Map<String, dynamic> row) async {
    if (row['id'] != remoteUser.id) throw const RepositoryException(profileReadMessage);
    final roleText = row['role'];
    final role = _role(roleText);
    if (role == null) {
      throw RepositoryException(roleText == 'administrador'
          ? 'Las cuentas de administrador todavía no tienen acceso desde la app.'
          : 'Tu cuenta tiene un rol no válido. Contacta al equipo de Tutorea.');
    }
    final catalog = await _catalogForUuid(_text(row, 'university_id'));
    final careerUuid = row['career_id'];
    final careerSlug = catalog.careerUuidBySlug.entries
        .where((e) => e.value == careerUuid)
        .map((e) => e.key)
        .firstOrNull;
    return AppUser(
      id: remoteUser.id,
      nombre: _text(row, 'full_name'),
      correo: remoteUser.email,
      password: '', // la contraseña nunca se guarda en el modelo
      universityId: catalog.university.id,
      careerId: careerSlug,
      carrera: _text(row, 'career_name'),
      anioAcademico: _int(row, 'academic_year'),
      rol: role,
      fechaCreacion: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
    );
  }

  Future<RemoteCatalog> _catalogFor(String universitySlug) async {
    final catalog = await _catalog.bySlug(universitySlug);
    if (catalog == null) throw const RepositoryException('Esa universidad no está disponible.');
    return catalog;
  }

  Future<RemoteCatalog> _catalogForUuid(String universityUuid) async {
    final catalog = await _catalog.byUuid(universityUuid);
    if (catalog == null) throw const RepositoryException('Tu universidad no está disponible.');
    return catalog;
  }

  static String _careerUuid(RemoteCatalog catalog, String careerId) {
    final uuid = catalog.careerUuidBySlug[careerId];
    if (uuid == null) throw const RepositoryException('Elige una carrera de tu universidad.');
    return uuid;
  }

  static String _validName(String nombre) {
    final name = nombre.trim();
    if (name.length < 2 || name.length > 120) {
      throw const RepositoryException('Escribe tu nombre (2 a 120 caracteres).');
    }
    return name;
  }

  static void _validYear(int anioAcademico) {
    if (anioAcademico < 1 || anioAcademico > 10) {
      throw const RepositoryException('El año académico no es válido.');
    }
  }

  /// Ejecuta una llamada remota con tiempo límite y errores traducidos.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } catch (error) {
      throw describeSupabaseAuthError(error);
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await _gateway.signOut().timeout(_timeout);
    } catch (_) {
      // La sesión local ya se borró; el aviso al servidor puede fallar sin red.
    }
  }

  static UserRole? _role(Object? value) => switch (value) {
        'estudiante' => UserRole.estudiante,
        'tutor' => UserRole.tutor,
        _ => null,
      };

  static String _text(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    throw const RepositoryException(profileReadMessage);
  }

  static int _int(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is num) return value.toInt();
    throw const RepositoryException(profileReadMessage);
  }
}
