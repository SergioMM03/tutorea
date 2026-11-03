import 'package:flutter/foundation.dart';

import '../../config/auth_mode.dart';
import '../../domain/repositories/repositories.dart';

/// Repositorios que cambian con el modo remoto (Fases 14.5 a 14.8):
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
    required this.remote,
  });
}

/// Elige las fuentes de datos al arrancar.
///
/// Supabase solo se usa si se pidió (`TUTOREA_AUTH=supabase`) y Supabase quedó
/// inicializado. En cualquier otro caso, o si no se pueden crear los
/// repositorios remotos, se usa [local]: la app conserva el modo local.
AppDataSources selectDataSources({
  required AuthMode mode,
  required bool supabaseReady,
  required AppDataSources local,
  required AppDataSources Function() remote,
  void Function(String message)? log,
}) {
  final emit = log ?? debugPrint;
  if (mode != AuthMode.supabase) {
    emit('[Datos] Modo local.');
    return local;
  }
  if (!supabaseReady) {
    emit('[Datos] Se pidió Supabase, pero Supabase no está inicializado. Modo local.');
    return local;
  }
  try {
    final sources = remote();
    emit('[Datos] Supabase activo: cuentas, perfiles, catálogo, tutores, disponibilidad, reservas, incidencias, reseñas y notificaciones.');
    return sources;
  } catch (_) {
    emit('[Datos] No se pudo preparar Supabase. Modo local.');
    return local;
  }
}
