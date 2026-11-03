import 'booking_party.dart';

/// Estado de una incidencia (enum incident_status, migración 02).
///   pendienteRevision → enInvestigacion | resuelta | desestimada
///   enInvestigacion   → resuelta | desestimada
enum IncidentStatus {
  pendienteRevision,
  enInvestigacion,
  resuelta,
  desestimada;

  String get label => switch (this) {
        IncidentStatus.pendienteRevision => 'Pendiente de revisión',
        IncidentStatus.enInvestigacion => 'En investigación',
        IncidentStatus.resuelta => 'Resuelta',
        IncidentStatus.desestimada => 'Desestimada',
      };

  /// Valor en la base de datos.
  String get dbValue => switch (this) {
        IncidentStatus.pendienteRevision => 'pendiente_revision',
        IncidentStatus.enInvestigacion => 'en_investigacion',
        IncidentStatus.resuelta => 'resuelta',
        IncidentStatus.desestimada => 'desestimada',
      };

  /// Abierta: impide completar y calificar la reserva.
  bool get abierta =>
      this == IncidentStatus.pendienteRevision || this == IncidentStatus.enInvestigacion;

  bool puedeCambiarA(IncidentStatus nuevo) => switch (this) {
        IncidentStatus.pendienteRevision => nuevo != IncidentStatus.pendienteRevision,
        IncidentStatus.enInvestigacion =>
          nuevo == IncidentStatus.resuelta || nuevo == IncidentStatus.desestimada,
        _ => false,
      };

  static IncidentStatus fromJson(String value) => IncidentStatus.values
      .firstWhere((s) => s.name == value || s.dbValue == value,
          orElse: () => throw FormatException('Estado de incidencia desconocido: $value'));
}

/// Categoría del problema (check de booking_incidents.category).
enum IncidentCategory {
  inasistencia,
  impuntualidad,
  conducta,
  calidad,
  tecnico,
  otro;

  String get label => switch (this) {
        IncidentCategory.inasistencia => 'No se presentó',
        IncidentCategory.impuntualidad => 'Llegó tarde',
        IncidentCategory.conducta => 'Conducta inapropiada',
        IncidentCategory.calidad => 'Calidad de la tutoría',
        IncidentCategory.tecnico => 'Problema técnico',
        IncidentCategory.otro => 'Otro',
      };

  static IncidentCategory fromJson(String value) => IncidentCategory.values
      .firstWhere((c) => c.name == value,
          orElse: () => throw FormatException('Categoría de incidencia desconocida: $value'));
}

/// Problema reportado por una de las partes de una reserva.
class Incident {
  final String id;
  final String bookingId;
  final String reportedBy; // AppUser.id
  final BookingParty reporterParty;
  final IncidentCategory category;
  final String description;
  final IncidentStatus status;

  /// Resolución del administrador al resolver o desestimar (la ven las partes).
  final String? resolutionNote;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  const Incident({
    required this.id,
    required this.bookingId,
    required this.reportedBy,
    required this.reporterParty,
    required this.category,
    required this.description,
    this.status = IncidentStatus.pendienteRevision,
    this.resolutionNote,
    this.resolvedAt,
    required this.createdAt,
  });

  bool get abierta => status.abierta;

  Incident copyWith({IncidentStatus? status, String? resolutionNote, DateTime? resolvedAt}) => Incident(
        id: id,
        bookingId: bookingId,
        reportedBy: reportedBy,
        reporterParty: reporterParty,
        category: category,
        description: description,
        status: status ?? this.status,
        resolutionNote: resolutionNote ?? this.resolutionNote,
        resolvedAt: resolvedAt ?? this.resolvedAt,
        createdAt: createdAt,
      );

  factory Incident.fromJson(Map<String, dynamic> json) => Incident(
        id: json['id'] as String,
        bookingId: json['bookingId'] as String,
        reportedBy: json['reportedBy'] as String,
        reporterParty: BookingParty.fromJson(json['reporterParty'] as String),
        category: IncidentCategory.fromJson(json['category'] as String),
        description: json['description'] as String,
        status: IncidentStatus.fromJson(json['status'] as String),
        resolutionNote: json['resolutionNote'] as String?,
        resolvedAt: json['resolvedAt'] is String ? DateTime.parse(json['resolvedAt'] as String) : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookingId': bookingId,
        'reportedBy': reportedBy,
        'reporterParty': reporterParty.name,
        'category': category.name,
        'description': description,
        'status': status.name,
        if (resolutionNote != null) 'resolutionNote': resolutionNote,
        if (resolvedAt != null) 'resolvedAt': resolvedAt!.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Tipo de entrada del historial de una incidencia.
enum IncidentEventType { reportada, estado, nota }

/// Entrada del historial: el reporte, cada cambio de estado y las notas
/// internas del administrador ([internal]: solo las ve él).
class IncidentEvent {
  final String id;
  final String incidentId;
  final IncidentEventType event;
  final IncidentStatus? fromStatus;
  final IncidentStatus? toStatus;
  final String? note;
  final bool internal;
  final String actorId;
  final DateTime createdAt;

  const IncidentEvent({
    required this.id,
    required this.incidentId,
    required this.event,
    this.fromStatus,
    this.toStatus,
    this.note,
    this.internal = false,
    required this.actorId,
    required this.createdAt,
  });

  factory IncidentEvent.fromJson(Map<String, dynamic> json) => IncidentEvent(
        id: json['id'] as String,
        incidentId: json['incidentId'] as String,
        event: IncidentEventType.values.byName(json['event'] as String),
        fromStatus: json['fromStatus'] is String ? IncidentStatus.fromJson(json['fromStatus'] as String) : null,
        toStatus: json['toStatus'] is String ? IncidentStatus.fromJson(json['toStatus'] as String) : null,
        note: json['note'] as String?,
        internal: json['internal'] as bool? ?? false,
        actorId: json['actorId'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'incidentId': incidentId,
        'event': event.name,
        if (fromStatus != null) 'fromStatus': fromStatus!.name,
        if (toStatus != null) 'toStatus': toStatus!.name,
        if (note != null) 'note': note,
        'internal': internal,
        'actorId': actorId,
        'createdAt': createdAt.toIso8601String(),
      };
}
