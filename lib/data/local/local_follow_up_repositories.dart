import '../../domain/follow_up_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../../utils/id_generator.dart';
import 'local_database.dart';
import 'local_notifications.dart';

/// Incidencias, gestión administrativa, reseñas y notificaciones del modo
/// local (Fase 14.9). Mismas reglas que las funciones del servidor
/// (migraciones 19 a 23, ver FollowUpRules); la diferencia es la identidad: en
/// el dispositivo no hay sesión del servidor, así que quién actúa lo indica la
/// app (actorId), como en LocalBookingRepository.

/// Lecturas compartidas sobre la base local.
class _Store {
  final LocalDatabase db;
  final TutorRepository tutors;
  final DateTime Function() now;
  _Store(this.db, this.tutors, this.now);

  List<Booking> bookings() => db.readList(LocalDatabase.bookings).map(Booking.fromJson).toList();

  Booking? booking(String id) => bookings().where((b) => b.id == id).firstOrNull;

  List<Incident> incidents() => db.readList(LocalDatabase.incidents).map(Incident.fromJson).toList();

  Future<void> saveIncidents(List<Incident> all) =>
      db.writeList(LocalDatabase.incidents, all.map((i) => i.toJson()).toList());

  List<IncidentEvent> events() =>
      db.readList(LocalDatabase.incidentEvents).map(IncidentEvent.fromJson).toList();

  Future<void> addEvent(IncidentEvent event) =>
      db.writeList(LocalDatabase.incidentEvents, [...db.readList(LocalDatabase.incidentEvents), event.toJson()]);

  bool hasOpenIncident(String bookingId) => incidents().any((i) => i.bookingId == bookingId && i.abierta);

  Future<String?> tutorUserId(String tutorId) async => (await tutors.getById(tutorId))?.userId;

  /// Parte de [actorId] en la reserva, o null si no participa.
  Future<BookingParty?> partyOf(Booking booking, String? actorId) async {
    if (actorId == null) return null;
    if (actorId == booking.studentId) return BookingParty.estudiante;
    if (actorId == await tutorUserId(booking.tutorId)) return BookingParty.tutor;
    return null;
  }
}

class LocalIncidentRepository implements IncidentRepository {
  final _Store _s;
  final LocalNotifications _notifications;

  LocalIncidentRepository(LocalDatabase db, TutorRepository tutors,
      {DateTime Function()? now, LocalNotifications? notifications})
      : _s = _Store(db, tutors, now ?? DateTime.now),
        _notifications = notifications ?? LocalNotifications(db, now: now);

  @override
  Future<Incident> report({
    required String bookingId,
    required IncidentCategory category,
    required String description,
    String? actorId,
  }) async {
    final booking = _s.booking(bookingId);
    final party = booking == null ? null : await _s.partyOf(booking, actorId);
    if (booking == null || party == null) throw const RepositoryException(confirmNotFoundMessage);
    final problem = FollowUpRules.reportProblem(booking: booking, now: _s.now()) ??
        FollowUpRules.incidentInputProblem(category, description);
    if (problem != null) throw RepositoryException(problem);
    final all = _s.incidents();
    if (all.any((i) => i.bookingId == bookingId && i.reportedBy == actorId && i.abierta)) {
      throw const RepositoryException(incidentAlreadyOpenMessage);
    }
    final incident = Incident(
      id: IdGenerator.newId('in'),
      bookingId: bookingId,
      reportedBy: actorId!,
      reporterParty: party,
      category: category,
      description: description.trim(),
      createdAt: _s.now(),
    );
    await _s.saveIncidents([...all, incident]);
    await _s.addEvent(IncidentEvent(
      id: IdGenerator.newId('ie'),
      incidentId: incident.id,
      event: IncidentEventType.reportada,
      actorId: actorId,
      createdAt: _s.now(),
    ));
    await _notifications.incidentEvent(incident,
        studentId: booking.studentId, tutorUserId: await _s.tutorUserId(booking.tutorId), created: true);
    return incident;
  }

