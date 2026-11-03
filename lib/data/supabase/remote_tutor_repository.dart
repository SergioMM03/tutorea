import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException, SupabaseClient;

import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/tutor_rules.dart';
import 'remote_catalog_repositories.dart';

/// TutorRepository con Supabase (Fase 14.7).
///
/// Tablas (migraciones 12 a 15): tutor_profiles, tutor_subjects y
/// availability_slots. Guardar usa la función `save_tutor_profile`, que corre
/// como el usuario (RLS) y guarda perfil, materias y horarios en una sola
/// transacción. El servidor toma el dueño de auth.uid() y la universidad de su
/// perfil: el id, userId y universityId que envía la app se ignoran.
///
/// Ids: el perfil y el usuario son uuid; las materias se traducen slug ↔ uuid
/// con el catálogo remoto ([RemoteCatalogCache]). La fotografía se sube con
/// TutorPhotoStorage (Fase 14.10): photoPath es la ruta del objeto en Storage.
class RemoteTutorRepository implements TutorRepository {
  final TutorRowsSource _source;
  final RemoteCatalogCache _catalog;
  final Duration _timeout;

  RemoteTutorRepository(this._source, this._catalog, {Duration timeout = const Duration(seconds: 15)})
      : _timeout = timeout;

  static final RegExp _uuid =
      RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

  @override
  Future<List<TutorProfile>> getAvailable({
    String? universityId,
    String? subjectId,
    String? categoria,
    TutoringModality? modalidad,
    DateTime? disponibleEn,
    int duracionMinutos = 60,
  }) async {
    String? universityUuid;
    Set<String>? categoryIds;
    if (universityId != null) {
      final catalog = await _catalog.bySlug(universityId);
      if (catalog == null) return const [];
      universityUuid = catalog.universityUuid;
      if (categoria != null) {
        categoryIds = {for (final s in catalog.subjects) if (s.categoria == categoria) s.id};
      }
    }
    // RLS ya limita a la universidad del usuario (activos, el propio o admin).
    final rows = await _guard(() => _source.fetchProfiles(universityUuid: universityUuid));
    final profiles = <TutorProfile>[];
    for (final row in rows) {
      final profile = await _mapOrNull(row);
      if (profile != null) profiles.add(profile);
    }
    if (categoria != null && categoryIds == null) {
      categoryIds = {
        for (final c in _catalog.loaded)
          for (final s in c.subjects)
            if (s.categoria == categoria) s.id,
      };
    }
    return TutorRules.visible(
      profiles,
      universityId: universityId,
      subjectId: subjectId,
      categorySubjectIds: categoryIds,
      modalidad: modalidad,
      disponibleEn: disponibleEn,
      duracionMinutos: duracionMinutos,
    );
  }

  /// Perfil por id, o null si no existe, no es visible o no se pudo leer
  /// (ids que no son uuid, como los del seed local, no existen en Supabase).
  @override
  Future<TutorProfile?> getById(String id) async {
    if (!_uuid.hasMatch(id)) return null;
    try {
      final row = await _source.fetchProfileById(id).timeout(_timeout);
      return row == null ? null : await _mapOrNull(row);
    } catch (_) {
      return null;
    }
  }

  /// Perfil de tutor de una cuenta. A diferencia de [getById], los errores de
  /// conexión se informan: así un tutor no ve "sin perfil" por un fallo de red.
  @override
  Future<TutorProfile?> getByUserId(String userId) async {
    if (!_uuid.hasMatch(userId)) return null;
    final row = await _guard(() => _source.fetchProfileByUserId(userId));
    if (row == null) return null;
    return _guard(() => _map(row));
  }

