import '../models/models.dart';

/// Notificaciones de la cuenta con sesión (Fase 14.9).
///
/// Las crea el sistema, nunca la app: en Supabase, triggers del servidor sobre
/// reservas e incidencias (migración 23); en modo local, los repositorios
/// locales al registrar cada hecho. La app solo las lee y las marca como leídas.
abstract class NotificationRepository {
  /// Notificaciones de [userId] (en Supabase, siempre las de la sesión), la más
  /// reciente primero.
  Future<List<AppNotification>> getMine(String userId);

  /// Marca como leídas las indicadas (solo las propias). Devuelve cuántas cambiaron.
  Future<int> markRead(String userId, List<String> ids);

  /// Marca como leídas todas las propias. Devuelve cuántas cambiaron.
  Future<int> markAllRead(String userId);
}

/// Capacidad opcional: avisa cuando llegan notificaciones nuevas (Supabase
/// Realtime). El modo local no la necesita.
abstract class NotificationChanges {
  Stream<void> get notificationChanges;
}
