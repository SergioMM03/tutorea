import 'package:flutter/material.dart';

import '../state/tutor_store.dart';
import '../routes/app_navigator.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../widgets/app_back_button.dart';
import '../widgets/bottom_action_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/rating_label.dart';
import '../widgets/section_title.dart';
import '../widgets/subject_chip.dart';
import '../widgets/tutor_avatar.dart';
import '../widgets/tutor_reviews_section.dart';

/// 4. Perfil del tutor. Recibe el [TutorSummary] real (perfil + cuenta + materias).
class TutorProfileScreen extends StatelessWidget {
  final TutorSummary tutor;
  const TutorProfileScreen({super.key, required this.tutor});

  void _openBooking(BuildContext context) {
    AppNavigator.toBooking(context, tutor);
  }

  /// Días distintos con disponibilidad, de lunes a domingo.
  List<int> get _availableDays =>
      tutor.profile.disponibilidad.map((s) => s.diaSemana).toSet().toList()..sort();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton()),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            children: [
              _ProfileHeader(tutor: tutor),
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const SectionTitle(title: 'Sobre mí'),
              const SizedBox(height: AppSpacing.sm),
              Text(
                tutor.profile.descripcion,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Materias que imparto'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final subject in tutor.subjects) SubjectChip(label: subject.nombre),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const SectionTitle(title: 'Disponibilidad'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final day in _availableDays)
                    _DayCircle(label: Formatters.weekdayShortOf(day)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Fase 14.9: reseñas públicas (sin datos de quién calificó).
              TutorReviewsSection(tutorId: tutor.id),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BookingBar(
        price: Formatters.pricePerHour(tutor.precioHora),
        onBook: () => _openBooking(context),
      ),
    );
  }
}

/// Foto, nombre, carrera y rating.
class _ProfileHeader extends StatelessWidget {
  final TutorSummary tutor;

  const _ProfileHeader({required this.tutor});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // La foto ocupa hasta la mitad del ancho, entre 140 y 220 px.
    final photoSize = (MediaQuery.of(context).size.width * 0.5).clamp(140.0, 220.0).toDouble();

    return Column(
      children: [
        TutorAvatar(name: tutor.nombre, photoPath: tutor.profile.photoPath, size: photoSize),
        const SizedBox(height: AppSpacing.md),
        Text(
          tutor.nombre,
          textAlign: TextAlign.center,
          style: textTheme.headlineLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        // El MVP no guarda "Tutor/Tutora": se muestra la carrera del tutor.
        Text(tutor.user.carrera, textAlign: TextAlign.center, style: textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.xs),
        RatingLabel(rating: tutor.calificacion, count: tutor.totalResenas, large: true),
      ],
    );
  }
}

/// Día disponible en un círculo azul claro (Lun, Mar...).
class _DayCircle extends StatelessWidget {
  final String label;
  const _DayCircle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

/// Barra fija inferior: precio a la izquierda, "Reservar sesión" a la derecha.
class _BookingBar extends StatelessWidget {
  final String price;
  final VoidCallback onBook;

  const _BookingBar({required this.price, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return BottomActionBar(
      child: Row(
        children: [
          Text(price, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(width: AppSpacing.lg),
          // El botón ocupa el resto del ancho, como en la barra de Reserva.
          Expanded(
            child: PrimaryButton(label: 'Reservar sesión', onPressed: onBook),
          ),
        ],
      ),
    );
  }
}
