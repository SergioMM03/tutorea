import '../../domain/models/models.dart';
import '../../utils/id_generator.dart';
import 'local_database.dart';

/// Registra las notificaciones del modo local (Fase 14.9). Es el equivalente de
/// los triggers notify_* del servidor (migración 23): lo usan los repositorios
/// locales al guardar cada hecho, nunca las pantallas.
///
/// Sin duplicados: [eventKey] identifica el hecho (p. ej. 'booking:<id>:aceptada')
/// y se guarda una sola vez por destinatario.
class LocalNotifications {
  final LocalDatabase _db;
  final DateTime Function() _now;

  LocalNotifications(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<void> push({
    required String? recipientId,
    required NotificationType type,
    String? bookingId,
    String? incidentId,
    required String eventKey,
  }) async {
    if (recipientId == null || recipientId.isEmpty) return;
    final all = _db.readList(LocalDatabase.notifications);
    final exists = all.any((n) => n['recipientId'] == recipientId && n['eventKey'] == eventKey);
    if (exists) return;
    final notification = AppNotification(
      id: IdGenerator.newId('nt'),
      recipientId: recipientId,
      type: type,
      bookingId: bookingId,
      incidentId: incidentId,
      eventKey: eventKey,
      createdAt: _now(),
    );
    await _db.writeList(LocalDatabase.notifications, [...all, notification.toJson()]);
  }

  /// Avisos de un cambio de estado de una reserva, con las mismas reglas que
  /// notify_booking_event: a quién avisar según el nuevo estado.
  Future<void> bookingEvent(
    Booking booking, {
    required String? tutorUserId,
    List<BookingConfirmation> confirmations = const [],
  }) async {
    final key = 'booking:${booking.id}:${booking.estado.dbValue}';
    Future<void> to(String? user, NotificationType type) =>
        push(recipientId: user, type: type, bookingId: booking.id, eventKey: key);
    switch (booking.estado) {
      case BookingStatus.pendiente:
        await to(tutorUserId, NotificationType.reservaSolicitada);
      case BookingStatus.aceptada:
        await to(booking.studentId, NotificationType.reservaAceptada);
      case BookingStatus.rechazada:
        await to(booking.studentId, NotificationType.reservaRechazada);
      case BookingStatus.cancelada:
        await to(booking.canceladaPor == booking.studentId ? tutorUserId : booking.studentId,
            NotificationType.reservaCancelada);
      case BookingStatus.pendienteConfirmacion:
        if (confirmations.any((c) => c.party == BookingParty.estudiante)) {
          await to(tutorUserId, NotificationType.confirmacionPendiente);
        }
        if (confirmations.any((c) => c.party == BookingParty.tutor)) {
          await to(booking.studentId, NotificationType.confirmacionPendiente);
        }
      case BookingStatus.completada:
        await to(booking.studentId, NotificationType.reservaCompletada);
        await to(tutorUserId, NotificationType.reservaCompletada);
    }
  }

  /// Avisos de una incidencia (notify_incident_event): al reportar, a la otra
  /// parte; al cambiar de estado, a las dos. (El modo local no tiene
  /// administradores que avisar.)
  Future<void> incidentEvent(
    Incident incident, {
    required String studentId,
    required String? tutorUserId,
    required bool created,
  }) async {
    final key = 'incident:${incident.id}:${incident.status.dbValue}';
    if (created) {
      await push(
        recipientId: incident.reportedBy == studentId ? tutorUserId : studentId,
        type: NotificationType.incidenciaReportada,
        bookingId: incident.bookingId,
        incidentId: incident.id,
        eventKey: key,
      );
      return;
    }
    for (final user in [studentId, tutorUserId]) {
      await push(
        recipientId: user,
        type: NotificationType.incidenciaActualizada,
        bookingId: incident.bookingId,
        incidentId: incident.id,
        eventKey: key,
      );
    }
  }
}