  @override
  Future<TutorProfile> save(TutorProfile profile) async {
    TutorRules.validateForSave(profile);
    final catalog = await _catalog.bySlug(profile.universityId);
    if (catalog == null) throw const RepositoryException('Tu universidad no está disponible.');
    final subjectUuids = <String>[];
    for (final slug in profile.materias.toSet()) {
      final uuid = catalog.subjectUuidBySlug[slug];
      if (uuid == null) throw const RepositoryException(foreignSubjectMessage);
      subjectUuids.add(uuid);
    }
    final id = await _guard(() => _source.saveOwnProfile(
          description: profile.descripcion.trim(),
          hourlyRate: profile.precioHora,
          offersInPerson: profile.ofrecePresencial,
          offersVirtual: profile.ofreceVirtual,
          isActive: profile.activo,
          subjectUuids: subjectUuids,
          slots: [
            for (final s in profile.disponibilidad)
              {'weekday': s.diaSemana, 'start_minute': s.horaInicio, 'end_minute': s.horaFin},
          ],
        ));
    final row = await _guard(() => _source.fetchProfileById(id));
    if (row == null) throw const RepositoryException(saveFailedMessage);
    return _guard(() => _map(row));
  }

  // ---------------------------------------------------------------- mapeo

  Future<TutorProfile?> _mapOrNull(Map<String, dynamic> row) async {
    try {
      return await _map(row);
    } on RepositoryException {
      return null; // una fila mal formada no impide mostrar las demás
    }
  }

  Future<TutorProfile> _map(Map<String, dynamic> row) async {
    final universityUuid = _text(row, 'university_id');
    final catalog = await _catalog.byUuid(universityUuid);
    if (catalog == null) throw const RepositoryException(formatMessage);
    final slugByUuid = {for (final e in catalog.subjectUuidBySlug.entries) e.value: e.key};

    final materias = <String>[
      for (final ts in _list(row, 'tutor_subjects'))
        if (ts is Map && slugByUuid[ts['subject_id']] != null) slugByUuid[ts['subject_id']]!,
    ];
    final slots = <AvailabilitySlot>[
      for (final s in _list(row, 'availability_slots'))
        if (s is Map) _slot(s),
    ]..sort((a, b) =>
        a.diaSemana != b.diaSemana ? a.diaSemana.compareTo(b.diaSemana) : a.horaInicio.compareTo(b.horaInicio));

    final rate = row['hourly_rate'];
    final rating = row['rating_avg'];
    if (rate is! num) throw const RepositoryException(formatMessage);
    return TutorProfile(
      id: _text(row, 'id'),
      userId: _text(row, 'user_id'),
      universityId: catalog.university.id,
      descripcion: row['description'] is String ? row['description'] as String : '',
      precioHora: rate.toDouble(),
      materias: materias,
      disponibilidad: slots,
      rating: rating is num ? rating.toDouble() : 0, // sin reseñas: null en la base («Nuevo»)
      totalResenas: row['rating_count'] is num ? (row['rating_count'] as num).toInt() : 0,
      activo: row['is_active'] == true,
      // Ruta del objeto en el bucket privado tutor-photos (Fase 14.10).
      photoPath: row['photo_path'] is String ? row['photo_path'] as String : null,
      ofrecePresencial: row['offers_in_person'] == true,
      ofreceVirtual: row['offers_virtual'] == true,
    );
  }

  static AvailabilitySlot _slot(Map<dynamic, dynamic> s) {
    final day = s['weekday'];
    final from = s['start_minute'];
    final to = s['end_minute'];
    if (day is! int || from is! int || to is! int || day < 1 || day > 7 || from < 0 || to > 1440 || from >= to) {
      throw const RepositoryException(formatMessage);
    }
    return AvailabilitySlot(diaSemana: day, horaInicio: from, horaFin: to);
  }

  static List<Object?> _list(Map<String, dynamic> row, String key) {
    final value = row[key];
    return value is List ? value : const [];
  }

  static String _text(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is String && value.isNotEmpty) return value;
    throw const RepositoryException(formatMessage);
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } catch (error) {
      throw describeTutorError(error);
    }
  }
}

