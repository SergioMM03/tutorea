import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/device/device_profile_photo_repository.dart';
import '../data/local/local_repositories.dart';
import '../data/supabase/auth_selection.dart';
import '../domain/repositories/repositories.dart';
import 'booking_store.dart';
import 'follow_up_stores.dart';
import 'session_store.dart';
import 'tutor_store.dart';

/// Registra los stores de la app con provider.
///
/// Recibe los repositorios como contratos (no sabe si son locales o Firebase)
/// y se los pasa a cada store por constructor. Las pantallas solo ven stores:
///   UI → Store → Repository → Storage
class AppProviders extends StatelessWidget {
  final AuthRepository auth;
  final SubjectRepository subjects;
  final TutorRepository tutors;
  final BookingRepository bookings;
  final IncidentRepository incidents;
  final ReviewRepository reviews;
  final NotificationRepository notifications;
  final UniversityRepository? universities;
  final ProfilePhotoRepository? photos;

  /// Fotografías en Supabase Storage (Fase 14.10); null en desarrollo local.
  final TutorPhotoStorage? photoStorage;
  final Widget child;

  const AppProviders({
    super.key,
    required this.auth,
    required this.subjects,
    required this.tutors,
    required this.bookings,
    required this.incidents,
    required this.reviews,
    required this.notifications,
    this.universities,
    this.photos,
    this.photoStorage,
    required this.child,
  });

  /// Producción (Fase 14.10): todo viene de [data] (Supabase); no se abre la
  /// base local. [photos] solo elige la imagen en la galería.
  factory AppProviders.fromSources(
    AppDataSources data, {
    Key? key,
    ProfilePhotoRepository? photos,
    required Widget child,
  }) =>
      AppProviders(
        key: key,
        auth: data.auth,
        subjects: data.subjects,
        tutors: data.tutors,
        bookings: data.bookings,
        incidents: data.incidents,
        reviews: data.reviews,
        notifications: data.notifications,
        universities: data.universities,
        photos: photos ?? DeviceProfilePhotoRepository(),
        photoStorage: data.photoStorage,
        child: child,
      );

  /// Versión local (shared_preferences): SOLO desarrollo y pruebas. Producción
  /// usa [AppProviders.fromSources] con Supabase.
  /// [photos]: selector de fotografías; por defecto la galería del dispositivo
  /// (las pruebas pasan uno falso).
  /// [auth], [universities], [subjects], [tutors], [bookings] y, desde la Fase
  /// 14.9, [incidents], [reviews] y [notifications]: reemplazan esos
  /// repositorios en el modo remoto (Supabase). Sin ellos, todo es local.
  factory AppProviders.local(
    LocalRepositories repos, {
    Key? key,
    ProfilePhotoRepository? photos,
    AuthRepository? auth,
    UniversityRepository? universities,
    SubjectRepository? subjects,
    TutorRepository? tutors,
    BookingRepository? bookings,
    IncidentRepository? incidents,
    ReviewRepository? reviews,
    NotificationRepository? notifications,
    required Widget child,
  }) =>
      AppProviders(
        key: key,
        auth: auth ?? repos.auth,
        subjects: subjects ?? repos.subjects,
        tutors: tutors ?? repos.tutors,
        bookings: bookings ?? repos.bookings,
        incidents: incidents ?? repos.incidents,
        reviews: reviews ?? repos.reviews,
        notifications: notifications ?? repos.notifications,
        universities: universities ?? repos.universities,
        photos: photos ?? DeviceProfilePhotoRepository(),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // load(): recupera la sesión guardada en cuanto arranca la app.
        ChangeNotifierProvider<SessionStore>(create: (_) => SessionStore(auth, universities)..load()),
        ChangeNotifierProvider<TutorStore>(
            create: (_) => TutorStore(tutors, subjects, auth, universities, photos, photoStorage)),
        // URLs firmadas de las fotos en Storage (null en desarrollo local).
        Provider<PhotoUrlResolver?>.value(value: photoStorage),
        ChangeNotifierProvider<BookingStore>(create: (_) => BookingStore(bookings)),
        ChangeNotifierProvider<IncidentStore>(create: (_) => IncidentStore(incidents)),
        ChangeNotifierProvider<ReviewStore>(create: (_) => ReviewStore(reviews)),
        ChangeNotifierProvider<NotificationStore>(create: (_) => NotificationStore(notifications)),
      ],
      child: child,
    );
  }
}
