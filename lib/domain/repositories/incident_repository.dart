import '../models/models.dart';

/// Incidencias de las reservas propias (Fase 14.9).
///
/// Implementaciones: LocalIncidentRepository (shared_preferences) y
/// RemoteIncidentRepository (Supabase: tabla booking_incidents y función
/// report_incident, migración 20).
abstract class IncidentRepository {
  /// Reporta un problema de una reserva aceptada, hasta 7 días después del fin.
  /// [actorId]: cuenta que reporta (Supabase usa la sesión: auth.uid()).
  Future<Incident> report({
    required String bookingId,
    required IncidentCategory category,
    required String description,
    String? actorId,
  });

  /// Incidencias de una reserva (de las dos partes), la más reciente primero.
  Future<List<Incident>> getForBooking(String bookingId);

  /// Historial visible para las partes (sin notas internas), en orden.
  Future<List<IncidentEvent>> getEvents(String incidentId);
}
