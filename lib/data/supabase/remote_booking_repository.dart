import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgresChangeEvent, PostgrestException, RealtimeChannel, SupabaseClient;

import '../../domain/follow_up_rules.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../../utils/tutorea_time.dart';
import 'remote_catalog_repositories.dart';

/// BookingRepository con Supabase (Fase 14.8).
///
/// Tabla `bookings` (migración 17) y funciones `request_booking`,
/// `accept_booking`, `reject_booking` y `cancel_booking` (migración 18). La app
/// solo LEE la tabla (RLS: quien solicitó o el dueño del perfil de tutor, en su
/// universidad); toda escritura pasa por las funciones, que toman la identidad
/// de auth.uid() y validan en el servidor: tutor activo de la misma
/// universidad, materia ofrecida, modalidad, disponibilidad, duración, fecha
/// futura, autorreserva, cruces de horario y transiciones de estado.
///
/// Nada se guarda en el dispositivo. Los ids enviados por la app para el
/// estudiante, la universidad o el precio no existen en la API: el servidor
/// los decide.
///
/// Ids: reservas, cuentas y perfiles de tutor son uuid; la materia se traduce
/// slug ↔ uuid con el catálogo remoto. Fechas: ver TutoreaTime (la reserva viaja
/// en UTC y en la app es hora de El Salvador).
class RemoteBookingRepository implements BookingRepository, BookingChanges {
  final BookingRowsSource _source;
  final RemoteCatalogCache _catalog;
  final TutorRepository _tutors;
  final Duration _timeout;

  RemoteBookingRepository(
    this._source,
    this._catalog,
    this._tutors, {
    Duration timeout = const Duration(seconds: 15),
  }) : _timeout = timeout;

  static final RegExp _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  // ---------------------------------------------------------------- lectura

  @override
  Future<List<Booking>> getForStudent(String studentId) async {
    if (!_uuid.hasMatch(studentId)) return const [];
    final rows = await _guard(() => _source.fetchForStudent(studentId));
    return _mapAll(rows);
  }

  @override
  Future<List<Booking>> getForTutor(String tutorId) async {
    if (!_uuid.hasMatch(tutorId)) return const [];
    final rows = await _guard(() => _source.fetchForTutor(tutorId));
    return _mapAll(rows);
  }

  @override
  Stream<void> get bookingChanges => _source.changes();

  // ---------------------------------------------------------------- escritura

  @override
  Future<Booking> create(Booking booking) async {
    final modalidad = booking.modalidad;
    if (modalidad == null) throw const RepositoryException(chooseModalityMessage);
    if (!Booking.duracionesPermitidas.contains(booking.duracion)) {
      throw const RepositoryException(invalidDurationMessage);
    }
    final tutor = _uuid.hasMatch(booking.tutorId) ? await _tutors.getById(booking.tutorId) : null;
    if (tutor == null) throw const RepositoryException(tutorUnavailableMessage);
    if (tutor.userId == booking.studentId) throw const RepositoryException(selfBookingMessage);

    final catalog = await _guard(() => _catalog.bySlug(tutor.universityId));
    final subjectUuid = catalog?.subjectUuidBySlug[booking.subjectId];
    if (subjectUuid == null) throw const RepositoryException(subjectNotOfferedMessage);

    final id = await _guard(() => _source.request(
          tutorProfileId: booking.tutorId,
          subjectId: subjectUuid,
          modality: modalidad.name, // 'presencial' | 'virtual' (enum booking_modality)
          startsAtUtc: TutoreaTime.toUtc(booking.fechaHora).toIso8601String(),
          durationMinutes: booking.duracion,
          topic: booking.tema,
          location: booking.ubicacion,
        ));
    return _reload(id);
  }

  @override
  Future<Booking> updateStatus(
    String bookingId,
    BookingStatus nuevo, {
    String? motivo,
    String? actorId, // se ignora: el servidor usa auth.uid()
  }) async {
    if (!_uuid.hasMatch(bookingId)) throw const RepositoryException(notFoundMessage);
    await _guard(() => switch (nuevo) {
          BookingStatus.aceptada => _source.accept(bookingId),
          BookingStatus.rechazada => _source.reject(bookingId),
          BookingStatus.cancelada => _source.cancel(bookingId, motivo),
          _ => throw const RepositoryException(notAvailableYetMessage),
        });
    return _reload(bookingId);
  }

