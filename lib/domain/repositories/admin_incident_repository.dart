import '../models/models.dart';

/// Gestión de incidencias por el administrador de una universidad (Fase 14.9).
///
/// Capa de datos para el futuro panel administrativo (ADMIN 1–3): todavía no
/// hay pantallas que la usen. En Supabase el servidor exige que la cuenta con
/// sesión sea administradora de la universidad de la incidencia (is_admin_of);
/// para cualquier otra cuenta la incidencia "no existe".
///
/// Resolver o desestimar no cambia la reserva, no crea calificaciones ni
/// sanciona a nadie.
abstract class AdminIncidentRepository {
  /// Incidencias de la universidad del administrador (filtro opcional por estado).
  Future<List<Incident>> listForUniversity({IncidentStatus? status});

  /// Historial completo, incluidas las notas internas.
  Future<List<IncidentEvent>> getEvents(String incidentId);

  /// pendienteRevision → enInvestigacion (con nota interna opcional).
  Future<Incident> startInvestigation(String incidentId, {String? note, String? actorId});

  /// Nota interna (solo la ve el administrador).
  Future<void> addNote(String incidentId, String note, {String? actorId});

  /// → resuelta, con la resolución que verán las partes.
  Future<Incident> resolve(String incidentId, String resolution, {String? actorId});

  /// → desestimada, con la resolución que verán las partes.
  Future<Incident> dismiss(String incidentId, String resolution, {String? actorId});
}
