import 'booking_status.dart';

/// Solicitud de tutoría. Relaciona estudiante, tutor y materia por id.
class Booking {
  final String id;
  final String studentId; // AppUser.id (rol estudiante)
  final String tutorId; // TutorProfile.id
  final String subjectId; // Subject.id
  final String? tema; // tema específico (opcional)
  final DateTime fechaHora; // inicio de la sesión
  final int duracion; // minutos: 60, 90, 120
  final double precio; // total acordado al reservar (USD)
  final BookingStatus estado;

  const Booking({
    required this.id,
    required this.studentId,
    required this.tutorId,
    required this.subjectId,
    this.tema,
    required this.fechaHora,
    required this.duracion,
    required this.precio,
    this.estado = BookingStatus.pendiente,
  });

  DateTime get fin => fechaHora.add(Duration(minutes: duracion));

  /// Total = precio por hora × horas.
  static double calcularPrecio(double precioHora, int duracionMinutos) =>
      precioHora * duracionMinutos / 60;

  Booking copyWith({BookingStatus? estado}) {
    return Booking(
      id: id,
      studentId: studentId,
      tutorId: tutorId,
      subjectId: subjectId,
      tema: tema,
      fechaHora: fechaHora,
      duracion: duracion,
      precio: precio,
      estado: estado ?? this.estado,
    );
  }

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        studentId: json['studentId'] as String,
        tutorId: json['tutorId'] as String,
        subjectId: json['subjectId'] as String,
        tema: json['tema'] as String?,
        fechaHora: DateTime.parse(json['fechaHora'] as String),
        duracion: (json['duracion'] as num).toInt(),
        precio: (json['precio'] as num).toDouble(),
        estado: BookingStatus.fromJson(json['estado'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'studentId': studentId,
        'tutorId': tutorId,
        'subjectId': subjectId,
        'tema': tema,
        'fechaHora': fechaHora.toIso8601String(),
        'duracion': duracion,
        'precio': precio,
        'estado': estado.name,
      };
}
