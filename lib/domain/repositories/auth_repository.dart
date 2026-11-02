import '../models/models.dart';

/// Cuentas y sesión.
/// Hoy: LocalAuthRepository (shared_preferences). Después: FirebaseAuthRepository.
abstract class AuthRepository {
  /// Crea la cuenta e inicia sesión con ella.
  /// [careerId] es obligatorio: toda cuenta pertenece a una carrera de su
  /// universidad (con Supabase, handle_new_user la exige).
  /// Lanza RepositoryException si el correo ya está registrado.
  Future<AppUser> register({
    required String nombre,
    required String correo,
    required String password,
    String universityId = kDefaultUniversityId,
    required String careerId,
    required String carrera,
    required int anioAcademico,
    required UserRole rol,
  });

  /// Lanza RepositoryException si el correo o la contraseña no coinciden.
  /// Si se indica [universityId] (la universidad seleccionada al entrar) y la
  /// cuenta es de otra, lanza UniversityMismatchException SIN iniciar sesión.
  /// La universidad de la cuenta nunca se modifica.
  Future<AppUser> login({
    required String correo,
    required String password,
    String? universityId,
  });

  Future<void> logout();

  /// Actualiza los datos editables de la cuenta: nombre, carrera y año.
  /// Correo, universidad, rol e id no cambian. Si es la cuenta con sesión
  /// iniciada, la sesión guardada también se actualiza.
  /// Lanza RepositoryException si la cuenta no existe o los datos no son válidos.
  Future<AppUser> updateProfile({
    required String userId,
    required String nombre,
    required String careerId,
    required String carrera,
    required int anioAcademico,
  });

  /// Sesión guardada (sigue iniciada al reabrir la app).
  Future<Session> currentSession();

  Future<AppUser?> getUserById(String id);
}
