import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, PostgrestException, RealtimeChannel, SupabaseClient;

import '../../domain/follow_up_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../../utils/tutorea_time.dart';

/// Incidencias, gestión administrativa, reseñas y notificaciones con Supabase
/// (Fase 14.9, migraciones 20, 22 y 23).
///
/// La app solo LEE las tablas (RLS) y escribe exclusivamente con las funciones
/// del servidor, que toman la identidad de auth.uid(): los parámetros actorId de
/// los contratos se ignoran aquí. Nada se guarda en el dispositivo.

final RegExp _uuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

const String followUpFormatMessage = 'Los datos recibidos no tienen el formato esperado.';
const String followUpPermissionMessage = 'No tienes permiso para esta acción.';
const String followUpFailedMessage = 'No se pudo completar la acción. Intenta de nuevo.';
const String followUpConnectionMessage = 'No se pudo conectar con el servidor. Revisa tu conexión a Internet.';
const String followUpTimeoutMessage = 'El servidor tardó demasiado en responder. Intenta de nuevo.';

/// Errores de la Fase 14.9 → mensajes fijos (nunca el texto del servidor).
/// [duplicate]: mensaje para una violación de unicidad (23505) según la acción.
RepositoryException describeFollowUpError(Object error, {String duplicate = followUpFailedMessage}) {
  if (error is RepositoryException) return error;
  if (error is TimeoutException) return const RepositoryException(followUpTimeoutMessage);
  if (error is PostgrestException) {
    return RepositoryException(switch (error.code) {
      'TU009' => confirmNotFoundMessage,
      // Incidencias (migración 20)
      'TU030' => notReportableMessage,
      'TU031' => reportWindowClosedMessage,
      'TU032' => incidentAlreadyOpenMessage,
      'TU033' => invalidIncidentMessage,
      'TU034' => incidentNotFoundMessage,
      'TU035' => incidentTransitionMessage,
      'TU036' => incidentNoteRequiredMessage,
      // Reseñas (migración 22)
      'TU040' => onlyStudentReviewsMessage,
      'TU041' => tutorSelfReviewMessage,
      'TU042' => notCompletedReviewMessage,
      'TU043' => openIncidentBlocksReviewMessage,
      'TU044' => alreadyReviewedMessage,
      'TU045' => invalidRatingMessage,
      '23505' => duplicate,
      '42501' => followUpPermissionMessage,
      _ => followUpFailedMessage,
    });
  }
  return const RepositoryException(followUpConnectionMessage);
}

Future<T> _guard<T>(Duration timeout, Future<T> Function() call, {String? duplicate}) async {
  try {
    return await call().timeout(timeout);
  } catch (error) {
    throw describeFollowUpError(error, duplicate: duplicate ?? followUpFailedMessage);
  }
}

String _text(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is String && value.isNotEmpty) return value;
  throw const FormatException('campo faltante');
}

DateTime _instant(Map<String, dynamic> row, String key) => TutoreaTime.fromUtc(DateTime.parse(_text(row, key)));

DateTime? _optInstant(Object? value) => value is String ? TutoreaTime.fromUtc(DateTime.parse(value)) : null;

/// Convierte las filas una a una; una fila con forma inesperada se omite.
List<T> _mapRows<T>(List<Map<String, dynamic>> rows, T Function(Map<String, dynamic>) map) {
  final result = <T>[];
  for (final row in rows) {
    try {
      result.add(map(row));
    } catch (_) {}
  }
  return result;
}

Incident incidentFromRow(Map<String, dynamic> row) => Incident(
      id: _text(row, 'id'),
      bookingId: _text(row, 'booking_id'),
      reportedBy: _text(row, 'reported_by'),
      reporterParty: BookingParty.fromJson(_text(row, 'reporter_party')),
      category: IncidentCategory.fromJson(_text(row, 'category')),
      description: _text(row, 'description'),
      status: IncidentStatus.fromJson(_text(row, 'status')),
      resolutionNote: row['resolution_note'] as String?,
      resolvedAt: _optInstant(row['resolved_at']),
      createdAt: _instant(row, 'created_at'),
    );

