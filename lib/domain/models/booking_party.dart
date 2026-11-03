/// Parte de una reserva: quien solicitó (estudiante) o el dueño del perfil de
/// tutor. Una misma cuenta puede ser estudiante en unas reservas y tutor en
/// otras, pero nunca las dos en la misma (no hay autorreservas).
enum BookingParty {
  estudiante,
  tutor;

  String get label => switch (this) {
        BookingParty.estudiante => 'Estudiante',
        BookingParty.tutor => 'Tutor',
      };

  BookingParty get other =>
      this == BookingParty.estudiante ? BookingParty.tutor : BookingParty.estudiante;

  static BookingParty fromJson(String value) => BookingParty.values
      .firstWhere((p) => p.name == value,
          orElse: () => throw FormatException('Parte de reserva desconocida: $value'));
}