  @override
  Future<List<Incident>> getForBooking(String bookingId) async =>
      _s.incidents().where((i) => i.bookingId == bookingId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Las partes no ven las notas internas.
  @override
  Future<List<IncidentEvent>> getEvents(String incidentId) async =>
      _s.events().where((e) => e.incidentId == incidentId && !e.internal).toList();
}

/// Gestión administrativa local. El modo local no tiene cuentas de
/// administrador ni sesión del servidor: no hay pantallas que la usen y no
/// comprueba identidad (sirve para probar las mismas reglas que el servidor).
class LocalAdminIncidentRepository implements AdminIncidentRepository {
  final _Store _s;
  final LocalNotifications _notifications;

  LocalAdminIncidentRepository(LocalDatabase db, TutorRepository tutors,
      {DateTime Function()? now, LocalNotifications? notifications})
      : _s = _Store(db, tutors, now ?? DateTime.now),
        _notifications = notifications ?? LocalNotifications(db, now: now);

  static const String _localAdmin = 'admin-local';

  @override
  Future<List<Incident>> listForUniversity({IncidentStatus? status}) async =>
      _s.incidents().where((i) => status == null || i.status == status).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<List<IncidentEvent>> getEvents(String incidentId) async =>
      _s.events().where((e) => e.incidentId == incidentId).toList();

  @override
  Future<Incident> startInvestigation(String incidentId, {String? note, String? actorId}) =>
      _change(incidentId, IncidentStatus.enInvestigacion, note, actorId);

  @override
  Future<Incident> resolve(String incidentId, String resolution, {String? actorId}) =>
      _change(incidentId, IncidentStatus.resuelta, resolution, actorId);

  @override
  Future<Incident> dismiss(String incidentId, String resolution, {String? actorId}) =>
      _change(incidentId, IncidentStatus.desestimada, resolution, actorId);

  @override
  Future<void> addNote(String incidentId, String note, {String? actorId}) async {
    if (!_s.incidents().any((i) => i.id == incidentId)) {
      throw const RepositoryException(incidentNotFoundMessage);
    }
    final text = note.trim();
    if (text.isEmpty || text.length > 2000) throw const RepositoryException(incidentNoteRequiredMessage);
    await _s.addEvent(IncidentEvent(
      id: IdGenerator.newId('ie'),
      incidentId: incidentId,
      event: IncidentEventType.nota,
      note: text,
      internal: true,
      actorId: actorId ?? _localAdmin,
      createdAt: _s.now(),
    ));
  }

  /// Mismas reglas que admin_change_incident (migración 20). No toca la reserva.
  Future<Incident> _change(String incidentId, IncidentStatus to, String? note, String? actorId) async {
    final all = _s.incidents();
    final index = all.indexWhere((i) => i.id == incidentId);
    if (index < 0) throw const RepositoryException(incidentNotFoundMessage);
    final current = all[index];
    if (!current.status.puedeCambiarA(to)) throw const RepositoryException(incidentTransitionMessage);
    final text = note?.trim();
    final isFinal = !to.abierta;
    if (isFinal && (text == null || text.length < 5)) {
      throw const RepositoryException(incidentNoteRequiredMessage);
    }
    final updated = isFinal
        ? current.copyWith(status: to, resolutionNote: text, resolvedAt: _s.now())
        : current.copyWith(status: to);
    all[index] = updated;
    await _s.saveIncidents(all);
    final actor = actorId ?? _localAdmin;
    await _s.addEvent(IncidentEvent(
      id: IdGenerator.newId('ie'),
      incidentId: incidentId,
      event: IncidentEventType.estado,
      fromStatus: current.status,
      toStatus: to,
      note: isFinal ? text : null,
      actorId: actor,
      createdAt: _s.now(),
    ));
    if (!isFinal && text != null && text.isNotEmpty) await addNote(incidentId, text, actorId: actor);
    final booking = _s.booking(current.bookingId);
    if (booking != null) {
      await _notifications.incidentEvent(updated,
          studentId: booking.studentId, tutorUserId: await _s.tutorUserId(booking.tutorId), created: false);
    }
    return updated;
  }
}

class LocalReviewRepository implements ReviewRepository {
  final _Store _s;

