import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';

/// Stores de la Fase 14.9: incidencias, reseñas y notificaciones.
///   UI → Store → Repository → almacenamiento local o Supabase.
/// Las reglas las vuelve a validar el repositorio (en Supabase, el servidor).

/// Base común: carga, error y ejecución con mensaje fijo.
abstract class _FollowUpStore extends ChangeNotifier {
  bool _loading = false;
  String? _error;

  bool get isLoading => _loading;
  String? get error => _error;

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() action) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on RepositoryException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = 'Ocurrió un error. Intenta de nuevo.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}

/// Incidencias de las reservas propias.
class IncidentStore extends _FollowUpStore {
  final IncidentRepository _incidents;
  IncidentStore(this._incidents);

  final Map<String, List<Incident>> _byBooking = {};
  final Map<String, List<IncidentEvent>> _events = {};

  /// Incidencias cargadas de una reserva (la más reciente primero).
  List<Incident> forBooking(String bookingId) => _byBooking[bookingId] ?? const [];

  bool hasOpen(String bookingId) => forBooking(bookingId).any((i) => i.abierta);

  /// ¿[userId] ya tiene una incidencia abierta en esa reserva?
  bool hasOpenBy(String bookingId, String userId) =>
      forBooking(bookingId).any((i) => i.abierta && i.reportedBy == userId);

  List<IncidentEvent> eventsFor(String incidentId) => _events[incidentId] ?? const [];

  Future<void> loadForBooking(String bookingId) async {
    try {
      _byBooking[bookingId] = await _incidents.getForBooking(bookingId);
      notifyListeners();
    } catch (_) {
      // Sin red: se mantiene lo que ya se mostraba.
    }
  }

  Future<void> loadEvents(String incidentId) async {
    try {
      _events[incidentId] = await _incidents.getEvents(incidentId);
      notifyListeners();
    } catch (_) {}
  }

  /// Reporta un problema. Devuelve la incidencia creada o null (motivo en [error]).
  Future<Incident?> report({
    required String bookingId,
    required IncidentCategory category,
    required String description,
    String? actorId,
  }) async {
    Incident? created;
    await _run(() async {
      created = await _incidents.report(
          bookingId: bookingId, category: category, description: description, actorId: actorId);
      _byBooking[bookingId] = [created!, ...forBooking(bookingId)];
    });
    return created;
  }

  void reset() {
    _byBooking.clear();
    _events.clear();
    _error = null;
    notifyListeners();
  }
}

/// Reseñas: la de cada reserva propia y las públicas de cada tutor.
class ReviewStore extends _FollowUpStore {
  final ReviewRepository _reviews;
  ReviewStore(this._reviews);

  final Map<String, Review?> _byBooking = {};
  final Map<String, List<Review>> _byTutor = {};

  /// Reseña de la reserva (null si no hay o no se cargó).
  Review? forBooking(String bookingId) => _byBooking[bookingId];

  /// ¿Ya se consultó la reseña de esa reserva?
  bool loadedForBooking(String bookingId) => _byBooking.containsKey(bookingId);

  /// Reseñas públicas cargadas de un tutor (la más reciente primero).
  List<Review> forTutor(String tutorId) => _byTutor[tutorId] ?? const [];

  Future<void> loadForBooking(String bookingId) async {
    try {
      _byBooking[bookingId] = await _reviews.getForBooking(bookingId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadForTutor(String tutorId) async {
    try {
      _byTutor[tutorId] = await _reviews.getForTutor(tutorId);
      notifyListeners();
    } catch (_) {}
  }

  /// Califica al tutor de una reserva completada. Devuelve la reseña o null.
  Future<Review?> submit({
    required String bookingId,
    required int rating,
    String? comment,
    String? actorId,
  }) async {
    Review? created;
    await _run(() async {
      created = await _reviews.submit(bookingId: bookingId, rating: rating, comment: comment, actorId: actorId);
      _byBooking[bookingId] = created;
      final tutorId = created!.tutorId;
      if (_byTutor.containsKey(tutorId)) _byTutor[tutorId] = [created!.public, ...forTutor(tutorId)];
    });
    return created;
  }

  void reset() {
    _byBooking.clear();
    _byTutor.clear();
    _error = null;
    notifyListeners();
  }
}

/// Notificaciones de la cuenta con sesión. Con Supabase Realtime
/// ([NotificationChanges]) se vuelven a leer en cuanto llega una nueva; la
/// lista inicial se obtiene siempre con una consulta ([load]).
class NotificationStore extends _FollowUpStore {
  final NotificationRepository _notifications;
  StreamSubscription<void>? _changes;

  NotificationStore(this._notifications) {
    if (_notifications case final NotificationChanges source) {
      _changes = source.notificationChanges.listen((_) => refresh(), onError: (_) {});
    }
  }

  List<AppNotification> _items = const [];
  String? _userId;

  List<AppNotification> get items => _items;
  int get unreadCount => _items.where((n) => !n.leida).length;
  bool get hasUnread => unreadCount > 0;

  Future<void> load(String userId) => _run(() async {
        _userId = userId;
        _items = await _notifications.getMine(userId);
      });

  /// Vuelve a leer sin indicador de carga.
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final items = await _notifications.getMine(userId);
      if (userId != _userId) return;
      _items = items;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    final userId = _userId;
    if (userId == null) return;
    final target = _items.where((n) => n.id == id).firstOrNull;
    if (target == null || target.leida) return;
    final ok = await _run(() => _notifications.markRead(userId, [id]));
    if (ok) await refresh();
  }

  Future<void> markAllRead() async {
    final userId = _userId;
    if (userId == null || !hasUnread) return;
    final ok = await _run(() => _notifications.markAllRead(userId));
    if (ok) await refresh();
  }

  void reset() {
    _items = const [];
    _userId = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }
}
