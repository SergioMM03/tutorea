import 'availability_slot.dart';
import 'tutoring_modality.dart';
import 'university.dart';

/// Perfil de tutor de una cuenta ([userId]). Es opcional: cualquier cuenta
/// (rol principal estudiante o tutor) puede tener uno y seguir solicitando
/// tutorías. Tenerlo = poder ofrecer tutorías.
class TutorProfile {
  final String id;
  final String userId;
  final String universityId; // University.id (la del usuario tutor)
  final String descripcion;
  final double precioHora; // USD por hora
  final List<String> materias; // ids de Subject
  final List<AvailabilitySlot> disponibilidad;
  /// Promedio de las reseñas (1.0 – 5.0). Solo tiene sentido si
  /// [totalResenas] > 0: un tutor sin reseñas se muestra como «Nuevo».
  /// Lo calcula el servidor (o el repositorio local) a partir de las reseñas.
  final double rating;

  /// Cantidad de reseñas recibidas.
  final int totalResenas;
  final bool activo; // visible para los estudiantes

  /// Fotografía elegida por el tutor: ruta de una copia guardada en la
  /// carpeta de la app (no el archivo temporal del selector).
  /// null = sin fotografía → se muestran sus iniciales.
  final String? photoPath;

  /// Modalidades que ofrece (al menos una). Perfiles guardados antes: ambas.
  final bool ofrecePresencial;
  final bool ofreceVirtual;

  const TutorProfile({
    required this.id,
    required this.userId,
    this.universityId = kDefaultUniversityId,
    required this.descripcion,
    required this.precioHora,
    required this.materias,
    required this.disponibilidad,
    this.rating = 0,
    this.totalResenas = 0,
    this.activo = true,
    this.photoPath,
    this.ofrecePresencial = true,
    this.ofreceVirtual = true,
  });

  /// Listo para aparecer en las búsquedas.
  bool get completo =>
      descripcion.trim().isNotEmpty &&
      precioHora > 0 &&
      materias.isNotEmpty &&
      disponibilidad.isNotEmpty;

  bool ensenaMateria(String subjectId) => materias.contains(subjectId);

  /// ¿Tiene reseñas? Si no, es «Nuevo» (nunca «0.0»).
  bool get tieneCalificaciones => totalResenas > 0;

  /// Promedio para mostrar u ordenar, o null si todavía no tiene reseñas.
  double? get calificacion => tieneCalificaciones ? rating : null;

  /// ¿Atiende en esa modalidad?
  bool ofrece(TutoringModality modalidad) => switch (modalidad) {
        TutoringModality.presencial => ofrecePresencial,
        TutoringModality.virtual => ofreceVirtual,
      };

  /// ¿El tutor atiende en ese horario?
  bool disponibleEn(DateTime inicio, int duracionMinutos) =>
      disponibilidad.any((s) => s.cubre(inicio, duracionMinutos));

  TutorProfile copyWith({
    String? descripcion,
    double? precioHora,
    List<String>? materias,
    List<AvailabilitySlot>? disponibilidad,
    double? rating,
    int? totalResenas,
    bool? activo,
    String? photoPath,
    bool removePhoto = false, // true = quitar la fotografía (photoPath = null)
    bool? ofrecePresencial,
    bool? ofreceVirtual,
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
      totalResenas: totalResenas ?? this.totalResenas,
      activo: activo ?? this.activo,
      photoPath: removePhoto ? null : (photoPath ?? this.photoPath),
      ofrecePresencial: ofrecePresencial ?? this.ofrecePresencial,
      ofreceVirtual: ofreceVirtual ?? this.ofreceVirtual,
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
        // Perfiles guardados antes de las reseñas (Fase 14.9): sin reseñas, «Nuevo».
        totalResenas: (json['ratingCount'] as num? ?? 0).toInt(),
        activo: json['activo'] as bool? ?? true,
        // Perfiles guardados antes de las fotografías: sin foto.
        photoPath: json['photoPath'] as String?,
        // Perfiles guardados antes de las modalidades: ofrecen ambas.
        ofrecePresencial: json['ofrecePresencial'] as bool? ?? true,
        ofreceVirtual: json['ofreceVirtual'] as bool? ?? true,
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
        'ratingCount': totalResenas,
        'activo': activo,
        'photoPath': photoPath,
        'ofrecePresencial': ofrecePresencial,
        'ofreceVirtual': ofreceVirtual,
      };
}