  // ------------------------------------------- confirmaciones (Fase 14.9)

  /// confirm_booking (migración 21): la parte la decide el servidor con
  /// auth.uid(); [actorId] se ignora.
  @override
  Future<Booking> confirm(String bookingId, {String? actorId}) async {
    if (!_uuid.hasMatch(bookingId)) throw const RepositoryException(confirmNotFoundMessage);
    await _guard(() => _source.confirm(bookingId));
    return _reload(bookingId);
  }

  @override
  Future<List<BookingConfirmation>> getConfirmations(String bookingId) async {
    if (!_uuid.hasMatch(bookingId)) return const [];
    final rows = await _guard(() => _source.fetchConfirmations(bookingId));
    final result = <BookingConfirmation>[];
    for (final row in rows) {
      final party = row['party'];
      final user = row['user_id'];
      final at = row['confirmed_at'];
      if (party is! String || user is! String || at is! String) continue;
      try {
        result.add(BookingConfirmation(
          bookingId: bookingId,
          party: BookingParty.fromJson(party),
          userId: user,
          confirmedAt: TutoreaTime.fromUtc(DateTime.parse(at)),
        ));
      } on FormatException {
        // Fila con forma inesperada: se omite.
      }
    }
    return result;
  }

  // ---------------------------------------------------------------- mapeo

  Future<Booking> _reload(String id) async {
    final row = await _guard(() => _source.fetchById(id));
    if (row == null) throw const RepositoryException(notFoundMessage);
    return _guard(() => _map(row));
  }

  Future<List<Booking>> _mapAll(List<Map<String, dynamic>> rows) async {
    final result = <Booking>[];
    for (final row in rows) {
      try {
        result.add(await _map(row));
      } catch (_) {
        // Una fila con forma inesperada no impide mostrar las demás.
      }
    }
    return result;
  }

  Future<Booking> _map(Map<String, dynamic> row) async {
    final catalog = await _catalog.byUuid(_text(row, 'university_id'));
    if (catalog == null) throw const RepositoryException(bookingFormatMessage);
    final subjectUuid = _text(row, 'subject_id');
    final subjectSlug = [
      for (final e in catalog.subjectUuidBySlug.entries)
        if (e.value == subjectUuid) e.key,
    ].firstOrNull;
    if (subjectSlug == null) throw const RepositoryException(bookingFormatMessage);

    final duration = row['duration_minutes'];
    final price = row['agreed_price'];
    if (duration is! int || price is! num) throw const RepositoryException(bookingFormatMessage);

    final BookingStatus status;
    try {
      status = BookingStatus.fromJson(_text(row, 'status'));
    } on FormatException {
      throw const RepositoryException(bookingFormatMessage);
    }

    return Booking(
      id: _text(row, 'id'),
      studentId: _text(row, 'student_id'),
      tutorId: _text(row, 'tutor_profile_id'),
      subjectId: subjectSlug,
      tema: row['topic'] as String?,
      fechaHora: TutoreaTime.fromUtc(DateTime.parse(_text(row, 'starts_at'))),
      duracion: duration,
      precio: price.toDouble(),
      estado: status,
      modalidad: TutoringModality.values.asNameMap()[row['modality']],
      ubicacion: row['location'] as String?,
      respondidaEn: _instant(row['responded_at']),
      canceladaPor: row['cancelled_by'] as String?,
      canceladaEn: _instant(row['cancelled_at']),
      motivoCancelacion: row['cancellation_reason'] as String?,
    );
  }

  static DateTime? _instant(Object? value) =>
      value is String ? TutoreaTime.fromUtc(DateTime.parse(value)) : null;

  static String _text(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    throw const RepositoryException(bookingFormatMessage);
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } catch (error) {
      throw describeBookingError(error);
    }
  }
}

