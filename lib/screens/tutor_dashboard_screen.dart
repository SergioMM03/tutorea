import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/booking_store.dart';
import '../state/session_store.dart';
import '../state/tutor_actions.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/tutor_bottom_nav.dart';
import '../widgets/tutor_request_card.dart';

/// Inicio del tutor: saludo, universidad y carrera, contadores de
/// solicitudes y las pendientes más próximas.
class TutorDashboardScreen extends StatefulWidget {
  const TutorDashboardScreen({super.key});

  @override
  State<TutorDashboardScreen> createState() => _TutorDashboardScreenState();
}

class _TutorDashboardScreenState extends State<TutorDashboardScreen>
    with TutorWorkspaceLoader<TutorDashboardScreen> {
  /// Cuántas pendientes se muestran en el resumen.
  static const int _preview = 3;

  @override
  Widget build(BuildContext context) {
    ensureTutorWorkspace();
    final textTheme = Theme.of(context).textTheme;
    final session = context.watch<SessionStore>();
    final tutors = context.watch<TutorStore>();
    final bookings = context.watch<BookingStore>();
    final user = session.user;

    final pending = bookings.tutorRequestsWith(BookingStatus.pendiente);
    final accepted = bookings.tutorRequestsWith(BookingStatus.aceptada);
    final university = user == null ? '' : session.universityName(user.universityId);
    final academic =
        [university, user?.carrera ?? ''].where((t) => t.isNotEmpty).join(' · ');
    final loading = !tutorWorkspaceReady && bookings.tutorRequests.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio'), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: RefreshIndicator(
            onRefresh: () => loadTutorWorkspace(context),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                Text(
                  user == null ? 'Hola' : 'Hola, ${user.nombre.split(' ').first}',
                  style: textTheme.headlineMedium,
                ),
                if (academic.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(academic,
                      style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (tutors.error != null || bookings.error != null) ...[
                  FormErrorBanner(message: tutors.error ?? bookings.error!),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (tutorWorkspaceReady && tutors.myProfile == null && user != null) ...[
                  _NoProfileCard(onCreate: () => AppNavigator.toTutorEditProfile(context)),
                  const SizedBox(height: AppSpacing.lg),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Pendientes',
                        value: pending.length,
                        color: AppColors.warningDark,
                        background: AppColors.warningLight,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _StatCard(
                        label: 'Aceptadas',
                        value: accepted.length,
                        color: AppColors.success,
                        background: AppColors.successLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                SectionTitle(
                  title: 'Solicitudes pendientes',
                  actionLabel: 'Ver todas',
                  onAction: () => AppNavigator.toTutorRequests(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (pending.isEmpty)
                  Text('No tienes solicitudes pendientes.',
                      style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary))
                else
                  for (final b in pending.take(_preview)) ...[
                    TutorRequestCard(
                      booking: b,
                      onTap: () => AppNavigator.toTutorRequestDetail(context, b.id),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Ver solicitudes',
                  icon: Icons.inbox_outlined,
                  onPressed: () => AppNavigator.toTutorRequests(context),
                ),
                const SizedBox(height: AppSpacing.sm),
                SecondaryButton(
                  label: 'Mi perfil de tutor',
                  icon: Icons.person_outline_rounded,
                  onPressed: () => AppNavigator.toTutorMyProfile(context),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const TutorBottomNav(current: TutorTab.home),
    );
  }
}

/// Contador (Pendientes / Aceptadas).
class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color background;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(label,
                style: textTheme.bodySmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('$value', key: Key('tutor-stat-$label'), style: textTheme.headlineLarge),
        ],
      ),
    );
  }
}

/// Tutor recién registrado: todavía no tiene perfil.
class _NoProfileCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _NoProfileCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Completa tu perfil de tutor', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Agrega tus materias, precio y disponibilidad para que los '
            'estudiantes puedan encontrarte.',
            style: textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Crear perfil', onPressed: onCreate),
        ],
      ),
    );
  }
}
