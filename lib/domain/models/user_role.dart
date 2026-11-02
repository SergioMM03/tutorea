/// Rol de una cuenta. Un usuario tiene un solo rol.
enum UserRole {
  estudiante,
  tutor;

  String get label => switch (this) {
        UserRole.estudiante => 'Estudiante',
        UserRole.tutor => 'Tutor',
      };

  /// Lee el rol desde JSON ('estudiante' | 'tutor').
  static UserRole fromJson(String value) => UserRole.values.byName(value);
}
