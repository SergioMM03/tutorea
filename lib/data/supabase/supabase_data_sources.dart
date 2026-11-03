import '../local/local_repositories.dart';
import 'auth_selection.dart';
import 'remote_auth_gateway.dart';
import 'remote_booking_repository.dart';
import 'remote_catalog.dart';
import 'remote_catalog_repositories.dart';
import 'remote_follow_up_repositories.dart';
import 'remote_tutor_repository.dart';
import 'supabase_auth_repository.dart';

/// Arma los repositorios remotos sobre el cliente ya inicializado (publishable
/// key + sesión del usuario). Lanza StateError si Supabase no está inicializado.
///
/// [local] aporta lo que sigue siendo del dispositivo: la universidad elegida en
/// la pantalla inicial y las cuentas del seed local (nombres en reservas
/// antiguas). Desde la Fase 14.8 las reservas son de Supabase: no se leen ni se
/// guardan en el dispositivo (las reservas locales antiguas no se mezclan ni se
/// migran). Fase 14.9: confirmaciones, incidencias, reseñas y notificaciones
/// también son solo de Supabase.
AppDataSources supabaseDataSources(LocalRepositories local) {
  final client = initializedSupabaseClient();
  final catalogSource = SupabaseCatalogSource(client);
  final cache = RemoteCatalogCache(catalog: catalogSource, universities: catalogSource);
  final tutors = RemoteTutorRepository(SupabaseTutorSource(client), cache);
  final followUp = SupabaseFollowUpSource(client);
  return AppDataSources(
    auth: SupabaseAuthRepository(
      gateway: SupabaseAuthGateway(client.auth),
      profiles: SupabaseProfileSource(client),
      catalog: cache,
      legacyUsers: local.auth,
    ),
    universities: RemoteUniversityRepository(cache, deviceSelection: local.universities),
    subjects: RemoteSubjectRepository(cache),
    tutors: tutors,
    bookings: RemoteBookingRepository(SupabaseBookingSource(client), cache, tutors),
    incidents: RemoteIncidentRepository(followUp),
    adminIncidents: RemoteAdminIncidentRepository(followUp),
    reviews: RemoteReviewRepository(followUp),
    notifications: RemoteNotificationRepository(followUp),
    remote: true,
  );
}

/// Fuentes locales de siempre.
AppDataSources localDataSources(LocalRepositories local) => AppDataSources(
      auth: local.auth,
      universities: local.universities,
      subjects: local.subjects,
      tutors: local.tutors,
      bookings: local.bookings,
      incidents: local.incidents,
      adminIncidents: local.adminIncidents,
      reviews: local.reviews,
      notifications: local.notifications,
      remote: false,
    );
