import 'models/models.dart';

// Mensajes de la Fase 14.9. Los usan el modo local (al validar) y el remoto
// (al traducir los códigos TU0xx del servidor), así los dos modos muestran
// exactamente el mismo texto.

// Confirmaciones (confirm_booking, migración 21)
const String confirmNotFoundMessage = 'No encontramos esa reserva entre las tuyas.';
const String sessionNotFinishedMessage = 'La sesión todavía no termina; podrás confirmarla al finalizar.';
const String alreadyConfirmedMessage = 'Ya confirmaste esta sesión.';
const String openIncidentBlocksCompletionMessage =
    'Hay una incidencia abierta; la sesión se completará cuando se resuelva.';
const String notConfirmableMessage = 'Solo se confirman sesiones aceptadas que ya terminaron.';

// Incidencias (report_incident y gestión, migración 20)
const String notReportableMessage = 'Solo se reportan incidencias de reservas aceptadas.';
const String reportWindowClosedMessage = 'Pasaron más de 7 días desde el fin de la sesión.';
const String incidentAlreadyOpenMessage = 'Ya tienes una incidencia abierta para esta reserva.';
const String invalidIncidentMessage =
    'Elige una categoría y describe el problema (10 a 2000 caracteres).';
const String incidentNotFoundMessage = 'No encontramos esa incidencia.';
const String incidentTransitionMessage = 'Esa incidencia ya no puede pasar a ese estado.';
const String incidentNoteRequiredMessage = 'Escribe la resolución (mínimo 5 caracteres).';

// Reseñas (submit_review, migración 22)
const String onlyStudentReviewsMessage = 'Solo el estudiante de la reserva puede calificar.';
const String tutorSelfReviewMessage = 'El tutor no puede calificarse a sí mismo.';
const String notCompletedReviewMessage = 'Solo se califican tutorías completadas.';
const String openIncidentBlocksReviewMessage =
    'Hay una incidencia abierta; podrás calificar cuando se resuelva.';
const String alreadyReviewedMessage = 'Ya calificaste esta tutoría.';
const String invalidRatingMessage =
    'La calificación debe ser de 1 a 5 estrellas (comentario hasta 1000 caracteres).';

/// Reglas de confirmaciones, incidencias y reseñas (Fase 14.9).
///
/// Son las mismas que aplican las funciones del servidor. El repositorio local
/// las usa para validar y las pantallas para decidir qué botones mostrar; en
/// modo Supabase la base vuelve a validarlo todo.
class FollowUpRules {
  FollowUpRules._();

  /// Se puede reportar hasta 7 días después del fin de la sesión.
  static const Duration incidentWindow = Duration(days: 7);

  /// Primer problema para que [party] confirme la sesión, o null si puede.
  /// [hasOpenIncident] solo impide la confirmación que completaría la reserva.
  static String? confirmProblem({
    required Booking booking,
    required BookingParty party,
    required List<BookingConfirmation> confirmations,
    required bool hasOpenIncident,
    required DateTime now,
  }) {
    if (booking.estado != BookingStatus.aceptada &&
        booking.estado != BookingStatus.pendienteConfirmacion) {
      return notConfirmableMessage;
    }
    if (now.isBefore(booking.fin)) return sessionNotFinishedMessage;
    if (confirmations.any((c) => c.party == party)) return alreadyConfirmedMessage;
    final otherConfirmed = confirmations.any((c) => c.party != party);
    if (otherConfirmed && hasOpenIncident) return openIncidentBlocksCompletionMessage;
    return null;
  }

  /// Estado que deja la confirmación de [party] (ya validada).
  static BookingStatus statusAfterConfirm(List<BookingConfirmation> confirmations, BookingParty party) =>
      confirmations.any((c) => c.party != party)
          ? BookingStatus.completada
          : BookingStatus.pendienteConfirmacion;

  /// ¿Se puede reportar una incidencia de esta reserva ahora?
  static String? reportProblem({required Booking booking, required DateTime now}) {
    if (booking.estado != BookingStatus.aceptada &&
        booking.estado != BookingStatus.pendienteConfirmacion &&
        booking.estado != BookingStatus.completada) {
      return notReportableMessage;
    }
    if (now.isAfter(booking.fin.add(incidentWindow))) return reportWindowClosedMessage;
    return null;
  }

  /// Valida categoría y descripción (10 a 2000 caracteres sin espacios sobrantes).
  static String? incidentInputProblem(IncidentCategory? category, String description) {
    final text = description.trim();
    if (category == null || text.length < 10 || text.length > 2000) return invalidIncidentMessage;
    return null;
  }

  /// ¿[party] puede calificar esta reserva?
  static String? reviewProblem({
    required Booking booking,
    required BookingParty party,
    required bool hasOpenIncident,
    required bool alreadyReviewed,
  }) {
    if (party == BookingParty.tutor) return tutorSelfReviewMessage;
    if (booking.estado != BookingStatus.completada) return notCompletedReviewMessage;
    if (hasOpenIncident) return openIncidentBlocksReviewMessage;
    if (alreadyReviewed) return alreadyReviewedMessage;
    return null;
  }

  /// Valida estrellas y comentario.
  static String? reviewInputProblem(int rating, String? comment) {
    if (rating < 1 || rating > 5 || (comment != null && comment.trim().length > 1000)) {
      return invalidRatingMessage;
    }
    return null;
  }

  /// Promedio redondeado a 2 decimales (como round(avg, 2) en el servidor).
  static double average(Iterable<int> ratings) {
    final list = ratings.toList();
    if (list.isEmpty) return 0;
    final avg = list.reduce((a, b) => a + b) / list.length;
    return (avg * 100).round() / 100;
  }
}
