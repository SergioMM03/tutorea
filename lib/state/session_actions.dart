import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../routes/app_navigator.dart';
import 'booking_store.dart';
import 'session_store.dart';
import 'tutor_store.dart';

/// Cerrar sesión completo: borra la sesión, olvida los datos del usuario
/// anterior en los stores y vuelve a la selección de universidad.
Future<void> signOutUser(BuildContext context) async {
  final session = context.read<SessionStore>();
  final tutors = context.read<TutorStore>();
  final bookings = context.read<BookingStore>();

  await session.logout();
  tutors.reset();
  bookings.reset();

  if (context.mounted) AppNavigator.toUniversitySelection(context);
}
