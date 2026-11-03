import 'booking_status.dart';
import 'tutoring_modality.dart';

/// Solicitud de tutoría. Relaciona a la cuenta que solicita, un perfil de tutor y
/// una materia por id. Una misma cuenta puede solicitar (studentId) y, con su
/// propio perfil de tutor, recibir solicitudes (tutorId de otras reservas).
///
/// [fechaHora] es hora de pared de El Salvador (ver `TutoreaTime`).
class Booking {
  final String id;
  final String studentId; // AppUser.id de quien solicita
  final String tutorId; // TutorProfile.id
  final String subjectId; // Subject.id
  final String? tema; // tema específico (opcional)
  final DateTime fechaHora; // inicio de la sesión
  final int duracion; // minutos: 60, 90, 120
  final double precio; // total acordado al reservar (USD); no cambia con la tarifa
  final BookingStatus estado;

  /// Presencial o virtual. Null solo en reservas locales creadas antes de 14.8.
  final TutoringModality? modalidad;

  /// Lugar (presencial) o enlace (virtual), opcional.
  final String? ubicacion;

  /// Cuándo respondió el tutor (aceptó o rechazó).
  final DateTime? respondidaEn;

  /// Cancelación: quién (AppUser.id), cuándo y por qué.
  final String? canceladaPor;
  final DateTime? canceladaEn;
  final String? motivoCancelacion;

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
    this.modalidad,
    this.ubicacion,
    this.respondidaEn,
    this.canceladaPor,
    this.canceladaEn,
    this.motivoCancelacion,
  });

  /// Duraciones permitidas (también en la base: check de bookings).
  static const List<int> duracionesPermitidas = [60, 90, 120];

  DateTime get fin => fechaHora.add(Duration(minutes: duracion));

  /// Total = precio por hora × horas.
  static double calcularPrecio(double precioHora, int duracionMinutos) =>
      precioHora * duracionMinutos / 60;

  /// ¿Quien solicitó puede cancelarla ahora? Pendiente: siempre. Aceptada:
  /// antes del inicio (con motivo, ver [requiereMotivo]).
  bool puedeCancelarEstudiante(DateTime ahora) =>
      estado == BookingStatus.pendiente ||
      (estado == BookingStatus.aceptada && fechaHora.isAfter(ahora));

  /// ¿El tutor puede cancelarla ahora? Solo aceptada y antes del inicio (una
  /// pendiente se rechaza).
  bool puedeCancelarTutor(DateTime ahora) =>
      estado == BookingStatus.aceptada && fechaHora.isAfter(ahora);

  /// Cancelar una aceptada exige motivo.
  bool get requiereMotivo => estado == BookingStatus.aceptada;

  Booking copyWith({
    BookingStatus? estado,
    DateTime? respondidaEn,
    String? canceladaPor,
    DateTime? canceladaEn,
    String? motivoCancelacion,
  }) {
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
      modalidad: modalidad,
      ubicacion: ubicacion,
      respondidaEn: respondidaEn ?? this.respondidaEn,
      canceladaPor: canceladaPor ?? this.canceladaPor,
      canceladaEn: canceladaEn ?? this.canceladaEn,
      motivoCancelacion: motivoCancelacion ?? this.motivoCancelacion,
    );
  }

  static DateTime? _date(Object? value) => value is String ? DateTime.parse(value) : null;

  /// Lee también reservas locales guardadas antes de la Fase 14.8 (sin
  /// modalidad ni datos de cancelación).
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
        modalidad: json['modalidad'] is String
            ? TutoringModality.values.asNameMap()[json['modalidad']]
            : null,
        ubicacion: json['ubicacion'] as String?,
        respondidaEn: _date(json['respondidaEn']),
        canceladaPor: json['canceladaPor'] as String?,
        canceladaEn: _date(json['canceladaEn']),
        motivoCancelacion: json['motivoCancelacion'] as String?,
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
        if (modalidad != null) 'modalidad': modalidad!.name,
        if (ubicacion != null) 'ubicacion': ubicacion,
        if (respondidaEn != null) 'respondidaEn': respondidaEn!.toIso8601String(),
        if (canceladaPor != null) 'canceladaPor': canceladaPor,
        if (canceladaEn != null) 'canceladaEn': canceladaEn!.toIso8601String(),
        if (motivoCancelacion != null) 'motivoCancelacion': motivoCancelacion,
      };
}
