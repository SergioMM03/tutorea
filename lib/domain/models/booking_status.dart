/// Estado de una solicitud de tutoría.
///
///   pendiente ──► aceptada
///       │   └───► rechazada
///       └───────► cancelada (por el estudiante)
enum BookingStatus {
  pendiente,
  aceptada,
  rechazada,
  cancelada;

  String get label => switch (this) {
        BookingStatus.pendiente => 'Pendiente',
        BookingStatus.aceptada => 'Aceptada',
        BookingStatus.rechazada => 'Rechazada',
        BookingStatus.cancelada => 'Cancelada',
      };

  /// Pendiente o aceptada: sigue vigente.
  bool get vigente => this == BookingStatus.pendiente || this == BookingStatus.aceptada;

  /// Cambios permitidos. Solo una solicitud pendiente puede cambiar.
  bool puedeCambiarA(BookingStatus nuevo) =>
      this == BookingStatus.pendiente && nuevo != BookingStatus.pendiente;

  static BookingStatus fromJson(String value) => BookingStatus.values.byName(value);
}
