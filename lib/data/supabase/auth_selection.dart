import 'package:flutter/foundation.dart';

import '../../config/auth_mode.dart';
import '../../domain/repositories/repositories.dart';

/// Repositorios de la app según el modo (Fases 14.5 a 14.10):
/// cuentas y perfiles, universidades y carreras, materias, tutores con su
/// disponibilidad y reservas; desde la Fase 14.9 también incidencias,
/// reseñas y notificaciones (en Supabase nunca se guardan en el dispositivo).
class AppDataSources {
  final AuthRepository auth;
  final UniversityRepository universities;
  final SubjectRepository subjects;
  final TutorRepository tutors;
  final BookingRepository bookings;
  final IncidentRepository incidents;
  final AdminIncidentRepository adminIncidents;
  final ReviewRepository reviews;
  final NotificationRepository notifications;

  /// Fotografías en Storage (Fase 14.10); null en el modo local de desarrollo.
  final TutorPhotoStorage? photoStorage;
  final bool remote;

  const AppDataSources({
    required this.auth,
    required this.universities,
    required this.subjects,
    required this.tutors,
    required this.bookings,
    required this.incidents,
    required this.adminIncidents,
    required this.reviews,
    required this.notifications,
    this.photoStorage,
    required this.remote,
  });
}

/// Supabase no se pudo usar al arrancar (sin configuración, sin conexión o
/// error al crear los repositorios). Nunca se cambia a datos locales: la app
/// muestra [message] con la opción de reintentar.
class DataSourcesUnavailable implements Exception {
  final String message;
  const DataSourcesUnavailable(this.message);
  @override
  String toString() => message;
}

const String supabaseNotConfiguredMessage =
    'La app no está configurada para conectarse al servidor. Contacta al equipo de Tutorea.';
const String supabaseUnreachableMessage =
    'No se pudo conectar con el servidor de Tutorea. Revisa tu conexión a Internet e intenta de nuevo.';

/// Elige las fuentes de datos al arrancar (Fase 14.10).
///
/// - [AuthMode.supabase] (producción): Supabase o [DataSourcesUnavailable]. Sin
///   respaldo local silencioso.
/// - [AuthMode.local]: solo desarrollo (ver AuthMode). [local] se crea solo en
///   este caso, así producción nunca abre la base local.
AppDataSources selectDataSources({
  required AuthMode mode,
  required bool supabaseReady,
  required AppDataSources Function() local,
  required AppDataSources Function() remote,
  void Function(String message)? log,
}) {
  final emit = log ?? debugPrint;
  if (mode == AuthMode.local) {
    emit('[Datos] Modo local de DESARROLLO (TUTOREA_AUTH=local). No usar en producción.');
    return local();
  }
  if (!supabaseReady) {
    emit('[Datos] Supabase no está inicializado. Sin respaldo local.');
    throw const DataSourcesUnavailable(supabaseNotConfiguredMessage);
  }
  try {
    final sources = remote();
    emit('[Datos] Supabase activo (única fuente de datos).');
    return sources;
  } catch (_) {
    emit('[Datos] No se pudo preparar Supabase. Sin respaldo local.');
    throw const DataSourcesUnavailable(supabaseUnreachableMessage);
  }
}