/// Errores de reservas → mensajes fijos para la UI (nunca el texto del servidor).
/// Los códigos TU0xx los lanzan las funciones de la migración 18.
RepositoryException describeBookingError(Object error) {
  if (error is RepositoryException) return error;
  if (error is TimeoutException) return const RepositoryException(bookingTimeoutMessage);
  if (error is PostgrestException) {
    return RepositoryException(switch (error.code) {
      'TU001' => tutorUnavailableMessage,
      'TU002' => selfBookingMessage,
      'TU003' => subjectNotOfferedMessage,
      'TU004' => modalityNotOfferedMessage,
      'TU005' => invalidDurationMessage,
      'TU006' => pastDateMessage,
      'TU007' => outsideAvailabilityMessage,
      'TU008' => tutorBusyMessage,
      'TU009' => notFoundMessage,
      'TU010' => statusChangedMessage,
      'TU011' => cancelReasonRequiredMessage,
      'TU012' => alreadyStartedMessage,
      'TU013' => tutorCannotCancelPendingMessage,
      'TU014' => studentBusyMessage,
      'TU015' => availabilityChangedMessage, // al aceptar: el tutor cambió su horario
      // Fase 14.9: confirm_booking (migración 21)
      'TU020' => sessionNotFinishedMessage,
      'TU021' => alreadyConfirmedMessage,
      'TU022' => openIncidentBlocksCompletionMessage,
      'TU023' => notConfirmableMessage,
      '23P01' => slotTakenMessage, // EXCLUDE: otra sesión se confirmó al mismo tiempo
      '23505' => duplicateRequestMessage,
      '23514' => bookingInvalidDataMessage,
      '42501' => bookingPermissionMessage,
      _ => actionFailedMessage,
    });
  }
  return const RepositoryException(bookingConnectionMessage);
}

const String tutorUnavailableMessage = 'Este tutor no está disponible.';
const String subjectNotOfferedMessage = 'El tutor no imparte esa materia.';
const String modalityNotOfferedMessage = 'El tutor no ofrece esa modalidad.';
const String chooseModalityMessage = 'Elige la modalidad de la tutoría.';
const String invalidDurationMessage = 'La duración debe ser de 60, 90 o 120 minutos.';
const String pastDateMessage = 'Elige una fecha y hora futuras.';
const String outsideAvailabilityMessage = 'El tutor no atiende en ese horario.';
const String tutorBusyMessage = 'Ese horario se cruza con otra sesión confirmada del tutor.';
const String studentBusyMessage = 'Ese horario se cruza con otra sesión confirmada del estudiante.';
const String slotTakenMessage =
    'Ese horario acaba de ocuparse con otra sesión confirmada. Actualiza e intenta de nuevo.';
const String notFoundMessage = 'No encontramos esa reserva entre las tuyas.';
const String statusChangedMessage = 'Esta reserva ya no se puede cambiar. Actualiza para ver su estado.';
const String alreadyStartedMessage = 'La hora de inicio ya pasó.';
const String tutorCannotCancelPendingMessage =
    'Una solicitud pendiente se rechaza; solo quien la envió puede cancelarla.';
const String duplicateRequestMessage = 'Ya enviaste una solicitud para ese horario.';
const String bookingInvalidDataMessage = 'Revisa los datos de la solicitud.';
const String bookingPermissionMessage = 'No tienes permiso para esta acción.';
const String notAvailableYetMessage = 'Esa acción todavía no está disponible.';
const String actionFailedMessage = 'No se pudo completar la acción. Intenta de nuevo.';
const String bookingFormatMessage = 'Los datos de la reserva no tienen el formato esperado.';
const String bookingConnectionMessage = 'No se pudo conectar con el servidor. Revisa tu conexión a Internet.';
const String bookingTimeoutMessage = 'El servidor tardó demasiado en responder. Intenta de nuevo.';

// ---------------------------------------------------------------------------
// Origen de las filas
// ---------------------------------------------------------------------------

/// Lecturas, funciones y cambios de reservas. En la app es Supabase; en las
/// pruebas, datos simulados.
abstract class BookingRowsSource {
  Future<List<Map<String, dynamic>>> fetchForStudent(String studentId);
  Future<List<Map<String, dynamic>>> fetchForTutor(String tutorProfileId);
  Future<Map<String, dynamic>?> fetchById(String id);

