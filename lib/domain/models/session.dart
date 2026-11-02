import 'app_user.dart';
import 'user_role.dart';

/// Sesión actual: quién está usando la app y con qué rol.
class Session {
  final AppUser? usuario;
  final UserRole? rol;

  const Session({this.usuario, this.rol});

  /// Nadie ha iniciado sesión.
  const Session.empty()
      : usuario = null,
        rol = null;

  factory Session.forUser(AppUser user) => Session(usuario: user, rol: user.rol);

  bool get iniciada => usuario != null;

  factory Session.fromJson(Map<String, dynamic> json) {
    final user = json['usuario'];
    final rol = json['rol'];
    return Session(
      usuario: user == null ? null : AppUser.fromJson(user as Map<String, dynamic>),
      rol: rol == null ? null : UserRole.fromJson(rol as String),
    );
  }

  /// Nunca guarda la contraseña.
  Map<String, dynamic> toJson() => {
        'usuario': usuario?.toPublicJson(),
        'rol': rol?.name,
      };
}
