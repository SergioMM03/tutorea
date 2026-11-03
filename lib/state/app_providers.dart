import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../data/device/device_profile_photo_repository.dart';
import '../data/local/local_repositories.dart';
import '../domain/repositories/repositories.dart';
import 'booking_store.dart';
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
  final UniversityRepository? universities;
  final ProfilePhotoRepository? photos;
  final Widget child;

  const AppProviders({
    super.key,
    required this.auth,
    required this.subjects,
    required this.tutors,
    required this.bookings,
    this.universities,
    this.photos,
    required this.child,
  });

  /// Versión local (shared_preferences). Para Firebase se agregaría
  /// `AppProviders.firebase(...)` y se cambia la llamada en main.dart.
  /// [photos]: selector de fotografías; por defecto la galería del dispositivo
  /// (las pruebas pasan uno falso).
  /// [auth]: reemplaza solo la autenticación (Fase 14.5: Supabase Auth); el resto
  /// de los repositorios sigue siendo local. Por defecto, la autenticación local.
  factory AppProviders.local(
    LocalRepositories repos, {
    Key? key,
    ProfilePhotoRepository? photos,
    AuthRepository? auth,
    required Widget child,
  }) =>
      AppProviders(
        key: key,
        auth: auth ?? repos.auth,
        subjects: repos.subjects,
        tutors: repos.tutors,
        bookings: repos.bookings,
        universities: repos.universities,
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
            create: (_) => TutorStore(tutors, subjects, auth, universities, photos)),
        ChangeNotifierProvider<BookingStore>(create: (_) => BookingStore(bookings)),
      ],
      child: child,
    );
  }
}
