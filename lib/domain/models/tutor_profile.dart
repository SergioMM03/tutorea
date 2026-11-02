import 'availability_slot.dart';
import 'university.dart';

/// Perfil de tutor. Pertenece a un AppUser con rol tutor ([userId]).
class TutorProfile {
  final String id;
  final String userId;
  final String universityId; // University.id (la del usuario tutor)
  final String descripcion;
  final double precioHora; // USD por hora
  final List<String> materias; // ids de Subject
  final List<AvailabilitySlot> disponibilidad;
  final double rating; // 0.0 – 5.0
  final bool activo; // visible para los estudiantes

  /// Fotografía elegida por el tutor: ruta de una copia guardada en la
  /// carpeta de la app (no el archivo temporal del selector).
  /// null = sin fotografía → se muestran sus iniciales.
  final String? photoPath;

  const TutorProfile({
    required this.id,
    required this.userId,
    this.universityId = kDefaultUniversityId,
    required this.descripcion,
    required this.precioHora,
    required this.materias,
    required this.disponibilidad,
    this.rating = 0,
    this.activo = true,
    this.photoPath,
  });

  /// Listo para aparecer en las búsquedas.
  bool get completo =>
      descripcion.trim().isNotEmpty &&
      precioHora > 0 &&
      materias.isNotEmpty &&
      disponibilidad.isNotEmpty;

  bool ensenaMateria(String subjectId) => materias.contains(subjectId);

  /// ¿El tutor atiende en ese horario?
  bool disponibleEn(DateTime inicio, int duracionMinutos) =>
      disponibilidad.any((s) => s.cubre(inicio, duracionMinutos));

  TutorProfile copyWith({
    String? descripcion,
    double? precioHora,
    List<String>? materias,
    List<AvailabilitySlot>? disponibilidad,
    double? rating,
    bool? activo,
    String? photoPath,
    bool removePhoto = false, // true = quitar la fotografía (photoPath = null)
  }) {
    return TutorProfile(
      id: id,
      userId: userId,
      universityId: universityId,
      descripcion: descripcion ?? this.descripcion,
      precioHora: precioHora ?? this.precioHora,
      materias: materias ?? this.materias,
      disponibilidad: disponibilidad ?? this.disponibilidad,
      rating: rating ?? this.rating,
      activo: activo ?? this.activo,
      photoPath: removePhoto ? null : (photoPath ?? this.photoPath),
    );
  }

  factory TutorProfile.fromJson(Map<String, dynamic> json) => TutorProfile(
        id: json['id'] as String,
        userId: json['userId'] as String,
        universityId: json['universityId'] as String? ?? kDefaultUniversityId,
        descripcion: json['descripcion'] as String? ?? '',
        precioHora: (json['precioHora'] as num).toDouble(),
        materias: (json['materias'] as List? ?? const [])
            .map((e) => e as String)
            .toList(),
        disponibilidad: (json['disponibilidad'] as List? ?? const [])
            .map((e) => AvailabilitySlot.fromJson(e as Map<String, dynamic>))
            .toList(),
        rating: (json['rating'] as num? ?? 0).toDouble(),
        activo: json['activo'] as bool? ?? true,
        // Perfiles guardados antes de las fotografías: sin foto.
        photoPath: json['photoPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'universityId': universityId,
        'descripcion': descripcion,
        'precioHora': precioHora,
        'materias': materias,
        'disponibilidad': disponibilidad.map((s) => s.toJson()).toList(),
        'rating': rating,
        'activo': activo,
        'photoPath': photoPath,
      };
}
