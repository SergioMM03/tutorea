import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/follow_up_rules.dart';
import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import '../utils/id_generator.dart';
import '../utils/tutorea_time.dart';

/// Reservas de la cuenta con sesión, en sus dos papeles (una misma cuenta puede
/// solicitar tutorías y, con su perfil de tutor, recibirlas):
/// - [studentBookings]: solicitudes que ENVIÓ (modo estudiante).
/// - [tutorRequests]: solicitudes que RECIBIÓ su perfil de tutor (modo tutor).
///
/// UI → BookingStore → BookingRepository → almacenamiento local o Supabase.
///
/// Si el repositorio avisa cambios ([BookingChanges], Supabase Realtime), vuelve
/// a leer las listas y deja un aviso en [notice] (lo muestra BookingNoticeListener).
class BookingStore extends ChangeNotifier {
  final BookingRepository _bookings;
  final DateTime Function() _now;
  StreamSubscription<void>? _changes;

  BookingStore(this._bookings, {DateTime Function()? now}) : _now = now ?? TutoreaTime.now {
    if (_bookings case final BookingChanges source) {
      _changes = source.bookingChanges.listen((_) => refresh(fromServer: true), onError: (_) {});
    }
  }

  List<Booking> _studentBookings = const [];
  List<Booking> _tutorRequests = const [];
  String? _studentId; // última cuenta cargada como estudiante
  String? _tutorId; // último perfil de tutor cargado
  bool _loading = false;
  String? _error;
  String? _notice;
  int _noticeSerial = 0;

  // ---------------- Lectura ----------------

  /// Solicitudes enviadas (la más reciente primero).
  List<Booking> get studentBookings => _studentBookings;

  /// Solicitudes recibidas por el perfil de tutor (la más próxima primero).
  List<Booking> get tutorRequests => _tutorRequests;

  /// Pestaña "Próximas" del estudiante: pendientes, aceptadas y por confirmar.
  List<Booking> get studentUpcoming =>
      _studentBookings.where((b) => b.estado.vigente).toList(growable: false);

  /// Pestaña "Historial" del estudiante: rechazadas, canceladas y completadas.
  List<Booking> get studentHistory =>
      _studentBookings.where((b) => !b.estado.vigente).toList(growable: false);

  /// Solicitudes recibidas con ese estado.
  List<Booking> tutorRequestsWith(BookingStatus estado) =>
      _tutorRequests.where((b) => b.estado == estado).toList(growable: false);

  /// Solicitudes recibidas con cualquiera de esos estados.
  List<Booking> tutorRequestsIn(Set<BookingStatus> estados) =>
      _tutorRequests.where((b) => estados.contains(b.estado)).toList(growable: false);

  int get pendingCount => tutorRequestsWith(BookingStatus.pendiente).length;

  bool get isLoading => _loading;
  String? get error => _error;

  /// Último aviso de un cambio hecho por la otra parte (null = ninguno).
  String? get notice => _notice;

  /// Cambia con cada aviso nuevo (para mostrarlo una sola vez).
  int get noticeSerial => _noticeSerial;

  /// ¿Puede cancelarla quien la solicitó? / ¿Puede cancelarla el tutor?
  bool canCancelAsStudent(Booking b) => b.puedeCancelarEstudiante(_now());
  bool canCancelAsTutor(Booking b) => b.puedeCancelarTutor(_now());

  // ---------------- Confirmaciones (Fase 14.9) ----------------

  final Map<String, List<BookingConfirmation>> _confirmations = {};

  /// Confirmaciones ya cargadas de una reserva (vacía si no se cargaron).
  List<BookingConfirmation> confirmationsFor(String bookingId) => _confirmations[bookingId] ?? const [];

  /// ¿Ya confirmó [party] esta reserva?
  bool hasConfirmed(String bookingId, BookingParty party) =>
      confirmationsFor(bookingId).any((c) => c.party == party);

  /// ¿La sesión ya terminó y la reserva espera confirmaciones? (La parte que
  /// falta y las incidencias abiertas las vuelve a validar el repositorio.)
  bool sessionEnded(Booking b) =>
      (b.estado == BookingStatus.aceptada || b.estado == BookingStatus.pendienteConfirmacion) &&
      !_now().isBefore(b.fin);