  LocalReviewRepository(LocalDatabase db, TutorRepository tutors, {DateTime Function()? now})
      : _s = _Store(db, tutors, now ?? DateTime.now);

  List<Review> _all() => _s.db.readList(LocalDatabase.reviews).map(Review.fromJson).toList();

  /// Mismas reglas que submit_review (migración 22).
  @override
  Future<Review> submit({
    required String bookingId,
    required int rating,
    String? comment,
    String? actorId,
  }) async {
    final booking = _s.booking(bookingId);
    final party = booking == null ? null : await _s.partyOf(booking, actorId);
    if (booking == null || party == null) throw const RepositoryException(confirmNotFoundMessage);
    final all = _all();
    final text = (comment?.trim().isEmpty ?? true) ? null : comment!.trim();
    final problem = FollowUpRules.reviewProblem(
          booking: booking,
          party: party,
          hasOpenIncident: _s.hasOpenIncident(bookingId),
          alreadyReviewed: all.any((r) => r.bookingId == bookingId),
        ) ??
        FollowUpRules.reviewInputProblem(rating, text);
    if (problem != null) throw RepositoryException(problem);

    final review = Review(
      id: IdGenerator.newId('rv'),
      tutorId: booking.tutorId,
      rating: rating,
      comment: text,
      createdAt: _s.now(),
      bookingId: bookingId,
      studentId: actorId,
    );
    final updated = [...all, review];
    await _s.db.writeList(LocalDatabase.reviews, updated.map((r) => r.toJson()).toList());
    await _recalcTutorRating(booking.tutorId, updated);
    return review;
  }

  /// Promedio y total del tutor a partir de las reseñas (recalc_tutor_rating).
  Future<void> _recalcTutorRating(String tutorId, List<Review> reviews) async {
    final ratings = [for (final r in reviews) if (r.tutorId == tutorId) r.rating];
    final profiles = _s.db.readList(LocalDatabase.tutorProfiles);
    for (final p in profiles) {
      if (p['id'] == tutorId) {
        p['rating'] = FollowUpRules.average(ratings);
        p['ratingCount'] = ratings.length;
      }
    }
    await _s.db.writeList(LocalDatabase.tutorProfiles, profiles);
  }

  @override
  Future<List<Review>> getForTutor(String tutorId) async =>
      [for (final r in _all()) if (r.tutorId == tutorId) r.public]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<Review?> getForBooking(String bookingId) async =>
      _all().where((r) => r.bookingId == bookingId).firstOrNull;
}

class LocalNotificationRepository implements NotificationRepository {
  final LocalDatabase _db;
  final DateTime Function() _now;

  LocalNotificationRepository(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  List<AppNotification> _all() =>
      _db.readList(LocalDatabase.notifications).map(AppNotification.fromJson).toList();

  @override
  Future<List<AppNotification>> getMine(String userId) async =>
      _all().where((n) => n.recipientId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<int> markRead(String userId, List<String> ids) => _mark(userId, ids.toSet());

  @override
  Future<int> markAllRead(String userId) => _mark(userId, null);

  Future<int> _mark(String userId, Set<String>? ids) async {
    var changed = 0;
    final now = _now();
    final updated = [
      for (final n in _all())
        if (n.recipientId == userId && !n.leida && (ids == null || ids.contains(n.id)))
          (() {
            changed++;
            return n.markedRead(now);
          })()
        else
          n,
    ];
    if (changed > 0) {
      await _db.writeList(LocalDatabase.notifications, updated.map((n) => n.toJson()).toList());
    }
    return changed;
  }
}
