import '../../domain/repositories/repositories.dart';
import 'local_auth_repository.dart';
import 'local_booking_repository.dart';
import 'local_database.dart';
import 'local_follow_up_repositories.dart';
import 'local_notifications.dart';
import 'local_subject_repository.dart';
import 'local_tutor_repository.dart';
import 'local_university_repository.dart';

/// Arma todos los repositorios locales sobre una misma base.
class LocalRepositories {
  final AuthRepository auth;
  final SubjectRepository subjects;
  final TutorRepository tutors;
  final BookingRepository bookings;
  final UniversityRepository universities;

  // Fase 14.9
  final IncidentRepository incidents;
  final AdminIncidentRepository adminIncidents;
  final ReviewRepository reviews;
  final NotificationRepository notifications;

  LocalRepositories._(
    this.auth,
    this.subjects,
    this.tutors,
    this.bookings,
    this.universities,
    this.incidents,
    this.adminIncidents,
    this.reviews,
    this.notifications,
  );

  static Future<LocalRepositories> open() async {
    final db = await LocalDatabase.open();
    final tutors = LocalTutorRepository(db);
    final notifier = LocalNotifications(db);
    return LocalRepositories._(
      LocalAuthRepository(db),
      LocalSubjectRepository(db),
      tutors,
      LocalBookingRepository(db, tutors, notifications: notifier),
      LocalUniversityRepository(db),
      LocalIncidentRepository(db, tutors, notifications: notifier),
      LocalAdminIncidentRepository(db, tutors, notifications: notifier),
      LocalReviewRepository(db, tutors),
      LocalNotificationRepository(db),
    );
  }
}
