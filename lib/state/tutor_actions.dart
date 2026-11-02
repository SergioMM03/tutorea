import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'booking_store.dart';
import 'session_store.dart';
import 'tutor_store.dart';

/// Carga todo lo que usan las pantallas del tutor:
/// 1. Su perfil (TutorStore.loadMyProfile) y el catálogo de materias.
/// 2. Las solicitudes dirigidas a su perfil (BookingStore.loadForTutor).
/// 3. Los estudiantes de esas solicitudes y su universidad (SessionStore.loadUsers).
Future<void> loadTutorWorkspace(BuildContext context) async {
  final session = context.read<SessionStore>();
  final tutors = context.read<TutorStore>();
  final bookings = context.read<BookingStore>();

  final user = session.user;
  if (user == null || !session.isTutor) return;

  await tutors.loadMyProfile(user.id);
  final profile = tutors.myProfile;
  if (profile != null) await bookings.loadForTutor(profile.id);

  await session.loadUsers([
    user.id,
    for (final b in bookings.tutorRequests) b.studentId,
  ]);
}

/// Para las pantallas del tutor: llama a [loadTutorWorkspace] una vez por
/// usuario, también cuando la sesión guardada termina de cargar después
/// del primer cuadro (al reabrir la app).
mixin TutorWorkspaceLoader<T extends StatefulWidget> on State<T> {
  String? _loadedFor;
  bool _ready = false;

  /// true cuando terminó la primera carga (perfil + solicitudes).
  bool get tutorWorkspaceReady => _ready;

  /// Llamar al inicio de build().
  void ensureTutorWorkspace() {
    final userId = context.watch<SessionStore>().user?.id;
    if (userId == null || userId == _loadedFor) return;
    _loadedFor = userId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await loadTutorWorkspace(context);
      if (mounted) setState(() => _ready = true);
    });
  }
}
