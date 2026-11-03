/// Tipo de notificación (enum notification_type, migración 02).
enum NotificationType {
  reservaSolicitada,
  reservaAceptada,
  reservaRechazada,
  reservaCancelada,
  confirmacionPendiente,
  reservaCompletada,
  incidenciaReportada,
  incidenciaActualizada;

  /// Valor en la base de datos.
  String get dbValue => switch (this) {
        NotificationType.reservaSolicitada => 'reserva_solicitada',
        NotificationType.reservaAceptada => 'reserva_aceptada',
        NotificationType.reservaRechazada => 'reserva_rechazada',
        NotificationType.reservaCancelada => 'reserva_cancelada',
        NotificationType.confirmacionPendiente => 'confirmacion_pendiente',
        NotificationType.reservaCompletada => 'reserva_completada',
        NotificationType.incidenciaReportada => 'incidencia_reportada',
        NotificationType.incidenciaActualizada => 'incidencia_actualizada',
      };

  /// Texto para la lista de notificaciones.
  String get title => switch (this) {
        NotificationType.reservaSolicitada => 'Nueva solicitud de tutoría',
        NotificationType.reservaAceptada => 'Tu solicitud fue aceptada',
        NotificationType.reservaRechazada => 'Tu solicitud fue rechazada',
        NotificationType.reservaCancelada => 'Una reserva fue cancelada',
        NotificationType.confirmacionPendiente => 'Falta tu confirmación de la sesión',
        NotificationType.reservaCompletada => 'Tutoría completada',
        NotificationType.incidenciaReportada => 'Se reportó una incidencia',
        NotificationType.incidenciaActualizada => 'Una incidencia cambió de estado',
      };

  static NotificationType fromJson(String value) => NotificationType.values
      .firstWhere((t) => t.name == value || t.dbValue == value,
          orElse: () => throw FormatException('Tipo de notificación desconocido: $value'));
}

/// Aviso para una cuenta. Lo crea el sistema (en Supabase, triggers del
/// servidor); la app solo lo lee y lo marca como leído.
class AppNotification {
  final String id;
  final String recipientId;
  final NotificationType type;
  final String? bookingId;
  final String? incidentId;

  /// Identifica el hecho (p. ej. 'booking:<id>:aceptada'): uno por persona.
  final String eventKey;
  final DateTime createdAt;
  final DateTime? readAt;

  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    this.bookingId,
    this.incidentId,
    required this.eventKey,
    required this.createdAt,
    this.readAt,
  });

  bool get leida => readAt != null;

  AppNotification markedRead(DateTime when) => AppNotification(
        id: id,
        recipientId: recipientId,
        type: type,
        bookingId: bookingId,
        incidentId: incidentId,
        eventKey: eventKey,
        createdAt: createdAt,
        readAt: readAt ?? when,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as String,
        recipientId: json['recipientId'] as String,
        type: NotificationType.fromJson(json['type'] as String),
        bookingId: json['bookingId'] as String?,
        incidentId: json['incidentId'] as String?,
        eventKey: json['eventKey'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        readAt: json['readAt'] is String ? DateTime.parse(json['readAt'] as String) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'recipientId': recipientId,
        'type': type.name,
        if (bookingId != null) 'bookingId': bookingId,
        if (incidentId != null) 'incidentId': incidentId,
        'eventKey': eventKey,
        'createdAt': createdAt.toIso8601String(),
        if (readAt != null) 'readAt': readAt!.toIso8601String(),
      };
}
