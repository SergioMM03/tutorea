import '../models/models.dart';

/// Solicitudes de tutoría.
abstract class BookingRepository {
  /// Crea la solicitud en estado pendiente.
  /// Lanza RepositoryException si el horario no es válido o está duplicada.
  Future<Booking> create(Booking booking);

  /// Solicitudes del estudiante, la más reciente primero.
  Future<List<Booking>> getForStudent(String studentId);

  /// Solicitudes recibidas por el tutor, la más próxima primero.
  Future<List<Booking>> getForTutor(String tutorId);

  /// Aceptar, rechazar o cancelar. Solo una solicitud pendiente puede cambiar.
  Future<Booking> updateStatus(String bookingId, BookingStatus nuevo);
}