  /// ¿Todavía se puede reportar una incidencia (hasta 7 días después del fin)?
  bool canReport(Booking b) => FollowUpRules.reportProblem(booking: b, now: _now()) == null;

  Future<void> loadConfirmations(String bookingId) async {
    try {
      _confirmations[bookingId] = await _bookings.getConfirmations(bookingId);
      notifyListeners();
    } catch (_) {
      // Sin red: se mantiene lo que ya se mostraba.
    }
  }

  /// Confirma que la sesión se realizó. La primera confirmación deja la reserva
  /// pendiente de confirmación; la segunda la completa (si no hay incidencias
  /// abiertas). [actorId]: la cuenta que confirma (Supabase usa la sesión).
  Future<bool> confirm(String bookingId, {String? actorId}) async {
    final ok = await _run(() async {
      final updated = await _bookings.confirm(bookingId, actorId: actorId);
      _studentBookings = _replace(_studentBookings, updated);
      _tutorRequests = _replace(_tutorRequests, updated);
    });
    await loadConfirmations(bookingId);
    return ok;
  }

  /// Reserva cargada por id, enviada o recibida (null si no está).
  Booking? bookingById(String id) =>
      _studentBookings.where((b) => b.id == id).firstOrNull ??
      _tutorRequests.where((b) => b.id == id).firstOrNull;

  // ---------------- Carga ----------------

  Future<void> loadForStudent(String studentId) => _run(() async {
        _studentId = studentId;
        _studentBookings = await _bookings.getForStudent(studentId);
      });

  Future<void> loadForTutor(String tutorId) => _run(() async {
        _tutorId = tutorId;
        _tutorRequests = await _bookings.getForTutor(tutorId);
      });

  /// Vuelve a leer las listas ya cargadas, sin indicador de carga.
  /// [fromServer]: el cambio lo hizo otra cuenta (Realtime) → deja un [notice].
  Future<void> refresh({bool fromServer = false}) async {
    final studentId = _studentId;
    final tutorId = _tutorId;
    if (studentId == null && tutorId == null) return;
    try {
      final oldStudent = _studentBookings;
      final oldTutor = _tutorRequests;
      final student = studentId == null ? null : await _bookings.getForStudent(studentId);
      final tutor = tutorId == null ? null : await _bookings.getForTutor(tutorId);
      // La sesión pudo cambiar mientras se leía.
      if (studentId != _studentId || tutorId != _tutorId) return;
      if (student != null) _studentBookings = student;
      if (tutor != null) _tutorRequests = tutor;
      if (fromServer) {
        final message = _describeChanges(oldStudent, _studentBookings, oldTutor, _tutorRequests);
        if (message != null) {
          _notice = message;
          _noticeSerial++;
        }
      }
      notifyListeners();
    } catch (_) {
      // Sin red: se mantiene lo que ya se mostraba; la próxima carga lo corrige.
    }
  }

  // ---------------- Quien solicita ----------------

  /// Envía una solicitud. Devuelve la reserva creada, o null si falló
  /// (el motivo queda en [error], ej. "El tutor no atiende en ese horario.").
  /// El precio acordado lo calcula el repositorio (en Supabase, el servidor)
  /// con la tarifa actual del tutor.
  Future<Booking?> createRequest({
    required String studentId,
    required String tutorId,
    required String subjectId,
    String? tema,
    required DateTime fechaHora,
    required int duracion,
    TutoringModality? modalidad,
    String? ubicacion,
  }) async {
    Booking? created;
    await _run(() async {
      created = await _bookings.create(Booking(
        id: IdGenerator.newId('bk'),
        studentId: studentId,
        tutorId: tutorId,
        subjectId: subjectId,
        tema: tema,
        fechaHora: fechaHora,
        duracion: duracion,
        precio: 0,
        modalidad: modalidad,
        ubicacion: ubicacion,
      ));
      _studentId ??= studentId;
      _studentBookings = [created!, ..._studentBookings];
    });
    return created;
  }

