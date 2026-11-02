import 'package:flutter/foundation.dart';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';

/// Sesión del usuario: quién está dentro y con qué rol.
/// UI → SessionStore → AuthRepository → almacenamiento.
///
/// También:
/// - resuelve ids de otras cuentas a nombres (ej. el estudiante de una
///   solicitud que ve el tutor) con [loadUsers] / [userById];
/// - guarda la universidad elegida en la pantalla inicial
///   ([selectedUniversity]): es contexto para Login y Registro, nunca cambia
///   la universidad de una cuenta.
class SessionStore extends ChangeNotifier {
  final AuthRepository _auth;
  final UniversityRepository? _universities; // universidades y selección inicial

  SessionStore(this._auth, [this._universities]);

  Session _session = const Session.empty();
  bool _initialized = false;
  bool _loading = false;
  String? _error;

  /// Cuentas ya consultadas por id (sin contraseña visible en la UI).
  final Map<String, AppUser> _users = {};

  /// Nombre de cada universidad ya consultada, por id.
  final Map<String, String> _universityNames = {};

  List<University> _activeUniversities = const [];
  bool _universitiesLoaded = false;
  University? _selectedUniversity;
  List<Career> _selectedCareers = const [];
  bool _universityMismatch = false;

  // ---------------- Lectura ----------------

  Session get session => _session;
  AppUser? get user => _session.usuario;
  UserRole? get role => _session.rol;

  bool get isLoggedIn => _session.iniciada;
  bool get isStudent => role == UserRole.estudiante;
  bool get isTutor => role == UserRole.tutor;

  /// Ya se revisó si había una sesión guardada (para decidir la pantalla inicial).
  bool get initialized => _initialized;
  bool get isLoading => _loading;

  /// Último error para mostrar en pantalla (ej. "Correo o contraseña incorrectos.").
  String? get error => _error;

  /// Cuenta por id, o null si aún no se cargó con [loadUsers].
  AppUser? userById(String id) => id == user?.id ? user : _users[id];

  /// Nombre de la universidad, o '' si aún no se cargó.
  String universityName(String universityId) => _universityNames[universityId] ?? '';

  /// Universidades activas (UniversityRepository.getActive).
  List<University> get activeUniversities => _activeUniversities;

  /// Ya se consultaron las universidades activas.
  bool get universitiesLoaded => _universitiesLoaded;

  /// Universidad elegida en la pantalla inicial (null = ninguna todavía).
  University? get selectedUniversity => _selectedUniversity;

  /// Carreras de la universidad elegida (para el registro).
  List<Career> get selectedUniversityCareers => _selectedCareers;

  /// El último intento de login falló porque la cuenta es de otra universidad.
  bool get universityMismatch => _universityMismatch;

  // ---------------- Acciones ----------------

  /// Recupera la sesión guardada y la universidad elegida al abrir la app.
  Future<void> load() async {
    _session = await _auth.currentSession();
    _initialized = true;
    notifyListeners();
    await loadUniversities();
  }

  /// Carga las universidades activas y recupera la última elegida en este
  /// dispositivo (si sigue activa).
  Future<void> loadUniversities() async {
    final universities = _universities;
    if (universities != null) {
      try {
        _activeUniversities = await universities.getActive();
        final savedId = await universities.getSelectedUniversityId();
        _selectedUniversity =
            _activeUniversities.where((u) => u.id == savedId).firstOrNull;
        for (final u in _activeUniversities) {
          _universityNames[u.id] = u.nombre;
        }
        _selectedCareers = _selectedUniversity == null
            ? const []
            : await universities.getCareers(_selectedUniversity!.id);
      } catch (_) {
        _error = 'No se pudieron cargar las universidades. Intenta de nuevo.';
      }
    }
    _universitiesLoaded = true;
    notifyListeners();
  }

  /// Elige la universidad (solo una activa) y la guarda en el dispositivo.
  Future<bool> selectUniversity(String universityId) async {
    final universities = _universities;
    final university =
        _activeUniversities.where((u) => u.id == universityId).firstOrNull;
    if (universities == null || university == null) {
      _error = 'Esa universidad no está disponible.';
      notifyListeners();
      return false;
    }
    await universities.saveSelectedUniversityId(university.id);
    _selectedUniversity = university;
    _selectedCareers = await universities.getCareers(university.id);
    _universityMismatch = false;
    _error = null;
    notifyListeners();
    return true;
  }

