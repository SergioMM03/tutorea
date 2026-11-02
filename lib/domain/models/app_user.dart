import 'university.dart';
import 'user_role.dart';

/// Cuenta de la app (estudiante o tutor).
class AppUser {
  final String id;
  final String nombre;
  final String correo;

  /// Solo para el almacenamiento local del MVP.
  /// Con Firebase Auth la contraseña no se guarda en el modelo.
  final String password;

  final String universityId; // University.id
  final String? careerId; // Career.id (null si se registró con carrera escrita a mano)

  /// Nombre visible de la carrera. Se mantiene por compatibilidad con
  /// cuentas creadas antes de [careerId]; con careerId, es el nombre de esa carrera.
  final String carrera;
  final int anioAcademico; // año académico: 1, 2, 3...
  final UserRole rol;
  final DateTime fechaCreacion;

  const AppUser({
    required this.id,
    required this.nombre,
    required this.correo,
    required this.password,
    this.universityId = kDefaultUniversityId,
    this.careerId,
    required this.carrera,
    required this.anioAcademico,
    required this.rol,
    required this.fechaCreacion,
  });

  bool get esTutor => rol == UserRole.tutor;
  bool get esEstudiante => rol == UserRole.estudiante;

  AppUser copyWith({
    String? nombre,
    String? correo,
    String? password,
    String? universityId,
    String? careerId,
    String? carrera,
    int? anioAcademico,
  }) {
    return AppUser(
      id: id,
      nombre: nombre ?? this.nombre,
      correo: correo ?? this.correo,
      password: password ?? this.password,
      universityId: universityId ?? this.universityId,
      careerId: careerId ?? this.careerId,
      carrera: carrera ?? this.carrera,
      anioAcademico: anioAcademico ?? this.anioAcademico,
      rol: rol, // el rol no cambia
      fechaCreacion: fechaCreacion,
    );
  }

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        correo: json['correo'] as String,
        password: json['password'] as String? ?? '',
        // Datos anteriores a varias universidades: se asume ESEN.
        universityId: json['universityId'] as String? ?? kDefaultUniversityId,
        careerId: json['careerId'] as String?,
        carrera: json['carrera'] as String? ?? '',
        anioAcademico: (json['anioAcademico'] as num).toInt(),
        rol: UserRole.fromJson(json['rol'] as String),
        fechaCreacion: DateTime.parse(json['fechaCreacion'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'correo': correo,
        'password': password,
        'universityId': universityId,
        'careerId': careerId,
        'carrera': carrera,
        'anioAcademico': anioAcademico,
        'rol': rol.name,
        'fechaCreacion': fechaCreacion.toIso8601String(),
      };

  /// Igual que [toJson] pero sin contraseña (para la sesión).
  Map<String, dynamic> toPublicJson() => toJson()..remove('password');

  @override
  bool operator ==(Object other) => other is AppUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