  /// Cancela una reserva propia (enviada o recibida):
  /// - pendiente: solo quien la solicitó (el tutor la rechaza);
  /// - aceptada: cualquiera de las dos partes, antes del inicio y con [motivo].
  /// [actorId]: la cuenta que cancela (el modo local lo guarda; Supabase usa la
  /// sesión). El repositorio vuelve a validarlo todo.
  Future<bool> cancel(String bookingId, {String? motivo, String? actorId}) {
    final sent = _studentBookings.where((b) => b.id == bookingId).firstOrNull;
    final received = sent == null ? _tutorRequests.where((b) => b.id == bookingId).firstOrNull : null;
    final booking = sent ?? received;
    if (booking == null) {
      reportError('No encontramos esa solicitud entre tus reservas.');
      return Future.value(false);
    }
    final allowed = sent != null ? canCancelAsStudent(booking) : canCancelAsTutor(booking);
    if (!allowed) {
      reportError(booking.estado == BookingStatus.aceptada
          ? 'La sesión ya empezó; no se puede cancelar.'
          : 'Una solicitud ${booking.estado.label.toLowerCase()} ya no se puede cancelar.');
      return Future.value(false);
    }
    if (booking.requiereMotivo && (motivo == null || motivo.trim().length < 3)) {
      reportError(cancelReasonRequiredMessage);
      return Future.value(false);
    }
    return _changeStatus(bookingId, BookingStatus.cancelada,
        motivo: motivo?.trim(), actorId: actorId ?? (sent != null ? booking.studentId : null));
  }

  /// Una reserva enviada por id (null si no está cargada).
  Booking? studentBookingById(String id) =>
      _studentBookings.where((b) => b.id == id).firstOrNull;

  // ---------------- Tutor ----------------

  Future<bool> accept(String bookingId) => _changeStatus(bookingId, BookingStatus.aceptada);

  Future<bool> reject(String bookingId) => _changeStatus(bookingId, BookingStatus.rechazada);

  // ---------------- General ----------------

  /// Al cerrar sesión, olvida las listas del usuario anterior.
  void reset() {
    _studentBookings = const [];
    _tutorRequests = const [];
    _studentId = null;
    _tutorId = null;
    _confirmations.clear();
    _error = null;
    _notice = null;
    notifyListeners();
  }

  /// Muestra un error de validación de la pantalla con el mismo canal
  /// que los errores del repositorio (ej. "Elige una hora.").
  void reportError(String message) {
    _error = message;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void clearNotice() => _notice = null;

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  // ---------------- Interno ----------------

  Future<bool> _changeStatus(String bookingId, BookingStatus nuevo,
          {String? motivo, String? actorId}) =>
      _run(() async {
        final updated =
            await _bookings.updateStatus(bookingId, nuevo, motivo: motivo, actorId: actorId);
        _studentBookings = _replace(_studentBookings, updated);
        _tutorRequests = _replace(_tutorRequests, updated);
      });

  static List<Booking> _replace(List<Booking> list, Booking updated) =>
      [for (final b in list) b.id == updated.id ? updated : b];

  /// Texto del aviso para un cambio que hizo la otra parte, o null.
  static String? _describeChanges(
    List<Booking> oldSent,
    List<Booking> newSent,
    List<Booking> oldReceived,
    List<Booking> newReceived,
  ) {
    final before = {for (final b in oldSent) b.id: b.estado};
    for (final b in newSent) {
      final previous = before[b.id];
      if (previous == null || previous == b.estado) continue;
      switch (b.estado) {
        case BookingStatus.aceptada:
          return 'El tutor aceptó tu solicitud.';
        case BookingStatus.rechazada:
          return 'El tutor rechazó tu solicitud.';
        case BookingStatus.cancelada when b.canceladaPor != b.studentId:
          return 'El tutor canceló una reserva.';
        default:
          break;
      }
    }
    final received = {for (final b in oldReceived) b.id: b.estado};
    for (final b in newReceived) {
      final previous = received[b.id];
      if (previous == null && b.estado == BookingStatus.pendiente) {
        return 'Recibiste una nueva solicitud de tutoría.';
      }
      if (previous != null && previous != b.estado && b.estado == BookingStatus.cancelada &&
          b.canceladaPor == b.studentId) {
        return 'El estudiante canceló una reserva.';
      }
    }
    return null;
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
      _error = 'Ocurrió un error con la solicitud. Intenta de nuevo.';
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