  /// request_booking: devuelve el id de la reserva creada.
  Future<String> request({
    required String tutorProfileId,
    required String subjectId,
    required String modality,
    required String startsAtUtc,
    required int durationMinutes,
    String? topic,
    String? location,
  });

  Future<void> accept(String bookingId);
  Future<void> reject(String bookingId);
  Future<void> cancel(String bookingId, String? reason);

  /// confirm_booking (Fase 14.9): devuelve el nuevo estado.
  Future<String> confirm(String bookingId);

  /// Filas de booking_confirmations de una reserva (party, user_id, confirmed_at).
  Future<List<Map<String, dynamic>>> fetchConfirmations(String bookingId);

  /// Un evento por cada cambio de una reserva visible para la cuenta.
  Stream<void> changes();
}

/// Consultas reales a Supabase con la sesión del usuario (publishable key + JWT).
class SupabaseBookingSource implements BookingRowsSource {
  final SupabaseClient _client;
  SupabaseBookingSource(this._client);

  static const String _columns =
      'id, university_id, student_id, tutor_profile_id, subject_id, modality, topic, location, '
      'starts_at, ends_at, duration_minutes, agreed_price, status, status_changed_at, '
      'responded_at, cancelled_by, cancelled_at, cancellation_reason, created_at';

  @override
  Future<List<Map<String, dynamic>>> fetchForStudent(String studentId) => _client
      .from('bookings')
      .select(_columns)
      .eq('student_id', studentId)
      .order('starts_at', ascending: false);

  @override
  Future<List<Map<String, dynamic>>> fetchForTutor(String tutorProfileId) => _client
      .from('bookings')
      .select(_columns)
      .eq('tutor_profile_id', tutorProfileId)
      .order('starts_at', ascending: true);

  @override
  Future<Map<String, dynamic>?> fetchById(String id) =>
      _client.from('bookings').select(_columns).eq('id', id).maybeSingle();

  @override
  Future<String> request({
    required String tutorProfileId,
    required String subjectId,
    required String modality,
    required String startsAtUtc,
    required int durationMinutes,
    String? topic,
    String? location,
  }) async {
    final id = await _client.rpc<dynamic>('request_booking', params: {
      'p_tutor_profile_id': tutorProfileId,
      'p_subject_id': subjectId,
      'p_modality': modality,
      'p_starts_at': startsAtUtc,
      'p_duration_minutes': durationMinutes,
      'p_topic': topic,
      'p_location': location,
    });
    if (id is! String) throw StateError('request_booking no devolvió el id.');
    return id;
  }

  @override
  Future<void> accept(String bookingId) async {
    await _client.rpc<dynamic>('accept_booking', params: {'p_booking_id': bookingId});
  }

  @override
  Future<void> reject(String bookingId) async {
    await _client.rpc<dynamic>('reject_booking', params: {'p_booking_id': bookingId});
  }

  @override
  Future<void> cancel(String bookingId, String? reason) async {
    await _client.rpc<dynamic>('cancel_booking', params: {'p_booking_id': bookingId, 'p_reason': reason});
  }

  @override
  Future<String> confirm(String bookingId) async {
    final status = await _client.rpc<dynamic>('confirm_booking', params: {'p_booking_id': bookingId});
    if (status is! String) throw StateError('confirm_booking no devolvió el estado.');
    return status;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchConfirmations(String bookingId) => _client
      .from('booking_confirmations')
      .select('booking_id, party, user_id, confirmed_at')
      .eq('booking_id', bookingId)
      .order('confirmed_at', ascending: true);

  /// Supabase Realtime (postgres_changes sobre bookings). Realtime aplica la RLS
  /// de bookings con el JWT de la sesión: cada cuenta recibe solo sus reservas.
  /// El canal se abre con el primer oyente y se cierra con el último.
  @override
  Stream<void> changes() {
    RealtimeChannel? channel;
    late final StreamController<void> controller;
    controller = StreamController<void>.broadcast(
      onListen: () {
        channel = _client
            .channel('tutorea-bookings')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'bookings',
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