IncidentEvent incidentEventFromRow(Map<String, dynamic> row) => IncidentEvent(
      id: _text(row, 'id'),
      incidentId: _text(row, 'incident_id'),
      event: IncidentEventType.values.byName(_text(row, 'event')),
      fromStatus: row['from_status'] is String ? IncidentStatus.fromJson(row['from_status'] as String) : null,
      toStatus: row['to_status'] is String ? IncidentStatus.fromJson(row['to_status'] as String) : null,
      note: row['note'] as String?,
      internal: row['internal'] == true,
      actorId: _text(row, 'actor_id'),
      createdAt: _instant(row, 'created_at'),
    );

Review reviewFromRow(Map<String, dynamic> row) {
  final rating = row['rating'];
  if (rating is! num) throw const FormatException('rating');
  return Review(
    id: _text(row, 'id'),
    tutorId: _text(row, 'tutor_profile_id'),
    rating: rating.toInt(),
    comment: row['comment'] as String?,
    createdAt: _instant(row, 'created_at'),
    bookingId: row['booking_id'] as String?,
    studentId: row['student_id'] as String?,
  );
}

AppNotification notificationFromRow(Map<String, dynamic> row) => AppNotification(
      id: _text(row, 'id'),
      recipientId: _text(row, 'recipient_id'),
      type: NotificationType.fromJson(_text(row, 'type')),
      bookingId: row['booking_id'] as String?,
      incidentId: row['incident_id'] as String?,
      eventKey: _text(row, 'event_key'),
      createdAt: _instant(row, 'created_at'),
      readAt: _optInstant(row['read_at']),
    );

// ---------------------------------------------------------------------------
// Origen de las filas (Supabase en la app; datos simulados en las pruebas)
// ---------------------------------------------------------------------------

abstract class FollowUpRowsSource {
  // Incidencias
  Future<String> reportIncident(String bookingId, String category, String description);
  Future<List<Map<String, dynamic>>> fetchIncidentsForBooking(String bookingId);
  Future<List<Map<String, dynamic>>> fetchIncidents({String? status});
  Future<Map<String, dynamic>?> fetchIncident(String id);
  Future<List<Map<String, dynamic>>> fetchIncidentEvents(String incidentId);

  // Gestión administrativa
  Future<void> adminStartInvestigation(String incidentId, String? note);
  Future<void> adminAddNote(String incidentId, String note);
  Future<void> adminResolve(String incidentId, String resolution);
  Future<void> adminDismiss(String incidentId, String resolution);

  // Reseñas
  Future<String> submitReview(String bookingId, int rating, String? comment);
  Future<List<Map<String, dynamic>>> fetchPublicReviews(String tutorProfileId);
  Future<Map<String, dynamic>?> fetchReviewForBooking(String bookingId);
  Future<Map<String, dynamic>?> fetchReview(String id);

  // Notificaciones
  Future<List<Map<String, dynamic>>> fetchNotifications();
  Future<int> markNotificationsRead(List<String>? ids);
  Stream<void> notificationChanges();
}

// ---------------------------------------------------------------------------
// Repositorios
// ---------------------------------------------------------------------------

class RemoteIncidentRepository implements IncidentRepository {
  final FollowUpRowsSource _source;
  final Duration _timeout;

  RemoteIncidentRepository(this._source, {Duration timeout = const Duration(seconds: 15)})
      : _timeout = timeout;