  /// Devuelve true si entró; si no, el motivo queda en [error].
  /// Con universidades disponibles, exige una universidad elegida y que la
  /// cuenta pertenezca a ella (lo valida AuthRepository.login).
  Future<bool> login({required String correo, required String password}) {
    _universityMismatch = false;
    final checkUniversity = _universities != null;
    if (checkUniversity && _selectedUniversity == null) {
      _error = 'Selecciona tu universidad antes de iniciar sesión.';
      notifyListeners();
      return Future.value(false);
    }
    return _run(() async {
      try {
        final user = await _auth.login(
          correo: correo,
          password: password,
          universityId: checkUniversity ? _selectedUniversity!.id : null,
        );
        _session = Session.forUser(user);
      } on UniversityMismatchException {
        _universityMismatch = true;
        rethrow;
      }
    });
  }

  /// Crea la cuenta y deja la sesión iniciada.
  /// Con universidades disponibles, la cuenta se crea en [universityId] o, si
  /// no se indica, en la universidad elegida; debe ser una universidad activa
  /// y la carrera ([careerId], obligatoria) debe pertenecer a ella.
  Future<bool> register({
    required String nombre,
    required String correo,
    required String password,
    String? universityId,
    required String careerId,
    required String carrera,
    required int anioAcademico,
    required UserRole rol,
  }) =>
      _run(() async {
        final universities = _universities;
        var targetId = universityId ?? _selectedUniversity?.id;
        if (universities == null) {
          targetId ??= kDefaultUniversityId; // sin catálogo (pruebas antiguas)
        } else {
          final university = targetId == null ? null : await universities.getById(targetId);
          if (university == null || !university.activo) {
            throw const RepositoryException(
                'Selecciona una universidad válida antes de crear tu cuenta.');
          }
          final career = await universities.getCareerById(careerId);
          if (career == null || career.universityId != university.id) {
            throw const RepositoryException('Elige una carrera de tu universidad.');
          }
        }
        final user = await _auth.register(
          nombre: nombre,
          correo: correo,
          password: password,
          universityId: targetId!,
          careerId: careerId,
          carrera: carrera,
          anioAcademico: anioAcademico,
          rol: rol,
        );
        _session = Session.forUser(user);
      });

  /// Carreras de la universidad del usuario con sesión (para editar su perfil).
  Future<List<Career>> careersOfCurrentUser() async {
    final universities = _universities;
    final current = user;
    if (universities == null || current == null) return const [];
    return universities.getCareers(current.universityId);
  }

  /// Guarda nombre, carrera y año del usuario con sesión y lo refleja de
  /// inmediato en [user]. Correo, universidad, rol e id no cambian.
  /// La carrera debe ser de la universidad de la cuenta.
  Future<bool> updateProfile({
    required String nombre,
    required String careerId,
    required int anioAcademico,
  }) =>
      _run(() async {
        final current = user;
        if (current == null) {
          throw const RepositoryException('Inicia sesión para editar tu perfil.');
        }
        final universities = _universities;
        var carrera = current.carrera;
        if (universities != null) {
          final career = await universities.getCareerById(careerId);
          if (career == null || career.universityId != current.universityId) {
            throw const RepositoryException('Elige una carrera de tu universidad.');
          }
          carrera = career.nombre;
        }
        final updated = await _auth.updateProfile(
          userId: current.id,
          nombre: nombre,
          careerId: careerId,
          carrera: carrera,
          anioAcademico: anioAcademico,
        );
        _session = Session.forUser(updated);
        if (_users.containsKey(updated.id)) _users[updated.id] = updated;
      });

  Future<void> logout() async {
    await _auth.logout();
    _session = const Session.empty();
    _users.clear();
    _error = null;
    notifyListeners();
  }

  /// Carga las cuentas indicadas (y el nombre de sus universidades)
  /// para mostrarlas por nombre. Las que ya estaban cargadas no se repiten.
  Future<void> loadUsers(Iterable<String> ids) async {
    var changed = false;
    for (final id in ids.toSet()) {
      if (!_users.containsKey(id)) {
        final found = await _auth.getUserById(id);
        if (found != null) {
          _users[id] = found;
          changed = true;
        }
      }
    }
    final universityIds = {
      if (user != null) user!.universityId,
      for (final u in _users.values) u.universityId,
    };
    final universities = _universities;
    for (final id in universityIds) {
      if (_universityNames.containsKey(id) || universities == null) continue;
      final university = await universities.getById(id);
      if (university != null) {
        _universityNames[id] = university.nombre;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void clearError() {
    if (_error == null && !_universityMismatch) return;
    _error = null;
    _universityMismatch = false;
    notifyListeners();
  }

  // ---------------- Interno ----------------

  /// Ejecuta una acción con estado de carga y captura el error de negocio.
  Future<bool> _run(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on RepositoryException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Ocurrió un error inesperado. Intenta de nuevo.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
