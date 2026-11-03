import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import 'booking_store.dart';
import 'follow_up_stores.dart';
import 'session_store.dart';
import 'tutor_store.dart';

/// Cerrar sesión completo: borra la sesión, olvida los datos del usuario
/// anterior en los stores y vuelve a la selección de universidad.
Future<void> signOutUser(BuildContext context) async {
  final session = context.read<SessionStore>();
  final tutors = context.read<TutorStore>();
  final bookings = context.read<BookingStore>();
  final incidents = context.read<IncidentStore>();
  final reviews = context.read<ReviewStore>();
  final notifications = context.read<NotificationStore>();

  await session.logout();
  tutors.reset();
  bookings.reset();
  incidents.reset();
  reviews.reset();
  notifications.reset();

  if (context.mounted) AppNavigator.toUniversitySelection(context);
}