  /// report_incident: el servidor decide quién reporta (auth.uid()).
  @override
  Future<Incident> report({
    required String bookingId,
    required IncidentCategory category,
    required String description,
    String? actorId,
  }) async {
    if (!_uuid.hasMatch(bookingId)) throw const RepositoryException(confirmNotFoundMessage);
    final problem = FollowUpRules.incidentInputProblem(category, description);
    if (problem != null) throw RepositoryException(problem);
    final id = await _guard(_timeout, () => _source.reportIncident(bookingId, category.name, description.trim()),
        duplicate: incidentAlreadyOpenMessage);
    final row = await _guard(_timeout, () => _source.fetchIncident(id));
    if (row == null) throw const RepositoryException(incidentNotFoundMessage);
    try {
      return incidentFromRow(row);
    } catch (_) {
      throw const RepositoryException(followUpFormatMessage);
    }
  }

  @override
  Future<List<Incident>> getForBooking(String bookingId) async {
    if (!_uuid.hasMatch(bookingId)) return const [];
    final rows = await _guard(_timeout, () => _source.fetchIncidentsForBooking(bookingId));
    return _mapRows(rows, incidentFromRow);
  }

  /// RLS: las partes no reciben las notas internas.
  @override
  Future<List<IncidentEvent>> getEvents(String incidentId) async {
    if (!_uuid.hasMatch(incidentId)) return const [];
    final rows = await _guard(_timeout, () => _source.fetchIncidentEvents(incidentId));
    return _mapRows(rows, incidentEventFromRow).where((e) => !e.internal).toList();
  }
}

/// Gestión administrativa. El servidor exige que la sesión sea administradora
/// de la universidad de la incidencia (is_admin_of); si no, TU034 / 42501.
class RemoteAdminIncidentRepository implements AdminIncidentRepository {
  final FollowUpRowsSource _source;
  final Duration _timeout;

  RemoteAdminIncidentRepository(this._source, {Duration timeout = const Duration(seconds: 15)})
      : _timeout = timeout;

  /// RLS: el administrador ve las incidencias de su universidad.
  @override
  Future<List<Incident>> listForUniversity({IncidentStatus? status}) async {
    final rows = await _guard(_timeout, () => _source.fetchIncidents(status: status?.dbValue));
    return _mapRows(rows, incidentFromRow);
  }

  @override
  Future<List<IncidentEvent>> getEvents(String incidentId) async {
    if (!_uuid.hasMatch(incidentId)) return const [];
    final rows = await _guard(_timeout, () => _source.fetchIncidentEvents(incidentId));
    return _mapRows(rows, incidentEventFromRow);
  }

  @override
  Future<Incident> startInvestigation(String incidentId, {String? note, String? actorId}) async {
    _check(incidentId);
    final text = note?.trim();
    await _guard(_timeout, () => _source.adminStartInvestigation(incidentId, (text?.isEmpty ?? true) ? null : text));
    return _reload(incidentId);
  }

  @override
  Future<void> addNote(String incidentId, String note, {String? actorId}) async {
    _check(incidentId);
    await _guard(_timeout, () => _source.adminAddNote(incidentId, note.trim()));
  }

  @override
  Future<Incident> resolve(String incidentId, String resolution, {String? actorId}) async {
    _check(incidentId);
    await _guard(_timeout, () => _source.adminResolve(incidentId, resolution.trim()));
    return _reload(incidentId);
  }

  @override
  Future<Incident> dismiss(String incidentId, String resolution, {String? actorId}) async {
    _check(incidentId);
    await _guard(_timeout, () => _source.adminDismiss(incidentId, resolution.trim()));
    return _reload(incidentId);
  }

  void _check(String incidentId) {
    if (!_uuid.hasMatch(incidentId)) throw const RepositoryException(incidentNotFoundMessage);
  }

  Future<Incident> _reload(String id) async {
    final row = await _guard(_timeout, () => _source.fetchIncident(id));
    if (row == null) throw const RepositoryException(incidentNotFoundMessage);
    try {
      return incidentFromRow(row);
    } catch (_) {
      throw const RepositoryException(followUpFormatMessage);
    }
  }
}

