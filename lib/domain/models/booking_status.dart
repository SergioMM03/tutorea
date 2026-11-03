/// Estado de una solicitud de tutoría (mismos valores que el enum
/// `booking_status` de Supabase, migración 02).
///
///   pendiente ──► aceptada ──► pendienteConfirmacion ──► completada
///       │            └──────► cancelada (estudiante o tutor, antes del inicio, con motivo)
///       ├──► rechazada (tutor)
///       └──► cancelada (estudiante)
///
/// rechazada, cancelada y completada son finales. Las confirmaciones
/// (pendienteConfirmacion → completada) llegan en una fase posterior.
enum BookingStatus {
  pendiente,
  aceptada,
  rechazada,
  cancelada,
  pendienteConfirmacion,
  completada;

  String get label => switch (this) {
        BookingStatus.pendiente => 'Pendiente',
        BookingStatus.aceptada => 'Aceptada',
        BookingStatus.rechazada => 'Rechazada',
        BookingStatus.cancelada => 'Cancelada',
        BookingStatus.pendienteConfirmacion => 'Por confirmar',
        BookingStatus.completada => 'Completada',
      };

  /// Valor en la base de datos (`booking_status`).
  String get dbValue => switch (this) {
        BookingStatus.pendienteConfirmacion => 'pendiente_confirmacion',
        _ => name,
      };

  /// Pendiente, aceptada o por confirmar: sigue abierta.
  bool get vigente =>
      this == BookingStatus.pendiente ||
      this == BookingStatus.aceptada ||
      this == BookingStatus.pendienteConfirmacion;

  /// Rechazada, cancelada o completada: ya no cambia.
  bool get esFinal => !vigente;

  /// Ocupa el horario del tutor y del estudiante (no se puede cruzar con otra).
  bool get ocupaHorario =>
      this == BookingStatus.aceptada ||
      this == BookingStatus.pendienteConfirmacion ||
      this == BookingStatus.completada;

  /// Transiciones permitidas (las mismas que protege la base de datos).
  bool puedeCambiarA(BookingStatus nuevo) => switch (this) {
        BookingStatus.pendiente => nuevo == BookingStatus.aceptada ||
            nuevo == BookingStatus.rechazada ||
            nuevo == BookingStatus.cancelada,
        BookingStatus.aceptada =>
          nuevo == BookingStatus.cancelada || nuevo == BookingStatus.pendienteConfirmacion,
        BookingStatus.pendienteConfirmacion => nuevo == BookingStatus.completada,
        _ => false,
      };

  /// Acepta el nombre de Dart (`pendienteConfirmacion`) y el de la base
  /// (`pendiente_confirmacion`).
  static BookingStatus fromJson(String value) => BookingStatus.values
      .firstWhere((s) => s.name == value || s.dbValue == value,
          orElse: () => throw FormatException('Estado de reserva desconocido: $value'));
}
