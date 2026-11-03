import '../../domain/follow_up_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';
import 'local_notifications.dart';

/// Reservas del modo local (shared_preferences). Mismas reglas que el servidor
/// de la Fase 14.8, salvo la identidad: en el dispositivo no hay sesión del
/// servidor, así que quién actúa lo indica la app ([updateStatus] actorId).
class LocalBookingRepository implements BookingRepository {
  final LocalDatabase _db;
  final TutorRepository _tutors;

  /// Reloj inyectable para las pruebas.
  final DateTime Function() _now;

  /// Avisos de cada hecho (Fase 14.9), como los triggers del servidor.
  final LocalNotifications _notifications;

  LocalBookingRepository(this._db, this._tutors,
      {DateTime Function()? now, LocalNotifications? notifications})
      : _now = now ?? DateTime.now,
        _notifications = notifications ?? LocalNotifications(_db, now: now);

  Future<String?> _tutorUserId(String tutorId) async => (await _tutors.getById(tutorId))?.userId;

  List<Booking> _all() =>
      _db.readList(LocalDatabase.bookings).map(Booking.fromJson).toList();

  Future<void> _saveAll(List<Booking> bookings) =>
      _db.writeList(LocalDatabase.bookings, bookings.map((b) => b.toJson()).toList());

  static bool _overlaps(Booking a, DateTime start, DateTime end) =>
      a.fechaHora.isBefore(end) && start.isBefore(a.fin);

  @override
  Future<Booking> create(Booking booking) async {
    final tutor = await _tutors.getById(booking.tutorId);
    if (tutor == null || !tutor.activo) {
      throw const RepositoryException('Este tutor no está disponible.');
    }
    if (tutor.userId == booking.studentId) {
      throw const RepositoryException(selfBookingMessage);
    }
    if (!tutor.ensenaMateria(booking.subjectId)) {
      throw const RepositoryException('El tutor no imparte esa materia.');
    }
    if (!Booking.duracionesPermitidas.contains(booking.duracion)) {
      throw const RepositoryException('La duración debe ser de 60, 90 o 120 minutos.');
    }
    final modalidad = booking.modalidad;
    if (modalidad != null && !tutor.ofrece(modalidad)) {
      throw const RepositoryException('El tutor no ofrece esa modalidad.');
    }
    if (booking.fechaHora.isBefore(_now())) {
      throw const RepositoryException('Elige una fecha y hora futuras.');
    }
    if (!tutor.disponibleEn(booking.fechaHora, booking.duracion)) {
      throw const RepositoryException('El tutor no atiende en ese horario.');
    }

    final all = _all();
    final duplicated = all.any((b) =>
        b.estado.vigente &&
        b.studentId == booking.studentId &&
        b.tutorId == booking.tutorId &&
        b.fechaHora == booking.fechaHora);
    if (duplicated) {
      throw const RepositoryException('Ya enviaste una solicitud para ese horario.');
    }
    final busy = all.any((b) =>
        b.tutorId == booking.tutorId &&
        b.estado.ocupaHorario &&
        _overlaps(b, booking.fechaHora, booking.fin));
    if (busy) {
      throw const RepositoryException('El tutor ya tiene una sesión en ese horario.');
    }

    // Toda solicitud nueva nace pendiente, con el precio calculado aquí.
    final saved = Booking(
      id: booking.id,
      studentId: booking.studentId,
      tutorId: booking.tutorId,
      subjectId: booking.subjectId,
      tema: (booking.tema?.trim().isEmpty ?? true) ? null : booking.tema!.trim(),
      fechaHora: booking.fechaHora,
      duracion: booking.duracion,
      precio: Booking.calcularPrecio(tutor.precioHora, booking.duracion),
      estado: BookingStatus.pendiente,
      modalidad: modalidad,
      ubicacion: (booking.ubicacion?.trim().isEmpty ?? true) ? null : booking.ubicacion!.trim(),
    );
    await _saveAll([...all, saved]);
    await _notifications.bookingEvent(saved, tutorUserId: tutor.userId);
    return saved;
  }

  @override
  Future<List<Booking>> getForStudent(String studentId) async =>
      _all().where((b) => b.studentId == studentId).toList()
        ..sort((a, b) => b.fechaHora.compareTo(a.fechaHora));

  @override
  Future<List<Booking>> getForTutor(String tutorId) async =>
      _all().where((b) => b.tutorId == tutorId).toList()
        ..sort((a, b) => a.fechaHora.compareTo(b.fechaHora));