class RemoteReviewRepository implements ReviewRepository {
  final FollowUpRowsSource _source;
  final Duration _timeout;

  RemoteReviewRepository(this._source, {Duration timeout = const Duration(seconds: 15)}) : _timeout = timeout;

  /// submit_review: el servidor valida al autor (auth.uid()), el estado, las
  /// incidencias y que sea la única reseña; el promedio lo recalcula un trigger.
  @override
  Future<Review> submit({
    required String bookingId,
    required int rating,
    String? comment,
    String? actorId,
  }) async {
    if (!_uuid.hasMatch(bookingId)) throw const RepositoryException(confirmNotFoundMessage);
    final text = (comment?.trim().isEmpty ?? true) ? null : comment!.trim();
    final problem = FollowUpRules.reviewInputProblem(rating, text);
    if (problem != null) throw RepositoryException(problem);
    final id = await _guard(_timeout, () => _source.submitReview(bookingId, rating, text),
        duplicate: alreadyReviewedMessage);
    final row = await _guard(_timeout, () => _source.fetchReview(id));
    if (row == null) throw const RepositoryException(followUpFormatMessage);
    try {
      return reviewFromRow(row);
    } catch (_) {
      throw const RepositoryException(followUpFormatMessage);
    }
  }

  /// Vista public_reviews: sin estudiante ni reserva.
  @override
  Future<List<Review>> getForTutor(String tutorId) async {
    if (!_uuid.hasMatch(tutorId)) return const [];
    final rows = await _guard(_timeout, () => _source.fetchPublicReviews(tutorId));
    return _mapRows(rows, (row) => reviewFromRow(row).public);
  }

  @override
  Future<Review?> getForBooking(String bookingId) async {
    if (!_uuid.hasMatch(bookingId)) return null;
    final row = await _guard(_timeout, () => _source.fetchReviewForBooking(bookingId));
    if (row == null) return null;
    try {
      return reviewFromRow(row);
    } catch (_) {
      return null;
    }
  }
}

class RemoteNotificationRepository implements NotificationRepository, NotificationChanges {
  final FollowUpRowsSource _source;
  final Duration _timeout;

  RemoteNotificationRepository(this._source, {Duration timeout = const Duration(seconds: 15)})
      : _timeout = timeout;

  /// RLS: solo las de la sesión; [userId] solo filtra por si acaso.
  @override
  Future<List<AppNotification>> getMine(String userId) async {
    final rows = await _guard(_timeout, () => _source.fetchNotifications());
    return _mapRows(rows, notificationFromRow).where((n) => n.recipientId == userId).toList();
  }

  @override
  Future<int> markRead(String userId, List<String> ids) async {
    final valid = ids.where(_uuid.hasMatch).toList();
    if (valid.isEmpty) return 0;
    return _guard(_timeout, () => _source.markNotificationsRead(valid));
  }

  @override
  Future<int> markAllRead(String userId) => _guard(_timeout, () => _source.markNotificationsRead(null));

  @override
  Stream<void> get notificationChanges => _source.notificationChanges();
}

// ---------------------------------------------------------------------------
// Supabase real (publishable key + JWT de la sesión)
// ---------------------------------------------------------------------------

class SupabaseFollowUpSource implements FollowUpRowsSource {
  final SupabaseClient _client;
  SupabaseFollowUpSource(this._client);

  static const String _incidentColumns =
      'id, booking_id, university_id, reported_by, reporter_party, category, description, status, '
      'resolution_note, resolved_at, created_at';
  static const String _eventColumns =
      'id, incident_id, event, from_status, to_status, note, internal, actor_id, created_at';
  static const String _notificationColumns =
      'id, recipient_id, type, booking_id, incident_id, event_key, read_at, created_at';

