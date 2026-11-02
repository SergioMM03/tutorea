import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';
import 'local_booking_repository.dart';
import 'local_database.dart';
import 'local_subject_repository.dart';
import 'local_tutor_repository.dart';
import 'local_university_repository.dart';

/// Arma todos los repositorios locales sobre una misma base.
/// Para usar Firebase se crea `FirebaseRepositories` con los mismos 5 campos
/// y se cambia una sola línea donde se configura provider.
class LocalRepositories {
  final AuthRepository auth;
  final SubjectRepository subjects;
  final TutorRepository tutors;
  final BookingRepository bookings;
  final UniversityRepository universities;

  LocalRepositories._(
      this.auth, this.subjects, this.tutors, this.bookings, this.universities);

  static Future<LocalRepositories> open() async {
    final db = await LocalDatabase.open();
    final tutors = LocalTutorRepository(db);
    return LocalRepositories._(
      LocalAuthRepository(db),
      LocalSubjectRepository(db),
      tutors,
      LocalBookingRepository(db, tutors),
      LocalUniversityRepository(db),
    );
  }
}
