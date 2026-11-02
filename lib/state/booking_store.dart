import 'package:flutter/foundation.dart';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';
import '../utils/id_generator.dart';

/// Solicitudes de tutoría para ambos roles.
/// UI → BookingStore → BookingRepository → almacenamiento.
class BookingStore extends ChangeNotifier {
  final BookingRepository _bookings;

  BookingStore(this._bookings);

  List<Booking> _studentBookings = const [];
  List<Booking> _tutorRequests = const [];
  bool _loading = false;
  String? _error;

  // ---------------- Lectura ----------------

  /// Reservas del estudiante (la más reciente primero).
  List<Booking> get studentBookings => _studentBookings;

  /// Solicitudes recibidas por el tutor (la más próxima primero).
  List<Booking> get tutorRequests => _tutorRequests;

  /// Pestaña "Próximas" del estudiante: pendientes y aceptadas.
  List<Booking> get studentUpcoming =>
      _studentBookings.where((b) => b.estado.vigente).toList(growable: false);

  /// Pestaña "Historial" del estudiante: rechazadas y canceladas.
  List<Booking> get studentHistory =>
      _studentBookings.where((b) => !b.estado.vigente).toList(growable: false);

  /// Solicitudes del tutor por estado (Pendientes / Aceptadas / Rechazadas).
  List<Booking> tutorRequestsWith(BookingStatus estado) =>
      _tutorRequests.where((b) => b.estado == estado).toList(growable: false);

  int get pendingCount => tutorRequestsWith(BookingStatus.pendiente).length;

  bool get isLoading => _loading;
  String? get error => _error;

  // ---------------- Carga ----------------

  Future<void> loadForStudent(String studentId) => _run(() async {
        _studentBookings = await _bookings.getForStudent(studentId);
      });

  Future<void> loadForTutor(String tutorId) => _run(() async {
        _tutorRequests = await _bookings.getForTutor(tutorId);
      });

  // ---------------- Estudiante ----------------

  /// Envía una solicitud. Devuelve la reserva creada, o null si falló
  /// (el motivo queda en [error], ej. "El tutor no atiende en ese horario.").
  /// El precio lo calcula el repositorio con el precio actual del tutor.
  Future<Booking?> createRequest({
    required String studentId,
    required String tutorId,
    required String subjectId,
    String? tema,
    required DateTime fechaHora,
    required int duracion,
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
      ));
      _studentBookings = [created!, ..._studentBookings];
    });
    return created;
  }

  /// El estudiante cancela una de SUS solicitudes, solo si está pendiente
  /// (BookingStatus.puedeCambiarA). Una aceptada, rechazada o cancelada no
  /// se puede cancelar; el repositorio vuelve a validarlo al guardar.
  Future<bool> cancel(String bookingId) {
    final booking = _studentBookings.where((b) => b.id == bookingId).firstOrNull;
    if (booking == null) {
      reportError('No encontramos esa solicitud entre tus reservas.');
      return Future.value(false);
    }
    if (!booking.estado.puedeCambiarA(BookingStatus.cancelada)) {
      reportError('Una solicitud ${booking.estado.label.toLowerCase()} ya no se puede cancelar.');
      return Future.value(false);
    }
    return _changeStatus(bookingId, BookingStatus.cancelada);
  }

  /// Una reserva del estudiante por id (null si no está cargada).
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
    _error = null;
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

  // ---------------- Interno ----------------

  Future<bool> _changeStatus(String bookingId, BookingStatus nuevo) => _run(() async {
        final updated = await _bookings.updateStatus(bookingId, nuevo);
        _studentBookings = _replace(_studentBookings, updated);
        _tutorRequests = _replace(_tutorRequests, updated);
      });

  static List<Booking> _replace(List<Booking> list, Booking updated) =>
      [for (final b in list) b.id == updated.id ? updated : b];

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
