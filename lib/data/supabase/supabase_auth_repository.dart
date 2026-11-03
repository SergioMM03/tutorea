import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'remote_auth_gateway.dart';
import 'remote_catalog.dart';
import 'supabase_auth_errors.dart';

/// AuthRepository con Supabase Auth (Fase 14.5).
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
///   (decisión 17).
///
/// Transición: el resto de la app (tutores, reservas, catálogo) sigue siendo
/// local. Para que los tutores del seed local sigan mostrando su nombre,
/// [getUserById] consulta [legacyUsers] cuando el id no es un uuid.
class SupabaseAuthRepository implements AuthRepository, AuthSessionChanges {
  final RemoteAuthGateway _gateway;
  final RemoteProfileSource _profiles;
  final CatalogRowsSource _catalog;
  final AuthRepository? _legacyUsers;
  final Duration _timeout;
  final Duration _startupTimeout;

  final Map<String, RemoteCatalog> _catalogBySlug = {};
  final Map<String, String> _slugByUniversityUuid = {};

  SupabaseAuthRepository({
    required RemoteAuthGateway gateway,
    required RemoteProfileSource profiles,
    required CatalogRowsSource catalog,
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
  factory SupabaseAuthRepository.fromInitializedClient({AuthRepository? legacyUsers}) {
    final client = initializedSupabaseClient();
    return SupabaseAuthRepository(
      gateway: SupabaseAuthGateway(client.auth),
      profiles: SupabaseProfileSource(client),
      catalog: SupabaseCatalogSource(client),
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
    final name = nombre.trim();
    // Mismas reglas que LocalAuthRepository y handle_new_user, antes de llamar
    // al servidor (Supabase Auth no devuelve el motivo exacto del trigger).
    if (name.length < 2) throw const RepositoryException('Escribe tu nombre.');
    if (!email.contains('@') || !email.contains('.')) {
      throw const RepositoryException(invalidEmailMessage);
    }
    if (password.length < 6) {
      throw const RepositoryException('La contraseña debe tener al menos 6 caracteres.');
    }
    if (anioAcademico < 1 || anioAcademico > 10) {
      throw const RepositoryException('El año académico no es válido.');
    }

    final catalog = await _guard(() => _catalogFor(universityId));
    final careerUuid = catalog.careerUuidBySlug[careerId];
    if (careerUuid == null) {
      throw const RepositoryException('Elige una carrera de tu universidad.');
    }

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

  /// La edición del perfil en Supabase corresponde a la Fase 14.6.
  @override
  Future<AppUser> updateProfile({
    required String userId,
    required String nombre,
    required String careerId,
    required String carrera,
    required int anioAcademico,
  }) async {
    throw const RepositoryException(
        'Editar el perfil con Supabase todavía no está disponible (Fase 14.6).');
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
    final cached = _catalogBySlug[universitySlug];
    if (cached != null) return cached;
    final rows = await _catalog.fetch(universitySlug);
    if (rows == null) throw const RepositoryException('Esa universidad no está disponible.');
    final RemoteCatalog catalog;
    try {
      catalog = CatalogMapper.map(rows);
    } on CatalogMappingException {
      throw const RepositoryException('No se pudo leer el catálogo de tu universidad.');
    }
    _catalogBySlug[universitySlug] = catalog;
    _slugByUniversityUuid[catalog.universityUuid] = universitySlug;
    return catalog;
  }

  Future<RemoteCatalog> _catalogForUuid(String universityUuid) async {
    final slug = _slugByUniversityUuid[universityUuid] ??
        await _profiles.universitySlugById(universityUuid);
    if (slug == null) throw const RepositoryException('Tu universidad no está disponible.');
    return _catalogFor(slug);
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
