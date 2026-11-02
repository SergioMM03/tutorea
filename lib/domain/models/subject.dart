import 'university.dart';

/// Materia del catálogo de una universidad (Estadística, Finanzas...).
class Subject {
  final String id;
  final String nombre;
  final String categoria; // Matemáticas, Economía, Negocios, Tecnología
  final String universityId; // University.id

  /// Career.id de la carrera a la que pertenece.
  /// null = materia común a varias carreras (ej. Matemáticas).
  final String? careerId;

  /// Año del plan de estudios en que se cursa (1, 2, 3...). null = sin dato.
  final int? anioAcademico;

  const Subject({
    required this.id,
    required this.nombre,
    required this.categoria,
    this.universityId = kDefaultUniversityId,
    this.careerId,
    this.anioAcademico,
  });

  /// ¿La ve un estudiante de esa carrera? (las comunes las ven todos).
  bool esDeCarrera(String? id) => careerId == null || careerId == id;

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        categoria: json['categoria'] as String,
        universityId: json['universityId'] as String? ?? kDefaultUniversityId,
        careerId: json['careerId'] as String?,
        anioAcademico: (json['anioAcademico'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'categoria': categoria,
        'universityId': universityId,
        'careerId': careerId,
        'anioAcademico': anioAcademico,
      };

  @override
  bool operator ==(Object other) => other is Subject && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
