import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_database.dart';

class LocalBookingRepository implements BookingRepository {
  final LocalDatabase _db;
  final TutorRepository _tutors;

  /// Reloj inyectable para las pruebas.
  final DateTime Function() _now;

  LocalBookingRepository(this._db, this._tutors, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

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
    if (!tutor.ensenaMateria(booking.subjectId)) {
      throw const RepositoryException('El tutor no imparte esa materia.');
    }
    if (booking.duracion <= 0) {
      throw const RepositoryException('La duración no es válida.');
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
        b.estado == BookingStatus.aceptada &&
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
    );
    await _saveAll([...all, saved]);
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
  Future<Booking> updateStatus(String bookingId, BookingStatus nuevo) async {
    final all = _all();
    final index = all.indexWhere((b) => b.id == bookingId);
    if (index < 0) {
      throw const RepositoryException('La solicitud no existe.');
    }
    final current = all[index];
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
      final busy = all.any((b) =>
          b.id != current.id &&
          b.tutorId == current.tutorId &&
          b.estado == BookingStatus.aceptada &&
          _overlaps(b, current.fechaHora, current.fin));
      if (busy) {
        throw const RepositoryException('Ya aceptaste otra sesión en ese horario.');
      }
    }
    final updated = current.copyWith(estado: nuevo);
    all[index] = updated;
    await _saveAll(all);
    return updated;
  }
}
