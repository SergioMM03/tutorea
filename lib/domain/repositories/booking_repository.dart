import '../models/models.dart';

/// Una misma cuenta puede ser estudiante y tutor, pero no se solicita una
/// tutoría a su propio perfil de tutor.
const String selfBookingMessage = 'No puedes solicitarte una tutoría a ti mismo.';

/// Al aceptar se vuelve a validar la disponibilidad ACTUAL del tutor: si la cambió
/// o la borró después de recibir la solicitud, ya no se acepta.
const String availabilityChangedMessage =
    'Esa sesión ya no está dentro de la disponibilidad actual del tutor.';

/// Cancelar una reserva aceptada exige motivo.
const String cancelReasonRequiredMessage = 'Escribe el motivo para cancelar una reserva aceptada.';

/// Solicitudes de tutoría. Cualquier cuenta con sesión puede solicitarlas,
/// tenga o no su propio perfil de tutor.
///
/// Implementaciones: LocalBookingRepository (modo local, shared_preferences) y
/// RemoteBookingRepository (modo Supabase: tabla bookings y funciones
/// request/accept/reject/cancel_booking, migraciones 17–18).
abstract class BookingRepository {
  /// Crea la solicitud en estado pendiente. El precio acordado lo calcula el
  /// repositorio (o el servidor) con la tarifa actual del tutor.
  /// Lanza RepositoryException si el horario no es válido, está duplicada o
  /// el tutor es la misma cuenta que solicita ([selfBookingMessage]).
  Future<Booking> create(Booking booking);

  /// Solicitudes que envió la cuenta, la más reciente primero.
  Future<List<Booking>> getForStudent(String studentId);

  /// Solicitudes recibidas por el perfil de tutor, la más próxima primero.
  Future<List<Booking>> getForTutor(String tutorId);

  /// Aceptar, rechazar o cancelar ([BookingStatus.puedeCambiarA]).
  /// Aceptar vuelve a validar: hora futura, tutor activo, disponibilidad
  /// actual ([availabilityChangedMessage]) y cruces con sesiones confirmadas.
  /// [motivo]: obligatorio para cancelar una reserva aceptada.
  /// [actorId]: cuenta que realiza la acción. El modo local lo guarda como
  /// quien canceló; Supabase lo ignora y usa siempre la sesión (auth.uid()).
  Future<Booking> updateStatus(
    String bookingId,
    BookingStatus nuevo, {
    String? motivo,
    String? actorId,
  });

  /// Confirma que la sesión se realizó (Fase 14.9), por la parte de [actorId]
  /// (Supabase usa la sesión: auth.uid()). La primera confirmación deja la
  /// reserva en pendienteConfirmacion y la segunda en completada, salvo que
  /// haya una incidencia abierta. Ver FollowUpRules.confirmProblem.
  Future<Booking> confirm(String bookingId, {String? actorId});

  /// Confirmaciones de una reserva (historial: no cambian).
  Future<List<BookingConfirmation>> getConfirmations(String bookingId);
}