/// Errores de tutores → mensajes fijos para la UI (nunca el texto del servidor).
RepositoryException describeTutorError(Object error) {
  if (error is RepositoryException) return error;
  if (error is TimeoutException) return const RepositoryException(catalogTimeoutMessage);
  if (error is PostgrestException) {
    return RepositoryException(switch (error.code) {
      '23P01' => overlapMessage,
      '23514' => invalidDataMessage,
      '23503' => foreignSubjectMessage,
      '23505' => duplicateProfileMessage,
      '42501' => permissionMessage,
      '22023' => invalidSlotsMessage,
      _ => saveFailedMessage,
    });
  }
  return const RepositoryException(catalogConnectionMessage);
}

const String overlapMessage = 'Hay horarios que se cruzan el mismo día.';
const String invalidDataMessage = 'Revisa la tarifa, las modalidades y los horarios.';
const String foreignSubjectMessage = 'Alguna materia no pertenece a tu universidad.';
const String duplicateProfileMessage = 'Ya tienes un perfil de tutor.';
const String permissionMessage =
    'No tienes permiso para guardar este perfil de tutor (solo el propio; las cuentas '
    'administradoras no ofrecen tutorías).';
const String invalidSlotsMessage = 'La disponibilidad no es válida.';
const String saveFailedMessage = 'No se pudo guardar el perfil de tutor. Intenta de nuevo.';
const String formatMessage = 'Los datos del tutor no tienen el formato esperado.';

// ---------------------------------------------------------------------------
// Origen de las filas
// ---------------------------------------------------------------------------

/// Lecturas y guardado de tutores. En la app es Supabase; en las pruebas, datos simulados.
abstract class TutorRowsSource {
  /// Perfiles visibles (RLS), con `tutor_subjects` y `availability_slots` anidados.
  Future<List<Map<String, dynamic>>> fetchProfiles({String? universityUuid});
  Future<Map<String, dynamic>?> fetchProfileById(String id);
  Future<Map<String, dynamic>?> fetchProfileByUserId(String userId);

  /// Llama a `save_tutor_profile` y devuelve el id del perfil.
  Future<String> saveOwnProfile({
    required String description,
    required double hourlyRate,
    required bool offersInPerson,
    required bool offersVirtual,
    required bool isActive,
    required List<String> subjectUuids,
    required List<Map<String, int>> slots,
  });
}

class SupabaseTutorSource implements TutorRowsSource {
  final SupabaseClient _client;
  SupabaseTutorSource(this._client);

  static const String _columns =
      'id, user_id, university_id, description, hourly_rate, offers_in_person, offers_virtual, '
      'is_active, rating_avg, rating_count, photo_path, '
      'tutor_subjects(subject_id), availability_slots(weekday, start_minute, end_minute)';

  @override
  Future<List<Map<String, dynamic>>> fetchProfiles({String? universityUuid}) {
    final query = _client.from('tutor_profiles').select(_columns);
    return universityUuid == null ? query : query.eq('university_id', universityUuid);
  }

  @override
  Future<Map<String, dynamic>?> fetchProfileById(String id) =>
      _client.from('tutor_profiles').select(_columns).eq('id', id).maybeSingle();

  @override
  Future<Map<String, dynamic>?> fetchProfileByUserId(String userId) =>
      _client.from('tutor_profiles').select(_columns).eq('user_id', userId).maybeSingle();

  @override
  Future<String> saveOwnProfile({
    required String description,
    required double hourlyRate,
    required bool offersInPerson,
    required bool offersVirtual,
    required bool isActive,
    required List<String> subjectUuids,
    required List<Map<String, int>> slots,
  }) async {
    final id = await _client.rpc<dynamic>('save_tutor_profile', params: {
      'p_description': description,
      'p_hourly_rate': hourlyRate,
      'p_offers_in_person': offersInPerson,
      'p_offers_virtual': offersVirtual,
      'p_is_active': isActive,
      'p_subject_ids': subjectUuids,
      'p_slots': slots,
    });
    if (id is! String) throw StateError('save_tutor_profile no devolvió el id.');
    return id;
  }
}
