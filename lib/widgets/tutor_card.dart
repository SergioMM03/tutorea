import 'package:flutter/material.dart';

import '../state/tutor_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'rating_label.dart';
import 'tutor_avatar.dart';

/// Tarjeta de tutor para Inicio y Búsqueda:
/// foto, nombre, rating, materias y precio por hora.
/// Recibe un [TutorSummary] ya resuelto por TutorStore (no consulta repositorios).
class TutorCard extends StatelessWidget {
  final TutorSummary tutor;
  final VoidCallback? onTap;

  const TutorCard({
    super.key,
    required this.tutor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = BorderRadius.circular(AppRadius.card);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                // Fotografía del propio tutor o sus iniciales.
                TutorAvatar(name: tutor.nombre, photoPath: tutor.profile.photoPath, size: 72),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tutor.nombre,
                        style: textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      RatingLabel(rating: tutor.rating),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              Formatters.names([for (final s in tutor.subjects) s.nombre]),
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            Formatters.pricePerHour(tutor.precioHora),
                            style: textTheme.titleMedium
                                ?.copyWith(color: AppColors.primary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
