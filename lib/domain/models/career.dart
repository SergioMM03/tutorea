/// Carrera de una universidad (ej. Economía y Negocios en ESEN).
class Career {
  final String id;
  final String universityId; // University.id
  final String nombre;

  const Career({
    required this.id,
    required this.universityId,
    required this.nombre,
  });

  factory Career.fromJson(Map<String, dynamic> json) => Career(
        id: json['id'] as String,
        universityId: json['universityId'] as String,
        nombre: json['nombre'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'universityId': universityId,
        'nombre': nombre,
      };

  @override
  bool operator ==(Object other) => other is Career && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
