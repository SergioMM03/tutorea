/// Hora de Tutorea: El Salvador (America/El_Salvador, UTC−6, sin horario de
/// verano desde 2006).
///
/// Convención de la app:
/// - En Flutter, `Booking.fechaHora` y la disponibilidad (`AvailabilitySlot`) son
///   "hora de pared" de El Salvador: un `DateTime` local (isUtc == false) cuyos
///   campos (día, hora, minuto) son los que ve el usuario, sin importar la zona
///   horaria configurada en el teléfono.
/// - En Supabase, `bookings.starts_at` es `timestamptz` (UTC). El servidor compara
///   con la disponibilidad convirtiendo a `America/El_Salvador`
///   (`public.tutorea_time_zone()`, migración 17).
/// - Las ÚNICAS conversiones están aquí y las usa RemoteBookingRepository:
///   [toUtc] al enviar y [fromUtc] al leer.
class TutoreaTime {
  TutoreaTime._();

  static const String zoneName = 'America/El_Salvador';

  /// Diferencia fija con UTC.
  static const Duration utcOffset = Duration(hours: -6);

  /// Hora de pared de El Salvador → instante UTC.
  static DateTime toUtc(DateTime wallClock) => DateTime.utc(
        wallClock.year,
        wallClock.month,
        wallClock.day,
        wallClock.hour,
        wallClock.minute,
        wallClock.second,
      ).subtract(utcOffset);

  /// Instante (UTC o con zona) → hora de pared de El Salvador.
  static DateTime fromUtc(DateTime instant) {
    final local = instant.toUtc().add(utcOffset);
    return DateTime(local.year, local.month, local.day, local.hour, local.minute, local.second);
  }

  /// Ahora mismo en El Salvador (hora de pared).
  static DateTime now() => fromUtc(DateTime.now());
}
