import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../../utils/id_generator.dart';
import 'local_database.dart';

/// Cuentas y sesión guardadas en el teléfono.
/// Solo para el MVP: la contraseña se guarda tal cual en el dispositivo.
/// Con Firebase Auth, esta clase se reemplaza por FirebaseAuthRepository.
class LocalAuthRepository implements AuthRepository {
  final LocalDatabase _db;

  LocalAuthRepository(this._db);

  List<AppUser> _users() =>
      _db.readList(LocalDatabase.users).map(AppUser.fromJson).toList();

  Future<void> _saveUsers(List<AppUser> users) =>
      _db.writeList(LocalDatabase.users, users.map((u) => u.toJson()).toList());

  Future<void> _startSession(AppUser user) =>
      _db.writeMap(LocalDatabase.session, Session.forUser(user).toJson());

  static String _normalize(String correo) => correo.trim().toLowerCase();

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
    if (nombre.trim().isEmpty) {
      throw const RepositoryException('Escribe tu nombre.');
    }
    if (!email.contains('@') || !email.contains('.')) {
      throw const RepositoryException('Escribe un correo válido.');
    }
    if (password.length < 6) {
      throw const RepositoryException('La contraseña debe tener al menos 6 caracteres.');
    }
    if (anioAcademico < 1) {
      throw const RepositoryException('El año académico no es válido.');
    }
    if (careerId.trim().isEmpty) {
      throw const RepositoryException('Elige tu carrera.');
    }

    final users = _users();
    if (users.any((u) => u.correo == email)) {
      throw const RepositoryException('Ya existe una cuenta con ese correo.');
    }

    final user = AppUser(
      id: IdGenerator.newId('u'),
      nombre: nombre.trim(),
      correo: email,
      password: password,
      universityId: universityId,
      careerId: careerId,
      carrera: carrera.trim(),
      anioAcademico: anioAcademico,
      rol: rol,
      fechaCreacion: DateTime.now(),
    );
    await _saveUsers([...users, user]);
    await _startSession(user);
    return user;
  }

  @override
  Future<AppUser> login({
    required String correo,
    required String password,
    String? universityId,
  }) async {
    final email = _normalize(correo);
    for (final user in _users()) {
      if (user.correo == email && user.password == password) {
        if (universityId != null && user.universityId != universityId) {
          throw const UniversityMismatchException();
        }
        await _startSession(user);
        return user;
      }
    }
    throw const RepositoryException('Correo o contraseña incorrectos.');
  }

  @override
  Future<void> logout() => _db.remove(LocalDatabase.session);

  @override
  Future<AppUser> updateProfile({
    required String userId,
    required String nombre,
    required String careerId,
    required String carrera,
    required int anioAcademico,
  }) async {
    if (nombre.trim().length < 2) {
      throw const RepositoryException('Escribe tu nombre.');
    }
    if (careerId.trim().isEmpty || carrera.trim().isEmpty) {
      throw const RepositoryException('Elige tu carrera.');
    }
    if (anioAcademico < 1) {
      throw const RepositoryException('El año académico no es válido.');
    }
    final users = _users();
    final index = users.indexWhere((u) => u.id == userId);
    if (index < 0) {
      throw const RepositoryException('La cuenta no existe.');
    }
    // copyWith no cambia id ni rol; correo y universidad no se pasan.
    final updated = users[index].copyWith(
      nombre: nombre.trim(),
      careerId: careerId,
      carrera: carrera.trim(),
      anioAcademico: anioAcademico,
    );
    users[index] = updated;
    await _saveUsers(users);

    final session = _db.readMap(LocalDatabase.session);
    final sessionUserId = (session?['usuario'] as Map<String, dynamic>?)?['id'];
    if (sessionUserId == userId) await _startSession(updated);
    return updated;
  }

  @override
  Future<Session> currentSession() async {
    final json = _db.readMap(LocalDatabase.session);
    if (json == null) return const Session.empty();
    final saved = Session.fromJson(json);
    // Datos frescos del usuario (por si cambiaron); si ya no existe, sin sesión.
    final user = saved.usuario == null ? null : await getUserById(saved.usuario!.id);
    return user == null ? const Session.empty() : Session.forUser(user);
  }

  @override
  Future<AppUser?> getUserById(String id) async {
    for (final user in _users()) {
      if (user.id == id) return user;
    }
    return null;
  }
}