  @override
  Future<Booking> updateStatus(
    String bookingId,
    BookingStatus nuevo, {
    String? motivo,
    String? actorId,
  }) async {
    final all = _all();
    final index = all.indexWhere((b) => b.id == bookingId);
    if (index < 0) {
      throw const RepositoryException('La solicitud no existe.');
    }
    final current = all[index];
    if (nuevo == BookingStatus.pendienteConfirmacion || nuevo == BookingStatus.completada) {
      // Solo con confirm(): cada parte confirma por separado y nunca por tiempo.
      throw const RepositoryException(notConfirmableMessage);
    }
    if (!current.estado.puedeCambiarA(nuevo)) {
      throw RepositoryException(
          'Una solicitud ${current.estado.label.toLowerCase()} ya no se puede modificar.');
    }
    if (nuevo == BookingStatus.aceptada) {
      // No se acepta una sesión cuya hora de inicio ya pasó.
      if (!current.fechaHora.isAfter(_now())) {
        throw const RepositoryException(
            'La fecha y hora de esta solicitud ya pasaron; no se puede aceptar.');
      }
      // Misma regla que accept_booking: perfil activo y la sesión completa dentro
      // de la disponibilidad ACTUAL (el tutor pudo cambiarla después de la solicitud).
      final tutor = await _tutors.getById(current.tutorId);
      if (tutor == null || !tutor.activo) {
        throw const RepositoryException('Tu perfil de tutor está desactivado.');
      }
      if (!tutor.disponibleEn(current.fechaHora, current.duracion)) {
        throw const RepositoryException(availabilityChangedMessage);
      }
      final busy = all.any((b) =>
          b.id != current.id &&
          b.tutorId == current.tutorId &&
          b.estado.ocupaHorario &&
          _overlaps(b, current.fechaHora, current.fin));
      if (busy) {
        throw const RepositoryException('Ya aceptaste otra sesión en ese horario.');
      }
    }
    final reason = motivo?.trim();
    if (nuevo == BookingStatus.cancelada && current.estado == BookingStatus.aceptada) {
      if (!current.fechaHora.isAfter(_now())) {
        throw const RepositoryException('La sesión ya empezó; no se puede cancelar.');
      }
      if (reason == null || reason.length < 3) {
        throw const RepositoryException(cancelReasonRequiredMessage);
      }
    }
    final now = _now();
    final updated = switch (nuevo) {
      BookingStatus.cancelada => current.copyWith(
          estado: nuevo,
          canceladaPor: actorId ?? current.studentId,
          canceladaEn: now,
          motivoCancelacion: (reason?.isEmpty ?? true) ? null : reason,
        ),
      _ => current.copyWith(estado: nuevo, respondidaEn: now),
    };
    all[index] = updated;
    await _saveAll(all);
    await _notifications.bookingEvent(updated, tutorUserId: await _tutorUserId(updated.tutorId));
    return updated;
  }

  // ---------------- Confirmaciones (Fase 14.9) ----------------

  List<BookingConfirmation> _confirmations() =>
      _db.readList(LocalDatabase.confirmations).map(BookingConfirmation.fromJson).toList();

  @override
  Future<List<BookingConfirmation>> getConfirmations(String bookingId) async =>
      _confirmations().where((c) => c.bookingId == bookingId).toList()
        ..sort((a, b) => a.confirmedAt.compareTo(b.confirmedAt));

  /// Mismas reglas que confirm_booking (migración 21). En el dispositivo no hay
  /// sesión del servidor: la parte se deduce de [actorId].
  @override
  Future<Booking> confirm(String bookingId, {String? actorId}) async {
    final all = _all();
    final index = all.indexWhere((b) => b.id == bookingId);
    if (index < 0 || actorId == null) throw const RepositoryException(confirmNotFoundMessage);
    final current = all[index];
    final tutorUserId = await _tutorUserId(current.tutorId);
    final BookingParty party;
    if (actorId == current.studentId) {
      party = BookingParty.estudiante;
    } else if (actorId == tutorUserId) {
      party = BookingParty.tutor;
    } else {
      throw const RepositoryException(confirmNotFoundMessage);
    }

    final confirmations = await getConfirmations(bookingId);
    final hasOpenIncident = _db
        .readList(LocalDatabase.incidents)
        .map(Incident.fromJson)
        .any((i) => i.bookingId == bookingId && i.abierta);
    final problem = FollowUpRules.confirmProblem(
      booking: current,
      party: party,
      confirmations: confirmations,
      hasOpenIncident: hasOpenIncident,
      now: _now(),
    );
    if (problem != null) throw RepositoryException(problem);

    final confirmation = BookingConfirmation(
      bookingId: bookingId,
      party: party,
      userId: actorId,
      confirmedAt: _now(),
    );
    await _db.writeList(LocalDatabase.confirmations,
        [..._db.readList(LocalDatabase.confirmations), confirmation.toJson()]);
    final updated = current.copyWith(estado: FollowUpRules.statusAfterConfirm(confirmations, party));
    all[index] = updated;
    await _saveAll(all);
    await _notifications.bookingEvent(updated,
        tutorUserId: tutorUserId, confirmations: [...confirmations, confirmation]);
    return updated;
  }
}
