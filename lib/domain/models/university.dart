/// Id de la universidad inicial. Se usa como valor por defecto para
/// datos guardados antes de soportar varias universidades.
const String kDefaultUniversityId = 'esen';

/// Universidad donde opera Tutorea. Hoy solo ESEN; después, otras.
class University {
  final String id;
  final String nombre;
  final String pais;
  final bool activo; // false = aún no disponible para registrarse

  const University({
    required this.id,
    required this.nombre,
    required this.pais,
    this.activo = true,
  });

  factory University.fromJson(Map<String, dynamic> json) => University(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        pais: json['pais'] as String,
        activo: json['activo'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'pais': pais,
        'activo': activo,
      };

  @override
  bool operator ==(Object other) => other is University && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
