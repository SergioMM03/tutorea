import '../../domain/repositories/repositories.dart';
import '../device/device_university_selection.dart';
import '../local/local_repositories.dart';
import 'auth_selection.dart';
import 'remote_auth_gateway.dart';
import 'remote_booking_repository.dart';
import 'remote_catalog.dart';
import 'remote_catalog_repositories.dart';
import 'remote_follow_up_repositories.dart';
import 'remote_tutor_photo_storage.dart';
import 'remote_tutor_repository.dart';
import 'supabase_auth_repository.dart';

/// Arma los repositorios remotos sobre el cliente ya inicializado (publishable
/// key + sesión del usuario). Lanza StateError si Supabase no está inicializado.
///
/// Fase 14.10: Supabase es la ÚNICA fuente de datos de producción. No se abre
/// la base local ni se consultan cuentas o datos del seed local. Lo único que
/// guarda el dispositivo es la universidad elegida en la pantalla inicial
/// (preferencia, no dato de negocio) y la sesión de Supabase Auth.
AppDataSources supabaseDataSources({UniversityRepository? deviceSelection}) {
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
    ),
    universities: RemoteUniversityRepository(cache,
        deviceSelection: deviceSelection ?? DeviceUniversitySelection()),
    subjects: RemoteSubjectRepository(cache),
    tutors: tutors,
    bookings: RemoteBookingRepository(SupabaseBookingSource(client), cache, tutors),
    incidents: RemoteIncidentRepository(followUp),
    adminIncidents: RemoteAdminIncidentRepository(followUp),
    reviews: RemoteReviewRepository(followUp),
    notifications: RemoteNotificationRepository(followUp),
    photoStorage: RemoteTutorPhotoStorage(SupabasePhotoStorageSource(client), cache),
    remote: true,
  );
}

/// Fuentes locales: SOLO desarrollo y pruebas (TUTOREA_AUTH=local fuera de release).
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