  @override
  Future<String> reportIncident(String bookingId, String category, String description) async {
    final id = await _client.rpc<dynamic>('report_incident', params: {
      'p_booking_id': bookingId,
      'p_category': category,
      'p_description': description,
    });
    if (id is! String) throw StateError('report_incident no devolvió el id.');
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchIncidentsForBooking(String bookingId) => _client
      .from('booking_incidents')
      .select(_incidentColumns)
      .eq('booking_id', bookingId)
      .order('created_at', ascending: false);

  @override
  Future<List<Map<String, dynamic>>> fetchIncidents({String? status}) {
    var query = _client.from('booking_incidents').select(_incidentColumns);
    if (status != null) query = query.eq('status', status);
    return query.order('created_at', ascending: false);
  }

  @override
  Future<Map<String, dynamic>?> fetchIncident(String id) =>
      _client.from('booking_incidents').select(_incidentColumns).eq('id', id).maybeSingle();

  @override
  Future<List<Map<String, dynamic>>> fetchIncidentEvents(String incidentId) => _client
      .from('booking_incident_events')
      .select(_eventColumns)
      .eq('incident_id', incidentId)
      .order('created_at', ascending: true);

  @override
  Future<void> adminStartInvestigation(String incidentId, String? note) async {
    await _client.rpc<dynamic>('admin_start_incident_investigation',
        params: {'p_incident_id': incidentId, 'p_note': note});
  }

  @override
  Future<void> adminAddNote(String incidentId, String note) async {
    await _client.rpc<dynamic>('admin_add_incident_note', params: {'p_incident_id': incidentId, 'p_note': note});
  }

  @override
  Future<void> adminResolve(String incidentId, String resolution) async {
    await _client.rpc<dynamic>('admin_resolve_incident',
        params: {'p_incident_id': incidentId, 'p_resolution': resolution});
  }

  @override
  Future<void> adminDismiss(String incidentId, String resolution) async {
    await _client.rpc<dynamic>('admin_dismiss_incident',
        params: {'p_incident_id': incidentId, 'p_resolution': resolution});
  }

  @override
  Future<String> submitReview(String bookingId, int rating, String? comment) async {
    final id = await _client.rpc<dynamic>('submit_review', params: {
      'p_booking_id': bookingId,
      'p_rating': rating,
      'p_comment': comment,
    });
    if (id is! String) throw StateError('submit_review no devolvió el id.');
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchPublicReviews(String tutorProfileId) => _client
      .from('public_reviews')
      .select('id, tutor_profile_id, rating, comment, created_at')
      .eq('tutor_profile_id', tutorProfileId)
      .order('created_at', ascending: false);

  @override
  Future<Map<String, dynamic>?> fetchReviewForBooking(String bookingId) => _client
      .from('reviews')
      .select('id, booking_id, tutor_profile_id, student_id, rating, comment, created_at')
      .eq('booking_id', bookingId)
      .maybeSingle();

  @override
  Future<Map<String, dynamic>?> fetchReview(String id) => _client
      .from('reviews')
      .select('id, booking_id, tutor_profile_id, student_id, rating, comment, created_at')
      .eq('id', id)
      .maybeSingle();

  @override
  Future<List<Map<String, dynamic>>> fetchNotifications() => _client
      .from('notifications')
      .select(_notificationColumns)
      .order('created_at', ascending: false)
      .limit(100);

  @override
  Future<int> markNotificationsRead(List<String>? ids) async {
    final count = await _client.rpc<dynamic>('mark_notifications_read', params: {'p_ids': ids});
    return count is num ? count.toInt() : 0;
  }

  /// Realtime (postgres_changes sobre notifications): aplica la RLS con el JWT
  /// de la sesión, así cada cuenta recibe solo las suyas. Se abre con el primer
  /// oyente y se cierra con el último.
  @override
  Stream<void> notificationChanges() {
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        channel = _client
            .channel('tutorea-notifications')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'notifications',
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final open = channel;
        channel = null;
        if (open != null) await _client.removeChannel(open);
      },
    );
    return controller.stream;
  }
}
