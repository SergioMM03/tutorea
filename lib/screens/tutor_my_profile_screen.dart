import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/models/models.dart';
import '../routes/app_navigator.dart';
import '../state/session_actions.dart';
import '../state/session_store.dart';
import '../state/tutor_actions.dart';
import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../widgets/form_error_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/primary_button.dart';
import '../widgets/rating_label.dart';
import '../widgets/secondary_button.dart';
import '../widgets/section_title.dart';
import '../widgets/subject_chip.dart';
import '../widgets/tutor_avatar.dart';
import '../widgets/tutor_bottom_nav.dart';
import '../widgets/tutor_reviews_section.dart';

/// Perfil propio del tutor: datos académicos, descripción, materias,
/// precio, disponibilidad y valoración. Desde aquí se edita, se vuelve al modo
/// estudiante (buscar y solicitar tutorías, con la misma cuenta) y se cierra sesión.
class TutorMyProfileScreen extends StatefulWidget {
  const TutorMyProfileScreen({super.key});

  @override
  State<TutorMyProfileScreen> createState() => _TutorMyProfileScreenState();
}

class _TutorMyProfileScreenState extends State<TutorMyProfileScreen>
    with TutorWorkspaceLoader<TutorMyProfileScreen> {
  @override
  Widget build(BuildContext context) {
    ensureTutorWorkspace();
    final textTheme = Theme.of(context).textTheme;
    final session = context.watch<SessionStore>();
    final tutors = context.watch<TutorStore>();
    final user = session.user;
    final profile = tutors.myProfile;

    final subjects = profile == null
        ? const <Subject>[]
        : tutors.subjects.where((s) => profile.materias.contains(s.id)).toList();
    final slots = profile == null
        ? const <AvailabilitySlot>[]
        : ([...profile.disponibilidad]..sort((a, b) => a.diaSemana != b.diaSemana
            ? a.diaSemana.compareTo(b.diaSemana)
            : a.horaInicio.compareTo(b.horaInicio)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        automaticallyImplyLeading: false,
        actions: const [NotificationBell()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Center(
                child: TutorAvatar(
                  name: user?.nombre ?? '',
                  photoPath: profile?.photoPath,
                  size: 96,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(user?.nombre ?? '',
                  textAlign: TextAlign.center, style: textTheme.headlineMedium),
              if (profile != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Center(child: RatingLabel(rating: profile.calificacion, count: profile.totalResenas, large: true)),
              ],
              const SizedBox(height: AppSpacing.lg),
              if (tutors.error != null) ...[
                FormErrorBanner(message: tutors.error!),
                const SizedBox(height: AppSpacing.md),
              ],
              const SectionTitle(title: 'Información académica'),
              const SizedBox(height: AppSpacing.sm),
              _InfoCard(rows: [
                ('Universidad', user == null ? '' : session.universityName(user.universityId)),
                ('Carrera', user?.carrera ?? ''),
                ('Año académico', user == null ? '' : '${user.anioAcademico}.º año'),
              ]),
              const SizedBox(height: AppSpacing.lg),
              if (!tutorWorkspaceReady && profile == null)
                const Center(child: CircularProgressIndicator())
              else if (profile == null)
                Text(
                  'Aún no tienes perfil de tutor. Créalo para que los estudiantes '
                  'puedan encontrarte.',
                  style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary),
                )
              else ...[
                const SectionTitle(title: 'Sobre mí'),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  profile.descripcion.isEmpty ? 'Sin descripción.' : profile.descripcion,
                  style: textTheme.bodyLarge?.copyWith(height: 1.4),
                ),
                const SizedBox(height: AppSpacing.lg),
                const SectionTitle(title: 'Materias que ofrezco'),
                const SizedBox(height: AppSpacing.sm),
                if (subjects.isEmpty)
                  Text('Sin materias.', style: textTheme.bodyLarge)
                else
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [for (final s in subjects) SubjectChip(label: s.nombre)],
                  ),
                const SizedBox(height: AppSpacing.lg),
                _InfoCard(rows: [
                  ('Precio por hora', Formatters.pricePerHour(profile.precioHora)),
                  ('Visible para estudiantes', profile.activo ? 'Sí' : 'No'),
                ]),
                const SizedBox(height: AppSpacing.lg),
                const SectionTitle(title: 'Disponibilidad'),
                const SizedBox(height: AppSpacing.sm),
                if (slots.isEmpty)
                  Text('Sin horarios.', style: textTheme.bodyLarge)
                else
                  _InfoCard(rows: [
                    for (final s in slots)
                      (
                        Formatters.weekdayShortOf(s.diaSemana),
                        '${Formatters.time(s.horaInicio)} – ${Formatters.time(s.horaFin)}',
                      ),
                  ]),
                const SizedBox(height: AppSpacing.lg),
                // Fase 14.9: lo que ven los estudiantes de sus reseñas.
                TutorReviewsSection(tutorId: profile.id, emptyText: 'Aún no recibes calificaciones.'),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: profile == null ? 'Crear perfil' : 'Editar perfil',
                icon: Icons.edit_outlined,
                onPressed: user == null ? null : () => AppNavigator.toTutorEditProfile(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                key: const Key('to-student-space'),
                label: 'Buscar y solicitar tutorías',
                onPressed: () => AppNavigator.toHome(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Cerrar sesión',
                onPressed: () => signOutUser(context),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const TutorBottomNav(current: TutorTab.profile),
    );
  }
}

/// Tarjeta con pares etiqueta / valor.
class _InfoCard extends StatelessWidget {
  final List<(String, String)> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  // Flexible: una etiqueta larga ("Visible para estudiantes") pasa
                  // a dos líneas en pantallas angostas en vez de desbordarse.
                  Flexible(
                    child: Text(rows[i].$1,
                        style: textTheme.bodyLarge?.copyWith(color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(rows[i].$2.isEmpty ? '—' : rows[i].$2,
                        textAlign: TextAlign.end, style: textTheme.titleMedium),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
